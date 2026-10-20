import Cocoa
import FlutterMacOS
import UniformTypeIdentifiers

class MainFlutterWindow: NSWindow, NSWindowDelegate {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    let imageChannel = FlutterMethodChannel(
      name: "blanko/image_picker", binaryMessenger: flutterViewController.engine.binaryMessenger)
    imageChannel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "pickImage" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let window = self else {
        result(FlutterError(code: "unavailable", message: "Editor window is unavailable.", details: nil))
        return
      }
      let panel = NSOpenPanel()
      if #available(macOS 11.0, *) {
        panel.allowedContentTypes = [.png, .jpeg, .webP, .gif, .bmp]
      } else {
        panel.allowedFileTypes = ["png", "jpg", "jpeg", "webp", "gif", "bmp"]
      }
      panel.allowsMultipleSelection = false
      panel.canChooseDirectories = false
      panel.beginSheetModal(for: window) { response in
        guard response == .OK, let url = panel.url else { result(nil); return }
        let scoped = url.startAccessingSecurityScopedResource()
        DispatchQueue.global(qos: .userInitiated).async {
          defer { if scoped { url.stopAccessingSecurityScopedResource() } }
          do {
            let data = try Data(contentsOf: url)
            let mime: String
            switch url.pathExtension.lowercased() {
            case "png": mime = "image/png"
            case "jpg", "jpeg": mime = "image/jpeg"
            case "webp": mime = "image/webp"
            case "gif": mime = "image/gif"
            case "bmp": mime = "image/bmp"
            default: mime = "application/octet-stream"
            }
            DispatchQueue.main.async {
              result(["bytes": FlutterStandardTypedData(bytes: data),
                      "filename": url.lastPathComponent, "mimeType": mime])
            }
          } catch {
            DispatchQueue.main.async {
              result(FlutterError(code: "read_failed", message: "Could not read selected image: \(error.localizedDescription)", details: nil))
            }
          }
        }
      }
    }

    super.awakeFromNib()
    delegate = self
  }

  func windowShouldClose(_ sender: NSWindow) -> Bool {
    // Keep the editor visible while Flutter asynchronously saves or cancels exit.
    NSApplication.shared.terminate(sender)
    return false
  }
}
