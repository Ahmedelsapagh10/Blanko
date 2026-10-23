#include "native_file_gateway.h"

#include <flutter/standard_method_codec.h>

#include <algorithm>
#include <array>
#include <cstdint>
#include <cwchar>
#include <mutex>
#include <string>
#include <thread>
#include <utility>
#include <vector>

namespace {

using flutter::EncodableMap;
using flutter::EncodableValue;
using Microsoft::WRL::ComPtr;

constexpr UINT kFileCompleted = WM_APP + 0x424;
constexpr size_t kImageLimit = 16 * 1024 * 1024;
constexpr size_t kProjectLimit = 64 * 1024 * 1024;
constexpr size_t kExportLimit = 128 * 1024 * 1024;
constexpr DWORD kChunkSize = 64 * 1024;

class FileHandle {
 public:
  explicit FileHandle(HANDLE value) : value_(value) {}
  ~FileHandle() { Close(); }
  FileHandle(const FileHandle&) = delete;
  FileHandle& operator=(const FileHandle&) = delete;
  HANDLE get() const { return value_; }
  bool valid() const { return value_ != INVALID_HANDLE_VALUE; }
  bool Close() {
    if (!valid()) return true;
    const HANDLE value = value_;
    value_ = INVALID_HANDLE_VALUE;
    return CloseHandle(value) != FALSE;
  }

 private:
  HANDLE value_;
};

template <typename T>
const T* Argument(const EncodableMap* arguments, const char* key) {
  if (!arguments) return nullptr;
  const auto entry = arguments->find(EncodableValue(key));
  return entry == arguments->end() ? nullptr : std::get_if<T>(&entry->second);
}

bool HasExtension(const std::wstring& path, const wchar_t* extension) {
  const size_t length = std::wcslen(extension);
  return path.size() >= length &&
         _wcsicmp(path.c_str() + path.size() - length, extension) == 0;
}

std::wstring FileName(const std::wstring& path) {
  const size_t separator = path.find_last_of(L"/\\");
  return separator == std::wstring::npos ? path : path.substr(separator + 1);
}

std::string Utf8FileName(const std::wstring& path) {
  const std::wstring name = FileName(path);
  const int length = WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS,
                                        name.data(), static_cast<int>(name.size()),
                                        nullptr, 0, nullptr, nullptr);
  if (length <= 0) return "Imported image";
  std::string result(static_cast<size_t>(length), '\0');
  if (WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, name.data(),
                          static_cast<int>(name.size()), result.data(), length,
                          nullptr, nullptr) == 0) return "Imported image";
  return result;
}

std::wstring FileSystemPath(const std::wstring& path) {
  if (path.rfind(L"\\\\?\\", 0) == 0) return path;
  if (path.rfind(L"\\\\", 0) == 0) return L"\\\\?\\UNC\\" + path.substr(2);
  return L"\\\\?\\" + path;
}

std::wstring SuggestedName(const std::string& value,
                           const std::wstring& extension) {
  const int length = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS,
                                        value.data(), static_cast<int>(value.size()),
                                        nullptr, 0);
  std::wstring name;
  if (length > 0) {
    name.resize(static_cast<size_t>(length));
    MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value.data(),
                        static_cast<int>(value.size()), name.data(), length);
  }
  for (wchar_t& character : name) {
    if (character < 32 || std::wcschr(L"<>:\"/\\|?*", character)) character = L'_';
  }
  if (name.size() > 120) {
    name.resize(120);
    if (name.back() >= 0xd800 && name.back() <= 0xdbff) name.pop_back();
  }
  while (!name.empty() && (name.back() == L'.' || name.back() == L' ')) {
    name.pop_back();
  }
  if (name.empty()) name = L"Blanko";
  if (!HasExtension(name, (L"." + extension).c_str())) name += L"." + extension;
  return name;
}

