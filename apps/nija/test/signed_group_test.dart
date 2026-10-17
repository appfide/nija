// Controller-level (no widgets) scenario for encrypted, signed groups:
// pairing delivers keys and a sealed passphrase, clips are sealed and
// signed, forged rows are ignored, rotation locks out removed devices.
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nija/data/local/database.dart';
import 'package:nija/data/settings/app_settings.dart';
import 'package:nija/features/sync/sync_controller.dart';
import 'package:nija/providers.dart';
import 'package:nija_core/nija_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _TestDb extends MemoryBackend {
  _TestDb(MemoryStore shared) : super(shared: shared);
  static const descriptorStatic = BackendDescriptor(
    id: 'testdb',
    displayName: 'Test database',
    description: 'in-memory',
    docsPath: 'docs/backends/memory.md',
    supportsRealtime: true,
    configSchema: <ConfigField>[
      ConfigField(key: 'url', label: 'URL', kind: ConfigFieldKind.url),
      ConfigField(key: 'token', label: 'Token', kind: ConfigFieldKind.secret),
    ],
  );
  @override
  BackendDescriptor get descriptor => descriptorStatic;
}

class _Node {
  _Node(this.c, this.db, this.prefs);
  final ProviderContainer c;
  final AppDatabase db;
  final SharedPreferences prefs;
  SyncController get sync => c.read(syncControllerProvider.notifier);
  SyncStatus get status => c.read(syncControllerProvider);
  Future<void> dispose() async {
    c.dispose();
    await db.close();
  }
}

/// Each node gets its own SharedPreferences store so scopes never bleed.
Future<_Node> _boot(AppSettings seed, MemoryStore shared) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final registry = BackendRegistry.builtIn()
    ..register(_TestDb.descriptorStatic, () => _TestDb(shared));
  final db = AppDatabase.withExecutor(NativeDatabase.memory());
  final c = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      databaseProvider.overrideWithValue(db),
      backendRegistryProvider.overrideWithValue(registry),
      settingsProvider.overrideWith(() => SeededSettings(seed)),
    ],
  );
  await c.read(settingsRepositoryProvider).save(seed);
  return _Node(c, db, prefs);
}

ClipItem _clip(String text, {required String device}) => ClipItem.create(
  id: 'clip-${text.hashCode}-${DateTime.now().microsecondsSinceEpoch}',
  deviceId: device,
  deviceName: device,
  type: ClipContentType.text,
  content: text,
  contentHash: sha256Hex(text),
  sizeBytes: text.length,
  now: DateTime.now().toUtc(),
);

Future<List<String>> _history(_Node n) async =>
    (await n.c.read(localStoreProvider).watchHistory().first)
        .map((r) => r.item.content)
        .toList();

