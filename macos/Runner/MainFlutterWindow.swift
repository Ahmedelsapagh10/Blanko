import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow, NSWindowDelegate {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
    delegate = self
  }

  func windowShouldClose(_ sender: NSWindow) -> Bool {
    // Keep the editor visible while Flutter asynchronously saves or cancels exit.
    NSApplication.shared.terminate(sender)
    return false
  }
}
