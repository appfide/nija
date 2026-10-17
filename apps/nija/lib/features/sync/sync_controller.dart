import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nija/core/build_info.dart';
import 'package:nija/core/logging.dart';
import 'package:nija/core/platform_info.dart';
import 'package:nija/data/settings/app_settings.dart';
import 'package:nija/data/settings/secret_store.dart';
import 'package:nija/platform/clipboard_service.dart';
import 'package:nija/providers.dart';
import 'package:nija_core/nija_core.dart';
import 'package:uuid/uuid.dart';

/// Owns the [SyncEngine], the connected backend and the clipboard capture
/// pipeline. Rebuilds when sync-affecting settings change.
final syncControllerProvider = NotifierProvider<SyncController, SyncStatus>(
  SyncController.new,
);

/// Live device list of the current sync group (empty in local-only mode).
final deviceListProvider = StreamProvider<List<Device>>(
  (ref) => ref.watch(syncControllerProvider.notifier).devices,
);

/// Why this device lost access to its sync group. Set once by the
/// controller when the engine reports [SyncPhase.revoked]; the UI shows it
/// and clears it.
class RevocationNotice {
  /// Creates a notice.
  const RevocationNotice({required this.reason, required this.backendName});

  /// `blocked`, `removed` or `expired`.
  final String reason;

  /// Display name of the backend the device was removed from.
  final String backendName;

  /// User-facing headline.
  String get title => switch (reason) {
    'blocked' => 'This device was blocked',
    'expired' => 'This device’s access has expired',
    _ => 'This device was removed',
  };

  /// User-facing detail.
  String get detail =>
      'Another device in your $backendName sync group ${switch (reason) {
        'blocked' => 'blocked this device',
        'expired' => 'gave this device temporary access, which has now ended',
        _ => 'removed this device',
      }}. The database credentials and passphrase were deleted from this device; '
      'your local history is still here. To rejoin, pair again from a device that still has access.';
}

/// An admin key seen on the group that this device has not pinned yet.
final pendingTrustProvider =
    NotifierProvider<PendingTrustNotifier, PendingTrust?>(
      PendingTrustNotifier.new,
    );

/// Holds the pending [PendingTrust].
class PendingTrustNotifier extends Notifier<PendingTrust?> {
  @override
  PendingTrust? build() => null;

  /// Pending request.
  PendingTrust? get request => state;

  /// Sets or clears the request.
  set request(PendingTrust? value) => state = value;
}

/// Pending revocation notice, or `null`.
final revocationProvider =
    NotifierProvider<RevocationNotifier, RevocationNotice?>(
      RevocationNotifier.new,
    );

/// Holds the pending [RevocationNotice].
class RevocationNotifier extends Notifier<RevocationNotice?> {
  @override
  RevocationNotice? build() => null;

  /// Pending notice.
  RevocationNotice? get notice => state;

  /// Sets or clears the notice.
  set notice(RevocationNotice? value) => state = value;
}

/// A generated pairing code and its PIN, shown by the host.
class PairingSession {
  /// Creates a session.
  const PairingSession({
    required this.code,
    required this.pin,
    required this.deviceId,
    required this.validUntil,
    required this.passphraseIncluded,
    required this.encryption,
    required this.grantsAdmin,
  });

  /// Sealed code (QR / text).
  final String code;

  /// 8-digit PIN the joiner must type.
  final String pin;

  /// Device id pre-created for the joiner.
  final String deviceId;

  /// After this instant the joiner refuses the code.
  final DateTime validUntil;

  /// Whether the E2E passphrase travelled inside the code.
  final bool passphraseIncluded;

  /// Whether the group encrypts (joiner must type the passphrase when it
  /// was not included).
  final bool encryption;

  /// Whether the code also carries the admin key.
  final bool grantsAdmin;
}

/// Sync lifecycle notifier; state is the engine status.
class SyncController extends Notifier<SyncStatus> {
  SyncEngine? _engine;
  SyncBackend? _backend;
  ClipboardService? _clipboard;
  StreamSubscription<SyncStatus>? _statusSub;
  StreamSubscription<List<ClipItem>>? _incomingSub;
  StreamSubscription<List<Device>>? _devicesSub;
  StreamSubscription<PendingTrust>? _trustSub;
  StreamSubscription<ClipItem>? _captureSub;
  Timer? _retention;
  final _devicesOut = StreamController<List<Device>>.broadcast();
  Future<void> _lifecycle = Future.value();
  DeviceKeys? _identity;
  AdminKey? _adminKey;
  String? _trustedAdminPub;

