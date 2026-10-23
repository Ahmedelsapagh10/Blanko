#include "native_file_bridge.h"

#include <array>
#include <cstring>
#include <memory>
#include <string>
#include <vector>

namespace {

constexpr size_t kImageLimit = 16 * 1024 * 1024;
constexpr size_t kProjectLimit = 64 * 1024 * 1024;
constexpr size_t kSaveLimit = 128 * 1024 * 1024;

enum class Operation { kImage, kProject, kSave };

struct FileOperation {
  Operation kind;
  GFile* file = nullptr;
  GBytes* output = nullptr;
  std::string filename;
  std::string mime_type;

  ~FileOperation() {
    g_clear_object(&file);
    g_clear_pointer(&output, g_bytes_unref);
  }
};

struct FileResult {
  std::vector<uint8_t> bytes;
  std::string filename;
  std::string mime_type;
};

bool HasExtension(const std::string& name, const char* extension) {
  g_autofree gchar* lowercase = g_ascii_strdown(name.c_str(), -1);
  return g_str_has_suffix(lowercase, extension);
}

void RunFileOperation(GTask* task, gpointer, gpointer task_data,
                      GCancellable* cancellable) {
  const auto* operation = static_cast<FileOperation*>(task_data);
  g_autoptr(GError) error = nullptr;
  if (operation->kind == Operation::kSave) {
    gsize length = 0;
    const auto* bytes =
        static_cast<const char*>(g_bytes_get_data(operation->output, &length));
    // GIO replaces local files through a temporary file and atomic rename.
    if (!g_file_replace_contents(operation->file, bytes, length, nullptr, FALSE,
                                 G_FILE_CREATE_NONE, nullptr, cancellable,
                                 &error)) {
      g_task_return_error(task, g_steal_pointer(&error));
      return;
    }
    g_task_return_pointer(task, new FileResult(), [](gpointer result) {
      delete static_cast<FileResult*>(result);
    });
    return;
  }

  const size_t limit =
      operation->kind == Operation::kImage ? kImageLimit : kProjectLimit;
  // Reject directories/devices/pipes before opening a potentially blocking
  // file.
  g_autoptr(GFileInfo) selected_info = g_file_query_info(
      operation->file,
      G_FILE_ATTRIBUTE_STANDARD_TYPE "," G_FILE_ATTRIBUTE_STANDARD_SIZE,
      G_FILE_QUERY_INFO_NONE, cancellable, &error);
  if (selected_info == nullptr) {
    g_task_return_error(task, g_steal_pointer(&error));
    return;
  }
  const goffset selected_size = g_file_info_get_size(selected_info);
  if (g_file_info_get_file_type(selected_info) != G_FILE_TYPE_REGULAR ||
      selected_size <= 0 || static_cast<guint64>(selected_size) > limit) {
    g_task_return_new_error(
        task, G_IO_ERROR, G_IO_ERROR_INVALID_DATA,
        "Choose a non-empty regular file no larger than %zu MiB.",
        limit / (1024 * 1024));
    return;
  }
  g_autoptr(GFileInputStream) stream =
      g_file_read(operation->file, cancellable, &error);
  if (stream == nullptr) {
    g_task_return_error(task, g_steal_pointer(&error));
    return;
  }
  g_autoptr(GFileInfo) info = g_file_input_stream_query_info(
      stream, G_FILE_ATTRIBUTE_STANDARD_TYPE "," G_FILE_ATTRIBUTE_STANDARD_SIZE,
      cancellable, &error);
  if (info == nullptr) {
    g_task_return_error(task, g_steal_pointer(&error));
    return;
  }
  const goffset size = g_file_info_get_size(info);
  if (g_file_info_get_file_type(info) != G_FILE_TYPE_REGULAR || size <= 0 ||
      static_cast<guint64>(size) > limit) {
    g_task_return_new_error(
        task, G_IO_ERROR, G_IO_ERROR_INVALID_DATA,
        "Choose a non-empty regular file no larger than %zu MiB.",
        limit / (1024 * 1024));
    return;
  }

  auto result = std::make_unique<FileResult>();
  result->filename = operation->filename;
  result->mime_type = operation->mime_type;
  result->bytes.reserve(static_cast<size_t>(size));
  std::array<uint8_t, 64 * 1024> buffer;
  while (true) {
    const gssize count =
        g_input_stream_read(G_INPUT_STREAM(stream), buffer.data(),
                            buffer.size(), cancellable, &error);
    if (count < 0) {
      g_task_return_error(task, g_steal_pointer(&error));
      return;
    }
    if (count == 0) break;
    if (result->bytes.size() + static_cast<size_t>(count) > limit) {
      g_task_return_new_error(
          task, G_IO_ERROR, G_IO_ERROR_INVALID_DATA,
          "The selected file grew beyond the %zu MiB limit.",
          limit / (1024 * 1024));
      return;
    }
    result->bytes.insert(result->bytes.end(), buffer.begin(),
                         buffer.begin() + count);
  }
  if (result->bytes.empty()) {
    g_task_return_new_error(task, G_IO_ERROR, G_IO_ERROR_INVALID_DATA,
                            "The selected file is empty.");
    return;
  }
  if (operation->kind == Operation::kImage) {
    const auto& bytes = result->bytes;
    constexpr uint8_t png_signature[] = {137, 80, 78, 71, 13, 10, 26, 10};
    const bool png =
        bytes.size() >= sizeof(png_signature) &&
        std::memcmp(bytes.data(), png_signature, sizeof(png_signature)) == 0;
    const bool jpeg = bytes.size() >= 3 && bytes[0] == 0xff &&
                      bytes[1] == 0xd8 && bytes[2] == 0xff;
    if ((operation->mime_type == "image/png" && !png) ||
        (operation->mime_type == "image/jpeg" && !jpeg)) {
      g_task_return_new_error(task, G_IO_ERROR, G_IO_ERROR_INVALID_DATA,
                              "The selected image is not a valid PNG or JPEG.");
      return;
    }
  }
  g_task_return_pointer(task, result.release(), [](gpointer value) {
    delete static_cast<FileResult*>(value);
  });
}

class NativeFileBridge : public std::enable_shared_from_this<NativeFileBridge> {
 public:
  NativeFileBridge(GtkWindow* window, FlView* view) : window_(window) {
    g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
    FlBinaryMessenger* messenger =
        fl_engine_get_binary_messenger(fl_view_get_engine(view));
    image_channel_ = fl_method_channel_new(messenger, "blanko/image_picker",
                                           FL_METHOD_CODEC(codec));
    project_channel_ = fl_method_channel_new(messenger, "blanko/project_files",
                                             FL_METHOD_CODEC(codec));
    for (FlMethodChannel* channel : {image_channel_, project_channel_}) {
      fl_method_channel_set_method_call_handler(channel, HandleCall, this,
                                                nullptr);
    }
  }

