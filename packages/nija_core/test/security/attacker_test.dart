// Threat-model tests: an attacker who holds the database credentials (a
// stolen device, a leaked pairing code, a rogue former member) tries to
// impersonate devices, forge membership, swap keys and read new content.
import 'dart:async';

import 'package:nija_core/nija_core.dart';
import 'package:test/test.dart';

import '../helpers/fakes.dart';

/// One simulated device: its own backend handle, store, keys and engine.
class Node {
  Node._(this.id, this.name, this.backend, this.store, this.keys);

  static Future<Node> create(
    MemoryStore shared,
    String id,
    String name, {
    DeviceKeys? keys,
  }) async {
    final b = MemoryBackend(shared: shared);
    await b.connect(const BackendConfig.empty('memory'));
    return Node._(
      id,
      name,
      b,
      FakeLocalStore(),
      keys ?? await DeviceKeys.generate(),
    );
  }

  final String id;
  final String name;
  final MemoryBackend backend;
  final FakeLocalStore store;
  final DeviceKeys keys;
  SyncEngine? engine;
  final Map<int, String> passphrases = {};
  final List<String> log = [];
  final List<PendingTrust> trustPrompts = [];
  final List<String> adminKeys = [];

  Device get device => Device(
    id: id,
    name: name,
    platform: 'test',
    lastSeen: DateTime.now().toUtc(),
  );

  /// [encrypted] mirrors the app's "encryption on" setting: the engine gets
  /// a ring (possibly still empty, waiting for the envelope) only then.
  Future<SyncEngine> start({
    AdminKey? adminKey,
    String? trustedAdminPub,
    Map<int, String>? passphrases,
    bool assumeRegistered = false,
    bool encrypted = true,
    Duration keyResendDelay = const Duration(seconds: 30),
  }) async {
    if (passphrases != null) this.passphrases.addAll(passphrases);
    final ring = await CipherRing.fromPassphrases(
      this.passphrases,
      keyScope: 'test',
    );
    final e = SyncEngine(
      backend: backend,
      store: store,
      device: device,
      identity: keys,
      adminKey: adminKey,
      trustedAdminPub: trustedAdminPub,
      cipherRing: encrypted ? ring : null,
      onKeyReceived: (v, p) async {
        this.passphrases[v] = p;
        ring.add(v, await ClipCipher.fromPassphrase(p, keyScope: 'test'));
      },
      onAdminKeyReceived: (k) async => adminKeys.add(k),
      pollInterval: const Duration(hours: 1),
      heartbeatInterval: const Duration(hours: 1),
      keyResendDelay: keyResendDelay,
      assumeRegistered: assumeRegistered,
      logger: (m, {error}) => log.add(m),
    );
    e.trustRequests.listen(trustPrompts.add);
    await e.start();
    engine = e;
    return e;
  }

  Future<void> stop() async {
    await engine?.dispose();
    await backend.dispose();
  }

  /// Captures text and pushes it.
  Future<ClipItem> say(String text, {String? to}) async {
    final item = ClipItem.create(
      id: '${id}_${store.items.length}_${text.hashCode}',
      deviceId: id,
      deviceName: name,
      type: ClipContentType.text,
      content: text,
      contentHash: sha256Hex(text),
      sizeBytes: text.length,
      now: DateTime.now().toUtc(),
      targetDeviceId: to,
    );
    store.capture(item);
    await engine!.syncNow();
    return item;
  }

  Iterable<String> get received => store.items.values
      .where((i) => i.deviceId != id && !i.isDeleted)
      .map((i) => i.content);
}

/// A database whose device rows have no columns for the 0.5 grant fields.
class _LossyBackend extends MemoryBackend {
  _LossyBackend(MemoryStore shared) : super(shared: shared);

  @override
  Future<void> updateDevice(Device device) => super.updateDevice(
    Device.fromMap(
      device.toMap()..removeWhere((k, _) => Device.grantKeys.contains(k)),
    ),
  );
}

/// Direct database access, as an attacker would have with stolen creds.
class Attacker {
  Attacker(this.shared);
  final MemoryStore shared;

  DateTime get now => DateTime.now().toUtc();

  /// Writes a raw item straight into the database.
  void inject(ClipItem i) => shared.items[i.id] = i;

  Device row(String id) => shared.devices[id]!;
  void setRow(Device d) => shared.devices[d.id] = d;

  ClipItem raw(
    String text, {
    required String asDevice,
    String? to,
    String? sig,
    DateTime? at,
  }) => ClipItem.create(
    id: 'atk_${text.hashCode}_${at?.millisecondsSinceEpoch ?? 0}',
    deviceId: asDevice,
    deviceName: 'spoof',
    type: ClipContentType.text,
    content: text,
    contentHash: sha256Hex(text),
    sizeBytes: text.length,
    now: at ?? now,
    targetDeviceId: to,
  ).copyWith(sig: sig);
}