  @override
  SyncStatus build() {
    ref
      ..listen<AppSettings>(settingsProvider, (prev, next) {
        if (prev == null) return;
        final c = _clipboard;
        if (c != null) {
          c
            ..deviceId = next.deviceId
            ..deviceName = next.deviceName
            ..captureImages = next.captureImages
            ..maxInlineBytes = next.maxInlineKb * 1024
            ..skipSensitive = next.skipSensitive
            ..skipSecretLike = next.skipSecretLike
            // Only while syncing: in local-only mode nothing else brings
            // those copies in.
            ..skipUniversalClipboard =
                next.skipUniversalClipboard && next.syncsRemotely
            ..paused = next.capturePaused;
        }
        if (prev.capturePaused != next.capturePaused) {
          unawaited(
            ref
                .read(desktopShellProvider)
                ?.setPaused(paused: next.capturePaused),
          );
        }
        // Only a running engine needs restarting; before start() the seeded
        // secrets simply become part of the initial configuration.
        final toggled = prev.remoteSyncEnabled != next.remoteSyncEnabled;
        if ((_engine != null || toggled) &&
            AppSettings.syncAffecting(prev, next)) {
          unawaited(restart());
        }
      })
      ..onDispose(() => unawaited(_teardown()));
    return const SyncStatus.stopped();
  }

  /// Backend currently connected (for settings screens).
  SyncBackend? get backend => _backend;

  /// Clipboard service (for share/notification entry points).
  ClipboardService? get clipboard => _clipboard;

  /// Device list snapshots from the running engine.
  Stream<List<Device>> get devices => _devicesOut.stream;

  /// Last known device list.
  List<Device> get knownDevices => _engine?.knownDevices ?? const [];

  /// Ids of devices whose membership verifies (signed group) or is active
  /// (legacy group).
  Set<String> get trustedDeviceIds =>
      _engine?.trustedDevices.keys.toSet() ?? const {};

  /// Whether a remote group is connected, so devices can be managed and
  /// pairing codes generated.
  bool get canManageDevices =>
      _engine != null && ref.read(settingsProvider).syncsRemotely;

  /// Whether this device holds the group's admin key.
  bool get isAdmin => _adminKey != null;

  /// Whether the group has a pinned admin key (signed membership).
  bool get isSignedGroup => _trustedAdminPub != null;

  /// Pinned admin public key (base64), or `null`.
  String? get adminPublicKey => _trustedAdminPub;

  /// Fingerprint of the pinned admin key, or `null`.
  String? get adminFingerprint =>
      _trustedAdminPub == null ? null : keyFingerprint(_trustedAdminPub!);

  /// Whether this device may change membership: legacy group, or admin.
  bool get canEditMembership => canManageDevices && (!isSignedGroup || isAdmin);

  /// This device's signing-key fingerprint, or `null` before first start.
  String? get deviceFingerprint => _identity?.fingerprint;

  /// Runs [op] after every earlier lifecycle operation finished, so two
  /// restarts (settings listener + an explicit call) never interleave and
  /// spawn two engines.
  Future<void> _serial(Future<void> Function() op) {
    final next = _lifecycle.catchError((_) {}).then((_) => op());
    _lifecycle = next;
    return next;
  }

  /// Starts sync, then clipboard capture, from current settings.
  Future<void> start() async {
    final s = ref.read(settingsProvider);
    // Engine first: a clipboard permission prompt on mobile must never
    // delay connecting to the backend.
    await _serial(() => _startEngine(s));
    if (_clipboard == null) {
      final c = ClipboardService(
        deviceId: s.deviceId,
        deviceName: s.deviceName,
        captureImages: s.captureImages,
        maxInlineBytes: s.maxInlineKb * 1024,
        paused: s.capturePaused,
        skipSensitive: s.skipSensitive,
        skipSecretLike: s.skipSecretLike,
        skipUniversalClipboard: s.skipUniversalClipboard && s.syncsRemotely,
      );
      _captureSub = c.captured.listen(_onCaptured);
      _clipboard = c;
      await c.start();
    }
  }

  Future<void> _onCaptured(ClipItem item) async {
    final store = ref.read(localStoreProvider);
    // A receive-only device, or one with database sync turned off, keeps
    // what it copies to itself.
    final localOnly =
        !state.role.canSend || !ref.read(settingsProvider).remoteSyncEnabled;
    final inserted = await store.capture(item, localOnly: localOnly);
    if (inserted) {
      log.i(
        'captured ${item.type.wire} ${item.sizeBytes}B'
        '${localOnly ? ' (local only)' : ''}',
      );
      if (!localOnly) await _engine?.syncNow();
    }
  }

  /// Stops and starts the engine (settings changed).
  Future<void> restart() => _serial(() async {
    await _stopEngine();
    if (!ref.mounted) return;
    await _startEngine(ref.read(settingsProvider));
  });

