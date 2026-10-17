import 'dart:async';

import 'package:nija_core/nija_core.dart';
import 'package:test/test.dart';

import '../helpers/fakes.dart';

void main() {
  late MemoryStore shared;
  late MemoryBackend backendA;
  late FakeLocalStore storeA;
  late SyncEngine engineA;

  setUp(() async {
    shared = MemoryStore();
    backendA = MemoryBackend(shared: shared);
    await backendA.connect(const BackendConfig.empty('memory'));
    storeA = FakeLocalStore();
    engineA = SyncEngine(
      backend: backendA,
      store: storeA,
      device: deviceA,
      pollInterval: const Duration(hours: 1),
      heartbeatInterval: const Duration(hours: 1),
    );
  });

  tearDown(() async {
    await engineA.dispose();
    await backendA.dispose();
  });

  test('start registers device and pushes outbox', () async {
    storeA
      ..capture(textItem('one'))
      ..capture(textItem('two'));
    await engineA.start();
    expect(shared.items.length, 2);
    expect(storeA.unsynced, isEmpty);
    expect(shared.devices.keys, contains('dev-a'));
    expect(engineA.status.phase, SyncPhase.idle);
    expect(engineA.status.realtime, isTrue);
  });

  test('pull applies items from other devices and advances cursor', () async {
    final remote = textItem('from B', deviceId: 'dev-b', deviceName: 'B');
    backendA.injectRemote(remote);
    final received = <ClipItem>[];
    engineA.incoming.listen(received.addAll);
    await engineA.start();
    expect(storeA.items[remote.id]?.content, 'from B');
    expect(storeA.cursor, remote.updatedAt);
    expect(received.single.id, remote.id);
  });

  test('own items are never pulled back (excludeDeviceId)', () async {
    storeA.capture(textItem('mine'));
    await engineA.start();
    expect(storeA.items.length, 1);
    expect(storeA.unsynced, isEmpty);
  });

  test('realtime event triggers a pull', () async {
    await engineA.start();
    final remote = textItem('live', deviceId: 'dev-b');
    backendA.injectRemote(remote);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await engineA.syncNow();
    expect(storeA.items.containsKey(remote.id), isTrue);
  });

  test(
    'echo suppression drops remote item whose hash we captured recently',
    () async {
      final local = textItem('same text');
      storeA.capture(local);
      await engineA.start();
      final echo = textItem('same text', deviceId: 'dev-b');
      backendA.injectRemote(echo);
      await engineA.syncNow();
      expect(storeA.items.containsKey(echo.id), isFalse);
      expect(storeA.cursor, echo.updatedAt, reason: 'cursor still advances');
    },
  );

  test('tombstones propagate', () async {
    final remote = textItem('bye', deviceId: 'dev-b');
    backendA.injectRemote(remote);
    await engineA.start();
    await backendA.tombstone(
      remote.id,
      DateTime.now().toUtc().add(const Duration(seconds: 1)),
    );
    await engineA.syncNow();
    expect(storeA.items[remote.id]!.isDeleted, isTrue);
  });

  test("another device's tombstone is kept local", () async {
    final theirs = textItem('from B', deviceId: 'dev-b', deviceName: 'B');
    backendA.injectRemote(theirs);
    await engineA.start();
    storeA.capture(
      theirs.copyWith(
        content: '',
        deletedAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      ),
    );
    await engineA.syncNow();
    expect(shared.items[theirs.id]!.isDeleted, isFalse);
    expect(shared.items[theirs.id]!.content, 'from B');
    expect(storeA.unsynced, isEmpty);
  });

  test('encrypts on push and decrypts on pull', () async {
    final cipher = await ClipCipher.fromPassphrase('pw', keyScope: 'memory');
    await engineA.dispose();
    engineA = SyncEngine(
      backend: backendA,
      store: storeA,
      device: deviceA,
      cipher: cipher,
      pollInterval: const Duration(hours: 1),
    );
    storeA.capture(textItem('plain'));
    await engineA.start();
    final stored = shared.items.values.single;
    expect(stored.encrypted, isTrue);
    expect(stored.content, isNot('plain'));

    // Device B with the same passphrase reads it back.
    final backendB = MemoryBackend(shared: shared);
    await backendB.connect(const BackendConfig.empty('memory'));
    final storeB = FakeLocalStore();
    final engineB = SyncEngine(
      backend: backendB,
      store: storeB,
      device: deviceB,
      cipher: await ClipCipher.fromPassphrase('pw', keyScope: 'memory'),
      pollInterval: const Duration(hours: 1),
    );
    await engineB.start();
    expect(storeB.items.values.single.content, 'plain');
    await engineB.dispose();
    await backendB.dispose();
  });

  group('legacy plaintext clips', () {
    late ClipCipher cipher;

    setUp(() async {
      cipher = await ClipCipher.fromPassphrase('pw', keyScope: 'memory');
      await engineA.dispose();
      engineA = SyncEngine(
        backend: backendA,
        store: storeA,
        device: deviceA,
        cipher: cipher,
        pollInterval: const Duration(hours: 1),
        heartbeatInterval: const Duration(hours: 1),
      );
    });

    void put(ClipItem item) => shared.items[item.id] = item;

    test('finds the rows written before the group was encrypted', () async {
      // Two rows from the plaintext era, one sealed since, one tombstone.
      final old1 = textItem('old secret', deviceId: 'dev-b');
      final old2 = textItem('another', deviceId: 'dev-b');
      put(old1);
      put(old2);
      put(await cipher.seal(textItem('sealed', deviceId: 'dev-b')));
      put(
        textItem('gone', deviceId: 'dev-b').copyWith(
          content: '',
          deletedAt: DateTime.now().toUtc(),
        ),
      );

      final stale = await engineA.plaintextClips();

      expect(stale.map((i) => i.id), unorderedEquals([old1.id, old2.id]));
    });

    test('purging clears the content, not just the deleted flag', () async {
      final old = textItem('old secret', deviceId: 'dev-b');
      put(old);

      final cleared = await engineA.purgePlaintextClips();

      expect(cleared, 1);
      final row = shared.items[old.id]!;
      expect(row.content, isEmpty, reason: 'plaintext must leave the database');
      expect(row.contentHash, isEmpty);
      expect(row.isDeleted, isTrue);
      expect(storeA.items[old.id]!.isDeleted, isTrue);
      expect(await engineA.plaintextClips(), isEmpty);
    });

    test('leaves encrypted rows alone', () async {
      final sealed = await cipher.seal(textItem('sealed', deviceId: 'dev-b'));
      put(sealed);

      expect(await engineA.purgePlaintextClips(), 0);
      expect(shared.items[sealed.id]!.content, sealed.content);
    });

    test('spots encrypted rows still carrying the plain digest', () async {
      // What the old build wrote: sealed content, plaintext SHA-256 beside it.
      final legacy = (await cipher.seal(
        textItem('one time code 123456', deviceId: deviceA.id),
      )).copyWith(contentHash: sha256Hex('one time code 123456'));
      put(legacy);
      // What this build writes.
      put(await cipher.seal(textItem('fresh', deviceId: deviceA.id)));

      final stale = await engineA.legacyHashedClips();

      expect(stale.map((i) => i.id), [legacy.id]);
    });

    test('rehashing keys the fingerprint and leaves the ciphertext', () async {
      const text = 'one time code 123456';
      final sealed = await cipher.seal(textItem(text, deviceId: deviceA.id));
      final legacy = sealed.copyWith(contentHash: sha256Hex(text));
      put(legacy);

      expect(await engineA.rehashLegacyClips(), 1);

      final row = shared.items[legacy.id]!;
      expect(row.content, sealed.content, reason: 'ciphertext untouched');
      expect(row.updatedAt, legacy.updatedAt, reason: 'no churn for others');
      expect(row.contentHash, isNot(sha256Hex(text)));
      expect(row.contentHash, await cipher.contentFingerprint(text));
      // Still decryptable, and the local view still sees the plain digest.
      final opened = await cipher.open(row);
      expect(opened.content, text);
      expect(opened.contentHash, sha256Hex(text));
      expect(await engineA.legacyHashedClips(), isEmpty);
    });

    test("leaves other devices' rows alone; it cannot re-sign them", () async {
      const text = 'theirs';
      final theirs = (await cipher.seal(
        textItem(text, deviceId: 'dev-b'),
      )).copyWith(contentHash: sha256Hex(text));
      put(theirs);

      expect(await engineA.legacyHashedClips(), isEmpty);
      expect(await engineA.rehashLegacyClips(), 0);
      expect(shared.items[theirs.id]!.contentHash, sha256Hex(text));
    });

    test('refuses to run when the group does not encrypt at all', () async {
      // Every row would qualify, so offering to purge would mean offering to
      // delete the entire history.
      await engineA.dispose();
      engineA = SyncEngine(
        backend: backendA,
        store: storeA,
        device: deviceA,
        pollInterval: const Duration(hours: 1),
      );
      put(textItem('old secret', deviceId: 'dev-b'));

      expect(engineA.plaintextClips, throwsStateError);
      expect(engineA.purgePlaintextClips, throwsStateError);
    });
  });

  test('wrong passphrase surfaces as auth failure and stops retries', () async {
    final cipher = await ClipCipher.fromPassphrase('pw', keyScope: 'memory');
    shared.items['x'] = await cipher.seal(
      textItem('secret', deviceId: 'dev-b'),
    );
    await engineA.dispose();
    engineA = SyncEngine(
      backend: backendA,
      store: storeA,
      device: deviceA,
      cipher: await ClipCipher.fromPassphrase('other', keyScope: 'memory'),
      pollInterval: const Duration(hours: 1),
    );
    await engineA.start();
    expect(engineA.status.phase, SyncPhase.error);
    expect(engineA.status.authFailed, isTrue);
  });

  test('transient failure schedules retry with backoff', () async {
    storeA.capture(textItem('retry me'));
    backendA.failWith = BackendException('boom', isTransient: true);
    await engineA.start();
    expect(engineA.status.phase, SyncPhase.error);
    expect(engineA.status.authFailed, isFalse);
    expect(storeA.unsynced, isNotEmpty);
    backendA.failWith = null;
    // First backoff is 2s (2^1 * 1000ms).
    await Future<void>.delayed(const Duration(milliseconds: 2200));
    expect(storeA.unsynced, isEmpty);
    expect(engineA.status.phase, SyncPhase.idle);
  });

  test('auth failure does not retry until restart', () async {
    storeA.capture(textItem('x'));
    backendA.failWith = BackendException('denied', isAuth: true);
    await engineA.start();
    expect(engineA.status.authFailed, isTrue);
    backendA.failWith = null;
    await engineA.syncNow(); // ignored while authFailed
    expect(storeA.unsynced, isNotEmpty);
    await engineA.restart();
    expect(storeA.unsynced, isEmpty);
  });

  test('concurrent syncNow calls coalesce', () async {
    await engineA.start();
    storeA.capture(textItem('a'));
    final f1 = engineA.syncNow();
    final f2 = engineA.syncNow();
    await Future.wait([f1, f2]);
    expect(backendA.upsertCalls, 1);
  });

  test('stop clears status and stops timers', () async {
    await engineA.start();
    await engineA.stop();
    expect(engineA.status.phase, SyncPhase.stopped);
    expect(engineA.isRunning, isFalse);
  });

  test('status stream emits transitions', () async {
    final phases = <SyncPhase>[];
    final sub = engineA.statusStream.listen((s) => phases.add(s.phase));
    await engineA.start();
    await sub.cancel();
    expect(
      phases,
      containsAllInOrder([SyncPhase.idle, SyncPhase.syncing, SyncPhase.idle]),
    );
  });

  group('membership', _membershipTests);
}