void main() {
  late MemoryStore shared;
  late Attacker atk;
  late Node admin;
  late Node member;
  late AdminKey adminKey;
  const pass1 = 'group passphrase v1';

  /// Signed, encrypted group: admin A invites member B through the normal
  /// pairing path (host generates B's keys and pre-signs the row).
  Future<void> setUpSignedGroup() async {
    shared = MemoryStore();
    atk = Attacker(shared);
    adminKey = await AdminKey.generate();
    admin = await Node.create(shared, 'A', 'Admin laptop');
    final memberKeys = await DeviceKeys.generate();
    member = await Node.create(shared, 'B', 'Phone', keys: memberKeys);
    // A secures the group (signs own row) then invites B.
    await admin.start(
      adminKey: adminKey,
      trustedAdminPub: adminKey.publicKey,
      passphrases: {1: pass1},
    );
    await admin.engine!.secureGroup();
    await admin.engine!.inviteDevice(
      id: 'B',
      role: DeviceRole.full,
      signPub: memberKeys.signPub,
      boxPub: memberKeys.boxPub,
      passphrase: pass1,
    );
    await member.start(trustedAdminPub: adminKey.publicKey);
  }

  group('signed group', () {
    setUp(setUpSignedGroup);
    tearDown(() async {
      await admin.stop();
      await member.stop();
    });

    test('after a database reset the admin signs its own row again', () async {
      await admin.stop();
      shared.devices.clear();
      shared.items.clear();
      admin = await Node.create(shared, 'A', 'Admin laptop', keys: admin.keys);
      await admin.start(
        adminKey: adminKey,
        trustedAdminPub: adminKey.publicKey,
        passphrases: {1: pass1},
        assumeRegistered: true,
      );
      expect(admin.engine!.status.phase, isNot(SyncPhase.revoked));
      final row = atk.row('A');
      expect(row.admin, isTrue);
      expect(
        await ClipSigning.verifyMembership(row, adminKey.publicKey),
        isTrue,
      );
      expect(admin.engine!.status.selfVerified, isTrue);
    });

    test('the admin grants and takes back a permission', () async {
      const perm = DevicePermission.clearHistory;
      await admin.engine!.setDevicePermissions('B', {perm});
      await member.engine!.refreshDevices();
      expect(member.engine!.permissions, {perm});
      expect(member.engine!.status.selfVerified, isTrue);
      expect(atk.row('B').may(perm), isTrue);

      await admin.engine!.setDevicePermissions('B', {});
      await member.engine!.refreshDevices();
      expect(member.engine!.permissions, isEmpty);
      expect(member.engine!.status.selfVerified, isTrue);
    });

    test('a member cannot grant itself a permission', () async {
      atk.setRow(
        atk.row('B').copyWith(permissions: {DevicePermission.clearHistory}),
      );
      await member.engine!.refreshDevices();
      expect(member.engine!.permissions, isEmpty);
      expect(member.engine!.status.selfVerified, isFalse);
      expect(
        () => member.engine!.setDevicePermissions('B', {
          DevicePermission.clearHistory,
        }),
        throwsStateError,
      );
    });

    test('making a member admin delivers the key sealed to it', () async {
      await admin.engine!.makeAdmin('B');
      final env = atk.row('B').adminEnvelope!;
      expect(env, isNot(contains(await adminKey.encode())));
      await member.engine!.refreshDevices();
      expect(member.adminKeys, [await adminKey.encode()]);
    });

    test('an admin envelope holding another key is ignored', () async {
      final mallory = await AdminKey.generate();
      final env = await KeyEnvelope.seal(
        passphrase: await mallory.encode(),
        version: 0,
        recipientBoxPub: member.keys.boxPub,
      );
      // Signed by the real admin, so only the key check can stop it.
      atk.setRow(
        await ClipSigning.signMembership(
          atk.row('B').copyWith(admin: true, adminEnvelope: env.encode()),
          adminKey,
        ),
      );
      await member.engine!.refreshDevices();
      expect(member.adminKeys, isEmpty);
    });

    test('a schema that drops the grant fields rolls the grant back', () async {
      final lossy = _LossyBackend(shared);
      await lossy.connect(const BackendConfig.empty('memory'));
      final e = SyncEngine(
        backend: lossy,
        store: FakeLocalStore(),
        device: admin.device,
        identity: admin.keys,
        adminKey: adminKey,
        trustedAdminPub: adminKey.publicKey,
        pollInterval: const Duration(hours: 1),
        heartbeatInterval: const Duration(hours: 1),
      );
      await e.start();
      await expectLater(
        e.setDevicePermissions('B', {DevicePermission.clearHistory}),
        throwsA(isA<BackendException>()),
      );
      await member.engine!.refreshDevices();
      expect(member.engine!.status.selfVerified, isTrue);
      expect(member.engine!.permissions, isEmpty);
      await e.dispose();
      await lossy.dispose();
    });

    test(
      'member receives the passphrase through its envelope, not the code',
      () async {
        expect(member.passphrases, {1: pass1});
        expect(member.engine!.status.selfVerified, isTrue);
        expect(member.engine!.status.keyVersion, 1);
        // Row stores only ciphertext of the passphrase.
        expect(atk.row('B').keyEnvelope, isNot(contains(pass1)));
      },
    );

    test('honest clips flow both ways, sealed and signed', () async {
      await admin.say('hello from A');
      await member.engine!.syncNow();
      expect(member.received, ['hello from A']);
      await member.say('hi from B');
      await admin.engine!.syncNow();
      expect(admin.received, ['hi from B']);
      for (final i in shared.items.values) {
        expect(i.encrypted, isTrue);
        expect(i.isSigned, isTrue);
        expect(i.content, isNot(contains('from')));
      }
    });

    test('an unsigned clip pretending to come from B is rejected', () async {
      atk.inject(atk.raw('forged', asDevice: 'B'));
      await admin.engine!.syncNow();
      expect(admin.received, isEmpty);
      expect(admin.log.any((l) => l.contains('rejected 1')), isTrue);
    });

    test(
      "a clip signed with the attacker's own key as B is rejected",
      () async {
        final mallory = await DeviceKeys.generate();
        final item = await ClipSigning.signItem(
          atk.raw('forged', asDevice: 'B'),
          mallory,
        );
        atk.inject(item);
        await admin.engine!.syncNow();
        expect(admin.received, isEmpty);
      },
    );

    test(
      'tampering with a genuine clip (content, target, time) breaks it',
      () async {
        final real = await member.say('genuine');
        final stored = shared.items[real.id]!;
        await admin.engine!.syncNow();
        expect(admin.received, ['genuine']);

        atk
          // Content swapped, signature kept.
          ..inject(
            stored
                .copyWith(content: 'x${stored.content}')
                .copyWith(updatedAt: atk.now),
          )
          // Re-addressed to the admin only.
          ..inject(
            stored.copyWith(
              targetDeviceId: 'A',
              updatedAt: atk.now.add(const Duration(seconds: 1)),
            ),
          );
        await admin.engine!.syncNow();
        expect(admin.received, ['genuine'], reason: 'nothing new applied');
        expect(admin.store.items[real.id]!.content, 'genuine');
      },
    );

    test('a replayed pre-delete version cannot undelete a clip', () async {
      final real = await member.say('to be deleted');
      final before = shared.items[real.id]!;
      await admin.engine!.syncNow();
      // B deletes it.
      member.store.items[real.id] = real.tombstone(
        atk.now.add(const Duration(seconds: 1)),
      );
      member.store.unsynced.add(real.id);
      await member.engine!.syncNow();
      await admin.engine!.syncNow();
      expect(admin.store.items[real.id]!.isDeleted, isTrue);
      // Attacker restores the old signed row.
      atk.inject(before);
      await admin.engine!.syncNow();
      expect(admin.store.items[real.id]!.isDeleted, isTrue);
    });

    test('a self-registered rogue device is ignored by everyone', () async {
      final rogue = await Node.create(shared, 'M', 'Rogue');
      await rogue.start(trustedAdminPub: adminKey.publicKey, encrypted: false);
      expect(rogue.engine!.status.selfVerified, isFalse);
      await rogue.say('from rogue');
      await admin.engine!.syncNow();
      await member.engine!.syncNow();
      expect(admin.received, isEmpty);
      expect(member.received, isEmpty);
      // It shows up in the list, unverified, so the admin can see it.
      await admin.engine!.refreshDevices();
      final row = admin.engine!.knownDevices.firstWhere((d) => d.id == 'M');
      expect(row.isSigned, isFalse);
      expect(admin.engine!.trustedDevices.containsKey('M'), isFalse);
      await rogue.stop();
    });

    test('an unsigned "blocked" written on the member is ignored', () async {
      atk.setRow(atk.row('B').copyWith(status: DeviceStatus.blocked));
      await member.engine!.refreshDevices();
      expect(member.engine!.status.phase, isNot(SyncPhase.revoked));
      expect(member.engine!.isRunning, isTrue);
      // The admin no longer trusts the tampered row either (signature broken)…
      await admin.engine!.refreshDevices();
      expect(admin.engine!.trustedDevices.containsKey('B'), isFalse);
      // …until it re-signs the true state.
      await admin.engine!.unblockDevice('B');
      expect(admin.engine!.trustedDevices.containsKey('B'), isTrue);
    });

    test('a block signed by a foreign admin key is ignored', () async {
      final fakeAdmin = await AdminKey.generate();
      atk.setRow(
        await ClipSigning.signMembership(
          atk.row('B').copyWith(status: DeviceStatus.blocked),
          fakeAdmin,
        ),
      );
      await member.engine!.refreshDevices();
      expect(member.engine!.isRunning, isTrue);
    });

    test(
      'a genuine block cannot be rolled back by restoring the old row',
      () async {
        final oldRow = atk.row('B');
        await admin.engine!.blockDevice('B');
        await member.engine!.refreshDevices();
        expect(member.engine!.status.phase, SyncPhase.revoked);
        expect(admin.engine!.trustedDevices.containsKey('B'), isFalse);
        // Attacker restores the previously valid, signed "active" row.
        atk.setRow(oldRow);
        await admin.engine!.refreshDevices();
        expect(admin.engine!.trustedDevices.containsKey('B'), isFalse);
        expect(admin.log.any((l) => l.contains('rolled-back')), isTrue);
        // Its clips stay ignored.
        atk.inject(
          await ClipSigning.signItem(
            atk.raw('after block', asDevice: 'B'),
            member.keys,
          ),
        );
        await admin.engine!.syncNow();
        expect(admin.received, isEmpty);
      },
    );

    test('a blocked device cannot unblock itself', () async {
      await admin.engine!.blockDevice('B');
      atk.setRow(atk.row('B').copyWith(status: DeviceStatus.active));
      await admin.engine!.refreshDevices();
      expect(admin.engine!.trustedDevices.containsKey('B'), isFalse);
      // Restarting the member does not help either: unsigned row → not obeyed
      // for revocation, but also not trusted, so nothing it sends is applied.
      final again = await Node.create(shared, 'B', 'Phone', keys: member.keys);
      await again.start(
        trustedAdminPub: adminKey.publicKey,
        passphrases: {1: pass1},
      );
      expect(again.engine!.status.selfVerified, isFalse);
      await again.say('sneaky');
      await admin.engine!.syncNow();
      expect(admin.received, isEmpty);
      await again.stop();
    });

    group('key drift', () {
      /// The admin starts over with a keyring of its own, as after losing
      /// it: same device, same admin key, a passphrase nobody else has.
      Future<Node> restartAdminWith(
        Map<int, String> ring, {
        Duration delay = Duration.zero,
      }) async {
        await admin.stop();
        // The device that created the key never had an envelope of its own
        // to recover it from.
        atk.setRow(
          await ClipSigning.signMembership(
            atk.row('A').copyWith(clearEnvelope: true),
            adminKey,
          ),
        );
        admin = await Node.create(
          shared,
          'A',
          'Admin laptop',
          keys: admin.keys,
        );
        await admin.start(
          adminKey: adminKey,
          trustedAdminPub: adminKey.publicKey,
          passphrases: ring,
          assumeRegistered: true,
          keyResendDelay: delay,
        );
        return admin;
      }

      test('an admin that lost its keyring re-keys the member', () async {
        await admin.engine!.rotatePassphrase('group passphrase v2');
        await member.engine!.refreshDevices();
        expect(member.passphrases.keys, [1, 2]);

        await restartAdminWith({1: 'started over'});
        final fresh = admin.passphrases[3];
        expect(fresh, isNotNull);
        expect(
          fresh,
          isNot(anyOf(pass1, 'group passphrase v2', 'started over')),
        );
        expect(atk.row('B').keyVersion, 3);
        expect(
          admin.log.any((l) => l.contains('held a different key')),
          isTrue,
        );

        await member.engine!.refreshDevices();
        expect(member.passphrases[3], fresh);
        await admin.say('after the drift');
        await member.engine!.syncNow();
        expect(member.received, contains('after the drift'));
        await member.say('and back');
        await admin.engine!.syncNow();
        expect(admin.received, contains('and back'));
      });

      test('a clip that does not open at the same version re-keys', () async {
        await restartAdminWith({1: 'started over'});
        expect(admin.passphrases.keys, [1], reason: 'rows look in step');
        await admin.say('sealed with the lost key');
        await member.engine!.syncNow();
        expect(member.received, isEmpty);

        await member.say('sealed with the old v1');
        await admin.engine!.syncNow();
        expect(admin.engine!.status.phase, isNot(SyncPhase.error));
        expect(admin.received, isEmpty);

        await admin.engine!.refreshDevices();
        expect(admin.passphrases.keys, [1, 2]);
        await member.engine!.refreshDevices();
        expect(member.passphrases[2], admin.passphrases[2]);
        await member.say('sealed with v2');
        await admin.engine!.syncNow();
        expect(admin.received, ['sealed with v2']);
        // The admin's clip from before the re-key went out again under v2.
        await member.engine!.syncNow();
        expect(member.received, contains('sealed with the lost key'));
        expect(
          shared.items.values
              .where((i) => i.deviceId == 'A')
              .map((i) => i.keyVersion),
          everyElement(2),
        );
      });

      test(
        'the admin waits out a rotation that is still being written',
        () async {
          await admin.engine!.rotatePassphrase('group passphrase v2');
          await restartAdminWith(
            {1: 'started over'},
            delay: const Duration(hours: 1),
          );
          expect(admin.engine!.status.keyDrift, isTrue);
          expect(admin.passphrases.keys, [1]);
          expect(atk.row('B').keyVersion, 2);
        },
      );

      test('a member never re-keys the group on its own', () async {
        await admin.engine!.rotatePassphrase('group passphrase v2');
        await member.stop();
        member = await Node.create(shared, 'B', 'Phone', keys: member.keys);
        await member.start(
          trustedAdminPub: adminKey.publicKey,
          passphrases: {3: 'typed on the phone'},
          keyResendDelay: Duration.zero,
        );
        await admin.say('sealed with v2');
        await member.engine!.syncNow();
        await member.engine!.refreshDevices();
        expect(member.engine!.status.phase, isNot(SyncPhase.error));
        expect(member.passphrases.keys, [3]);
        expect(atk.row('B').keyVersion, 2);
      });
    });

    test('only the admin can manage a signed group', () async {
      expect(() => member.engine!.blockDevice('A'), throwsStateError);
      expect(() => member.engine!.forgetDevice('A'), throwsStateError);
      expect(() => member.engine!.rotatePassphrase('x'), throwsStateError);
      expect(
        () => member.engine!.inviteDevice(id: 'Z', role: DeviceRole.full),
        throwsStateError,
      );
    });

    test('a swapped key envelope is not opened', () async {
      final trap = await KeyEnvelope.seal(
        passphrase: 'attacker chosen',
        version: 9,
        recipientBoxPub: member.keys.boxPub,
      );
      atk.setRow(
        atk.row('B').copyWith(keyVersion: 9, keyEnvelope: trap.encode()),
      );
      await member.engine!.refreshDevices();
      expect(member.passphrases.keys, [1]);
      expect(member.engine!.status.keyVersion, 1);
    });

    test('rotation locks out a removed device but not a member', () async {
      // A third device that was in the group, then removed.
      final exKeys = await DeviceKeys.generate();
      await admin.engine!.inviteDevice(
        id: 'C',
        role: DeviceRole.full,
        signPub: exKeys.signPub,
        boxPub: exKeys.boxPub,
        passphrase: pass1,
      );
      final ex = await Node.create(shared, 'C', 'Old tablet', keys: exKeys);
      await ex.start(trustedAdminPub: adminKey.publicKey);
      expect(ex.passphrases, {1: pass1});
      await admin.say('before rotation');
      await ex.engine!.syncNow();
      expect(ex.received, ['before rotation']);

      await admin.engine!.removeDevice('C');
      final envelopeC = atk.row('C').keyEnvelope;
      // C keeps running a modified client that ignores revocation and
      // still holds passphrase v1.
      final issued = await admin.engine!.rotatePassphrase(
        'group passphrase v2',
      );
      expect(issued, 2, reason: 'A and B only');
      await member.engine!.refreshDevices();
      expect(member.passphrases[2], 'group passphrase v2');
      // C was not re-issued: its envelope and version are untouched.
      expect(atk.row('C').keyVersion, 1);
      expect(atk.row('C').keyEnvelope, envelopeC);

      await admin.say('after rotation');
      await member.engine!.syncNow();
      expect(member.received, contains('after rotation'));

      // A modified client that ignores its removal (it rewrites its row
      // to "active" and runs without the admin pin) cannot read v2 content.
      atk.setRow(atk.row('C').copyWith(status: DeviceStatus.active));
      final rogueC = await Node.create(shared, 'C', 'Old tablet', keys: exKeys);
      await rogueC.start(passphrases: {1: pass1});
      await rogueC.engine!.syncNow();
      expect(rogueC.received, ['before rotation']);
      expect(rogueC.log.any((l) => l.contains('no key v2')), isTrue);
      await rogueC.stop();
      await ex.stop();
    });

    test(
      'a clip under a key that is still in the envelope is not lost',
      () async {
        await admin.engine!.rotatePassphrase('group passphrase v2');
        // No heartbeat on the member yet: the clip arrives before the key.
        await admin.say('right after rotation');
        await member.engine!.syncNow();
        expect(member.received, contains('right after rotation'));
        expect(member.passphrases.keys, [1, 2]);
      },
    );

    test('rotation skips a device whose old signed row was restored', () async {
      final oldRow = atk.row('B');
      await admin.engine!.blockDevice('B');
      atk.setRow(oldRow); // rollback: valid signature, older version
      final issued = await admin.engine!.rotatePassphrase('v2');
      expect(issued, 1, reason: 'admin only');
      expect(atk.row('B').keyVersion, 1);
      expect(atk.row('B').keyEnvelope, oldRow.keyEnvelope);
    });

    test('a device cannot forge the admin flag or its own role', () async {
      atk.setRow(atk.row('B').copyWith(admin: true, role: DeviceRole.full));
      await admin.engine!.refreshDevices();
      expect(admin.engine!.trustedDevices.containsKey('B'), isFalse);
      // Role the admin set is what B obeys; a tampered role is ignored.
      await admin.engine!.setDeviceRole('B', DeviceRole.sendOnly);
      await member.engine!.refreshDevices();
      expect(member.engine!.role, DeviceRole.sendOnly);
      atk.setRow(atk.row('B').copyWith(role: DeviceRole.full));
      await member.engine!.refreshDevices();
      expect(member.engine!.role, DeviceRole.sendOnly);
    });

    test('heartbeat never overwrites the admin-signed keys', () async {
      final impostor = await Node.create(shared, 'B', 'Phone clone');
      await impostor.start(
        trustedAdminPub: adminKey.publicKey,
        passphrases: {1: pass1},
      );
      expect(atk.row('B').signPub, member.keys.signPub);
      expect(atk.row('B').boxPub, member.keys.boxPub);
      expect(
        impostor.engine!.status.selfVerified,
        isTrue,
        reason: "row still verifies: but with B's keys, which the clone lacks",
      );
      await impostor.say('clone');
      await admin.engine!.syncNow();
      expect(admin.received, isEmpty);
      await impostor.stop();
    });

    test('a clip addressed to one device is not readable by another', () async {
      await admin.say('only for B', to: 'B');
      final rogue = await Node.create(shared, 'M', 'Rogue');
      await rogue.start(
        trustedAdminPub: adminKey.publicKey,
        passphrases: {1: pass1},
      );
      await rogue.engine!.syncNow();
      expect(rogue.received, isEmpty);
      await member.engine!.syncNow();
      expect(member.received, ['only for B']);
      await rogue.stop();
    });
  });

  group('removing a device', () {
    late Node other;

    setUp(() async {
      await setUpSignedGroup();
      final keys = await DeviceKeys.generate();
      other = await Node.create(shared, 'C', 'Tablet', keys: keys);
      await admin.engine!.inviteDevice(
        id: 'C',
        role: DeviceRole.full,
        signPub: keys.signPub,
        boxPub: keys.boxPub,
        passphrase: pass1,
      );
      await other.start(trustedAdminPub: adminKey.publicKey);
    });
    tearDown(() async {
      await admin.stop();
      await member.stop();
      await other.stop();
    });

    test(
      'its clips can be deleted from the database and every device',
      () async {
        await member.say('from the phone');
        await other.engine!.syncNow();
        await admin.engine!.syncNow();
        expect(other.received, contains('from the phone'));

        await admin.engine!.removeDevice('B');
        final n = await admin.engine!.purgeDeviceClips('B');
        expect(n, 1);
        expect(admin.received, isNot(contains('from the phone')));
        final row = shared.items.values.single;
        expect(row.isDeleted, isTrue);
        expect(row.content, isEmpty, reason: 'the ciphertext is gone too');

        await other.engine!.refreshDevices();
        await other.engine!.syncNow();
        expect(other.received, isNot(contains('from the phone')));
      },
    );

    test('a deletion not signed by the admin is ignored', () async {
      await member.say('keep me');
      await other.engine!.syncNow();
      await admin.engine!.removeDevice('B');
      await other.engine!.refreshDevices();

      // A member, not the admin, signs the deletion.
      final row = shared.items.values.single;
      atk.inject(
        await ClipSigning.signItem(
          row.tombstone(DateTime.now().toUtc()),
          other.keys,
        ),
      );
      await other.engine!.syncNow();
      expect(other.received, contains('keep me'));
    });

    test('a device unblocked after a rotation gets the new key', () async {
      await admin.engine!.blockDevice('B');
      await admin.engine!.rotatePassphrase('after the block');
      await admin.engine!.unblockDevice('B');
      await admin.engine!.sendKeyTo('B', 2, 'after the block');
      await admin.say('new key era');
      await member.engine!.refreshDevices();
      await member.engine!.syncNow();
      expect(member.passphrases[2], 'after the block');
      expect(member.received, contains('new key era'));
    });
  });

  group('admin key replaced', () {
    setUp(setUpSignedGroup);
    tearDown(() async {
      await admin.stop();
      await member.stop();
    });

    test('a member asks before following an admin that started over, '
        'then syncs again', () async {
      // The admin device lost its admin key and secured the group again
      // with a new one, re-signing the member's row and sealing it a key.
      await admin.stop();
      final newKey = await AdminKey.generate();
      admin = await Node.create(shared, 'A', 'Admin laptop', keys: admin.keys);
      await admin.start(
        adminKey: newKey,
        trustedAdminPub: newKey.publicKey,
        passphrases: {2: 'after starting over'},
        assumeRegistered: true,
      );
      await admin.engine!.secureGroup();
      await admin.engine!.rotatePassphrase('after starting over again');
      await admin.say('from the new admin');

      // The member still pins the old key: it reads nothing and asks.
      await member.engine!.refreshDevices();
      await member.engine!.syncNow();
      expect(member.received, isNot(contains('from the new admin')));
      expect(member.engine!.status.selfVerified, isFalse);
      expect(member.trustPrompts.map((t) => t.adminPub), [newKey.publicKey]);
      expect(member.trustPrompts.single.replacesPinned, isTrue);
      expect(member.trustPrompts.single.adminDeviceName, 'Admin laptop');

      // Asking again on the next heartbeat would nag; once is enough.
      await member.engine!.refreshDevices();
      expect(member.trustPrompts, hasLength(1));

      // The user compared fingerprints and trusted it.
      await member.engine!.dispose();
      member = await Node.create(shared, 'B', 'Phone', keys: member.keys)
        ..passphrases.addAll(member.passphrases);
      await member.start(
        trustedAdminPub: newKey.publicKey,
        assumeRegistered: true,
      );
      expect(member.engine!.status.selfVerified, isTrue);
      expect(member.received, contains('from the new admin'));
      await member.say('from the member');
      await admin.engine!.syncNow();
      expect(admin.received, contains('from the member'));
    });

    test('a planned change signed by the old key needs no question', () async {
      final next = await AdminKey.generate();
      expect(await admin.engine!.rolloverAdmin(next), isTrue);
      await member.engine!.refreshDevices();
      expect(member.trustPrompts.single.adminPub, next.publicKey);
      expect(member.trustPrompts.single.vouched, isTrue);

      // A device that missed two changes still follows the chain.
      await admin.engine!.dispose();
      admin = await Node.create(shared, 'A', 'Admin laptop', keys: admin.keys);
      await admin.start(
        adminKey: next,
        trustedAdminPub: next.publicKey,
        assumeRegistered: true,
      );
      final third = await AdminKey.generate();
      await admin.engine!.rolloverAdmin(third);
      await member.engine!.dispose();
      member = await Node.create(shared, 'B', 'Phone', keys: member.keys)
        ..passphrases.addAll(member.passphrases);
      await member.start(
        trustedAdminPub: adminKey.publicKey,
        assumeRegistered: true,
      );
      expect(member.trustPrompts.single.adminPub, third.publicKey);
      expect(member.trustPrompts.single.vouched, isTrue);
    });

    test('a change the old key did not sign is not followed', () async {
      // Someone with database access signs every row with their own key
      // and adds a link that claims to come from the trusted key.
      final mallory = await AdminKey.generate();
      final forged = AdminLink(
        from: adminKey.publicKey,
        to: mallory.publicKey,
        sig: await mallory.sign([1, 2, 3]),
      );
      atk.setRow(
        await ClipSigning.signMembership(
          atk
              .row('A')
              .copyWith(
                adminEnvelope: AdminNotice(links: [forged]).encode(),
              ),
          mallory,
        ),
      );
      atk.setRow(await ClipSigning.signMembership(atk.row('B'), mallory));
      await member.engine!.refreshDevices();
      expect(member.trustPrompts.single.vouched, isFalse);
    });

    test('a one-time code proves a new admin key', () async {
      // The admin lost its key and secured the group again.
      await admin.stop();
      final newKey = await AdminKey.generate();
      admin = await Node.create(shared, 'A', 'Admin laptop', keys: admin.keys);
      await admin.start(
        adminKey: newKey,
        trustedAdminPub: newKey.publicKey,
        passphrases: {1: pass1},
        assumeRegistered: true,
      );
      await admin.engine!.secureGroup();
      await admin.engine!.publishAdminCode('12345678');

      await member.engine!.refreshDevices();
      expect(member.trustPrompts.single.vouched, isFalse);
      final e = member.engine!;
      expect(await e.adminCodeOpens(newKey.publicKey, '1234 5678'), isTrue);
      expect(await e.adminCodeOpens(newKey.publicKey, '87654321'), isFalse);
      // The code belongs to that key only.
      final other = await AdminKey.generate();
      expect(await e.adminCodeOpens(other.publicKey, '12345678'), isFalse);
    });

    test('an unsigned or forged row does not prompt', () async {
      final forger = await AdminKey.generate();
      final row = atk.row('B');
      // Claims another admin key without a valid signature from it.
      atk.setRow(row.copyWith(adminPub: forger.publicKey));
      await member.engine!.refreshDevices();
      expect(member.trustPrompts, isEmpty);
    });
  });

  group('legacy group (no admin pinned)', () {
    late Node a;
    late Node b;
    setUp(() async {
      shared = MemoryStore();
      atk = Attacker(shared);
      a = await Node.create(shared, 'A', 'A');
      b = await Node.create(shared, 'B', 'B');
      await a.start(encrypted: false);
      await b.start(encrypted: false);
    });
    tearDown(() async {
      await a.stop();
      await b.stop();
    });

    test(
      'devices publish keys and sign; unsigned spoof of a keyed device is dropped',
      () async {
        expect(atk.row('B').signPub, b.keys.signPub);
        await b.say('real');
        await a.engine!.syncNow();
        expect(a.received, ['real']);
        atk.inject(atk.raw('spoof', asDevice: 'B'));
        await a.engine!.syncNow();
        expect(a.received, ['real']);
      },
    );

    test(
      'unknown or key-less devices are still accepted (compatibility)',
      () async {
        atk.inject(atk.raw('from old app', asDevice: 'legacy-device'));
        await a.engine!.syncNow();
        expect(a.received, ['from old app']);
      },
    );

    test(
      'an attacker-signed admin key is surfaced, never auto-trusted',
      () async {
        final mallory = await AdminKey.generate();
        atk.setRow(
          await ClipSigning.signMembership(
            atk.row('B').copyWith(admin: true),
            mallory,
          ),
        );
        await a.engine!.refreshDevices();
        expect(a.trustPrompts.single.adminPub, mallory.publicKey);
        expect(a.trustPrompts.single.fingerprint, mallory.fingerprint);
        expect(a.engine!.isSignedGroup, isFalse);
        // A cooperative block still works in a legacy group (documented).
        atk.setRow(atk.row('A').copyWith(status: DeviceStatus.blocked));
        await a.engine!.refreshDevices();
        expect(a.engine!.status.phase, SyncPhase.revoked);
      },
    );

    test(
      'securing the group signs every active row and pins on restart',
      () async {
        final key = await AdminKey.generate();
        await a.stop();
        a = await Node.create(shared, 'A', 'A', keys: a.keys);
        await a.start(adminKey: key);
        await a.engine!.secureGroup();
        expect(atk.row('A').admin, isTrue);
        expect(
          await ClipSigning.verifyMembership(atk.row('A'), key.publicKey),
          isTrue,
        );
        expect(
          await ClipSigning.verifyMembership(atk.row('B'), key.publicKey),
          isTrue,
        );
        // B sees the prompt and, once it pins the key, verifies.
        await b.engine!.refreshDevices();
        expect(b.trustPrompts.single.adminDeviceName, 'A');
        await b.stop();
        b = await Node.create(shared, 'B', 'B', keys: b.keys);
        await b.start(trustedAdminPub: key.publicKey);
        expect(b.engine!.status.selfVerified, isTrue);
      },
    );
  });

  group('primitives', () {
    test('device keys round-trip and verify', () async {
      final k = await DeviceKeys.generate();
      final again = await DeviceKeys.decode(await k.encode());
      expect(again.signPub, k.signPub);
      expect(again.boxPub, k.boxPub);
      final sig = await k.sign([1, 2, 3]);
      expect(
        await DeviceKeys.verify(
          [1, 2, 3],
          signature: sig,
          publicKey: k.signPub,
        ),
        isTrue,
      );
      expect(
        await DeviceKeys.verify(
          [1, 2, 4],
          signature: sig,
          publicKey: k.signPub,
        ),
        isFalse,
      );
      expect(
        await DeviceKeys.verify(
          [1, 2, 3],
          signature: 'nope',
          publicKey: k.signPub,
        ),
        isFalse,
      );
      expect(k.fingerprint, matches(RegExp(r'^[0-9a-f]{4} [0-9a-f]{4}$')));
    });

    test('a signature survives a database that keeps milliseconds', () async {
      // PocketBase and MongoDB store times to the millisecond; the app's
      // clock has microseconds.
      DateTime ms(DateTime t) => DateTime.fromMillisecondsSinceEpoch(
        t.millisecondsSinceEpoch,
        isUtc: true,
      );
      final k = await DeviceKeys.generate();
      final at = DateTime.utc(2026, 10, 17, 15, 0, 47, 831, 526);
      final signed = await ClipSigning.signItem(
        ClipItem.fromMap({
          'id': 'c',
          'device_id': 'd',
          'device_name': 'Android',
          'content_type': 'text',
          'content': 'hello',
          'content_hash': 'h',
          'size_bytes': 5,
          'created_at': at.toIso8601String(),
          'updated_at': at.toIso8601String(),
          'deleted_at': at.toIso8601String(),
        }),
        k,
      );
      final stored = ClipItem.fromMap({
        ...signed.toMap(),
        'created_at': ms(signed.createdAt).toIso8601String(),
        'updated_at': ms(signed.updatedAt).toIso8601String(),
        'deleted_at': ms(signed.deletedAt!).toIso8601String(),
      });
      expect(await ClipSigning.verifyItem(stored, k.signPub), isTrue);

      final admin = await AdminKey.generate();
      final row = await ClipSigning.signMembership(
        Device.fromMap({'id': 'd', 'expires_at': at.toIso8601String()}),
        admin,
      );
      final reread = Device.fromMap({
        ...row.toMap(),
        'expires_at': ms(row.expiresAt!).toIso8601String(),
      });
      expect(
        await ClipSigning.verifyMembership(reread, admin.publicKey),
        isTrue,
      );
    });

    test('a one-time admin code expires', () async {
      final now = DateTime.utc(2026, 10, 18, 12);
      final code = await AdminCode.seal(
        'pub',
        '11112222',
        until: now.add(AdminCode.validFor),
      );
      final back = AdminNotice.tryDecode(
        AdminNotice(code: code).encode(),
      )!.code!;
      expect(await back.open('11112222', now: now), 'pub');
      expect(
        await back.open('11112222', now: now.add(const Duration(minutes: 11))),
        isNull,
      );
      expect(AdminNotice.tryDecode('not a notice'), isNull);
    });

    test('envelope opens only for the recipient', () async {
      final a = await DeviceKeys.generate();
      final b = await DeviceKeys.generate();
      final env = await KeyEnvelope.seal(
        passphrase: 's3cret',
        version: 2,
        recipientBoxPub: a.boxPub,
      );
      final back = KeyEnvelope.decode(env.encode());
      expect(await back.open(a), 's3cret');
      expect(() => back.open(b), throwsA(isA<EnvelopeException>()));
      final tampered = KeyEnvelope(
        version: 3,
        ephemeralPub: back.ephemeralPub,
        nonce: back.nonce,
        ciphertext: back.ciphertext,
      );
      expect(
        () => tampered.open(a),
        throwsA(isA<EnvelopeException>()),
        reason: 'version is authenticated data',
      );
    });

    test('a grant from a newer app version still verifies', () async {
      final admin = await AdminKey.generate();
      final signed = await ClipSigning.signMembership(
        Device.fromMap(const {
          'id': 'd',
          'permissions': 'clear_history,something_newer',
        }),
        admin,
      );
      final reread = Device.fromMap(signed.toMap());
      expect(reread.permissions, {DevicePermission.clearHistory});
      expect(
        await ClipSigning.verifyMembership(reread, admin.publicKey),
        isTrue,
      );
    });

    test('membership signature covers every access-relevant field', () async {
      final admin = await AdminKey.generate();
      final base = Device(
        id: 'd',
        name: 'n',
        platform: 'p',
        lastSeen: DateTime.utc(2026),
        signPub: 'sp',
        boxPub: 'bp',
      );
      final signed = await ClipSigning.signMembership(base, admin);
      expect(signed.membershipVersion, 1);
      expect(
        await ClipSigning.verifyMembership(signed, admin.publicKey),
        isTrue,
      );
      // Presence changes keep it valid…
      expect(
        await ClipSigning.verifyMembership(
          signed.copyWith(
            name: 'renamed',
            lastSeen: DateTime.utc(2027),
            appVersion: '9',
          ),
          admin.publicKey,
        ),
        isTrue,
      );
      // …every membership change breaks it.
      for (final mutated in [
        signed.copyWith(status: DeviceStatus.blocked),
        signed.copyWith(role: DeviceRole.receiveOnly),
        signed.copyWith(expiresAt: DateTime.utc(2030)),
        signed.copyWith(signPub: 'other'),
        signed.copyWith(boxPub: 'other'),
        signed.copyWith(admin: true),
        signed.copyWith(membershipVersion: 2),
        signed.copyWith(keyVersion: 5),
        signed.copyWith(keyEnvelope: '{}'),
        signed.copyWith(permissions: {DevicePermission.clearHistory}),
        signed.copyWith(adminEnvelope: '{}'),
      ]) {
        expect(
          await ClipSigning.verifyMembership(mutated, admin.publicKey),
          isFalse,
        );
      }
      final other = await AdminKey.generate();
      expect(
        await ClipSigning.verifyMembership(signed, other.publicKey),
        isFalse,
      );
    });

    test('cipher ring keeps old versions readable', () async {
      final ring = await CipherRing.fromPassphrases({
        1: 'one',
        2: 'two',
      }, keyScope: 's');
      expect(ring.currentVersion, 2);
      final item = textItem('old');
      final sealed = await ring.cipherFor(1)!.seal(item);
      expect((await ring.cipherFor(1)!.open(sealed)).content, 'old');
      expect(() => ring.current!.open(sealed), throwsA(isA<CipherException>()));
      expect(ring.cipherFor(3), isNull);
    });
  });
}
