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
      guard !window.productFilePending else {
        result(FlutterError(code: "busy", message: "Another file operation is in progress.", details: nil))
        return
      }
      window.productFilePending = true
      let panel = NSOpenPanel()
      if #available(macOS 11.0, *) {
        panel.allowedContentTypes = [.png, .jpeg, .webP, .gif, .bmp]
      } else {
        panel.allowedFileTypes = ["png", "jpg", "jpeg", "webp", "gif", "bmp"]
      }
      panel.allowsMultipleSelection = false
      panel.canChooseDirectories = false
      panel.beginSheetModal(for: window) { response in
        guard response == .OK, let url = panel.url else {
          window.productFilePending = false
          result(nil)
          return
        }
        let scoped = url.startAccessingSecurityScopedResource()
        DispatchQueue.global(qos: .userInitiated).async {
          defer { if scoped { url.stopAccessingSecurityScopedResource() } }
          do {
            let data = try window.readImport(url, maximumBytes: 16 * 1024 * 1024)
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
              window.productFilePending = false
              result(["bytes": FlutterStandardTypedData(bytes: data),
                      "filename": url.lastPathComponent, "mimeType": mime])
            }
          } catch {
            DispatchQueue.main.async {
              window.productFilePending = false
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
          let data = try readImport(url, maximumBytes: 64 * 1024 * 1024)
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

  private func readImport(_ url: URL, maximumBytes: Int) throws -> Data {
    let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
    guard values.isRegularFile == true else {
      throw NSError(domain: "Blanko", code: 1, userInfo: [
        NSLocalizedDescriptionKey: "Select a regular file."])
    }
    if let size = values.fileSize, size > maximumBytes {
      throw NSError(domain: "Blanko", code: 2, userInfo: [
        NSLocalizedDescriptionKey: "File exceeds the \(maximumBytes / 1024 / 1024) MiB import limit."])
    }
    guard let stream = InputStream(url: url) else {
      throw NSError(domain: "Blanko", code: 3, userInfo: [
        NSLocalizedDescriptionKey: "Could not open the selected file."])
    }
    stream.open()
    defer { stream.close() }
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 64 * 1024)
    while true {
      let count = stream.read(&buffer, maxLength: buffer.count)
      if count < 0 { throw stream.streamError ?? NSError(domain: "Blanko", code: 4) }
      if count == 0 { break }
      guard count <= maximumBytes - data.count else {
        throw NSError(domain: "Blanko", code: 2, userInfo: [
          NSLocalizedDescriptionKey: "File exceeds the \(maximumBytes / 1024 / 1024) MiB import limit."])
      }
      data.append(contentsOf: buffer.prefix(count))
    }
    guard !data.isEmpty else {
      throw NSError(domain: "Blanko", code: 5, userInfo: [
        NSLocalizedDescriptionKey: "The selected file is empty."])
    }
    return data
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