  /// Push + pull now.
  Future<void> syncNow() async => _engine?.syncNow();

  /// Reads the clipboard immediately (mobile entry points).
  Future<void> captureNow() async => _clipboard?.checkNow();

  /// Checks clipboard access for the Permissions section.
  Future<ClipboardProbe> probeClipboard() async =>
      _clipboard?.probe() ??
      const ClipboardProbe(
        ClipboardAccess.blocked,
        'Capture service not running.',
      );

  /// Writes [item] to the clipboard.
  Future<void> copyToClipboard(ClipItem item) async => _clipboard?.write(item);

  /// Stops recording the clipboard while [held] is true, without touching
  /// the saved *Pause capture* setting: used while the user copies a
  /// credential into a dialog, so it never reaches the synced history.
  void holdCapture({required bool held}) {
    final c = _clipboard;
    if (c == null) return;
    c.paused = held || ref.read(settingsProvider).capturePaused;
  }

  /// Writes [text] to the clipboard without recording it in history.
  Future<void> copyTextUnrecorded(String text) async =>
      _clipboard?.writeText(text);

  /// Whether this device captured [item], and so may delete it from the
  /// group. Other devices' clips can only be removed from this device.
  bool owns(ClipItem item) =>
      item.deviceId == ref.read(settingsProvider).deviceId;

  /// Powers the admin granted this device (signed groups only).
  Set<DevicePermission> get permissions =>
      _engine?.permissions ?? const <DevicePermission>{};

  /// Whether this device may delete every clip from the database: any
  /// device of a legacy group; in a signed one the admin, or a member the
  /// admin allowed to.
  bool get canDeleteRemoteHistory =>
      ref.read(settingsProvider).syncsRemotely &&
      (!isSignedGroup ||
          isAdmin ||
          permissions.contains(DevicePermission.clearHistory));

  /// Deletes [item]. A clip this device captured is tombstoned locally and
  /// (via outbox) remotely; another device's clip is only removed here.
  Future<void> delete(ClipItem item) async {
    final store = ref.read(localStoreProvider);
    final now = DateTime.now().toUtc();
    if (!owns(item)) return store.hide(item.id, now);
    await store.delete(item.id, now);
    await _engine?.syncNow();
  }

  /// Queues a copy of [item] addressed to [deviceId] only.
  Future<void> sendToDevice(ClipItem item, String deviceId) async {
    final s = ref.read(settingsProvider);
    final copy = ClipItem.create(
      id: const Uuid().v4(),
      deviceId: s.deviceId,
      deviceName: s.deviceName,
      type: item.type,
      content: item.content,
      contentHash: item.contentHash,
      sizeBytes: item.sizeBytes,
      now: DateTime.now().toUtc(),
      blobRef: item.blobRef,
      targetDeviceId: deviceId,
    );
    await ref.read(localStoreProvider).enqueue(copy);
    await _engine?.syncNow();
  }

  /// Tests a backend configuration without touching the running engine.
  Future<(ConnectionCheck, SchemaCheck?)> probe(BackendConfig config) async {
    final b = ref.read(backendRegistryProvider).create(config.backendId);
    try {
      await b.connect(config);
      final conn = await b.testConnection();
      if (!conn.ok) return (conn, null);
      final schema = await b.verifySchema();
      return (conn, schema);
    } on BackendException catch (e) {
      return (ConnectionCheck.failure(e.message), null);
    } catch (e) {
      return (ConnectionCheck.failure(redactSecrets(e.toString())), null);
    } finally {
      await b.dispose();
    }
  }

  /// Runs local + remote retention.
  Future<void> runRetention() async {
    final days = ref.read(settingsProvider).retentionDays;
    if (days <= 0) return;
    final before = DateTime.now().toUtc().subtract(Duration(days: days));
    try {
      final local = await ref.read(localStoreProvider).purgeBefore(before);
      final remote = await _backend?.purgeBefore(before) ?? 0;
      log.i(
        'retention: purged $local local, $remote remote (older than $days d)',
      );
    } catch (e) {
      log.w('retention failed', error: e);
    }
  }

  /// Deletes every clip stored on this device. The database keeps its copy
  /// and later clips keep syncing. Returns how many were removed.
  Future<int> deleteLocalHistory() async {
    var removed = 0;
    // With the engine stopped, no pull that started earlier can write the
    // cleared clips back.
    await _serial(() async {
      await _stopEngine();
      try {
        removed = await ref.read(localStoreProvider).clearHistory();
      } finally {
        if (ref.mounted) await _startEngine(ref.read(settingsProvider));
      }
    });
    log.i('deleted $removed clip(s) from this device');
    return removed;
  }

