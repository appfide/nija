import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:nija/core/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Thrown by [SecretStore.read] with `strict: true` when the credential
/// store did not answer in time and there is no fallback copy, so the
/// caller cannot tell "missing" from "unreadable right now".
class SecretStoreTimeout implements Exception {
  /// Creates the exception.
  const SecretStoreTimeout(this.key);

  /// Key that could not be read.
  final String key;

  @override
  String toString() => 'SecretStoreTimeout: $key';
}

enum _Outcome { ok, timedOut, failed }

/// Credential storage. Uses the OS credential store (Keychain / Keystore /
/// DPAPI / libsecret); if that is unavailable on this machine (e.g. an
/// unsigned macOS build without keychain entitlements, or a Linux desktop
/// without a Secret Service) it falls back to app preferences and flags
/// [degraded] so Settings can warn the user.
///
/// Every call is bounded by [timeout]: on macOS an unsigned build whose
/// signature changed since the keychain item was created blocks in a
/// SecurityAgent prompt until the user answers, and the app must not hang.
///
/// A delete the credential store did not confirm is remembered and retried;
/// until it succeeds the stale value is never returned, so credentials the
/// app was told to forget cannot come back on the next launch.
class SecretStore {
  /// Creates a store. [timeout] bounds each credential-store call.
  SecretStore(this._secure, this._prefs, {this.timeout = defaultTimeout});

  final FlutterSecureStorage _secure;
  final SharedPreferences _prefs;
  static const _fallbackPrefix = 'secret_fallback.';
  static const _pendingDeletesKey = 'secret_pending_deletes';

  /// Default upper bound for one credential-store call.
  static const Duration defaultTimeout = Duration(seconds: 10);

  /// Upper bound for one credential-store call.
  final Duration timeout;

  final ValueNotifier<bool> _degraded = ValueNotifier(false);

  /// True once any secure-storage call has failed and the fallback is in use.
  ValueListenable<bool> get degraded => _degraded;

  /// Reads a secret. With [strict], a timeout with no fallback copy throws
  /// [SecretStoreTimeout] instead of returning `null`.
  Future<String?> read(String key, {bool strict = false}) async {
    if (_pendingDeletes.contains(key) && !await _retryDelete(key)) {
      return _fallback(key);
    }
    String? value;
    final outcome = await _call(
      () async => value = await _secure.read(key: key),
    );
    final fallback = _fallback(key);
    if (outcome == _Outcome.ok && value != null) {
      // The keychain is authoritative. A fallback copy written while it was
      // unreachable is stale and would win the next time it is.
      if (fallback != null) await _prefs.remove('$_fallbackPrefix$key');
      return value;
    }
    if (strict && outcome == _Outcome.timedOut && fallback == null) {
      throw SecretStoreTimeout(key);
    }
    return fallback;
  }

  /// Writes a secret (deletes when [value] is null/empty).
  Future<void> write(String key, String? value) async {
    if (value == null || value.isEmpty) return delete(key);
    final outcome = await _call(() => _secure.write(key: key, value: value));
    if (outcome == _Outcome.ok) {
      await _prefs.remove('$_fallbackPrefix$key');
      await _markDeleted(key, pending: false);
      return;
    }
    await _prefs.setString('$_fallbackPrefix$key', value);
  }

  /// Deletes a secret from both locations. When the credential store does
  /// not confirm, the delete is retried on later reads.
  Future<void> delete(String key) async {
    final outcome = await _call(() => _secure.delete(key: key));
    await _prefs.remove('$_fallbackPrefix$key');
    await _markDeleted(key, pending: outcome != _Outcome.ok);
  }

  String? _fallback(String key) => _prefs.getString('$_fallbackPrefix$key');

  Set<String> get _pendingDeletes =>
      (_prefs.getStringList(_pendingDeletesKey) ?? const []).toSet();

  Future<void> _markDeleted(String key, {required bool pending}) async {
    final keys = _pendingDeletes;
    if (pending ? !keys.add(key) : !keys.remove(key)) return;
    await _prefs.setStringList(_pendingDeletesKey, keys.toList()..sort());
  }

  Future<bool> _retryDelete(String key) async {
    if (await _call(() => _secure.delete(key: key)) != _Outcome.ok) {
      return false;
    }
    await _markDeleted(key, pending: false);
    return true;
  }

  Future<_Outcome> _call(Future<void> Function() op) async {
    try {
      await op().timeout(timeout);
      return _Outcome.ok;
    } on TimeoutException catch (e) {
      _fail(e);
      return _Outcome.timedOut;
    } on PlatformException catch (e) {
      _fail(e);
    } on MissingPluginException catch (e) {
      _fail(e);
    }
    return _Outcome.failed;
  }

  void _fail(Object e) {
    if (!_degraded.value) {
      log.w(
        'OS credential store unavailable, using app preferences fallback',
        error: e,
      );
      _degraded.value = true;
    }
  }
}
