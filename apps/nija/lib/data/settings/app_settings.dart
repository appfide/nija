import 'package:flutter/foundation.dart';
import 'package:nija_core/nija_core.dart';

/// User preferences. Backend secrets and the passphrase are **not** part of
/// this object's persisted form; see `SettingsRepository`.
@immutable
class AppSettings {
  /// Creates settings.
  const AppSettings({
    required this.deviceId,
    required this.deviceName,
    this.onboarded = false,
    this.backendId = 'memory',
    this.backendValues = const {},
    this.encryptionEnabled = false,
    this.pollIntervalSeconds = 5,
    this.retentionDays = 30,
    this.maxInlineKb = 1024,
    this.captureImages = true,
    this.writeIncomingToClipboard = false,
    this.autoStart = false,
    this.launchHidden = false,
    this.hotkeyEnabled = true,
    this.themeMode = 'system',
    this.capturePaused = false,
    this.skipSensitive = true,
    this.skipSecretLike = false,
    this.hideAfterCopy = false,
    this.trayRecents = true,
  });

  /// Stable id for this installation.
  final String deviceId;

  /// User-visible device name.
  final String deviceName;

  /// First-run wizard completed.
  final bool onboarded;

  /// Selected `BackendDescriptor.id`.
  final String backendId;

  /// Backend form values, secrets included (populated from secure storage).
  final Map<String, String> backendValues;

  /// Encrypt content before it leaves the device.
  final bool encryptionEnabled;

  /// Poll cadence for non-realtime backends.
  final int pollIntervalSeconds;

  /// Purge items older than this; 0 = keep forever.
  final int retentionDays;

  /// Largest image/file inlined as base64.
  final int maxInlineKb;

  /// Capture images from the clipboard.
  final bool captureImages;

  /// Put the newest incoming item onto this device's clipboard automatically.
  final bool writeIncomingToClipboard;

  /// Desktop: start at login.
  final bool autoStart;

  /// Desktop: start minimised to tray.
  final bool launchHidden;

  /// Desktop: global hotkey to open the window.
  final bool hotkeyEnabled;

  /// `system`, `light` or `dark`.
  final String themeMode;

  /// Capture is paused: nothing new is recorded or synced until resumed.
  final bool capturePaused;

  /// Honour the OS "sensitive / transient" clipboard hints set by password
  /// managers (macOS `ConcealedType`, Windows
  /// `ExcludeClipboardContentFromMonitorProcessing`, Android 13+
  /// `EXTRA_IS_SENSITIVE`) and never capture such content.
  final bool skipSensitive;

  /// Skip text that looks like a credential (API keys, tokens, private
  /// keys, connection strings with passwords).
  final bool skipSecretLike;

  /// Desktop: hide the window once a clip is copied from history, so the
  /// hotkey, pick, paste loop never needs a mouse.
  final bool hideAfterCopy;

  /// Desktop: list the newest clips in the tray menu for one-click copy.
  final bool trayRecents;

  /// Backend config derived from these settings.
  BackendConfig get backendConfig =>
      BackendConfig(backendId: backendId, values: backendValues);

  /// Key scope for the E2E cipher: ties the passphrase to backend + primary URL.
  String get cipherKeyScope => backendScope;

  /// Identifies one sync group: backend id + primary URL. Used for the
  /// cipher key scope and to remember that this device registered there.
  String get backendScope {
    final primary =
        backendValues['url'] ??
        backendValues['project_id'] ??
        backendValues['uri']?.split('@').last ??
        '';
    return '$backendId|$primary';
  }

  /// Whether a real (non local-only) backend is selected.
  bool get syncsRemotely => backendId != 'memory';

  /// Copy with fields replaced.
  AppSettings copyWith({
    String? deviceId,
    String? deviceName,
    bool? onboarded,
    String? backendId,
    Map<String, String>? backendValues,
    bool? encryptionEnabled,
    int? pollIntervalSeconds,
    int? retentionDays,
    int? maxInlineKb,
    bool? captureImages,
    bool? writeIncomingToClipboard,
    bool? autoStart,
    bool? launchHidden,
    bool? hotkeyEnabled,
    String? themeMode,
    bool? capturePaused,
    bool? skipSensitive,
    bool? skipSecretLike,
    bool? hideAfterCopy,
    bool? trayRecents,
  }) => AppSettings(
    deviceId: deviceId ?? this.deviceId,
    deviceName: deviceName ?? this.deviceName,
    onboarded: onboarded ?? this.onboarded,
    backendId: backendId ?? this.backendId,
    backendValues: backendValues ?? this.backendValues,
    encryptionEnabled: encryptionEnabled ?? this.encryptionEnabled,
    pollIntervalSeconds: pollIntervalSeconds ?? this.pollIntervalSeconds,
    retentionDays: retentionDays ?? this.retentionDays,
    maxInlineKb: maxInlineKb ?? this.maxInlineKb,
    captureImages: captureImages ?? this.captureImages,
    writeIncomingToClipboard:
        writeIncomingToClipboard ?? this.writeIncomingToClipboard,
    autoStart: autoStart ?? this.autoStart,
    launchHidden: launchHidden ?? this.launchHidden,
    hotkeyEnabled: hotkeyEnabled ?? this.hotkeyEnabled,
    themeMode: themeMode ?? this.themeMode,
    capturePaused: capturePaused ?? this.capturePaused,
    skipSensitive: skipSensitive ?? this.skipSensitive,
    skipSecretLike: skipSecretLike ?? this.skipSecretLike,
    hideAfterCopy: hideAfterCopy ?? this.hideAfterCopy,
    trayRecents: trayRecents ?? this.trayRecents,
  );

  /// Whether a backend/cipher rebuild is needed between [a] and [b].
  static bool syncAffecting(AppSettings a, AppSettings b) =>
      a.deviceId != b.deviceId ||
      a.backendId != b.backendId ||
      !mapEquals(a.backendValues, b.backendValues) ||
      a.encryptionEnabled != b.encryptionEnabled ||
      a.pollIntervalSeconds != b.pollIntervalSeconds ||
      a.deviceName != b.deviceName;
}