  /// Physically deletes every clip and tombstone in the connected database,
  /// for every device in the group. Device rows, membership and keys stay,
  /// so the group keeps syncing; each device keeps its own local history.
  /// Returns how many rows were removed.
  Future<int> deleteRemoteHistory() async {
    final s = ref.read(settingsProvider);
    if (!s.syncsRemotely) {
      throw StateError('Local-only mode has no database to delete from');
    }
    if (!canDeleteRemoteHistory) {
      throw StateError(
        'Only the admin, or a device it allows, can clear this group',
      );
    }
    var removed = 0;
    // The engine stays stopped meanwhile so no push lands mid-delete.
    await _serial(() async {
      await _stopEngine();
      final b = ref.read(backendRegistryProvider).create(s.backendId);
      try {
        // Our queued deletions would only write deletion records back.
        await ref.read(localStoreProvider).dropPendingTombstones();
        await b.connect(s.backendConfig);
        // Far-future cutoff: a device whose clock runs ahead stamps rows
        // with future `updated_at` values.
        final cutoff = DateTime.utc(9999);
        // Firestore and CouchDB delete one page per call. The bound stops a
        // backend that keeps reporting rows it cannot delete.
        for (var page = 0; page < 10000; page++) {
          final n = await b.purgeBefore(cutoff);
          if (n <= 0) break;
          removed += n;
        }
        // A database policy can refuse deletes without an error (Supabase
        // row level security returns zero rows): say so instead of
        // reporting success.
        final left = await b.pullSince(null, excludeDeviceId: '', limit: 1);
        if (left.isNotEmpty) {
          throw BackendException(
            'The database kept some clips after deleting $removed. Check that '
            'its access rules allow this device to delete clip rows.',
          );
        }
      } finally {
        await b.dispose();
        if (ref.mounted) await _startEngine(ref.read(settingsProvider));
      }
    });
    log.i('deleted $removed row(s) from the ${s.backendId} database');
    return removed;
  }

  /// Clips in the database that predate encryption and are still readable by
  /// anyone holding the credentials. Empty when sync is not running.
  Future<List<ClipItem>> plaintextClips() async {
    final engine = _engine;
    if (engine == null || !ref.read(settingsProvider).encryptionEnabled) {
      return const [];
    }
    try {
      return await engine.plaintextClips();
    } catch (e) {
      log.w('plaintext scan failed', error: e);
      return const [];
    }
  }

  /// Encrypted clips this device wrote before the fingerprint was keyed, whose
  /// `content_hash` still gives away short content. Empty when sync is off.
  Future<List<ClipItem>> legacyHashedClips() async {
    final engine = _engine;
    if (engine == null || !ref.read(settingsProvider).encryptionEnabled) {
      return const [];
    }
    try {
      return await engine.legacyHashedClips();
    } catch (e) {
      log.w('fingerprint scan failed', error: e);
      return const [];
    }
  }

  /// Rewrites those fingerprints. Returns how many. Keeps the clips.
  Future<int> rehashLegacyClips() async {
    final fixed = await _managed.rehashLegacyClips();
    log.i('rewrote $fixed leaky fingerprint(s)');
    return fixed;
  }

  /// Overwrites those clips with empty tombstones. Returns how many.
  Future<int> purgePlaintextClips() async {
    final cleared = await _managed.purgePlaintextClips();
    log.i('purged $cleared plaintext clip(s) from the database');
    return cleared;
  }

  // --- Device management ---------------------------------------------------

  SyncEngine get _managed =>
      _engine ?? (throw StateError('Sync is not running'));

  /// Re-reads the device list.
  Future<List<Device>> refreshDevices() => _managed.refreshDevices();

  /// See [SyncEngine.blockDevice].
  Future<void> blockDevice(String id) => _managed.blockDevice(id);

  /// See [SyncEngine.unblockDevice].
  Future<void> unblockDevice(String id) => _managed.unblockDevice(id);

  /// See [SyncEngine.removeDevice].
  Future<void> removeDevice(String id) => _managed.removeDevice(id);

  /// See [SyncEngine.forgetDevice].
  Future<void> forgetDevice(String id) => _managed.forgetDevice(id);

  /// See [SyncEngine.pauseDevice].
  Future<void> pauseDevice(String id) => _managed.pauseDevice(id);

  /// See [SyncEngine.resumeDevice].
  Future<void> resumeDevice(String id) => _managed.resumeDevice(id);

  /// See [SyncEngine.setDevicePermissions].
  Future<void> setDevicePermissions(
    String id,
    Set<DevicePermission> permissions,
  ) => _managed.setDevicePermissions(id, permissions);