  ~NativeFileBridge() { Shutdown(); }

  void Shutdown() {
    if (!active_) return;
    active_ = false;
    if (cancellable_ != nullptr) g_cancellable_cancel(cancellable_);
    CloseDialog();
    if (pending_ != nullptr) {
      FinishError("unavailable",
                  "The editor window closed. Retry the file operation.");
    }
    for (FlMethodChannel* channel : {image_channel_, project_channel_}) {
      fl_method_channel_set_method_call_handler(channel, nullptr, nullptr,
                                                nullptr);
    }
    g_clear_object(&image_channel_);
    g_clear_object(&project_channel_);
    window_ = nullptr;
  }

 private:
  static void HandleCall(FlMethodChannel* channel, FlMethodCall* call,
                         gpointer user_data) {
    auto* self = static_cast<NativeFileBridge*>(user_data);
    const char* method = fl_method_call_get_name(call);
    Operation kind;
    if (channel == self->image_channel_ && g_str_equal(method, "pickImage")) {
      kind = Operation::kImage;
    } else if (channel == self->project_channel_ &&
               g_str_equal(method, "pickProject")) {
      kind = Operation::kProject;
    } else if (channel == self->project_channel_ &&
               g_str_equal(method, "saveFile")) {
      kind = Operation::kSave;
    } else {
      fl_method_call_respond_not_implemented(call, nullptr);
      return;
    }
    if (!self->active_) {
      fl_method_call_respond_error(call, "unavailable",
                                   "The editor window is unavailable.", nullptr,
                                   nullptr);
      return;
    }
    if (self->pending_ != nullptr) {
      fl_method_call_respond_error(call, "busy",
                                   "Another file operation is in progress.",
                                   nullptr, nullptr);
      return;
    }

    std::string suggested_name;
    if (kind == Operation::kSave) {
      FlValue* args = fl_method_call_get_args(call);
      FlValue* bytes = nullptr;
      FlValue* name = nullptr;
      FlValue* extension = nullptr;
      if (args != nullptr && fl_value_get_type(args) == FL_VALUE_TYPE_MAP) {
        bytes = fl_value_lookup_string(args, "bytes");
        name = fl_value_lookup_string(args, "suggestedName");
        extension = fl_value_lookup_string(args, "extension");
      }
      if (bytes == nullptr || name == nullptr || extension == nullptr ||
          fl_value_get_type(bytes) != FL_VALUE_TYPE_UINT8_LIST ||
          fl_value_get_type(name) != FL_VALUE_TYPE_STRING ||
          fl_value_get_type(extension) != FL_VALUE_TYPE_STRING ||
          fl_value_get_length(bytes) == 0 ||
          fl_value_get_length(bytes) > kSaveLimit ||
          (!g_str_equal(fl_value_get_string(extension), "png") &&
           !g_str_equal(fl_value_get_string(extension), "wboard"))) {
        fl_method_call_respond_error(call, "invalid_file",
                                     "Choose PNG or .wboard output containing "
                                     "between 1 byte and 128 MiB.",
                                     nullptr, nullptr);
        return;
      }
      self->extension_ = fl_value_get_string(extension);
      suggested_name = fl_value_get_string(name);
      for (char& character : suggested_name) {
        if (character == '/' || character == '\\' ||
            static_cast<unsigned char>(character) < 32) {
          character = '_';
        }
      }
      if (suggested_name.empty()) suggested_name = "Blanko";
      if (!HasExtension(suggested_name, ("." + self->extension_).c_str())) {
        suggested_name += "." + self->extension_;
      }
      self->output_ = g_bytes_new(fl_value_get_uint8_list(bytes),
                                  fl_value_get_length(bytes));
    }
    self->kind_ = kind;
    self->pending_ = FL_METHOD_CALL(g_object_ref(call));
    self->ShowDialog(suggested_name);
  }

