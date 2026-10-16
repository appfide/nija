import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    registerClipboardHints(messenger: flutterViewController.engine.binaryMessenger)

    super.awakeFromNib()
  }

  /// Exposes the pasteboard "do not record" hints (nspasteboard.org) that
  /// password managers set, so Dart can skip such content before reading it.
  private func registerClipboardHints(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "com.appfide.nija/clipboard", binaryMessenger: messenger)
    let flagged: [NSPasteboard.PasteboardType] = [
      NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"),
      NSPasteboard.PasteboardType("org.nspasteboard.TransientType"),
    ]
    // Set on content that arrived from another Apple device through
    // Universal Clipboard.
    let remote = NSPasteboard.PasteboardType("com.apple.is-remote-clipboard")
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "isSensitive":
        let types = NSPasteboard.general.types ?? []
        result(types.contains { flagged.contains($0) })
      case "isRemote":
        result((NSPasteboard.general.types ?? []).contains(remote))
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