const _host = AppSettings(
  deviceId: 'host-id',
  deviceName: 'Host',
  onboarded: true,
  backendId: 'testdb',
  backendValues: {'url': 'https://db.example.com', 'token': 't0k3n'},
  encryptionEnabled: true,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('encrypted signed group end to end', () async {
    final shared = MemoryStore();
    final host = await _boot(_host, shared);
    await host.c.read(settingsRepositoryProvider).savePassphrase('v1 pass');
    await host.sync.start();
    await host.sync.secureGroup();
    expect(host.sync.isAdmin, isTrue);
    expect(host.status.selfVerified, isTrue);
    expect(host.status.keyVersion, 1);

    // --- pairing with sealed passphrase -----------------------------------
    final session = await host.sync.createPairing(
      role: DeviceRole.full,
      includePassphrase: true,
    );
    expect(session.passphraseIncluded, isTrue);
    expect(session.grantsAdmin, isFalse);
    expect(session.code, isNot(contains('v1 pass')));
    final pending = shared.devices[session.deviceId]!;
    expect(pending.isSigned, isTrue);
    expect(pending.hasKeys, isTrue);
    expect(pending.keyEnvelope, isNot(contains('v1 pass')));
    expect(
      await ClipSigning.verifyMembership(pending, host.sync.adminPublicKey!),
      isTrue,
    );

    final joiner = await _boot(
      const AppSettings(
        deviceId: 'old-id',
        deviceName: 'Phone',
        onboarded: true,
      ),
      shared,
    );
    await joiner.sync.start();
    final payload = await PairingCodec.open(session.code, session.pin);
    expect(payload.needsPassphrase, isFalse);
    expect(payload.isSignedGroup, isTrue);
    await joiner.sync.joinFromPairing(payload);
    // The settings listener restarts the engine; give it a moment.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(joiner.sync.isSignedGroup, isTrue);
    expect(joiner.sync.isAdmin, isFalse);
    expect(joiner.status.selfVerified, isTrue);
    expect(joiner.status.keyVersion, 1);
    final repoJ = joiner.c.read(settingsRepositoryProvider);
    expect(await repoJ.loadKeyring(), {1: 'v1 pass'});
    expect(await repoJ.loadDeviceKeys(), payload.deviceKeys);
    expect(joiner.c.read(settingsProvider).encryptionEnabled, isTrue);

    // --- clips: sealed, signed, both directions ---------------------------
    await host.c
        .read(localStoreProvider)
        .capture(_clip('from host', device: 'host-id'));
    await host.sync.syncNow();
    await joiner.sync.syncNow();
    expect(await _history(joiner), contains('from host'));
    await joiner.c
        .read(localStoreProvider)
        .capture(_clip('from phone', device: session.deviceId));
    await joiner.sync.syncNow();
    await host.sync.syncNow();
    expect(await _history(host), contains('from phone'));
    for (final i in shared.items.values) {
      expect(i.encrypted, isTrue);
      expect(i.isSigned, isTrue);
      expect(i.keyVersion, 1);
      expect(i.content, isNot(contains('from')));
    }

    // --- forgery from the database side -----------------------------------
    expect(joiner.sync.canEditMembership, isFalse);
    expect(() => joiner.sync.blockDevice('host-id'), throwsStateError);
    expect(() => joiner.sync.rotatePassphrase(), throwsStateError);
    shared.devices[session.deviceId] = shared.devices[session.deviceId]!
        .copyWith(admin: true);
    shared.devices['host-id'] = shared.devices['host-id']!.copyWith(
      status: DeviceStatus.blocked,
    );
    await host.sync.refreshDevices();
    expect(host.status.phase, isNot(SyncPhase.revoked));
    expect(host.sync.trustedDeviceIds, isNot(contains(session.deviceId)));
    // A forged clip "from the phone" is dropped by the host.
    final forged = _clip('forged', device: session.deviceId);
    shared.items[forged.id] = forged;
    await host.sync.syncNow();
    expect(await _history(host), isNot(contains('forged')));
    // Admin restores the truth.
    await host.sync.unblockDevice(session.deviceId);
    await host.sync.unblockDevice('host-id');
    expect(
      host.sync.trustedDeviceIds,
      containsAll(['host-id', session.deviceId]),
    );

    // --- an ex-member and rotation -----------------------------------------
    final exSession = await host.sync.createPairing(
      role: DeviceRole.full,
      includePassphrase: true,
    );
    final ex = await _boot(
      const AppSettings(
        deviceId: 'ex-old',
        deviceName: 'Tablet',
        onboarded: true,
      ),
      shared,
    );
    await ex.sync.start();
    await ex.sync.joinFromPairing(
      await PairingCodec.open(exSession.code, exSession.pin),
    );
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(await ex.c.read(settingsRepositoryProvider).loadKeyring(), {
      1: 'v1 pass',
    });
    await ex.sync.syncNow();
    expect(await _history(ex), containsAll(['from host', 'from phone']));

    // Removing hands the remaining devices a fresh key on its own.
    await host.sync.removeDevice(exSession.deviceId);
    expect(host.status.keyVersion, 2);
    await joiner.sync.refreshDevices();
    final ringJ = await repoJ.loadKeyring();
    expect(ringJ.keys, containsAll([1, 2]));
    expect(joiner.status.keyVersion, 2);
    expect(
      shared.devices[exSession.deviceId]!.keyVersion,
      1,
      reason: 'no v2 envelope',
    );

    await host.c
        .read(localStoreProvider)
        .capture(_clip('after rotation', device: 'host-id'));
    await host.sync.syncNow();
    await joiner.sync.syncNow();
    expect(await _history(joiner), contains('after rotation'));
    expect(shared.items.values.where((i) => i.keyVersion == 2).length, 1);

    // The removed tablet (its client wiped credentials), even a rogue copy
    // that kept v1 cannot read v2: prove via a raw ring.
    final rogueRing = await CipherRing.fromPassphrases(
      {1: 'v1 pass'},
      keyScope: joiner.c.read(settingsProvider).cipherKeyScope,
    );
    final v2Item = shared.items.values.firstWhere((i) => i.keyVersion == 2);
    expect(
      () => rogueRing.current!.open(v2Item),
      throwsA(isA<CipherException>()),
    );
    // The tablet's own client notices the removal on its next check-in,
    // wipes its credentials and keys, and falls back to local-only.
    await ex.sync.refreshDevices();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(ex.c.read(settingsProvider).backendId, 'memory');
    expect(ex.c.read(settingsProvider).encryptionEnabled, isFalse);
    expect(ex.c.read(revocationProvider)?.reason, 'removed');
    expect(await ex.c.read(settingsRepositoryProvider).loadKeyring(), isEmpty);
    expect(ex.sync.isSignedGroup, isFalse);

    // Old history stays readable on the joiner through its keyring.
    expect(
      await _history(joiner),
      containsAll(['from host', 'after rotation']),
    );

    await ex.dispose();
    await joiner.dispose();
    await host.dispose();
  });

  test('a pairing code that grants admin makes the joiner an admin', () async {
    final shared = MemoryStore();
    final host = await _boot(_host.copyWith(encryptionEnabled: false), shared);
    await host.sync.start();
    await host.sync.secureGroup();
    final session = await host.sync.createPairing(
      role: DeviceRole.full,
      grantAdmin: true,
    );
    expect(session.grantsAdmin, isTrue);
    final joiner = await _boot(
      const AppSettings(deviceId: 'j', deviceName: 'J', onboarded: true),
      shared,
    );
    await joiner.sync.start();
    await joiner.sync.joinFromPairing(
      await PairingCodec.open(session.code, session.pin),
    );
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(joiner.sync.isAdmin, isTrue);
    expect(joiner.sync.adminFingerprint, host.sync.adminFingerprint);
    // The new admin can manage, and its signatures verify on the host.
    await joiner.sync.blockDevice('host-id');
    await host.sync.refreshDevices();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(host.c.read(revocationProvider)?.reason, 'blocked');
    expect(host.c.read(settingsProvider).backendId, 'memory');
    await joiner.dispose();
    await host.dispose();
  });

  test(
    'removing a device can delete its clips and re-keys the group',
    () async {
      final shared = MemoryStore();
      final host = await _boot(
        _host.copyWith(encryptionEnabled: false),
        shared,
      );
      await host.sync.start();
      await host.sync.secureNewGroup();
      Future<_Node> join(String id) async {
        final session = await host.sync.createPairing(
          role: DeviceRole.full,
          includePassphrase: true,
        );
        final n = await _boot(
          AppSettings(deviceId: id, deviceName: id, onboarded: true),
          shared,
        );
        await n.sync.start();
        await n.sync.joinFromPairing(
          await PairingCodec.open(session.code, session.pin),
        );
        await Future<void>.delayed(const Duration(milliseconds: 300));
        return n;
      }

      final phone = await join('phone');
      final tablet = await join('tablet');
      final phoneId = phone.c.read(settingsProvider).deviceId;
      await phone.c
          .read(localStoreProvider)
          .capture(_clip('copied on the phone', device: phoneId));
      await phone.sync.syncNow();
      await tablet.sync.syncNow();
      await host.sync.syncNow();
      expect(await _history(tablet), contains('copied on the phone'));
      final before = host.status.keyVersion;

      await host.sync.removeDevice(phoneId, deleteClips: true);
      expect(host.status.keyVersion, before + 1);
      expect(await _history(host), isNot(contains('copied on the phone')));

      await tablet.sync.refreshDevices();
      await tablet.sync.syncNow();
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(await _history(tablet), isNot(contains('copied on the phone')));
      expect(tablet.status.keyVersion, before + 1);
      await phone.dispose();
      await tablet.dispose();
      await host.dispose();
    },
  );

  test('trusting an admin that started over brings a member back', () async {
    final shared = MemoryStore();
    final host = await _boot(_host.copyWith(encryptionEnabled: false), shared);
    await host.sync.start();
    await host.sync.secureNewGroup();
    final session = await host.sync.createPairing(
      role: DeviceRole.full,
      includePassphrase: true,
      grantAdmin: true,
    );
    final joiner = await _boot(
      const AppSettings(deviceId: 'j', deviceName: 'Phone', onboarded: true),
      shared,
    );
    await joiner.sync.start();
    await joiner.sync.joinFromPairing(
      await PairingCodec.open(session.code, session.pin),
    );
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(joiner.sync.isAdmin, isTrue);

    // The host loses its admin key and secures the group again.
    final scope = host.c.read(settingsProvider).backendScope;
    await host.c.read(settingsRepositoryProvider).clearGroupTrust(scope);
    await host.sync.restart();
    await host.sync.secureGroup();
    await host.sync.rotatePassphrase();
    final newPub = host.sync.adminPublicKey!;
    await host.c
        .read(localStoreProvider)
        .capture(_clip('after starting over', device: 'host-id'));
    await host.sync.syncNow();

    await joiner.sync.refreshDevices();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final ask = joiner.c.read(pendingTrustProvider);
    expect(ask?.adminPub, newPub);
    expect(ask?.replacesPinned, isTrue);
    expect(ask?.adminDeviceName, 'Host');
    expect(await _history(joiner), isNot(contains('after starting over')));

    await joiner.sync.trustAdmin(newPub);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(joiner.status.selfVerified, isTrue);
    expect(joiner.status.waitingForKey, isFalse);
    expect(joiner.sync.isAdmin, isFalse, reason: 'the old admin key is gone');
    expect(await _history(joiner), contains('after starting over'));
    await joiner.dispose();
    await host.dispose();
  });

  test(
    'joining a signed group without the sealed passphrase asks for it',
    () async {
      final shared = MemoryStore();
      final host = await _boot(_host, shared);
      await host.c
          .read(settingsRepositoryProvider)
          .savePassphrase('typed pass');
      await host.sync.start();
      await host.sync.secureGroup();
      final session = await host.sync.createPairing(role: DeviceRole.full);
      expect(session.passphraseIncluded, isFalse);
      final payload = await PairingCodec.open(session.code, session.pin);
      expect(payload.needsPassphrase, isTrue);
      final joiner = await _boot(
        const AppSettings(deviceId: 'j', deviceName: 'J', onboarded: true),
        shared,
      );
      await joiner.sync.start();
      expect(() => joiner.sync.joinFromPairing(payload), throwsStateError);
      await joiner.sync.joinFromPairing(payload, passphrase: 'typed pass');
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await host.c
          .read(localStoreProvider)
          .capture(_clip('hello', device: 'host-id'));
      await host.sync.syncNow();
      await joiner.sync.syncNow();
      expect(await _history(joiner), contains('hello'));
      await joiner.dispose();
      await host.dispose();
    },
  );

  group('default security', _defaultSecurityTests);
}

