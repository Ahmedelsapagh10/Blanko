import Flutter
import UIKit
import UniformTypeIdentifiers

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate, UIDocumentPickerDelegate {
  private let maximumBytes = 128 * 1024 * 1024
  private var fileResult: FlutterResult?
  private var fileKind: String?
  private var exportDirectory: URL?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Public export location; private Boards/assets remain in Application Support.
    if let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
      do {
        try FileManager.default.createDirectory(at: documents.appendingPathComponent("Exports", isDirectory: true), withIntermediateDirectories: true)
      } catch {
        NSLog("Blanko export folder unavailable: %@", error.localizedDescription)
      }
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    for name in ["blanko/image_picker", "blanko/project_files"] {
      FlutterMethodChannel(name: name, binaryMessenger: engineBridge.applicationRegistrar.messenger())
        .setMethodCallHandler { [weak self] call, result in
          guard let self = self else {
            result(FlutterError(code: "unavailable", message: "Editor is unavailable.", details: nil))
            return
          }
          self.handleFile(call, result: result)
        }
    }
  }

  private func handleFile(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard ["pickImage", "pickProject", "saveFile"].contains(call.method) else {
      result(FlutterMethodNotImplemented)
      return
    }
    guard fileResult == nil else {
      result(FlutterError(code: "busy", message: "Another file operation is in progress.", details: nil))
      return
    }
    guard let presenter = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
      .flatMap({ $0.windows }).first(where: { $0.isKeyWindow })?.rootViewController,
      presenter.presentedViewController == nil else {
      result(FlutterError(code: "unavailable", message: "The document picker cannot be presented right now.", details: nil))
      return
    }
    fileResult = result
    fileKind = call.method
    if call.method == "saveFile" {
      guard let arguments = call.arguments as? [String: Any],
        let typed = arguments["bytes"] as? FlutterStandardTypedData,
        let name = arguments["suggestedName"] as? String,
        let ext = arguments["extension"] as? String,
        ["png", "wboard"].contains(ext), !typed.data.isEmpty, typed.data.count <= maximumBytes else {
        finish(FlutterError(code: "invalid_file", message: "Unsupported file type or file exceeds the 128 MiB limit.", details: nil))
        return
      }
      let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
      exportDirectory = directory
      var safeName = name.components(separatedBy: CharacterSet(charactersIn: "/\\\0")).joined(separator: "_")
      if safeName.isEmpty { safeName = "Blanko.\(ext)" }
      if !(safeName.lowercased().hasSuffix(".\(ext)")) { safeName += ".\(ext)" }
      let url = directory.appendingPathComponent(safeName)
      DispatchQueue.global(qos: .userInitiated).async { [self] in
        do {
          try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
          try typed.data.write(to: url, options: .atomic)
          DispatchQueue.main.async { [self] in
            guard fileResult != nil, UIApplication.shared.applicationState == .active,
              presenter.view.window != nil, presenter.presentedViewController == nil else {
              finish(FlutterError(code: "unavailable", message: "Return to the editor and retry the export.", details: nil))
              return
            }
            let picker: UIDocumentPickerViewController
            if #available(iOS 14.0, *) {
              picker = UIDocumentPickerViewController(forExporting: [url], asCopy: true)
            } else {
              picker = UIDocumentPickerViewController(url: url, in: .exportToService)
            }
            picker.delegate = self
            presenter.present(picker, animated: true)
          }
        } catch {
          DispatchQueue.main.async { [self] in
            finish(FlutterError(code: "write_failed", message: "Could not prepare export: \(error.localizedDescription)", details: nil))
          }
        }
      }
    } else {
      // Projects have no registered UTI; permit data and validate the chosen extension.
      let picker: UIDocumentPickerViewController
      if #available(iOS 14.0, *) {
        let types: [UTType] = call.method == "pickImage" ? [.png, .jpeg] : [.data]
        picker = UIDocumentPickerViewController(forOpeningContentTypes: types)
      } else {
        let types = call.method == "pickImage" ? ["public.png", "public.jpeg"] : ["public.data"]
        picker = UIDocumentPickerViewController(documentTypes: types, in: .open)
      }
      picker.allowsMultipleSelection = false
      picker.delegate = self
      presenter.present(picker, animated: true)
    }
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    finish(fileKind == "saveFile" ? false : nil)
  }

  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    guard fileResult != nil else { return }
    guard let url = urls.first else {
      finish(FlutterError(code: "read_failed", message: "No file was selected.", details: nil))
      return
    }
    if fileKind == "saveFile" { finish(true); return }
    let image = fileKind == "pickImage"
    let importLimit = (image ? 16 : 64) * 1024 * 1024
    let ext = url.pathExtension.lowercased()
    guard image ? ["png", "jpg", "jpeg"].contains(ext) : ext == "wboard" else {
      finish(FlutterError(code: "invalid_file", message: image ? "Select a PNG or JPEG image." : "Select a .wboard project file.", details: nil))
      return
    }
    DispatchQueue.global(qos: .userInitiated).async { [self] in
      let scoped = url.startAccessingSecurityScopedResource()
      defer { if scoped { url.stopAccessingSecurityScopedResource() } }
      var coordinationError: NSError?
      var payload: Any?
      var readError: Error?
      NSFileCoordinator(filePresenter: nil).coordinate(readingItemAt: url, options: [], error: &coordinationError) { readableURL in
        do {
          guard let stream = InputStream(url: readableURL) else {
            throw NSError(domain: "Blanko", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not open selected file."])
          }
          stream.open()
          defer { stream.close() }
          var data = Data()
          var buffer = [UInt8](repeating: 0, count: 64 * 1024)
          while true {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count < 0 { throw stream.streamError ?? NSError(domain: "Blanko", code: 2) }
            if count == 0 { break }
            guard data.count + count <= importLimit else {
              throw NSError(domain: "Blanko", code: 3, userInfo: [NSLocalizedDescriptionKey: "File exceeds the \(importLimit / 1024 / 1024) MiB import limit."])
            }
            data.append(contentsOf: buffer.prefix(count))
          }
          guard !data.isEmpty else {
            throw NSError(domain: "Blanko", code: 4, userInfo: [NSLocalizedDescriptionKey: "The selected file is empty."])
          }
          let bytes = FlutterStandardTypedData(bytes: data)
          payload = image ? ["bytes": bytes, "filename": url.lastPathComponent,
            "mimeType": ext == "png" ? "image/png" : "image/jpeg"] : bytes
        } catch { readError = error }
      }
      DispatchQueue.main.async { [self] in
        if let error = readError ?? coordinationError {
          finish(FlutterError(code: "read_failed", message: "Could not read selected file: \(error.localizedDescription)", details: nil))
        } else { finish(payload) }
      }
    }
  }

  private func finish(_ value: Any?) {
    let result = fileResult
    fileResult = nil
    fileKind = nil
    if let directory = exportDirectory {
      try? FileManager.default.removeItem(at: directory)
      exportDirectory = nil
    }
    result?(value)
  }
}