  /// See [SyncEngine.makeAdmin].
  Future<void> makeAdmin(String id) => _managed.makeAdmin(id);

  /// See [SyncEngine.setDeviceRole].
  Future<void> setDeviceRole(String id, DeviceRole role) =>
      _managed.setDeviceRole(id, role);

  /// See [SyncEngine.setDeviceExpiry].
  Future<void> setDeviceExpiry(String id, DateTime? expiresAt) =>
      _managed.setDeviceExpiry(id, expiresAt);

  // --- Pairing -------------------------------------------------------------

  /// Pre-registers a device row and seals the current backend settings into
  /// a pairing code. The row stays pending until the joiner's first
  /// heartbeat; cancel it with [forgetDevice] if the code goes unused.
  Future<PairingSession> createPairing({
    required DeviceRole role,
    DateTime? expiresAt,
    bool includePassphrase = false,
    bool grantAdmin = false,
    Duration validity = PairingCodec.defaultValidity,
  }) async {
    final s = ref.read(settingsProvider);
    if (!s.syncsRemotely) {
      throw StateError('Local-only mode has no database to share');
    }
    if (isSignedGroup && !isAdmin) {
      throw StateError('Only the admin device can add devices to this group');
    }
    final engine = _managed;
    final id = const Uuid().v4();
    final pin = PairingCodec.generatePin();
    final now = DateTime.now().toUtc();
    // The host generates the new device's identity so it can sign its
    // public keys (and seal the passphrase to it) before it ever connects.
    final joinerKeys = await DeviceKeys.generate();
    String? passphrase;
    if (includePassphrase && s.encryptionEnabled) {
      passphrase = await ref.read(settingsRepositoryProvider).loadPassphrase();
    }
    await engine.inviteDevice(
      id: id,
      role: role,
      expiresAt: expiresAt,
      signPub: joinerKeys.signPub,
      boxPub: joinerKeys.boxPub,
      admin: grantAdmin && isAdmin,
      passphrase: passphrase,
    );
    final adminPub = _trustedAdminPub ?? _adminKey?.publicKey;
    final payload = PairingPayload(
      backendId: s.backendId,
      values: Map.of(s.backendValues),
      deviceId: id,
      issuedAt: now,
      validUntil: now.add(validity),
      hostDeviceId: s.deviceId,
      hostDeviceName: s.deviceName,
      deviceKeys: await joinerKeys.encode(),
      adminPub: adminPub,
      adminKey: grantAdmin && isAdmin ? await _adminKey!.encode() : null,
      encryption: s.encryptionEnabled,
      passphraseDelivered: passphrase != null,
      role: role,
      expiresAt: expiresAt,
    );
    final code = await PairingCodec.seal(payload, pin);
    log.i('pairing code issued for $id (${role.wire})');
    return PairingSession(
      code: code,
      pin: pin,
      deviceId: id,
      validUntil: payload.validUntil,
      passphraseIncluded: passphrase != null,
      encryption: s.encryptionEnabled,
      grantsAdmin: payload.adminKey != null,
    );
  }

  /// Adopts everything in [payload]: device id, backend settings and
  /// (optionally) the passphrase. The settings listener restarts the engine
  /// against the new group.
  Future<void> joinFromPairing(
    PairingPayload payload, {
    String? passphrase,
  }) async {
    final registry = ref.read(backendRegistryProvider);
    if (registry.descriptor(payload.backendId) == null) {
      throw StateError(
        'This code is for a database type this build does not support (${payload.backendId}).',
      );
    }
    final repo = ref.read(settingsRepositoryProvider);
    if (payload.needsPassphrase && (passphrase == null || passphrase.isEmpty)) {
      throw StateError('This group uses encryption; a passphrase is required.');
    }
    final scope = AppSettings(
      deviceId: payload.deviceId,
      deviceName: '',
      backendId: payload.backendId,
      backendValues: payload.values,
    ).backendScope;
    await repo.saveRegisteredScope(null);
    await ref.read(localStoreProvider).resetCursor();
    // Identity chosen by the host; keys arrive only through the PIN-sealed
    // code, never through the database.
    final keys = payload.deviceKeys;
    if (keys != null) {
      await repo.saveDeviceKeys(keys);
      _identity = await DeviceKeys.decode(keys);
    }
    await repo.clearGroupTrust(scope);
    await repo.saveTrustedAdminPub(scope, payload.adminPub);
    await repo.saveAdminKey(scope, payload.adminKey);
    // Passphrase: either sealed to us in our device row (arrives on first
    // check-in) or typed now.
    await repo.saveKeyring(
      payload.encryption && !payload.passphraseDelivered
          ? {1: passphrase!}
          : {},
    );
    await ref
        .read(settingsProvider.notifier)
        .update(
          (x) => x.copyWith(
            deviceId: payload.deviceId,
            backendId: payload.backendId,
            backendValues: Map.of(payload.values),
            encryptionEnabled: payload.encryption,
            onboarded: true,
          ),
        );
    log.i('joined ${payload.backendId} group from ${payload.hostDeviceName}');
  }

