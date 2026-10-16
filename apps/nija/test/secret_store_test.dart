import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nija/data/settings/secret_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A keychain that can be made to hang (a pending SecurityAgent prompt) or
/// fail, with an in-memory store behind it.
class _Keychain extends FlutterSecureStorage {
  _Keychain();

  final Map<String, String> data = {};
  bool hang = false;
  bool fail = false;

  Future<T> _op<T>(T Function() run) {
    if (hang) return Completer<T>().future;
    if (fail) throw PlatformException(code: '-34018');
    return Future.value(run());
  }

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) => _op(() => data[key]);

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) => _op(() => value == null ? data.remove(key) : data[key] = value);

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) => _op(() => data.remove(key));
}

void main() {
  late _Keychain keychain;
  late SecretStore store;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    keychain = _Keychain();
    store = SecretStore(
      keychain,
      await SharedPreferences.getInstance(),
      timeout: const Duration(milliseconds: 20),
    );
  });

  test('reads and writes through the keychain', () async {
    await store.write('k', 'v');
    expect(keychain.data['k'], 'v');
    expect(await store.read('k'), 'v');
    expect(store.degraded.value, isFalse);
  });

  test('a failing keychain falls back to preferences', () async {
    keychain.fail = true;
    await store.write('k', 'v');
    expect(keychain.data, isEmpty);
    expect(await store.read('k'), 'v');
    expect(store.degraded.value, isTrue);
  });

  test(
    'a strict read that times out throws instead of returning null',
    () async {
      keychain.data['k'] = 'v';
      keychain.hang = true;
      expect(await store.read('k'), isNull);
      await expectLater(
        store.read('k', strict: true),
        throwsA(isA<SecretStoreTimeout>()),
      );
      // Not latched: once the prompt is answered, reads work again.
      keychain.hang = false;
      expect(await store.read('k', strict: true), 'v');
    },
  );

  test('a keychain answer drops a stale fallback copy', () async {
    keychain.fail = true;
    await store.write('k', 'written while unreachable');
    keychain
      ..fail = false
      ..data['k'] = 'original';
    expect(await store.read('k'), 'original');
    keychain.fail = true;
    expect(await store.read('k'), isNull);
  });

  test('an unconfirmed delete never resurfaces the old value', () async {
    keychain.data['k'] = 'old password';
    keychain.hang = true;
    await store.delete('k');
    keychain.hang = false;
    // Next launch: the keychain answers again and still holds the item.
    final next = SecretStore(
      keychain,
      await SharedPreferences.getInstance(),
      timeout: const Duration(milliseconds: 20),
    );
    expect(await next.read('k'), isNull);
    expect(keychain.data, isEmpty);
  });

  test('writing after an unconfirmed delete stores the new value', () async {
    keychain.data['k'] = 'old';
    keychain.hang = true;
    await store.delete('k');
    await store.write('k', 'new');
    expect(await store.read('k'), 'new');
    keychain.hang = false;
    expect(await store.read('k'), 'new');
    expect(keychain.data['k'], isNot('old'));
  });
}
