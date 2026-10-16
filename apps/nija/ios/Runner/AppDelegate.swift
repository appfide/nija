import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "NijaClipboardHints") {
      registerClipboardHints(messenger: registrar.messenger())
    }
  }

  /// Tells Dart whether the pasteboard content arrived from another Apple
  /// device through Universal Clipboard. Reading the types does not read
  /// the content.
  private func registerClipboardHints(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "com.appfide.nija/clipboard", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "isRemote":
        result(UIPasteboard.general.types.contains("com.apple.is-remote-clipboard"))
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
