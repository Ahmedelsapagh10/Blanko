import Cocoa
import FlutterMacOS
import UniformTypeIdentifiers

class MainFlutterWindow: NSWindow, NSWindowDelegate {
  private var productFilePending = false
  private let maximumProductFileBytes = 128 * 1024 * 1024

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

    let projectChannel = FlutterMethodChannel(
      name: "blanko/project_files", binaryMessenger: flutterViewController.engine.binaryMessenger)
    projectChannel.setMethodCallHandler { [weak self] call, result in
      guard let window = self else {
        result(FlutterError(code: "unavailable", message: "Editor window is unavailable.", details: nil))
        return
      }
      switch call.method {
      case "pickProject": window.pickProject(result: result)
      case "saveFile": window.saveProductFile(arguments: call.arguments, result: result)
      default: result(FlutterMethodNotImplemented)
      }
    }

    super.awakeFromNib()
    delegate = self
  }

  private func pickProject(result: @escaping FlutterResult) {
    guard !productFilePending else {
      result(FlutterError(code: "busy", message: "Another file operation is in progress.", details: nil))
      return
    }
    productFilePending = true
    let panel = NSOpenPanel()
    panel.allowedFileTypes = ["wboard"]
    panel.allowsMultipleSelection = false
    panel.canChooseDirectories = false
    panel.beginSheetModal(for: self) { [self] response in
      guard response == .OK, let url = panel.url else {
        productFilePending = false
        result(nil)
        return
      }
      let scoped = url.startAccessingSecurityScopedResource()
      DispatchQueue.global(qos: .userInitiated).async { [self] in
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
          let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
          guard values.isRegularFile == true,
                let size = values.fileSize, size > 0, size <= maximumProductFileBytes else {
            throw NSError(domain: "Blanko", code: 1, userInfo: [
              NSLocalizedDescriptionKey: "Project file must contain between 1 byte and 128 MiB."])
          }
          let data = try Data(contentsOf: url, options: .mappedIfSafe)
          guard data.count <= maximumProductFileBytes else {
            throw NSError(domain: "Blanko", code: 1, userInfo: [
              NSLocalizedDescriptionKey: "Project file exceeds the 128 MiB limit."])
          }
          DispatchQueue.main.async { [self] in
            productFilePending = false
            result(FlutterStandardTypedData(bytes: data))
          }
        } catch {
          DispatchQueue.main.async { [self] in
            productFilePending = false
            result(FlutterError(code: "read_failed", message: "Could not read project: \(error.localizedDescription)", details: nil))
          }
        }
      }
    }
  }

  private func saveProductFile(arguments: Any?, result: @escaping FlutterResult) {
    guard !productFilePending else {
      result(FlutterError(code: "busy", message: "Another file operation is in progress.", details: nil))
      return
    }
    guard let arguments = arguments as? [String: Any],
          let typedData = arguments["bytes"] as? FlutterStandardTypedData,
          let name = arguments["suggestedName"] as? String,
          let fileExtension = arguments["extension"] as? String,
          ["png", "wboard"].contains(fileExtension),
          !typedData.data.isEmpty, typedData.data.count <= maximumProductFileBytes else {
      result(FlutterError(code: "invalid_file", message: "Unsupported file type or file exceeds the 128 MiB limit.", details: nil))
      return
    }
    productFilePending = true
    let panel = NSSavePanel()
    panel.allowedFileTypes = [fileExtension]
    panel.canCreateDirectories = true
    panel.isExtensionHidden = false
    let safeName = name.components(separatedBy: CharacterSet(charactersIn: "/\\\0")).joined(separator: "_")
    panel.nameFieldStringValue = safeName.isEmpty ? "Blanko.\(fileExtension)" : safeName
    panel.beginSheetModal(for: self) { [self] response in
      guard response == .OK, let url = panel.url else {
        productFilePending = false
        result(false)
        return
      }
      let scoped = url.startAccessingSecurityScopedResource()
      DispatchQueue.global(qos: .userInitiated).async { [self] in
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
          try typedData.data.write(to: url, options: .atomic)
          DispatchQueue.main.async { [self] in
            productFilePending = false
            result(true)
          }
        } catch {
          DispatchQueue.main.async { [self] in
            productFilePending = false
            result(FlutterError(code: "write_failed", message: "Could not save file: \(error.localizedDescription)", details: nil))
          }
        }
      }
    }
  }

  func windowShouldClose(_ sender: NSWindow) -> Bool {
    // Keep the editor visible while Flutter asynchronously saves or cancels exit.
    NSApplication.shared.terminate(sender)
    return false
  }
}