  // --- Group security --------------------------------------------------------

  /// Turns the current (legacy) group into a signed one managed by this
  /// device: generates the admin key, pins it, signs every active row.
  Future<void> secureGroup() async {
    final s = ref.read(settingsProvider);
    if (!s.syncsRemotely) throw StateError('No sync group');
    if (isSignedGroup) throw StateError('Group is already secured');
    final repo = ref.read(settingsRepositoryProvider);
    final key = await AdminKey.generate();
    await repo.saveAdminKey(s.backendScope, await key.encode());
    await repo.saveTrustedAdminPub(s.backendScope, key.publicKey);
    await restart();
    await _managed.secureGroup();
    log.i('group secured; admin key ${key.fingerprint}');
  }

  /// Default protection for a group this device just created or joined by
  /// typing credentials: turns on encryption with a fresh random passphrase
  /// (other devices receive it sealed through pairing) and secures the
  /// group with an admin key. No-op when the group is already signed.
  Future<void> secureNewGroup() async {
    final s = ref.read(settingsProvider);
    if (!s.syncsRemotely) return;
    final repo = ref.read(settingsRepositoryProvider);
    if (repo.loadTrustedAdminPub(s.backendScope) != null) return;
    if (!s.encryptionEnabled) {
      final bytes = List<int>.generate(32, (_) => Random.secure().nextInt(256));
      await repo.saveKeyring({1: base64UrlEncode(bytes)});
      await ref
          .read(settingsProvider.notifier)
          .update((x) => x.copyWith(encryptionEnabled: true));
    }
    await secureGroup();
  }

  /// Whether other verified admins exist in this group, so it stays
  /// managed after this device leaves.
  bool get hasOtherAdmin {
    final self = ref.read(settingsProvider).deviceId;
    return (_engine?.trustedDevices.values ?? const <Device>[]).any(
      (d) => d.admin && d.id != self,
    );
  }

  /// Leaves the current group: deletes this device's row (best effort),
  /// forgets the database credentials, passphrase and admin key, and goes
  /// back to local-only. With [deleteHistory] the local clips go too.
  Future<void> leaveGroup({bool deleteHistory = false}) async {
    final s = ref.read(settingsProvider);
    if (!s.syncsRemotely) throw StateError('This device is not in a group');
    await _serial(() async {
      await _stopEngine();
      final b = ref.read(backendRegistryProvider).create(s.backendId);
      try {
        await b.connect(s.backendConfig);
        await b.deleteDevice(s.deviceId);
      } catch (e) {
        // Leaving must work offline too; the row then just goes stale.
        log.w('could not delete this device row while leaving', error: e);
      } finally {
        await b.dispose();
      }
      await _forgetGroup(s);
      if (deleteHistory) await ref.read(localStoreProvider).clearHistory();
    });
    log.i('left the ${s.backendId} group');
    await ref
        .read(settingsProvider.notifier)
        .update(
          (x) => x.copyWith(
            backendId: 'memory',
            backendValues: const {},
            encryptionEnabled: false,
          ),
        );
    // The engine was stopped, so the settings listener does not restart it.
    await restart();
  }

  /// Starts a new group on the connected database, with this device as its
  /// admin: deletes every clip and device row, then creates a new admin key
  /// and a new passphrase. Every other device notices on its next check-in
  /// that it was removed and forgets the credentials; pair them again.
  ///
  /// This is also how a group whose admin is lost gets one again. It needs
  /// nothing but the database credentials, like any direct database edit.
  Future<void> startNewGroup() async {
    final s = ref.read(settingsProvider);
    if (!s.syncsRemotely) throw StateError('Connect a database first');
    final repo = ref.read(settingsRepositoryProvider);
    await _serial(() async {
      await _stopEngine();
      final b = ref.read(backendRegistryProvider).create(s.backendId);
      try {
        await b.connect(s.backendConfig);
        final cutoff = DateTime.utc(9999);
        for (var page = 0; page < 10000; page++) {
          if (await b.purgeBefore(cutoff) <= 0) break;
        }
        for (final d in await b.listDevices()) {
          await b.deleteDevice(d.id);
        }
      } finally {
        await b.dispose();
      }
      await repo.clearGroupTrust(s.backendScope);
      _adminKey = null;
      _trustedAdminPub = null;
      await repo.saveRegisteredScope(null);
      await ref.read(localStoreProvider).resetCursor();
      // Old members know the old passphrase: the new group gets its own.
      final bytes = List<int>.generate(32, (_) => Random.secure().nextInt(256));
      await repo.saveKeyring({1: base64UrlEncode(bytes)});
    });
    if (!s.encryptionEnabled) {
      // The listener restarts the engine with encryption on.
      await ref
          .read(settingsProvider.notifier)
          .update((x) => x.copyWith(encryptionEnabled: true));
    }
    await secureGroup();
    log.i('started a new group on the ${s.backendId} database');
  }