void _defaultSecurityTests() {
  test('secureNewGroup encrypts with a random passphrase and signs', () async {
    final shared = MemoryStore();
    final host = await _boot(_host.copyWith(encryptionEnabled: false), shared);
    await host.sync.start();
    expect(host.sync.isSignedGroup, isFalse);
    await host.sync.secureNewGroup();
    final s = host.c.read(settingsProvider);
    expect(s.encryptionEnabled, isTrue);
    final pass = await host.sync.revealPassphrase();
    expect(pass, isNotNull);
    expect(pass!.length, greaterThanOrEqualTo(40), reason: '32 random bytes');
    expect(host.sync.isSignedGroup, isTrue);
    expect(host.sync.isAdmin, isTrue);
    expect(host.status.selfVerified, isTrue);
    expect(host.status.keyVersion, 1);
    // Idempotent: a second call changes nothing.
    final fp = host.sync.adminFingerprint;
    await host.sync.secureNewGroup();
    expect(host.sync.adminFingerprint, fp);
    expect(await host.sync.revealPassphrase(), pass);
    // Clips are sealed from the first push.
    await host.c
        .read(localStoreProvider)
        .capture(_clip('secret', device: 'host-id'));
    await host.sync.syncNow();
    expect(shared.items.values.single.encrypted, isTrue);
    expect(shared.items.values.single.isSigned, isTrue);
    // A device pairing in gets the passphrase sealed and can read it.
    final session = await host.sync.createPairing(
      role: DeviceRole.full,
      includePassphrase: true,
    );
    final joiner = await _boot(
      const AppSettings(deviceId: 'j', deviceName: 'J', onboarded: true),
      shared,
    );
    await joiner.sync.start();
    await joiner.sync.joinFromPairing(
      await PairingCodec.open(session.code, session.pin),
    );
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await joiner.sync.syncNow();
    expect(await _history(joiner), ['secret']);
    await joiner.dispose();
    await host.dispose();
  });

  test(
    'the admin lets a member clear the database, then makes it admin',
    () async {
      final shared = MemoryStore();
      final host = await _boot(
        _host.copyWith(encryptionEnabled: false),
        shared,
      );
      await host.sync.start();
      await host.sync.secureGroup();
      final session = await host.sync.createPairing(role: DeviceRole.full);
      final joiner = await _boot(
        const AppSettings(deviceId: 'j', deviceName: 'J', onboarded: true),
        shared,
      );
      await joiner.sync.start();
      await joiner.sync.joinFromPairing(
        await PairingCodec.open(session.code, session.pin),
      );
      await Future<void>.delayed(const Duration(milliseconds: 300));
      final id = joiner.c.read(settingsProvider).deviceId;
      expect(joiner.sync.canDeleteRemoteHistory, isFalse);
      await expectLater(joiner.sync.deleteRemoteHistory(), throwsStateError);

      await host.sync.setDevicePermissions(id, {DevicePermission.clearHistory});
      await joiner.sync.refreshDevices();
      expect(joiner.sync.canDeleteRemoteHistory, isTrue);
      expect(joiner.sync.isAdmin, isFalse);
      final old = _clip('old', device: 'host-id');
      shared.items[old.id] = old;
      expect(await joiner.sync.deleteRemoteHistory(), 1);
      expect(shared.items, isEmpty);

      await host.sync.makeAdmin(id);
      await joiner.sync.refreshDevices();
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(joiner.sync.isAdmin, isTrue);
      expect(joiner.sync.adminFingerprint, host.sync.adminFingerprint);
      await joiner.dispose();
      await host.dispose();
    },
  );

  test(
    'a member whose admin is lost starts a new group and leads it',
    () async {
      final shared = MemoryStore();
      final host = await _boot(_host, shared);
      await host.c.read(settingsRepositoryProvider).savePassphrase('old pass');
      await host.sync.start();
      await host.sync.secureGroup();
      final session = await host.sync.createPairing(
        role: DeviceRole.full,
        includePassphrase: true,
      );
      final joiner = await _boot(
        const AppSettings(deviceId: 'j', deviceName: 'J', onboarded: true),
        shared,
      );
      await joiner.sync.start();
      await joiner.sync.joinFromPairing(
        await PairingCodec.open(session.code, session.pin),
      );
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(joiner.sync.isAdmin, isFalse);
      final oldAdmin = host.sync.adminFingerprint;

      await joiner.sync.startNewGroup();
      final id = joiner.c.read(settingsProvider).deviceId;
      expect(joiner.sync.isAdmin, isTrue);
      expect(joiner.sync.isSignedGroup, isTrue);
      expect(joiner.sync.adminFingerprint, isNot(oldAdmin));
      expect(shared.devices.keys, [id]);
      expect(
        await joiner.c.read(settingsRepositoryProvider).loadPassphrase(),
        isNot('old pass'),
      );

      // The old admin finds itself removed and forgets the credentials.
      await host.sync.refreshDevices();
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(host.c.read(revocationProvider)?.reason, 'removed');
      expect(host.c.read(settingsProvider).backendId, 'memory');
      await joiner.dispose();
      await host.dispose();
    },
  );

  test('leaving a group removes the row and forgets the group', () async {
    final shared = MemoryStore();
    final host = await _boot(_host.copyWith(encryptionEnabled: false), shared);
    await host.sync.start();
    await host.sync.secureGroup();
    expect(host.sync.hasOtherAdmin, isFalse);
    final repo = host.c.read(settingsRepositoryProvider);
    final scope = host.c.read(settingsProvider).backendScope;

    await host.sync.leaveGroup();

    expect(shared.devices.containsKey('host-id'), isFalse);
    expect(host.c.read(settingsProvider).backendId, 'memory');
    expect(host.c.read(settingsProvider).backendValues, isEmpty);
    expect(await repo.loadAdminKey(scope), isNull);
    expect(repo.loadTrustedAdminPub(scope), isNull);
    expect(host.sync.isAdmin, isFalse);
    expect(host.status.phase, isNot(SyncPhase.error));
    await host.dispose();
  });

  test('concurrent restarts never leave two engines running', () async {
    final shared = MemoryStore();
    final host = await _boot(_host.copyWith(encryptionEnabled: false), shared);
    await host.sync.start();
    // Fire several overlapping restarts (settings listener + explicit).
    await Future.wait([
      host.sync.restart(),
      host.sync.restart(),
      host.c
          .read(settingsProvider.notifier)
          .update(
            (x) => x.copyWith(deviceName: 'Renamed'),
          ),
      host.sync.restart(),
    ]);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(host.status.phase, SyncPhase.idle);
    // Exactly one registration for this device and it reflects the rename.
    expect(shared.devices.keys.where((k) => k == 'host-id').length, 1);
    expect(shared.devices['host-id']!.name, 'Renamed');
    // One heartbeat per membership check: a further sync does not duplicate.
    await host.sync.syncNow();
    expect(host.sync.knownDevices.length, 1);
    await host.dispose();
  });
}
