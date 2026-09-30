import 'dart:convert';

import 'package:nija/core/platform_info.dart';
import 'package:nija/data/settings/app_settings.dart';
import 'package:nija/data/settings/secret_store.dart';
import 'package:nija_core/nija_core.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// Persists [AppSettings]: plain values in `SharedPreferences`, anything a
/// `ConfigField` marks sensitive plus the passphrase in the OS credential
/// store via [SecretStore].
class SettingsRepository {
  /// Creates a repository.
  SettingsRepository(this._prefs, this._secure, this._registry);

  final SharedPreferences _prefs;
  final SecretStore _secure;
  final BackendRegistry _registry;

  static const _kDeviceId = 'device_id';
  static const _kPassphrase = 'e2e_passphrase';
  static const _kRegisteredScope = 'registered_scope';
  static const _kDeviceKeys = 'device_keys';
  static const _kKeyring = 'e2e_keyring';
  static String _kAdminKey(String scope) => 'admin_key.$scope';
  static String _kAdminPub(String scope) => 'admin_pub.$scope';
  static String _kSeenVersions(String scope) => 'seen_versions.$scope';
  static String _kSecret(String backendId, String key) =>
      'backend.$backendId.$key';
  static String _kPlain(String backendId, String key) =>
      'backend.$backendId.$key';

  /// Loads settings, creating the device id on first launch.
  ///
  /// With [includeSecrets] false, sensitive backend fields are left out so
  /// the call never touches the OS credential store; bootstrap uses this so
  /// a keychain prompt cannot block the first frame; secrets are merged in
  /// afterwards with [loadBackendValues].
  Future<AppSettings> load({bool includeSecrets = true}) async {
    // The device id is an identifier, not a credential: plain preferences.
    var deviceId = _prefs.getString(_kDeviceId);
    if (deviceId == null || deviceId.isEmpty) {
      deviceId = const Uuid().v4();
      await _prefs.setString(_kDeviceId, deviceId);
    }
    final backendId = _prefs.getString('backend_id') ?? 'memory';
    return AppSettings(
      deviceId: deviceId,
      deviceName:
          _prefs.getString('device_name') ?? PlatformInfo.defaultDeviceName,
      onboarded: _prefs.getBool('onboarded') ?? false,
      backendId: backendId,
      backendValues: await loadBackendValues(
        backendId,
        includeSecrets: includeSecrets,
      ),
      encryptionEnabled: _prefs.getBool('encryption_enabled') ?? false,
      pollIntervalSeconds: _prefs.getInt('poll_interval_seconds') ?? 5,
      retentionDays: _prefs.getInt('retention_days') ?? 30,
      maxInlineKb: _prefs.getInt('max_inline_kb') ?? 1024,
      captureImages: _prefs.getBool('capture_images') ?? true,
      writeIncomingToClipboard: _prefs.getBool('write_incoming') ?? false,
      autoStart: _prefs.getBool('auto_start') ?? false,
      launchHidden: _prefs.getBool('launch_hidden') ?? false,
      hotkeyEnabled: _prefs.getBool('hotkey_enabled') ?? true,
      themeMode: _prefs.getString('theme_mode') ?? 'system',
      capturePaused: _prefs.getBool('capture_paused') ?? false,
      skipSensitive: _prefs.getBool('skip_sensitive') ?? true,
      skipSecretLike: _prefs.getBool('skip_secret_like') ?? false,
      hideAfterCopy: _prefs.getBool('hide_after_copy') ?? false,
      trayRecents: _prefs.getBool('tray_recents') ?? true,
    );
  }

  /// Reads the stored form values for [backendId] (secrets from keychain
  /// unless [includeSecrets] is false).
  Future<Map<String, String>> loadBackendValues(
    String backendId, {
    bool includeSecrets = true,
  }) async {
    final d = _registry.descriptor(backendId);
    if (d == null) return const {};
    final out = <String, String>{};
    for (final f in d.configSchema) {
      if (f.isSensitive && !includeSecrets) continue;
      final v = f.isSensitive
          ? await _secure.read(_kSecret(backendId, f.key))
          : _prefs.getString(_kPlain(backendId, f.key));
      if (v != null && v.isNotEmpty) {
        out[f.key] = v;
      } else if (f.defaultValue != null) {
        out[f.key] = f.defaultValue.toString();
      }
    }
    return out;
  }

  /// Persists everything in [s].
  Future<void> save(AppSettings s) async {
    await _prefs.setString(_kDeviceId, s.deviceId);
    await _prefs.setString('device_name', s.deviceName);
    await _prefs.setBool('onboarded', s.onboarded);
    await _prefs.setString('backend_id', s.backendId);
    await _prefs.setBool('encryption_enabled', s.encryptionEnabled);
    await _prefs.setInt('poll_interval_seconds', s.pollIntervalSeconds);
    await _prefs.setInt('retention_days', s.retentionDays);
    await _prefs.setInt('max_inline_kb', s.maxInlineKb);
    await _prefs.setBool('capture_images', s.captureImages);
    await _prefs.setBool('write_incoming', s.writeIncomingToClipboard);
    await _prefs.setBool('auto_start', s.autoStart);
    await _prefs.setBool('launch_hidden', s.launchHidden);
    await _prefs.setBool('hotkey_enabled', s.hotkeyEnabled);
    await _prefs.setString('theme_mode', s.themeMode);
    await _prefs.setBool('capture_paused', s.capturePaused);
    await _prefs.setBool('skip_sensitive', s.skipSensitive);
    await _prefs.setBool('skip_secret_like', s.skipSecretLike);
    await _prefs.setBool('hide_after_copy', s.hideAfterCopy);
    await _prefs.setBool('tray_recents', s.trayRecents);
    await saveBackendValues(s.backendId, s.backendValues);
  }