bool ReadBounded(const std::wstring& path, size_t limit,
                 std::vector<uint8_t>* bytes, std::string* error) {
  FileHandle file(CreateFileW(FileSystemPath(path).c_str(), GENERIC_READ,
                              FILE_SHARE_READ, nullptr, OPEN_EXISTING,
                              FILE_FLAG_SEQUENTIAL_SCAN, nullptr));
  LARGE_INTEGER size{};
  if (!file.valid() || GetFileType(file.get()) != FILE_TYPE_DISK ||
      !GetFileSizeEx(file.get(), &size)) {
    *error = "Could not open the selected file. Check permissions and retry.";
    return false;
  }
  if (size.QuadPart <= 0 || static_cast<uint64_t>(size.QuadPart) > limit) {
    *error = "The selected file must contain between 1 byte and " +
             std::to_string(limit / 1024 / 1024) + " MiB.";
    return false;
  }
  bytes->resize(static_cast<size_t>(size.QuadPart));
  size_t offset = 0;
  while (offset < bytes->size()) {
    const DWORD requested = static_cast<DWORD>(
        std::min<size_t>(kChunkSize, bytes->size() - offset));
    DWORD count = 0;
    if (!ReadFile(file.get(), bytes->data() + offset, requested, &count, nullptr) ||
        count == 0) {
      *error = "Could not read the complete file. Retry after it finishes downloading.";
      return false;
    }
    offset += count;
  }
  return true;
}

std::string ImageMimeType(const std::vector<uint8_t>& bytes,
                          const std::wstring& path) {
  constexpr std::array<uint8_t, 8> png = {137, 80, 78, 71, 13, 10, 26, 10};
  if (HasExtension(path, L".png") && bytes.size() >= png.size() &&
      std::equal(png.begin(), png.end(), bytes.begin())) return "image/png";
  if ((HasExtension(path, L".jpg") || HasExtension(path, L".jpeg")) &&
      bytes.size() >= 3 && bytes[0] == 0xff && bytes[1] == 0xd8 &&
      bytes[2] == 0xff) return "image/jpeg";
  return {};
}

bool WriteAtomically(const std::wstring& path,
                      const std::vector<uint8_t>& bytes, std::string* error) {
  GUID identifier{};
  wchar_t identifier_text[40]{};
  if (FAILED(CoCreateGuid(&identifier)) ||
      StringFromGUID2(identifier, identifier_text, 40) == 0) {
    *error = "Could not prepare the export. Please retry.";
    return false;
  }
  const size_t separator = path.find_last_of(L"\\/");
  if (separator == std::wstring::npos) {
    *error = "Choose a destination folder for the export.";
    return false;
  }
  // Stage beside the destination so a failed write never truncates its content.
  const std::wstring temporary = FileSystemPath(
      path.substr(0, separator + 1) + L".blanko-" + identifier_text + L".tmp");
  FileHandle file(CreateFileW(temporary.c_str(), GENERIC_WRITE, 0, nullptr,
                              CREATE_NEW, FILE_ATTRIBUTE_NORMAL, nullptr));
  if (!file.valid()) {
    *error = "Could not create the export. Check folder permissions and free space.";
    return false;
  }
  bool complete = true;
  size_t offset = 0;
  while (offset < bytes.size()) {
    const DWORD requested = static_cast<DWORD>(
        std::min<size_t>(kChunkSize, bytes.size() - offset));
    DWORD count = 0;
    if (!WriteFile(file.get(), bytes.data() + offset, requested, &count, nullptr) ||
        count == 0) {
      complete = false;
      break;
    }
    offset += count;
  }
  if (complete && !FlushFileBuffers(file.get())) complete = false;
  if (!file.Close()) complete = false;
  if (complete) {
    complete = MoveFileExW(temporary.c_str(), FileSystemPath(path).c_str(),
                            MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH) != FALSE;
  }
  if (!complete) {
    DeleteFileW(temporary.c_str());
    *error = "Could not finish saving. Check free space and destination permissions, then retry.";
  }
  return complete;
}

}  // namespace

struct NativeFileGateway::Completion {
  EncodableValue value;
  std::string error_code;
  std::string error_message;
};

struct NativeFileGateway::WorkerState {
  std::mutex mutex;
  bool active = true;
  HWND owner = nullptr;
  std::unique_ptr<Completion> completion;
};

std::shared_ptr<NativeFileGateway> NativeFileGateway::Create(
    HWND owner, flutter::BinaryMessenger* messenger) {
  auto gateway = std::shared_ptr<NativeFileGateway>(new NativeFileGateway(owner));
  gateway->RegisterChannels(messenger);
  return gateway;
}