  void ShowDialog(const std::string& suggested_name) {
    const bool save = kind_ == Operation::kSave;
    const char* title = save                         ? "Save Blanko file"
                        : kind_ == Operation::kImage ? "Insert image"
                                                     : "Open Blanko project";
    dialog_ = gtk_file_chooser_native_new(
        title, window_,
        save ? GTK_FILE_CHOOSER_ACTION_SAVE : GTK_FILE_CHOOSER_ACTION_OPEN,
        save ? "Save" : "Open", "Cancel");
    GtkFileChooser* chooser = GTK_FILE_CHOOSER(dialog_);
    gtk_native_dialog_set_modal(GTK_NATIVE_DIALOG(dialog_), TRUE);
    gtk_file_chooser_set_select_multiple(chooser, FALSE);
    gtk_file_chooser_set_local_only(chooser, TRUE);
    GtkFileFilter* filter = gtk_file_filter_new();
    if (kind_ == Operation::kImage) {
      gtk_file_filter_set_name(filter, "PNG and JPEG images");
      gtk_file_filter_add_mime_type(filter, "image/png");
      gtk_file_filter_add_mime_type(filter, "image/jpeg");
    } else {
      const bool png = save && extension_ == "png";
      gtk_file_filter_set_name(filter,
                               png ? "PNG image" : "Blanko project (.wboard)");
      gtk_file_filter_add_pattern(filter, png ? "*.png" : "*.wboard");
      gtk_file_filter_add_pattern(filter, png ? "*.PNG" : "*.WBOARD");
    }
    gtk_file_chooser_add_filter(chooser, filter);
    gtk_file_chooser_set_filter(chooser, filter);
    if (save) {
      gtk_file_chooser_set_do_overwrite_confirmation(chooser, TRUE);
      gtk_file_chooser_set_create_folders(chooser, TRUE);
      gtk_file_chooser_set_current_name(chooser, suggested_name.c_str());
    }
    g_signal_connect(dialog_, "response", G_CALLBACK(DialogResponse), this);
    gtk_native_dialog_show(GTK_NATIVE_DIALOG(dialog_));
  }

