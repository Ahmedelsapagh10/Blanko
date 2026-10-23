#ifndef RUNNER_NATIVE_FILE_GATEWAY_H_
#define RUNNER_NATIVE_FILE_GATEWAY_H_

#include <windows.h>
#include <shobjidl.h>
#include <wrl/client.h>

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>

#include <memory>

// Owns the two product file channels for one editor window. Dialogs run on the
// platform thread; bounded disk I/O runs separately and replies on that thread.
class NativeFileGateway
    : public std::enable_shared_from_this<NativeFileGateway> {
 public:
  static std::shared_ptr<NativeFileGateway> Create(
      HWND owner, flutter::BinaryMessenger* messenger);
  ~NativeFileGateway();

  bool HandleWindowMessage(UINT message);
  void Shutdown();

 private:
  struct WorkerState;
  struct Completion;

  explicit NativeFileGateway(HWND owner);
  void RegisterChannels(flutter::BinaryMessenger* messenger);
  void HandleCall(const flutter::MethodCall<flutter::EncodableValue>& call,
                  std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                      result,
                  bool image_channel);
  void Finish(Completion completion);

  HWND owner_;
  bool stopped_ = false;
  std::shared_ptr<WorkerState> worker_state_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> image_channel_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> project_channel_;
  std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> pending_;
  Microsoft::WRL::ComPtr<IFileDialog> dialog_;
};

#endif  // RUNNER_NATIVE_FILE_GATEWAY_H_