  /// Forgets everything that ties this device to the group in [s].
  Future<void> _forgetGroup(AppSettings s) async {
    final repo = ref.read(settingsRepositoryProvider);
    await repo.clearBackendValues(s.backendId);
    await repo.savePassphrase(null);
    await repo.saveRegisteredScope(null);
    await repo.clearGroupTrust(s.backendScope);
    if (!ref.mounted) return;
    ref.read(pendingTrustProvider.notifier).request = null;
    await ref.read(localStoreProvider).resetCursor();
    if (!_devicesOut.isClosed) _devicesOut.add(const []);
  }

  /// Newest passphrase (for showing it to the user on request).
  Future<String?> revealPassphrase() =>
      ref.read(settingsRepositoryProvider).loadPassphrase();

  /// Pins [adminPub] for the current group after the user compared the
  /// fingerprint with the admin device.
  Future<void> trustAdmin(String adminPub) async {
    final s = ref.read(settingsProvider);
    await ref
        .read(settingsRepositoryProvider)
        .saveTrustedAdminPub(s.backendScope, adminPub);
    ref.read(pendingTrustProvider.notifier).request = null;
    await restart();
  }

  /// Issues a new passphrase, [passphrase] or a random one, to every
  /// verified active device. Returns the new version.
  Future<int> rotatePassphrase({String? passphrase}) async {
    final s = ref.read(settingsProvider);
    if (!s.encryptionEnabled) throw StateError('Encryption is off');
    final bytes = List<int>.generate(32, (_) => Random.secure().nextInt(256));
    await _managed.rotatePassphrase(passphrase ?? base64UrlEncode(bytes));
    return _managed.status.keyVersion;
  }

  // --- Internals -----------------------------------------------------------