NativeFileGateway::NativeFileGateway(HWND owner)
    : owner_(owner), worker_state_(std::make_shared<WorkerState>()) {
  worker_state_->owner = owner;
}

NativeFileGateway::~NativeFileGateway() { Shutdown(); }

void NativeFileGateway::RegisterChannels(flutter::BinaryMessenger* messenger) {
  const auto* codec = &flutter::StandardMethodCodec::GetInstance();
  image_channel_ = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      messenger, "blanko/image_picker", codec);
  project_channel_ = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      messenger, "blanko/project_files", codec);
  const std::weak_ptr<NativeFileGateway> weak = shared_from_this();
  for (const bool image : {true, false}) {
    auto* channel = image ? image_channel_.get() : project_channel_.get();
    channel->SetMethodCallHandler(
        [weak, image](const flutter::MethodCall<EncodableValue>& call,
                      std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
          if (auto self = weak.lock()) self->HandleCall(call, std::move(result), image);
          else result->Error("unavailable", "The editor window is closed.");
        });
  }
}

void NativeFileGateway::HandleCall(
    const flutter::MethodCall<EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<EncodableValue>> result,
    bool image_channel) {
  const std::string& method = call.method_name();
  const bool save = method == "saveFile";
  if (image_channel ? method != "pickImage" : (method != "pickProject" && !save)) {
    result->NotImplemented();
    return;
  }
  if (stopped_) {
    result->Error("unavailable", "The editor window is closed.");
    return;
  }
  if (pending_) {
    result->Error("busy", "Another file operation is in progress.");
    return;
  }
  const auto* arguments = call.arguments()
                              ? std::get_if<EncodableMap>(call.arguments())
                              : nullptr;
  const auto* bytes = Argument<std::vector<uint8_t>>(arguments, "bytes");
  const auto* extension = Argument<std::string>(arguments, "extension");
  const auto* name = Argument<std::string>(arguments, "suggestedName");
  if (save && (!bytes || bytes->empty() || bytes->size() > kExportLimit ||
               !extension || (*extension != "png" && *extension != "wboard") ||
               !name || name->size() > 4096)) {
    result->Error("invalid_file", "Unsupported file type or file exceeds the 128 MiB limit.");
    return;
  }
  pending_ = std::move(result);
  ComPtr<IFileDialog> dialog;
  HRESULT status = CoCreateInstance(save ? CLSID_FileSaveDialog : CLSID_FileOpenDialog,
                                    nullptr, CLSCTX_INPROC_SERVER,
                                    IID_PPV_ARGS(dialog.GetAddressOf()));
  DWORD options = 0;
  if (SUCCEEDED(status)) status = dialog->GetOptions(&options);
  if (SUCCEEDED(status)) {
    options |= FOS_FORCEFILESYSTEM | FOS_PATHMUSTEXIST | FOS_NOCHANGEDIR;
    options |= save ? FOS_OVERWRITEPROMPT | FOS_STRICTFILETYPES : FOS_FILEMUSTEXIST;
    status = dialog->SetOptions(options);
  }
  const COMDLG_FILTERSPEC image_filter[] = {{L"PNG or JPEG images", L"*.png;*.jpg;*.jpeg"}};
  const COMDLG_FILTERSPEC project_filter[] = {{L"Blanko project", L"*.wboard"}};
  const COMDLG_FILTERSPEC png_filter[] = {{L"PNG image", L"*.png"}};
  if (SUCCEEDED(status)) {
    const COMDLG_FILTERSPEC* filter = image_channel ? image_filter
        : (save && *extension == "png" ? png_filter : project_filter);
    status = dialog->SetFileTypes(1, filter);
  }
  if (SUCCEEDED(status) && save) {
    const std::wstring wide_extension(extension->begin(), extension->end());
    status = dialog->SetDefaultExtension(wide_extension.c_str());
    if (SUCCEEDED(status)) {
      status = dialog->SetFileName(SuggestedName(*name, wide_extension).c_str());
    }
  }
  if (SUCCEEDED(status)) {
    status = dialog->SetTitle(save ? L"Save Blanko export"
                                  : (image_channel ? L"Import image" : L"Open Blanko project"));
  }
  if (SUCCEEDED(status)) {
    dialog_ = dialog;
    status = dialog->Show(owner_);
    dialog_.Reset();
  }
  // A modal dialog pumps messages; the editor may have shut down during Show.
  if (stopped_) return;
  if (status == HRESULT_FROM_WIN32(ERROR_CANCELLED)) {
    Finish({save ? EncodableValue(false) : EncodableValue(), {}, {}});
    return;
  }
  ComPtr<IShellItem> item;
  PWSTR selected_path = nullptr;
  if (SUCCEEDED(status)) status = dialog->GetResult(item.GetAddressOf());
  if (SUCCEEDED(status)) status = item->GetDisplayName(SIGDN_FILESYSPATH, &selected_path);
  std::wstring path = selected_path ? selected_path : L"";
  CoTaskMemFree(selected_path);
  if (FAILED(status) || path.empty()) {
    Finish({EncodableValue(), "unavailable", "The file dialog could not complete. Please retry."});
    return;
  }
  if ((!save && !image_channel && !HasExtension(path, L".wboard")) ||
      (save && !HasExtension(path, (L"." + std::wstring(extension->begin(), extension->end())).c_str()))) {
    Finish({EncodableValue(), "invalid_file", "Choose a file with the requested extension."});
    return;
  }
  auto state = worker_state_;
  std::vector<uint8_t> output = save ? *bytes : std::vector<uint8_t>();
  std::thread([state, path = std::move(path), output = std::move(output),
               save, image_channel]() mutable {
    auto completion = std::make_unique<Completion>();
    std::string error;
    if (save) {
      if (WriteAtomically(path, output, &error)) completion->value = EncodableValue(true);
      else completion->error_code = "write_failed";
    } else {
      std::vector<uint8_t> input;
      if (!ReadBounded(path, image_channel ? kImageLimit : kProjectLimit, &input, &error)) {
        completion->error_code = "read_failed";
      } else if (image_channel) {
        const std::string mime = ImageMimeType(input, path);
        if (mime.empty()) {
          completion->error_code = "invalid_file";
          error = "Select a PNG or JPEG image with matching file content.";
        } else {
          EncodableMap image;
          image.emplace(EncodableValue("bytes"), EncodableValue(std::move(input)));
          image.emplace(EncodableValue("filename"), EncodableValue(Utf8FileName(path)));
          image.emplace(EncodableValue("mimeType"), EncodableValue(mime));
          completion->value = EncodableValue(std::move(image));
        }
      } else {
        completion->value = EncodableValue(std::move(input));
      }
    }
    completion->error_message = std::move(error);
    std::lock_guard<std::mutex> lock(state->mutex);
    if (!state->active) return;
    state->completion = std::move(completion);
    PostMessageW(state->owner, kFileCompleted, 0, 0);
  }).detach();
}

bool NativeFileGateway::HandleWindowMessage(UINT message) {
  if (message != kFileCompleted) return false;
  std::unique_ptr<Completion> completion;
  {
    std::lock_guard<std::mutex> lock(worker_state_->mutex);
    completion = std::move(worker_state_->completion);
  }
  if (completion && !stopped_) Finish(std::move(*completion));
  return true;
}

void NativeFileGateway::Finish(Completion completion) {
  auto result = std::move(pending_);
  if (!result) return;
  if (completion.error_code.empty()) result->Success(completion.value);
  else result->Error(completion.error_code, completion.error_message);
}

void NativeFileGateway::Shutdown() {
  if (stopped_) return;
  stopped_ = true;
  {
    std::lock_guard<std::mutex> lock(worker_state_->mutex);
    worker_state_->active = false;
    worker_state_->completion.reset();
  }
  if (image_channel_) image_channel_->SetMethodCallHandler(nullptr);
  if (project_channel_) project_channel_->SetMethodCallHandler(nullptr);
  if (dialog_) dialog_->Close(HRESULT_FROM_WIN32(ERROR_CANCELLED));
  if (pending_) Finish({EncodableValue(), "unavailable", "The editor closed before the file operation completed."});
}
