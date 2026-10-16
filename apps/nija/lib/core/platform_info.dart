import 'dart:io';

/// Host platform helpers (no web support in this app).
abstract final class PlatformInfo {
  /// macOS, Windows or Linux: background capture, tray, hotkeys.
  static bool get isDesktop =>
      Platform.isMacOS || Platform.isWindows || Platform.isLinux;

  /// Android or iOS: foreground capture only.
  static bool get isMobile => Platform.isAndroid || Platform.isIOS;

  /// macOS or iOS: Universal Clipboard can bring in copies from other
  /// Apple devices.
  static bool get isApple => Platform.isMacOS || Platform.isIOS;

  /// Wire value stored in `devices.platform`.
  static String get name => Platform.operatingSystem;

  /// Best-effort default device name; the user can rename it in settings.
  static String get defaultDeviceName {
    if (Platform.isAndroid) return 'Android device';
    if (Platform.isIOS) return 'iPhone';
    final host = Platform.localHostname;
    return host.isEmpty ? name : host.split('.').first;
  }
}