  /// Persists form values for one backend, routing secrets to the keychain.
  Future<void> saveBackendValues(
    String backendId,
    Map<String, String> values,
  ) async {
    final d = _registry.descriptor(backendId);
    if (d == null) return;
    for (final f in d.configSchema) {
      final v = values[f.key]?.trim() ?? '';
      if (f.isSensitive) {
        await _secure.write(_kSecret(backendId, f.key), v);
      } else {
        if (v.isEmpty) {
          await _prefs.remove(_kPlain(backendId, f.key));
        } else {
          await _prefs.setString(_kPlain(backendId, f.key), v);
        }
      }
    }
  }

  /// Removes every stored value (and secret) for [backendId].
  Future<void> clearBackendValues(String backendId) =>
      saveBackendValues(backendId, const {});

  /// `AppSettings.backendScope` of the group this device is known to have
  /// registered with, or `null`. Lets the engine tell "first run" apart from
  /// "my row was deleted".
  String? loadRegisteredScope() => _prefs.getString(_kRegisteredScope);

  /// Stores or clears (`null`) the registered scope.
  Future<void> saveRegisteredScope(String? scope) => scope == null
      ? _prefs.remove(_kRegisteredScope)
      : _prefs.setString(_kRegisteredScope, scope);

  // --- Encryption keyring ---------------------------------------------------

  /// Every passphrase version this device holds, `{version: passphrase}`.
  /// Migrates a pre-0.2 single passphrase to version 1.
  Future<Map<int, String>> loadKeyring() async {
    final raw = await _secure.read(_kKeyring);
    if (raw != null && raw.isNotEmpty) {
      final m = jsonDecode(raw) as Map<String, Object?>;
      return {for (final e in m.entries) int.parse(e.key): e.value! as String};
    }
    final legacy = await _secure.read(_kPassphrase);
    if (legacy != null && legacy.isNotEmpty) {
      final ring = {1: legacy};
      await saveKeyring(ring);
      await _secure.delete(_kPassphrase);
      return ring;
    }
    return {};
  }

  /// Persists the keyring (empty map clears it).
  Future<void> saveKeyring(Map<int, String> ring) => _secure.write(
    _kKeyring,
    ring.isEmpty
        ? null
        : jsonEncode({for (final e in ring.entries) '${e.key}': e.value}),
  );

  /// Newest passphrase, or `null`.
  Future<String?> loadPassphrase() async {
    final ring = await loadKeyring();
    if (ring.isEmpty) return null;
    return ring[ring.keys.reduce((a, b) => a > b ? a : b)];
  }

  /// Replaces the keyring with a single, manually entered passphrase
  /// (`null` clears everything).
  Future<void> savePassphrase(String? passphrase) => saveKeyring(
    passphrase == null || passphrase.isEmpty ? {} : {1: passphrase},
  );

  // --- Device identity and group trust --------------------------------------

  /// This device's signing / box keys (`DeviceKeys.encode`), or `null` on
  /// first run.
  Future<String?> loadDeviceKeys() => _secure.read(_kDeviceKeys);

  /// Stores the device keys.
  Future<void> saveDeviceKeys(String encoded) =>
      _secure.write(_kDeviceKeys, encoded);

  /// Admin key for [scope] (`AdminKey.encode`) when this device manages
  /// that group.
  Future<String?> loadAdminKey(String scope) => _secure.read(_kAdminKey(scope));

  /// Stores or clears (`null`) the admin key for [scope].
  Future<void> saveAdminKey(String scope, String? encoded) =>
      _secure.write(_kAdminKey(scope), encoded);

  /// Pinned admin public key for [scope], or `null` (legacy group).
  String? loadTrustedAdminPub(String scope) =>
      _prefs.getString(_kAdminPub(scope));

  /// Pins or clears (`null`) the admin public key for [scope].
  Future<void> saveTrustedAdminPub(String scope, String? pub) => pub == null
      ? _prefs.remove(_kAdminPub(scope))
      : _prefs.setString(_kAdminPub(scope), pub);

  /// Highest membership version seen per device in [scope] (rollback
  /// detection across restarts).
  Map<String, int> loadSeenVersions(String scope) {
    final raw = _prefs.getString(_kSeenVersions(scope));
    if (raw == null) return {};
    final m = jsonDecode(raw) as Map<String, Object?>;
    return {for (final e in m.entries) e.key: e.value! as int};
  }

  /// Persists seen membership versions for [scope].
  Future<void> saveSeenVersions(String scope, Map<String, int> seen) =>
      _prefs.setString(_kSeenVersions(scope), jsonEncode(seen));

  /// Forgets everything tied to [scope]: admin key, pinned admin, versions.
  Future<void> clearGroupTrust(String scope) async {
    await saveAdminKey(scope, null);
    await saveTrustedAdminPub(scope, null);
    await _prefs.remove(_kSeenVersions(scope));
  }
}