// ---------------------------------------------------------------------------
// Device management
// ---------------------------------------------------------------------------

void _membershipTests() {
  late MemoryStore shared;
  late MemoryBackend backend;
  late FakeLocalStore store;
  final revoked = <String>[];

  SyncEngine engine({
    bool assumeRegistered = false,
    Map<String, int>? seen,
  }) {
    final e = SyncEngine(
      backend: backend,
      store: store,
      device: deviceA,
      pollInterval: const Duration(hours: 1),
      heartbeatInterval: const Duration(hours: 1),
      assumeRegistered: assumeRegistered,
      seenMembershipVersions: seen,
    );
    e.statusStream.listen((s) {
      if (s.phase == SyncPhase.revoked) revoked.add(s.revokedReason!);
    });
    return e;
  }

  setUp(() async {
    revoked.clear();
    shared = MemoryStore();
    backend = MemoryBackend(shared: shared);
    await backend.connect(const BackendConfig.empty('memory'));
    store = FakeLocalStore();
  });

  tearDown(() => backend.dispose());

  test('first run registers the device with default membership', () async {
    final e = engine();
    await e.start();
    final me = shared.devices['dev-a']!;
    expect(me.status, DeviceStatus.active);
    expect(me.role, DeviceRole.full);
    expect(e.knownDevices.map((d) => d.id), contains('dev-a'));
    expect(e.status.phase, SyncPhase.idle);
    await e.dispose();
  });

  test('a blocked device stops itself with reason "blocked"', () async {
    shared.devices['dev-a'] = deviceA.copyWith(status: DeviceStatus.blocked);
    final e = engine();
    await e.start();
    expect(e.status.phase, SyncPhase.revoked);
    expect(revoked, ['blocked']);
    expect(e.isRunning, isFalse);
    // The heartbeat did not resurrect or alter the row.
    expect(shared.devices['dev-a']!.status, DeviceStatus.blocked);
    await e.dispose();
  });

  test('a removed row with assumeRegistered means revoked', () async {
    // The device that forgot us is still there, and we knew it.
    shared.devices['dev-b'] = deviceB;
    final e = engine(assumeRegistered: true, seen: {'dev-a': 0, 'dev-b': 0});
    await e.start();
    expect(e.status.phase, SyncPhase.revoked);
    expect(revoked, ['removed']);
    expect(shared.devices.containsKey('dev-a'), isFalse);
    await e.dispose();
  });

  test(
    'an empty device list after a reset re-registers, not revokes',
    () async {
      // A device we knew exists, so a missing own row means "removed"...
      shared.devices['dev-b'] = deviceB;
      final forgotten = engine(assumeRegistered: true, seen: {'dev-b': 0});
      await forgotten.start();
      expect(revoked, ['removed']);
      await forgotten.dispose();

      // ...but with no rows at all the tables were dropped and recreated.
      revoked.clear();
      shared.devices.clear();
      final e = engine(assumeRegistered: true);
      await e.start();
      expect(revoked, isEmpty);
      expect(e.status.phase, SyncPhase.idle);
      expect(shared.devices.keys, ['dev-a']);
      await e.dispose();

      // ...and so do rows that only appeared after the reset: another device
      // that registered before us is not proof we were removed.
      revoked.clear();
      shared.devices
        ..clear()
        ..['dev-new'] = Device(
          id: 'dev-new',
          name: 'New',
          platform: 'test',
          lastSeen: DateTime.now().toUtc(),
        );
      final newcomer = engine(
        assumeRegistered: true,
        seen: {'dev-a': 0, 'dev-b': 0},
      );
      await newcomer.start();
      expect(revoked, isEmpty);
      expect(shared.devices.keys, containsAll(['dev-a', 'dev-new']));
      await newcomer.dispose();
    },
  );

  test('legacy groups remember device ids for that check', () async {
    shared.devices['dev-b'] = deviceB;
    final e = engine();
    await e.start();
    expect(e.seenMembershipVersions.keys, containsAll(['dev-a', 'dev-b']));
    await e.dispose();
  });

  test('an expired membership means revoked', () async {
    shared.devices['dev-a'] = deviceA.copyWith(
      expiresAt: DateTime.now().toUtc().subtract(const Duration(minutes: 1)),
    );
    final e = engine();
    await e.start();
    expect(revoked, ['expired']);
    await e.dispose();
  });

  test(
    'joining again replaces a removed row from an earlier membership',
    () async {
      shared.devices['dev-b'] = deviceB;
      shared.devices['dev-a'] = deviceA.copyWith(status: DeviceStatus.removed);
      final e = engine();
      await e.start();
      expect(revoked, isEmpty);
      expect(e.status.phase, SyncPhase.idle);
      expect(shared.devices['dev-a']!.status, DeviceStatus.active);
      await e.dispose();
    },
  );

  test('a registered device still obeys a removed row', () async {
    shared.devices['dev-a'] = deviceA.copyWith(status: DeviceStatus.removed);
    final e = engine(assumeRegistered: true);
    await e.start();
    expect(revoked, ['removed']);
    expect(shared.devices['dev-a']!.status, DeviceStatus.removed);
    await e.dispose();
  });

  test('status removed set later is noticed on the next heartbeat', () async {
    final e = engine();
    await e.start();
    expect(e.status.phase, SyncPhase.idle);
    shared.devices['dev-a'] = shared.devices['dev-a']!.copyWith(
      status: DeviceStatus.removed,
    );
    await e.refreshDevices();
    expect(e.status.phase, SyncPhase.revoked);
    expect(revoked, ['removed']);
    await e.dispose();
  });

  test('heartbeat keeps membership fields set by another device', () async {
    final e = engine();
    await e.start();
    // Manager changes our role and expiry directly in the backend.
    final until = DateTime.now().toUtc().add(const Duration(days: 1));
    await backend.updateDevice(
      shared.devices['dev-a']!.copyWith(
        role: DeviceRole.sendOnly,
        expiresAt: until,
        pairedBy: 'dev-b',
      ),
    );
    await e.refreshDevices();
    final me = shared.devices['dev-a']!;
    expect(me.role, DeviceRole.sendOnly);
    expect(me.expiresAt, until);
    expect(me.pairedBy, 'dev-b');
    expect(e.role, DeviceRole.sendOnly);
    expect(e.status.role, DeviceRole.sendOnly);
    await e.dispose();
  });

  test('a paused device holds sync and skips the paused period', () async {
    shared.devices['dev-a'] = deviceA.copyWith(status: DeviceStatus.paused);
    final changes = <bool>[];
    final e = SyncEngine(
      backend: backend,
      store: store,
      device: deviceA,
      pollInterval: const Duration(hours: 1),
      heartbeatInterval: const Duration(hours: 1),
      onPausedChanged: ({required paused}) => changes.add(paused),
    );
    await e.start();
    expect(e.isPaused, isTrue);
    expect(e.status.phase, SyncPhase.paused);
    expect(revoked, isEmpty);

    // Written by another device, and captured here, while paused.
    backend.injectRemote(textItem('while paused', deviceId: 'dev-b'));
    store.capture(textItem('captured while paused'));
    await e.syncNow();
    expect(store.items.values.map((i) => i.content), [
      'captured while paused',
    ]);
    expect(shared.items.values.map((i) => i.content), ['while paused']);

    // Resume: neither crosses over, later clips do.
    await backend.updateDevice(
      shared.devices['dev-a']!.copyWith(status: DeviceStatus.active),
    );
    await e.refreshDevices();
    expect(e.isPaused, isFalse);
    backend.injectRemote(textItem('after resume', deviceId: 'dev-b'));
    await e.syncNow();
    expect(e.status.phase, isNot(SyncPhase.paused));
    expect(
      store.items.values.map((i) => i.content),
      unorderedEquals(['captured while paused', 'after resume']),
    );
    expect(
      shared.items.values.map((i) => i.content),
      unorderedEquals(['while paused', 'after resume']),
    );
    expect(changes, [true, false]);
    await e.dispose();
  });

  test('deletions and sends queued while paused go out on resume', () async {
    final old = textItem('before pause');
    store.capture(old);
    final e = engine();
    await e.start();
    await backend.updateDevice(
      shared.devices['dev-a']!.copyWith(status: DeviceStatus.paused),
    );
    await e.refreshDevices();
    expect(e.isPaused, isTrue);

    final now = DateTime.now().toUtc();
    store
      ..capture(old.copyWith(content: '', deletedAt: now, updatedAt: now))
      ..capture(
        ClipItem.create(
          id: 'sent-to-b',
          deviceId: 'dev-a',
          deviceName: 'A',
          type: ClipContentType.text,
          content: 'for B',
          contentHash: sha256Hex('for B'),
          sizeBytes: 5,
          now: now,
          targetDeviceId: 'dev-b',
        ),
      )
      ..capture(textItem('copied while paused'));
    await e.syncNow();
    expect(shared.items[old.id]!.isDeleted, isFalse);

    await backend.updateDevice(
      shared.devices['dev-a']!.copyWith(status: DeviceStatus.active),
    );
    await e.refreshDevices();
    await e.syncNow();
    expect(shared.items[old.id]!.isDeleted, isTrue);
    expect(shared.items['sent-to-b']!.content, 'for B');
    expect(
      shared.items.values.map((i) => i.content),
      isNot(contains('copied while paused')),
    );
    expect(store.unsynced, isEmpty);
    await e.dispose();
  });

  test('a resume missed while stopped still skips the pause', () async {
    shared.devices['dev-a'] = deviceA;
    backend.injectRemote(textItem('while paused', deviceId: 'dev-b'));
    store.capture(textItem('captured while paused'));
    final e = SyncEngine(
      backend: backend,
      store: store,
      device: deviceA,
      pollInterval: const Duration(hours: 1),
      heartbeatInterval: const Duration(hours: 1),
      paused: true,
    );
    await e.start();
    expect(e.isPaused, isFalse);
    expect(store.items.values.map((i) => i.content), [
      'captured while paused',
    ]);
    expect(store.unsynced, isEmpty);
    expect(shared.items.values.map((i) => i.content), ['while paused']);
    await e.dispose();
  });

  test('clips from paused devices are skipped on pull', () async {
    shared.devices['dev-b'] = deviceB.copyWith(status: DeviceStatus.paused);
    backend.injectRemote(textItem('from paused', deviceId: 'dev-b'));
    final e = engine();
    await e.start();
    expect(store.items, isEmpty);
    expect(e.trustedDevices.keys, isNot(contains('dev-b')));
    await e.dispose();
  });

  test('clips from blocked devices are skipped on pull', () async {
    shared.devices['dev-b'] = deviceB.copyWith(status: DeviceStatus.blocked);
    shared.devices['dev-c'] = Device(
      id: 'dev-c',
      name: 'C',
      platform: 'test',
      lastSeen: DateTime.now().toUtc(),
    );
    backend
      ..injectRemote(textItem('from blocked', deviceId: 'dev-b'))
      ..injectRemote(textItem('from c', deviceId: 'dev-c'));
    final e = engine();
    await e.start();
    expect(store.items.values.map((i) => i.content), ['from c']);
    await e.dispose();
  });

  test('targeted clips reach only the addressed device', () async {
    final forMe = ClipItem.create(
      id: 'for-a',
      deviceId: 'dev-b',
      deviceName: 'B',
      type: ClipContentType.text,
      content: 'for a',
      contentHash: sha256Hex('for a'),
      sizeBytes: 5,
      now: DateTime.now().toUtc(),
      targetDeviceId: 'dev-a',
    );
    final forOther = ClipItem.create(
      id: 'for-c',
      deviceId: 'dev-b',
      deviceName: 'B',
      type: ClipContentType.text,
      content: 'for c',
      contentHash: sha256Hex('for c'),
      sizeBytes: 5,
      now: DateTime.now().toUtc(),
      targetDeviceId: 'dev-c',
    );
    backend
      ..injectRemote(forMe)
      ..injectRemote(forOther);
    final e = engine();
    await e.start();
    expect(store.items.keys, ['for-a']);
    // Cursor still advanced past the skipped item.
    expect(store.cursor, isNotNull);
    await e.dispose();
  });

  test('send-only role pushes but never pulls', () async {
    shared.devices['dev-a'] = deviceA.copyWith(role: DeviceRole.sendOnly);
    backend.injectRemote(textItem('remote', deviceId: 'dev-b'));
    store.capture(textItem('mine'));
    final e = engine();
    await e.start();
    expect(store.unsynced, isEmpty, reason: 'push happened');
    expect(store.items.length, 1, reason: 'nothing pulled');
    expect(e.role, DeviceRole.sendOnly);
    await e.dispose();
  });

  test('receive-only role pulls but never pushes', () async {
    shared.devices['dev-a'] = deviceA.copyWith(role: DeviceRole.receiveOnly);
    backend.injectRemote(textItem('remote', deviceId: 'dev-b'));
    final mine = textItem('mine');
    store.capture(mine);
    final e = engine();
    await e.start();
    expect(store.unsynced, {mine.id}, reason: 'outbox untouched');
    expect(shared.items.containsKey(mine.id), isFalse);
    expect(store.items.length, 2, reason: 'remote applied');
    await e.dispose();
  });

  test('management helpers write through and refresh the list', () async {
    shared.devices['dev-b'] = deviceB;
    final e = engine();
    await e.start();
    final snapshots = <List<Device>>[];
    e.devices.listen(snapshots.add);

    await e.blockDevice('dev-b');
    expect(shared.devices['dev-b']!.status, DeviceStatus.blocked);
    await e.unblockDevice('dev-b');
    await e.pauseDevice('dev-b');
    expect(shared.devices['dev-b']!.status, DeviceStatus.paused);
    await e.resumeDevice('dev-b');
    expect(shared.devices['dev-b']!.status, DeviceStatus.active);
    expect(shared.devices['dev-b']!.status, DeviceStatus.active);
    await e.setDeviceRole('dev-b', DeviceRole.receiveOnly);
    expect(shared.devices['dev-b']!.role, DeviceRole.receiveOnly);
    final until = DateTime.now().toUtc().add(const Duration(hours: 2));
    await e.setDeviceExpiry('dev-b', until);
    expect(shared.devices['dev-b']!.expiresAt, until);
    await e.setDeviceExpiry('dev-b', null);
    expect(shared.devices['dev-b']!.expiresAt, isNull);
    await e.removeDevice('dev-b');
    expect(shared.devices['dev-b']!.status, DeviceStatus.removed);
    await e.forgetDevice('dev-b');
    expect(shared.devices.containsKey('dev-b'), isFalse);
    await e.inviteDevice(id: 'dev-new', role: DeviceRole.sendOnly);
    final invited = shared.devices['dev-new']!;
    expect(invited.isPending, isTrue);
    expect(invited.role, DeviceRole.sendOnly);
    expect(invited.pairedBy, 'dev-a');
    expect(snapshots, isNotEmpty);
    expect(e.knownDevices.map((d) => d.id), containsAll(['dev-a', 'dev-new']));
    expect(() => e.blockDevice('nope'), throwsA(isA<BackendException>()));
    await e.dispose();
  });

  test('a joining device adopts the invited row and its role', () async {
    // Host pre-created the row; the joiner (dev-a) heartbeats into it.
    shared.devices['dev-a'] = Device(
      id: 'dev-a',
      name: 'Pending device',
      platform: '',
      lastSeen: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      role: DeviceRole.receiveOnly,
      pairedBy: 'dev-host',
    );
    final e = engine();
    await e.start();
    final me = shared.devices['dev-a']!;
    expect(me.name, 'A');
    expect(me.platform, 'test');
    expect(me.isPending, isFalse);
    expect(me.role, DeviceRole.receiveOnly);
    expect(me.pairedBy, 'dev-host');
    expect(e.role, DeviceRole.receiveOnly);
    await e.dispose();
  });

  test('device list failure does not stop syncing', () async {
    final e = engine();
    await e.start();
    backend.failWith = BackendException('boom', isTransient: true);
    await e.refreshDevices();
    expect(e.status.phase, isNot(SyncPhase.revoked));
    backend.failWith = null;
    await e.dispose();
  });
}