  static void DialogResponse(GtkNativeDialog*, gint response,
                             gpointer user_data) {
    auto* self = static_cast<NativeFileBridge*>(user_data);
    g_autoptr(GFile) file =
        response == GTK_RESPONSE_ACCEPT
            ? gtk_file_chooser_get_file(GTK_FILE_CHOOSER(self->dialog_))
            : nullptr;
    self->CloseDialog();
    if (response != GTK_RESPONSE_ACCEPT) {
      g_autoptr(FlValue) value = self->kind_ == Operation::kSave
                                     ? fl_value_new_bool(false)
                                     : fl_value_new_null();
      self->FinishSuccess(value);
      return;
    }
    if (file == nullptr) {
      self->FinishError("invalid_file",
                        "No local file was selected. Please retry.");
      return;
    }
    g_autofree gchar* basename = g_file_get_basename(file);
    if (basename == nullptr) {
      self->FinishError("invalid_file",
                        "Choose a local file with a valid name.");
      return;
    }
    g_autofree gchar* display_name = g_filename_display_name(basename);
    auto operation = std::make_unique<FileOperation>();
    operation->kind = self->kind_;
    operation->file = G_FILE(g_object_ref(file));
    operation->filename = display_name;
    if (self->kind_ == Operation::kImage) {
      if (HasExtension(basename, ".png")) {
        operation->mime_type = "image/png";
      } else if (HasExtension(basename, ".jpg") ||
                 HasExtension(basename, ".jpeg")) {
        operation->mime_type = "image/jpeg";
      } else {
        self->FinishError("invalid_file", "Select a PNG or JPEG image.");
        return;
      }
    } else {
      const std::string suffix =
          self->kind_ == Operation::kSave ? "." + self->extension_ : ".wboard";
      if (!HasExtension(basename, suffix.c_str())) {
        // Do not append after GTK's overwrite confirmation: that could replace
        // a different, unconfirmed destination.
        self->FinishError("invalid_file",
                          ("Use a filename ending in " + suffix + ".").c_str());
        return;
      }
    }
    operation->output = g_steal_pointer(&self->output_);
    self->cancellable_ = g_cancellable_new();
    auto* retained =
        new std::shared_ptr<NativeFileBridge>(self->shared_from_this());
    g_autoptr(GTask) task =
        g_task_new(nullptr, self->cancellable_, OperationFinished, retained);
    g_task_set_task_data(task, operation.release(), [](gpointer value) {
      delete static_cast<FileOperation*>(value);
    });
    g_task_run_in_thread(task, RunFileOperation);
  }

  static void OperationFinished(GObject*, GAsyncResult* async_result,
                                gpointer user_data) {
    std::unique_ptr<std::shared_ptr<NativeFileBridge>> retained(
        static_cast<std::shared_ptr<NativeFileBridge>*>(user_data));
    NativeFileBridge* self = retained->get();
    g_autoptr(GError) error = nullptr;
    std::unique_ptr<FileResult> result(static_cast<FileResult*>(
        g_task_propagate_pointer(G_TASK(async_result), &error)));
    if (!self->active_ || self->pending_ == nullptr) return;
    if (error != nullptr) {
      self->FinishError(
          self->kind_ == Operation::kSave ? "write_failed" : "read_failed",
          error->message);
      return;
    }
    g_autoptr(FlValue) value = nullptr;
    if (self->kind_ == Operation::kSave) {
      value = fl_value_new_bool(true);
    } else if (self->kind_ == Operation::kProject) {
      value =
          fl_value_new_uint8_list(result->bytes.data(), result->bytes.size());
    } else {
      value = fl_value_new_map();
      fl_value_set_string_take(
          value, "bytes",
          fl_value_new_uint8_list(result->bytes.data(), result->bytes.size()));
      fl_value_set_string_take(value, "filename",
                               fl_value_new_string(result->filename.c_str()));
      fl_value_set_string_take(value, "mimeType",
                               fl_value_new_string(result->mime_type.c_str()));
    }
    self->FinishSuccess(value);
  }

  void CloseDialog() {
    if (dialog_ == nullptr) return;
    g_signal_handlers_disconnect_by_data(dialog_, this);
    gtk_native_dialog_destroy(GTK_NATIVE_DIALOG(dialog_));
    g_clear_object(&dialog_);
  }

  void FinishSuccess(FlValue* value) {
    fl_method_call_respond_success(pending_, value, nullptr);
    ClearPending();
  }

  void FinishError(const char* code, const char* message) {
    fl_method_call_respond_error(pending_, code, message, nullptr, nullptr);
    ClearPending();
  }

  void ClearPending() {
    g_clear_object(&pending_);
    g_clear_object(&cancellable_);
    g_clear_pointer(&output_, g_bytes_unref);
  }

  GtkWindow* window_;
  bool active_ = true;
  FlMethodChannel* image_channel_ = nullptr;
  FlMethodChannel* project_channel_ = nullptr;
  GtkFileChooserNative* dialog_ = nullptr;
  FlMethodCall* pending_ = nullptr;
  GCancellable* cancellable_ = nullptr;
  GBytes* output_ = nullptr;
  Operation kind_ = Operation::kImage;
  std::string extension_;
};

}  // namespace

void blanko_register_native_file_bridge(GtkWindow* window, FlView* view) {
  auto* bridge = new std::shared_ptr<NativeFileBridge>(
      std::make_shared<NativeFileBridge>(window, view));
  g_object_set_data_full(
      G_OBJECT(window), "blanko-native-files", bridge, [](gpointer value) {
        delete static_cast<std::shared_ptr<NativeFileBridge>*>(value);
      });
  g_signal_connect(window, "destroy",
                   G_CALLBACK(+[](GtkWidget*, gpointer value) {
                     static_cast<NativeFileBridge*>(value)->Shutdown();
                   }),
                   bridge->get());
}