  Future<void> _startEngine(AppSettings s) async {
    // Never run two engines against the same store.
    if (_engine != null || _backend != null) await _stopEngine();
    final registry = ref.read(backendRegistryProvider);
    final store = ref.read(localStoreProvider);
    final repo = ref.read(settingsRepositoryProvider);
    final descriptor = registry.descriptor(s.backendId);
    if (descriptor == null) {
      state = SyncStatus(
        phase: SyncPhase.error,
        lastError: 'Unknown backend ${s.backendId}',
      );
      return;
    }
    final errors = s.backendConfig.validate(descriptor);
    if (errors.isNotEmpty) {
      state = SyncStatus(
        phase: SyncPhase.error,
        lastError: 'Backend settings incomplete: ${errors.values.first}',
        authFailed: true,
      );
      return;
    }

    final scope = s.backendScope;
    CipherRing? ring;
    if (s.encryptionEnabled) {
      // An empty ring is legal right after joining: the passphrase arrives
      // sealed in our device row and the engine holds pushes until then.
      ring = await CipherRing.fromPassphrases(
        await repo.loadKeyring(),
        keyScope: s.cipherKeyScope,
      );
    }
    String? keysEncoded;
    try {
      keysEncoded = await repo.loadDeviceKeys();
    } on SecretStoreTimeout {
      // Never mint a new identity because the keychain was slow: peers
      // would reject every clip signed with it.
      state = const SyncStatus(
        phase: SyncPhase.error,
        lastError:
            "Could not read this device's keys from the keychain. Answer the "
            'keychain prompt, then restart Nija.',
      );
      return;
    }
    if (keysEncoded == null) {
      final fresh = await DeviceKeys.generate();
      keysEncoded = await fresh.encode();
      await repo.saveDeviceKeys(keysEncoded);
    }
    _identity = await DeviceKeys.decode(keysEncoded);
    final adminEncoded = s.syncsRemotely
        ? await repo.loadAdminKey(scope)
        : null;
    _adminKey = adminEncoded == null
        ? null
        : await AdminKey.decode(adminEncoded);
    _trustedAdminPub = s.syncsRemotely ? repo.loadTrustedAdminPub(scope) : null;

    if (s.syncsRemotely && !s.remoteSyncEnabled) {
      // Turned off on this device: no connection at all; capture goes on.
      state = const SyncStatus(phase: SyncPhase.paused);
      return;
    }

    final backend = registry.create(s.backendId);
    try {
      await backend.connect(s.backendConfig);
    } on BackendException catch (e) {
      state = SyncStatus(
        phase: SyncPhase.error,
        lastError: e.message,
        authFailed: e.isAuth,
      );
      await backend.dispose();
      return;
    }
    _backend = backend;

    final engine = SyncEngine(
      backend: backend,
      store: store,
      device: Device(
        id: s.deviceId,
        name: s.deviceName,
        platform: PlatformInfo.name,
        lastSeen: DateTime.now().toUtc(),
        appVersion: BuildInfo.version,
      ),
      identity: _identity,
      adminKey: _adminKey,
      trustedAdminPub: _trustedAdminPub,
      cipherRing: ring,
      onAdminKeyReceived: (encoded) async {
        // Made admin by the group's admin: keep the key and restart so the
        // engine signs with it.
        await repo.saveAdminKey(scope, encoded);
        log.i('this device is now an admin of the group');
        unawaited(restart());
      },
      onKeyReceived: (version, passphrase) async {
        final current = await repo.loadKeyring();
        current[version] = passphrase;
        await repo.saveKeyring(current);
        ring?.add(
          version,
          await ClipCipher.fromPassphrase(
            passphrase,
            keyScope: s.cipherKeyScope,
          ),
        );
        log.i('encryption key v$version installed');
      },
      pollInterval: Duration(seconds: s.pollIntervalSeconds.clamp(2, 3600)),
      assumeRegistered: s.syncsRemotely && repo.loadRegisteredScope() == scope,
      paused: s.syncsRemotely && repo.loadPaused(scope),
      onPausedChanged: ({required paused}) {
        if (s.syncsRemotely) unawaited(repo.savePaused(scope, paused: paused));
      },
      seenMembershipVersions: s.syncsRemotely
          ? repo.loadSeenVersions(scope)
          : null,
      logger: log.sync,
    );
    _engine = engine;
    _trustSub = engine.trustRequests.listen(
      (t) => ref.read(pendingTrustProvider.notifier).request = t,
    );
    _statusSub = engine.statusStream.listen((st) {
      state = st;
      if (st.phase == SyncPhase.revoked) {
        unawaited(
          _onRevoked(st.revokedReason ?? 'removed', descriptor.displayName),
        );
      }
    });
    _devicesSub = engine.devices.listen((list) {
      _devicesOut.add(list);
      if (s.syncsRemotely) {
        if (repo.loadRegisteredScope() != scope) {
          unawaited(repo.saveRegisteredScope(scope));
        }
        unawaited(repo.saveSeenVersions(scope, engine.seenMembershipVersions));
      }
    });
    _incomingSub = engine.incoming.listen((items) async {
      if (!ref.read(settingsProvider).writeIncomingToClipboard) return;
      final newest = items
          .where((i) => !i.isDeleted)
          .fold<ClipItem?>(
            null,
            (a, b) => a == null || b.createdAt.isAfter(a.createdAt) ? b : a,
          );
      if (newest != null) await _clipboard?.write(newest);
    });
    await engine.start();
    _retention = Timer.periodic(
      const Duration(hours: 12),
      (_) => runRetention(),
    );
    unawaited(runRetention());
  }

  /// The group no longer wants this device: forget the credentials and the
  /// passphrase, fall back to local-only, and tell the user once.
  Future<void> _onRevoked(String reason, String backendName) async {
    final s = ref.read(settingsProvider);
    if (!s.syncsRemotely) return;
    log.w('access revoked ($reason); forgetting $backendName credentials');
    await _forgetGroup(s);
    if (!ref.mounted) return;
    // Switching the backend restarts the engine in local-only mode.
    await ref
        .read(settingsProvider.notifier)
        .update(
          (x) => x.copyWith(
            backendId: 'memory',
            backendValues: const {},
            encryptionEnabled: false,
          ),
        );
    if (!ref.mounted) return;
    ref.read(revocationProvider.notifier).notice = RevocationNotice(
      reason: reason,
      backendName: backendName,
    );
  }

  Future<void> _stopEngine() async {
    _retention?.cancel();
    await _statusSub?.cancel();
    await _incomingSub?.cancel();
    await _devicesSub?.cancel();
    await _trustSub?.cancel();
    await _engine?.dispose();
    await _backend?.dispose();
    _engine = null;
    _backend = null;
    if (ref.mounted) state = const SyncStatus.stopped();
  }

  Future<void> _teardown() async {
    await _stopEngine();
    await _captureSub?.cancel();
    await _clipboard?.dispose();
    _clipboard = null;
    await _devicesOut.close();
  }
}
