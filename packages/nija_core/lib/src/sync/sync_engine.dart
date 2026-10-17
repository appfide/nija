import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:clock/clock.dart';
import 'package:nija_core/src/backend/sync_backend.dart';
import 'package:nija_core/src/crypto/cipher_ring.dart';
import 'package:nija_core/src/crypto/clip_cipher.dart';
import 'package:nija_core/src/crypto/clip_signing.dart';
import 'package:nija_core/src/crypto/device_keys.dart';
import 'package:nija_core/src/crypto/key_envelope.dart';
import 'package:nija_core/src/model/clip_item.dart';
import 'package:nija_core/src/model/device.dart';
import 'package:nija_core/src/sync/local_store.dart';
import 'package:nija_core/src/sync/sync_status.dart';
import 'package:nija_core/src/sync/timed_backend.dart';
import 'package:nija_core/src/util/redact.dart';

/// Log sink; the app wires this to its logger. Messages are pre-redacted.
typedef SyncLogger = void Function(String message, {Object? error});

/// Called when a new passphrase version reached this device through its
/// key envelope. The app persists it and adds it to the [CipherRing].
typedef KeyReceived = Future<void> Function(int version, String passphrase);

/// Receives the group's admin key (`AdminKey.encode`) when the admin made
/// this device an admin after pairing.
typedef AdminKeyReceived = Future<void> Function(String encodedAdminKey);

/// An admin key the device has not pinned yet but whose signatures appear
/// on the group's rows. The app asks the user to compare the fingerprint
/// with the admin device before trusting it.
class PendingTrust {
  /// Creates the request.
  const PendingTrust({required this.adminPub, required this.adminDeviceName});

  /// Admin public key, base64.
  final String adminPub;

  /// Name of the device row flagged `admin` under that key, if any.
  final String adminDeviceName;

  /// Comparable fingerprint.
  String get fingerprint => keyFingerprint(adminPub);
}

/// Drives replication between a [LocalStore] and a [SyncBackend].
///
/// * **Push**: drains the outbox in batches, sealing with the newest
///   [CipherRing] key and signing with the device [identity], with
///   exponential backoff on transient errors.
/// * **Pull**: `pullSince(cursor)` on start, on demand, on a timer when the
///   backend has no realtime, and after every realtime event. Every item is
///   verified against the signing key of a trusted device before it is
///   decrypted or applied.
/// * **Echo suppression**: incoming items whose hash was captured locally in
///   the last [echoWindow] are dropped.
/// * **Membership**: every [heartbeatInterval] the engine reads the device
///   list, refreshes its presence row, checks admin signatures, adopts its
///   role and key envelopes, and stops with [SyncPhase.revoked] when its
///   own (signed) row says blocked, removed or expired.
///
/// ## Trust model
///
/// With [trustedAdminPub] set ("signed group") only rows carrying a valid
/// signature by that key count; unsigned rows and rows signed by another
/// key are *untrusted*: their clips are dropped and a block written on them
/// is ignored. Without it ("legacy group") membership is cooperative and
/// item signatures are checked only when the sending device published a
/// key. A membership row whose version is lower than one already seen for
/// that device is treated as a rollback and ignored.
class SyncEngine {
  /// Creates an engine. Call [start] to begin.
  ///
  /// [assumeRegistered] tells the engine this device already had a row on
  /// this backend (persisted by the app after the first successful
  /// heartbeat). A missing row then means "removed and forgotten" rather
  /// than "first run".
  SyncEngine({
    required SyncBackend backend,
    required this._store,
    required this._device,
    this.identity,
    this.adminKey,
    this.trustedAdminPub,
    CipherRing? cipherRing,
    ClipCipher? cipher,
    this.onKeyReceived,
    this.onAdminKeyReceived,
    this.pollInterval = const Duration(seconds: 5),
    this.heartbeatInterval = const Duration(minutes: 1),
    this.echoWindow = const Duration(seconds: 10),
    this.pushBatchSize = 50,
    this.keyResendDelay = const Duration(seconds: 30),
    Duration deviceRequestTimeout = const Duration(seconds: 20),
    Duration dataRequestTimeout = const Duration(minutes: 2),
    this.assumeRegistered = false,
    this._paused = false,
    this.onPausedChanged,
    Map<String, int>? seenMembershipVersions,
    SyncLogger? logger,
  }) : _backend = TimedBackend(
         backend,
         deviceTimeout: deviceRequestTimeout,
         dataTimeout: dataRequestTimeout,
       ),
       _ring =
           cipherRing ??
           (cipher == null ? null : (CipherRing()..add(1, cipher))),
       _seenVersions = {...?seenMembershipVersions},
       _log = logger ?? _noopLog;

  final SyncBackend _backend;
  final LocalStore _store;
  final Device _device;
  final SyncLogger _log;
  final CipherRing? _ring;

  /// This device's signing / box keys. `null` disables signing (tests).
  final DeviceKeys? identity;

  /// Admin key when this device manages the group.
  final AdminKey? adminKey;

  /// Pinned admin public key (base64). Turns on strict verification.
  final String? trustedAdminPub;

  /// Receives passphrases delivered through key envelopes.
  final KeyReceived? onKeyReceived;

  /// Receives the admin key sealed to this device by [makeAdmin].
  final AdminKeyReceived? onAdminKeyReceived;

  /// Poll cadence when the backend lacks realtime.
  final Duration pollInterval;

  /// Device heartbeat / membership check cadence.
  final Duration heartbeatInterval;

  /// Window for echo suppression.
  final Duration echoWindow;

  /// Max items per upsert call.
  final int pushBatchSize;

  /// How long an admin waits before it hands out a fresh key because a
  /// member seems to hold a different one. A rotation in progress writes
  /// rows one by one, so a member briefly looks out of step; real drift
  /// still shows on a later check.
  final Duration keyResendDelay;

  /// Whether a missing own row means revocation (see constructor).
  final bool assumeRegistered;

  /// Called when the admin pauses or resumes this device. Persist the value
  /// and pass it back as `paused`, so a resume that happens while the app is
  /// closed still skips the paused period.
  final void Function({required bool paused})? onPausedChanged;

  final _statusCtl = StreamController<SyncStatus>.broadcast(sync: true);
  final _incomingCtl = StreamController<List<ClipItem>>.broadcast();
  final _devicesCtl = StreamController<List<Device>>.broadcast();
  final _trustCtl = StreamController<PendingTrust>.broadcast();
  SyncStatus _status = const SyncStatus.stopped();
  Timer? _pollTimer;
  Timer? _heartbeatTimer;
  Timer? _retryTimer;
  StreamSubscription<ClipItem>? _watchSub;
  int _failures = 0;
  bool _running = false;
  Future<void>? _inFlight;
  Completer<void>? _next;

  List<Device> _devices = const [];
  Map<String, Device> _trusted = const {};
  Map<String, Device> _held = const {};
  bool _paused;
  Set<DevicePermission> _permissions = const {};
  Set<String> _known = const {};
  DeviceRole _role = DeviceRole.full;
  bool _registered = false;
  DateTime? _lastMembership;
  final Map<String, int> _seenVersions;
  String? _lastTrustPrompt;

  /// Members that seem to hold a different key than ours, with when that
  /// was first noticed: their row carries a newer version than we have...
  final Map<String, DateTime> _aheadSince = {};

  /// ...or their signed clips at our current version do not open.
  final Map<String, DateTime> _unreadableSince = {};

  /// Current status.
  SyncStatus get status => _status;

  /// Status changes.
  Stream<SyncStatus> get statusStream => _statusCtl.stream;

  /// Items applied from remote (already decrypted). The app uses this to
  /// refresh the list and, optionally, write the newest one to the clipboard.
  Stream<List<ClipItem>> get incoming => _incomingCtl.stream;

  /// Device list snapshots, emitted after every membership check.
  Stream<List<Device>> get devices => _devicesCtl.stream;

  /// Admin keys seen on the group's rows while none is pinned.
  Stream<PendingTrust> get trustRequests => _trustCtl.stream;

  /// Last known device list (empty before the first check).
  List<Device> get knownDevices => List.unmodifiable(_devices);

  /// Devices whose membership is verified (signed groups) or simply active
  /// (legacy groups), keyed by id.
  Map<String, Device> get trustedDevices => Map.unmodifiable(_trusted);

  /// Highest membership version seen per device; persist and pass back so
  /// rollback detection survives restarts.
  Map<String, int> get seenMembershipVersions =>
      Map.unmodifiable(_seenVersions);

  /// Role the group assigned to this device.
  DeviceRole get role => _role;

  /// Whether the group has a pinned admin key.
  bool get isSignedGroup => trustedAdminPub != null;

  /// Whether this device can sign membership changes.
  bool get isAdmin => adminKey != null;

  /// Powers the admin granted this device, read from its own verified row.
  /// Empty in a legacy group, where nothing is signed.
  Set<DevicePermission> get permissions => Set.unmodifiable(_permissions);

  /// Whether the admin paused this device.
  bool get isPaused => _paused;

  /// Whether [start] has been called and [stop] has not.
  bool get isRunning => _running;

  /// Connects, checks membership, subscribes to realtime (if any) and runs
  /// an initial sync.
  Future<void> start() async {
    if (_running) return;
    _running = true;
    _failures = 0;
    _emit(
      _status.copyWith(
        phase: SyncPhase.idle,
        authFailed: false,
        clearError: true,
        signedGroup: isSignedGroup,
        keyVersion: _ring?.currentVersion ?? 0,
      ),
    );

    if (!await _membership()) return; // revoked

    if (_backend.descriptor.supportsRealtime) {
      _watchSub = _backend
          .watch(excludeDeviceId: _device.id)
          .listen(
            (_) => syncNow(),
            onError: (Object e) => _log('realtime stream error', error: e),
          );
      _emit(_status.copyWith(realtime: true));
    } else {
      _pollTimer = Timer.periodic(pollInterval, (_) => syncNow());
    }
    // Each heartbeat also pulls. A realtime connection can drop without an
    // error (iOS closes it while the app is in the background), and the
    // events it missed are never replayed.
    _heartbeatTimer = Timer.periodic(heartbeatInterval, (_) => _beat());

    await syncNow();
  }

  /// Stops timers and subscriptions. Safe to call twice.
  Future<void> stop() async {
    _running = false;
    _cancelTimers();
    await _watchSub?.cancel();
    _watchSub = null;
    await _inFlight;
    _emit(const SyncStatus.stopped());
  }

  /// Stops and starts again (after settings changed).
  Future<void> restart() async {
    await stop();
    await start();
  }

  /// Releases the engine (does not dispose the backend).
  Future<void> dispose() async {
    await stop();
    await _statusCtl.close();
    await _incomingCtl.close();
    await _devicesCtl.close();
    await _trustCtl.close();
  }

  Future<void> _beat() async {
    if (!await _membership()) return;
    await syncNow();
  }

  /// Push the outbox then pull remote changes. Coalesces concurrent calls:
  /// while a sync is in flight, callers share one follow-up run and their
  /// future completes when *that* run finishes, so "capture, then
  /// `await syncNow()`" always means the capture was pushed.
  Future<void> syncNow() {
    if (!_running || _status.authFailed) return Future.value();
    if (_inFlight != null) return (_next ??= Completer<void>()).future;
    final run = _runSync();
    _inFlight = run;
    unawaited(
      run.whenComplete(() {
        _inFlight = null;
        final next = _next;
        if (next != null) {
          _next = null;
          unawaited(syncNow().whenComplete(next.complete));
        }
      }),
    );
    return run;
  }

  // --- Device management ---------------------------------------------------

  /// Re-reads the device list (and refreshes this device's presence).
  Future<List<Device>> refreshDevices() async {
    await _membership();
    return knownDevices;
  }

  /// Blocks [id]: other devices ignore its clips and it stops syncing.
  Future<void> blockDevice(String id) =>
      _patch(id, (d) => d.copyWith(status: DeviceStatus.blocked));

  /// Re-activates a blocked or paused device.
  Future<void> unblockDevice(String id) =>
      _patch(id, (d) => d.copyWith(status: DeviceStatus.active));

  /// Pauses [id]: it keeps its credentials but stops syncing until
  /// [resumeDevice]. Clips written meanwhile never reach it.
  Future<void> pauseDevice(String id) =>
      _patch(id, (d) => d.copyWith(status: DeviceStatus.paused));

  /// Resumes a paused device.
  Future<void> resumeDevice(String id) => unblockDevice(id);

  /// Marks [id] as removed. The row stays so the device learns about it;
  /// call [forgetDevice] later to delete the row.
  Future<void> removeDevice(String id) =>
      _patch(id, (d) => d.copyWith(status: DeviceStatus.removed));

  /// Changes what [id] may do.
  Future<void> setDeviceRole(String id, DeviceRole role) =>
      _patch(id, (d) => d.copyWith(role: role));

  /// Sets or clears (`null`) the membership expiry of [id].
  Future<void> setDeviceExpiry(String id, DateTime? expiresAt) => _patch(
    id,
    (d) => expiresAt == null
        ? d.copyWith(clearExpiresAt: true)
        : d.copyWith(expiresAt: expiresAt.toUtc()),
  );

  /// Deletes the row of [id]. Use after the device has disconnected; a
  /// device that is still running would otherwise stop with "removed".
  Future<void> forgetDevice(String id) async {
    _requireAdminIfSigned();
    await _backend.deleteDevice(id);
    _seenVersions.remove(id);
    await _membership();
  }

  /// Pre-creates a row for a device that will join with a pairing code,
  /// so the host decides its role, expiry and, in a signed group, the
  /// keys that will speak for it. [passphrase] (when given and the device
  /// has a box key) is sealed into the row so it never travels in the code.
  Future<void> inviteDevice({
    required String id,
    required DeviceRole role,
    DateTime? expiresAt,
    String? signPub,
    String? boxPub,
    bool admin = false,
    String? passphrase,
  }) async {
    _requireAdminIfSigned();
    var d = Device(
      id: id,
      name: 'Pending device',
      platform: '',
      lastSeen: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      role: role,
      expiresAt: expiresAt?.toUtc(),
      pairedBy: _device.id,
      signPub: signPub,
      boxPub: boxPub,
      admin: admin,
    );
    if (passphrase != null && boxPub != null) {
      final v = _ring?.currentVersion ?? 1;
      final env = await KeyEnvelope.seal(
        passphrase: passphrase,
        version: v,
        recipientBoxPub: boxPub,
      );
      d = d.copyWith(keyVersion: v, keyEnvelope: env.encode());
    }
    await _backend.updateDevice(await _signed(d));
    await _membership();
  }

  /// Turns a legacy group into a signed one: signs every current active
  /// row (including this device, flagged `admin`) with [adminKey]. The
  /// caller pins the key and restarts with [trustedAdminPub] set.
  Future<void> secureGroup() async {
    final admin = adminKey ?? (throw StateError('No admin key'));
    final list = await _backend.listDevices();
    for (final d in list) {
      if (d.status != DeviceStatus.active) continue;
      final row = d.id == _device.id
          ? d.copyWith(
              admin: true,
              signPub: identity?.signPub,
              boxPub: identity?.boxPub,
            )
          : d;
      await _backend.updateDevice(await ClipSigning.signMembership(row, admin));
    }
    _log('group secured with admin key ${admin.fingerprint}');
    await _membership();
  }

  /// Clips that predate encryption: rows any holder of the database
  /// credentials can still read.
  ///
  /// Turning encryption on seals what is written *next*; it does not reach
  /// back over history. This is the scan behind the warning the app shows.
  /// Only meaningful for a group that encrypts: with encryption off, every
  /// row is plaintext by definition, so this throws rather than inviting the
  /// user to delete their whole history.
  Future<List<ClipItem>> plaintextClips() async {
    if (_ring == null) {
      throw StateError('Encryption is off for this group');
    }
    final found = (await _allRemote())
        .where((i) => !i.encrypted && !i.isDeleted && i.content.isNotEmpty)
        .toList();
    _log('found ${found.length} plaintext clip(s)');
    return found;
  }

  /// Every row in the table, this device's own included.
  Future<List<ClipItem>> _allRemote() async {
    final all = <ClipItem>[];
    DateTime? cursor;
    while (true) {
      final page = await _backend.pullSince(
        cursor,
        // Sentinel: no device id looks like this, so nothing is excluded.
        excludeDeviceId: '-',
      );
      if (page.isEmpty) break;
      all.addAll(page);
      final newest = page
          .map((i) => i.updatedAt)
          .reduce((a, b) => a.isAfter(b) ? a : b);
      if (cursor != null && !newest.isAfter(cursor)) break;
      cursor = newest;
      if (page.length < 500) break;
    }
    return all;
  }

  /// Encrypted clips this device wrote whose `content_hash` is still the plain
  /// SHA-256 of the plaintext, from before the fingerprint was keyed.
  ///
  /// The ciphertext is safe; the fingerprint beside it is not: it lets anyone
  /// with read access confirm a guess about a short clip. Detection is exact
  /// rather than heuristic: decrypt, hash the plaintext, and see whether that
  /// is what the row carries.
  ///
  /// Only this device's own rows qualify. A clip's signature is verified
  /// against the *writing* device's key, so re-signing someone else's row
  /// would make every other device reject it; each device fixes its own.
  Future<List<ClipItem>> legacyHashedClips() async {
    final ring = _ring;
    if (ring == null || ring.isEmpty) return const [];
    final found = <ClipItem>[];
    for (final row in await _allRemote()) {
      if (!row.encrypted || row.isDeleted || row.content.isEmpty) continue;
      if (row.deviceId != _device.id) continue;
      final cipher = ring.cipherFor(row.keyVersion == 0 ? 1 : row.keyVersion);
      if (cipher == null) continue;
      try {
        // open() sets contentHash to the plain digest, so an unchanged value
        // means the row was written before the fingerprint was keyed.
        final opened = await cipher.open(row);
        if (opened.contentHash == row.contentHash) found.add(row);
      } on CipherException {
        continue;
      }
    }
    _log('found ${found.length} clip(s) with a leaky fingerprint');
    return found;
  }

  /// Replaces the plain digest on those rows with the keyed fingerprint,
  /// leaving the ciphertext and every timestamp untouched. Returns how many.
  Future<int> rehashLegacyClips() async {
    final ring = _ring;
    if (ring == null) throw StateError('Encryption is off for this group');
    final stale = await legacyHashedClips();
    if (stale.isEmpty) return 0;
    final fixed = <ClipItem>[];
    for (final row in stale) {
      final cipher = ring.cipherFor(row.keyVersion == 0 ? 1 : row.keyVersion)!;
      final opened = await cipher.open(row);
      var item = row.copyWith(
        contentHash: await cipher.contentFingerprint(opened.content),
        clearSig: true,
      );
      final keys = identity;
      if (keys != null) item = await ClipSigning.signItem(item, keys);
      fixed.add(item);
    }
    for (var i = 0; i < fixed.length; i += pushBatchSize) {
      final end = (i + pushBatchSize).clamp(0, fixed.length);
      await _backend.upsert(fixed.sublist(i, end));
    }
    _log('rewrote ${fixed.length} leaky fingerprint(s)');
    return fixed.length;
  }

  /// Overwrites every clip from [plaintextClips] with an empty tombstone and
  /// drops it locally. Returns how many were cleared.
  ///
  /// The content is replaced rather than only marked deleted, because a
  /// tombstone that keeps its `content` column leaves the plaintext exactly
  /// where it was.
  Future<int> purgePlaintextClips() async {
    final stale = await plaintextClips();
    if (stale.isEmpty) return 0;
    final now = clock.now().toUtc();
    final cleared = <ClipItem>[];
    for (final i in stale) {
      var item = i.copyWith(
        content: '',
        contentHash: '',
        deletedAt: now,
        updatedAt: now,
        clearNonce: true,
        clearSig: true,
      );
      final keys = identity;
      if (keys != null) item = await ClipSigning.signItem(item, keys);
      cleared.add(item);
    }
    for (var i = 0; i < cleared.length; i += pushBatchSize) {
      final end = (i + pushBatchSize).clamp(0, cleared.length);
      await _backend.upsert(cleared.sublist(i, end));
    }
    await _store.applyRemote(cleared);
    _log('purged ${cleared.length} plaintext clip(s)');
    return cleared.length;
  }

  /// Issues passphrase version `current + 1` = [newPassphrase] to every
  /// trusted active device with a box key (this device included) and
  /// reports it through [onKeyReceived]. Devices that are blocked, removed,
  /// expired or unverified get nothing and cannot read clips sealed with
  /// the new key.
  Future<int> rotatePassphrase(String newPassphrase) async {
    _requireAdminIfSigned();
    if (adminKey == null) throw StateError('Only the admin can rotate keys');
    // Refresh first and issue only to the trusted set: it already excludes
    // blocked / expired / unverified rows *and* rolled-back rows that still
    // carry an older valid signature.
    await _membership();
    final version = (_ring?.currentVersion ?? 0) + 1;
    final issued = await _issueKey(version, newPassphrase);
    _log('passphrase rotated to v$version for $issued device(s)');
    await _membership();
    return issued;
  }

  /// Seals [passphrase] as [version] to every trusted active device with a
  /// box key, this one last, and installs it here through [onKeyReceived].
  Future<int> _issueKey(int version, String passphrase) async {
    var issued = 0;
    // Paused devices get the key too: they will need it once resumed. Our
    // own row goes last, so a peer that reads the rows halfway through
    // sees the issuer behind rather than ahead.
    final targets = [..._trusted.values, ..._held.values]
      ..sort(
        (a, b) => (a.id == _device.id ? 1 : 0) - (b.id == _device.id ? 1 : 0),
      );
    for (final d in targets) {
      if (d.boxPub == null) continue;
      final env = await KeyEnvelope.seal(
        passphrase: passphrase,
        version: version,
        recipientBoxPub: d.boxPub!,
      );
      await _backend.updateDevice(
        await _signed(
          d.copyWith(keyVersion: version, keyEnvelope: env.encode()),
        ),
      );
      issued++;
    }
    await onKeyReceived?.call(version, passphrase);
    _aheadSince.clear();
    _unreadableSince.clear();
    _emit(_status.copyWith(keyVersion: version, keyDrift: false));
    return issued;
  }

  /// Admin only: hands the group a fresh key when a member holds a
  /// different one. That happens when a device lost its keyring and
  /// started over, or a passphrase was typed on one device only: each side
  /// then seals with a key the other cannot open, and comparing
  /// fingerprints by hand does not fix it. The key is random rather than
  /// our current one, which a removed device may know, and numbered above
  /// every version in the group so that every member accepts it.
  Future<void> _resendKeyOnDrift(DateTime now) async {
    final ring = _ring;
    final members = [
      for (final d in [..._trusted.values, ..._held.values])
        if (d.id != _device.id) d,
    ];
    final current = ring?.currentVersion ?? 0;
    final ahead = {
      for (final d in members)
        if (ring != null && !ring.isEmpty && d.keyVersion > current) d.id,
    };
    _aheadSince.removeWhere((id, _) => !ahead.contains(id));
    for (final id in ahead) {
      _aheadSince.putIfAbsent(id, () => now);
    }
    _unreadableSince.removeWhere((id, _) => !members.any((d) => d.id == id));
    final since = {..._unreadableSince, ..._aheadSince};
    final drift = since.isNotEmpty;
    if (drift != _status.keyDrift) {
      _emit(_status.copyWith(keyDrift: drift));
    }
    if (!drift ||
        ring == null ||
        ring.isEmpty ||
        adminKey == null ||
        !isSignedGroup ||
        onKeyReceived == null) {
      return;
    }
    final settled = since.values.any(
      (t) => now.difference(t) >= keyResendDelay,
    );
    if (!settled) return;
    final names = [
      for (final d in members)
        if (since.containsKey(d.id)) d.name,
    ];
    final version = members.map((d) => d.keyVersion).fold(current, max) + 1;
    final random = Random.secure();
    final passphrase = base64UrlEncode(
      List<int>.generate(32, (_) => random.nextInt(256)),
    );
    final issued = await _issueKey(version, passphrase);
    // What we sent under the key nobody else had never opened anywhere;
    // send it again under the new one. This also unblocks members on 0.5.0,
    // which stop syncing at the first clip they cannot open.
    final resent = await _store.requeueOwn(_device.id, now);
    _log(
      '${names.join(', ')} held a different key; issued a fresh key '
      'v$version to $issued device(s), sending $resent clip(s) again',
    );
    if (resent > 0) unawaited(syncNow());
  }

  /// Replaces the powers granted to [id]. Signed groups only: in a legacy
  /// group every device may already do everything.
  Future<void> setDevicePermissions(
    String id,
    Set<DevicePermission> permissions,
  ) => _patchGrant(id, (d) => d.copyWith(permissions: {...permissions}));

  /// Makes [id] an admin: seals the admin key to its box key and flags the
  /// row. The device installs the key on its next check-in. There is no
  /// undo: the device keeps the key, and only a new admin key (securing the
  /// group again) takes the power back.
  Future<void> makeAdmin(String id) async {
    final admin = adminKey;
    if (!isSignedGroup || admin == null) {
      throw StateError('Only the admin of a signed group can add admins');
    }
    final target = await _deviceRow(id);
    final boxPub = target.boxPub;
    if (boxPub == null) {
      throw StateError('${target.name} has not published its keys yet');
    }
    // Version 0 marks an admin key; passphrase envelopes start at 1.
    final env = await KeyEnvelope.seal(
      passphrase: await admin.encode(),
      version: 0,
      recipientBoxPub: boxPub,
    );
    await _patchGrant(
      id,
      (d) => d.copyWith(admin: true, adminEnvelope: env.encode()),
    );
  }

  /// [_patch] for the grant fields added in 0.5, with a read-back: a schema
  /// without them may drop the values silently, leaving a row whose
  /// signature no longer verifies. In that case the previous state is
  /// signed again and the error names the upgrade to run.
  Future<void> _patchGrant(String id, Device Function(Device) change) async {
    if (!isSignedGroup || adminKey == null) {
      throw StateError('Only the admin of a signed group can grant powers');
    }
    final before = await _deviceRow(id);
    final want = await _signed(change(before));
    Object? failure;
    try {
      await _backend.updateDevice(want);
      final stored = (await _backend.listDevices())
          .where((d) => d.id == id)
          .firstOrNull;
      if (stored != null &&
          DevicePermission.encode(stored.permissionNames) ==
              DevicePermission.encode(want.permissionNames) &&
          stored.adminEnvelope == want.adminEnvelope) {
        await _membership();
        return;
      }
    } on BackendException catch (e) {
      failure = e;
    }
    // The previous row, signed above the failed version so no device
    // treats it as a rollback.
    await _backend.updateDevice(
      await _signed(before.copyWith(membershipVersion: want.membershipVersion)),
    );
    await _membership();
    throw BackendException(
      'The database did not keep the new permission fields. Run the 0.5 '
      'upgrade for ${_backend.descriptor.displayName} '
      '(${_backend.descriptor.docsPath}).',
      cause: failure,
    );
  }

  Future<Device> _deviceRow(String id) async {
    final row =
        _devices.where((d) => d.id == id).firstOrNull ??
        (await _backend.listDevices()).where((d) => d.id == id).firstOrNull;
    return row ?? (throw BackendException('Unknown device $id'));
  }

  Future<void> _patch(String id, Device Function(Device) change) async {
    _requireAdminIfSigned();
    final current = await _deviceRow(id);
    await _backend.updateDevice(await _signed(change(current)));
    await _membership();
  }

  /// Signs [d] when this device holds the admin key; otherwise returns it
  /// unchanged (legacy group): a signed group refuses earlier.
  Future<Device> _signed(Device d) async {
    final a = adminKey;
    return a == null ? d : ClipSigning.signMembership(d, a);
  }

  void _requireAdminIfSigned() {
    if (isSignedGroup && adminKey == null) {
      throw StateError('Only the admin device can manage this group');
    }
  }

  // --- Internals -----------------------------------------------------------

  Future<void> _runSync() async {
    _emit(_status.copyWith(phase: SyncPhase.syncing));
    try {
      final last = _lastMembership;
      if (last == null ||
          clock.now().toUtc().difference(last) >= heartbeatInterval) {
        if (!await _membership()) return;
      }
      if (_paused) {
        _emit(_status.copyWith(phase: SyncPhase.paused, clearError: true));
        return;
      }
      if (_role.canSend) await _push();
      if (_role.canReceive) await _pull();
      _failures = 0;
      final pending = (await _store.pendingOutbox(limit: 1)).length;
      _emit(
        _status.copyWith(
          phase: SyncPhase.idle,
          lastSyncAt: clock.now().toUtc(),
          pendingCount: pending,
          clearError: true,
        ),
      );
    } on BackendException catch (e) {
      _onError(e.message, e, isAuth: e.isAuth);
    } on CipherException catch (e) {
      // Wrong passphrase: behaves like auth, user must fix settings.
      _onError(e.message, e, isAuth: true);
    } catch (e) {
      _onError(e.toString(), e);
    }
  }

  Future<void> _push() async {
    final ring = _ring;
    if (ring != null && ring.isEmpty) {
      // Encryption is on but no passphrase has arrived yet (joined with a
      // sealed key that is still in transit). Never push plaintext.
      _log('waiting for the group passphrase before pushing');
      if (!_status.waitingForKey) _emit(_status.copyWith(waitingForKey: true));
      return;
    }
    if (_status.waitingForKey) _emit(_status.copyWith(waitingForKey: false));
    final cipher = ring?.current;
    final version = ring?.currentVersion ?? 0;
    while (true) {
      final batch = await _store.pendingOutbox(limit: pushBatchSize);
      if (batch.isEmpty) return;
      final out = <ClipItem>[];
      for (final item in batch) {
        // Only a clip's origin may delete it from the group. A tombstone for
        // another device's clip would overwrite its row under that device's
        // id with our signature, which every other device then rejects.
        if (item.isDeleted && item.deviceId != _device.id) {
          _log('kept tombstone for ${item.id} local: another device owns it');
          continue;
        }
        var i = cipher == null
            ? item
            : (await cipher.seal(item)).copyWith(keyVersion: version);
        final keys = identity;
        if (keys != null) i = await ClipSigning.signItem(i, keys);
        out.add(i);
      }
      if (out.isNotEmpty) await _backend.upsert(out);
      await _store.markSynced(batch.map((i) => i.id));
      _log('pushed ${batch.length} item(s)');
      if (batch.length < pushBatchSize) return;
    }
  }

  Future<void> _pull() async {
    var cursor = await _store.loadCursor();
    var refreshed = false;
    while (true) {
      final page = await _backend.pullSince(
        cursor,
        excludeDeviceId: _device.id,
      );
      if (page.isEmpty) return;

      final accepted = <ClipItem>[];
      final echoSince = clock.now().toUtc().subtract(echoWindow);
      var skipped = 0;
      var rejected = 0;
      // A device that joined since the last heartbeat is not in the trust
      // snapshot yet; refresh once so its first clips are not lost.
      // Likewise a clip sealed with a key version newer than ours: its
      // envelope is waiting in our row, and skipping the clip would lose it.
      final newest = _ring?.currentVersion ?? 0;
      if (!refreshed &&
          page.any(
            (i) =>
                !_known.contains(i.deviceId) ||
                (i.encrypted && _ring != null && i.keyVersion > newest),
          )) {
        refreshed = true;
        if (!await _membership()) return;
      }
      for (final raw in page) {
        if (raw.isTargeted && raw.targetDeviceId != _device.id) {
          skipped++;
          continue; // addressed to another device
        }
        final sender = _trusted[raw.deviceId];
        if (sender == null) {
          // Signed group: only verified members may speak. Legacy group:
          // a device that is blocked / expired / removed is ignored, an
          // unknown one (no row yet) is accepted like before.
          if (isSignedGroup || _known.contains(raw.deviceId)) {
            skipped++;
            continue;
          }
        }
        if (!await _authentic(raw, sender)) {
          rejected++;
          continue;
        }
        final ClipItem item;
        if (raw.encrypted) {
          final v = raw.keyVersion == 0 ? 1 : raw.keyVersion;
          var c = _ring?.cipherFor(v);
          if (c == null &&
              _ring != null &&
              !_ring.isEmpty &&
              !_ring.versions.contains(v)) {
            // A manually typed passphrase has no version; try the newest key.
            final current = _ring.current!;
            try {
              item = await current.open(raw);
              _ring.add(v, current);
              c = current;
            } on CipherException {
              _log('no key v${raw.keyVersion} for ${raw.id}, skipped');
              skipped++;
              continue;
            }
          } else if (c == null) {
            _log('no key v${raw.keyVersion} for ${raw.id}, skipped');
            skipped++;
            continue;
          } else if (isSignedGroup) {
            // Every key in a signed group arrives sealed from the admin, so
            // a clip that does not open means the sender holds a different
            // key under the same number. Skip it rather than stall the pull;
            // the admin hands out a fresh key (see _resendKeyOnDrift).
            try {
              item = await c.open(raw);
            } on CipherException {
              if (v == _ring?.currentVersion) {
                _unreadableSince.putIfAbsent(
                  raw.deviceId,
                  () => clock.now().toUtc(),
                );
              }
              _log('key v$v does not open ${raw.id}, skipped');
              skipped++;
              continue;
            }
          } else {
            item = await c.open(raw);
          }
        } else {
          item = raw;
        }
        if (!item.isDeleted &&
            await _store.hasRecentHash(item.contentHash, echoSince)) {
          continue; // our own clipboard write bouncing back via another device
        }
        accepted.add(item);
      }
      if (accepted.isNotEmpty) {
        await _store.applyRemote(accepted);
        _incomingCtl.add(accepted);
      }
      if (rejected > 0) {
        _log('rejected $rejected item(s) with bad or missing signatures');
      }
      cursor = page
          .map((i) => i.updatedAt)
          .reduce((a, b) => a.isAfter(b) ? a : b);
      await _store.saveCursor(cursor);
      _log(
        'pulled ${page.length} item(s), applied ${accepted.length}'
        '${skipped > 0 ? ', skipped $skipped' : ''}',
      );
      if (page.length < 500) return;
    }
  }

  /// Signature policy for one incoming item from a trusted [sender].
  ///
  /// * Sender published a signing key → signature required and must verify
  ///   (also blocks downgrade to unsigned by an attacker).
  /// * No key on record and legacy group → accept unsigned.
  /// * No key on record in a signed group cannot happen: unverified rows
  ///   are not trusted.
  Future<bool> _authentic(ClipItem item, Device? sender) async {
    final pub = sender?.signPub;
    if (pub == null) return !isSignedGroup;
    return ClipSigning.verifyItem(item, pub);
  }

  Future<bool> _verified(Device d) async {
    final admin = trustedAdminPub;
    if (admin == null) return true;
    return ClipSigning.verifyMembership(d, admin);
  }

  /// Reads the device list, refreshes this device's presence and applies
  /// what the group says about it. Returns false when access was revoked.
  Future<bool> _membership() async {
    if (!_running) return false;
    final now = clock.now().toUtc();
    List<Device> list;
    try {
      list = await _backend.listDevices();
    } catch (e) {
      // A transient failure must not stop sync; push/pull report the
      // real error. Keep the previous device knowledge.
      _log('device list unavailable', error: e);
      return true;
    }
    try {
      var me = list.where((d) => d.id == _device.id).firstOrNull;
      if (me?.status == DeviceStatus.removed &&
          !(_registered || assumeRegistered)) {
        // Left over from an earlier membership of this device: it is joining
        // again with credentials typed in, which is what removal asks for.
        // The new row starts unsigned, so a signed group still requires the
        // admin to approve it. A blocked row keeps applying.
        _log('replacing a removed row left by an earlier membership');
        await _backend.deleteDevice(_device.id);
        list = [
          for (final d in list)
            if (d.id != _device.id) d,
        ];
        me = null;
      }
      // Only publish our own keys when the row does not carry any yet: in a
      // signed group the admin-signed keys are authoritative.
      final presence = _device.copyWith(
        lastSeen: now,
        signPub: me?.signPub == null ? identity?.signPub : null,
        boxPub: me?.boxPub == null ? identity?.boxPub : null,
      );
      if (me == null) {
        // Being forgotten leaves the rows of devices we already knew (at
        // least the one that did it). When none of the rows is one of
        // those, the database was reset (tables dropped and created again)
        // and other devices merely registered before us.
        final knewAny = list.any(
          (d) => _known.contains(d.id) || _seenVersions.containsKey(d.id),
        );
        final reset = !knewAny && (_registered || assumeRegistered);
        if ((_registered || assumeRegistered) && !reset) {
          _revoke('removed');
          return false;
        }
        if (reset) _log('device list is empty: database reset, registering');
        await _backend.registerDevice(presence);
        me = presence;
        final admin = adminKey;
        if (reset && admin != null && isSignedGroup) {
          // The admin signs its own row again so the group stays managed,
          // above any version other devices have seen for it.
          me = await ClipSigning.signMembership(
            presence.copyWith(
              admin: true,
              membershipVersion: _seenVersions[_device.id] ?? 0,
            ),
            admin,
          );
          await _backend.updateDevice(me);
        }
        list = [...list, me];
      } else {
        // Decide what to obey. In a signed group only a validly signed,
        // non-rolled-back row may block us; an unsigned or foreign-signed
        // "blocked" is an attack and is ignored.
        final obey = !isSignedGroup || await _verified(me);
        if (obey && !_isRollback(me)) {
          if (me.status == DeviceStatus.blocked) {
            _revoke('blocked');
            return false;
          }
          if (me.status == DeviceStatus.removed) {
            _revoke('removed');
            return false;
          }
          if (me.isExpired(now)) {
            _revoke('expired');
            return false;
          }
          await _applyPause(now, paused: me.status == DeviceStatus.paused);
        } else if (!obey) {
          _log('own membership row is not signed by the pinned admin');
        }
        await _backend.registerDevice(presence);
        final refreshed = me.withPresence(presence);
        list = [
          for (final d in list)
            if (d.id == refreshed.id) refreshed else d,
        ];
        me = refreshed;
      }

      // Trust computation.
      final trusted = <String, Device>{};
      final held = <String, Device>{};
      var selfVerified = !isSignedGroup;
      String? seenAdmin;
      String? seenAdminName;
      for (final d in list) {
        if (isSignedGroup) {
          final ok = await _verified(d) && !_isRollback(d);
          if (ok) {
            _seenVersions[d.id] = max(
              _seenVersions[d.id] ?? 0,
              d.membershipVersion,
            );
          }
          if (d.id == me.id) selfVerified = ok;
          if (ok && d.canSync(now)) trusted[d.id] = d;
          if (ok && d.isHeld(now)) held[d.id] = d;
        } else {
          // Remembered (and persisted by the app) so a later missing own row
          // can tell "forgotten" from "database reset".
          _seenVersions[d.id] = max(
            _seenVersions[d.id] ?? 0,
            d.membershipVersion,
          );
          if (d.canSync(now)) trusted[d.id] = d;
          if (d.isHeld(now)) held[d.id] = d;
          // Legacy group: notice an admin key so the app can offer to pin it.
          if (d.isSigned) {
            seenAdmin ??= d.adminPub;
            if (d.admin) seenAdminName = d.name;
          }
        }
      }
      if (!isSignedGroup &&
          seenAdmin != null &&
          seenAdmin != _lastTrustPrompt) {
        _lastTrustPrompt = seenAdmin;
        if (!_trustCtl.isClosed) {
          _trustCtl.add(
            PendingTrust(
              adminPub: seenAdmin,
              adminDeviceName: seenAdminName ?? '',
            ),
          );
        }
      }

      // Key envelope addressed to us (only trust it from a verified row).
      final myRow = me;
      if (selfVerified || !isSignedGroup) await _acceptEnvelope(myRow);
      _permissions = isSignedGroup && selfVerified
          ? myRow.permissions
          : const {};
      if (isSignedGroup && selfVerified) await _acceptAdminKey(myRow);

      _registered = true;
      _role = selfVerified || !isSignedGroup ? me.role : _role;
      _trusted = trusted;
      _held = held;
      await _resendKeyOnDrift(now);
      _known = {for (final d in list) d.id};
      _devices = list;
      _lastMembership = now;
      if (!_devicesCtl.isClosed) _devicesCtl.add(knownDevices);
      _emit(
        _status.copyWith(
          role: _role,
          selfVerified: selfVerified,
          signedGroup: isSignedGroup,
          keyVersion: _ring?.currentVersion ?? 0,
        ),
      );
      return true;
    } catch (e) {
      _log('heartbeat failed', error: e);
      return true;
    }
  }

  /// Applies the pause flag from our own row. While paused the cursor
  /// follows the clock, so on resume nothing written during the pause is
  /// pulled; clips other devices wrote between the last pull and the first
  /// paused heartbeat are skipped too. On resume, clips captured meanwhile
  /// are marked sent without pushing, so they stay local.
  Future<void> _applyPause(DateTime now, {required bool paused}) async {
    if (paused) {
      await _store.saveCursor(now);
      if (!_paused) {
        _paused = true;
        _log('paused by the group admin');
        onPausedChanged?.call(paused: true);
      }
      return;
    }
    if (!_paused) return;
    _paused = false;
    await _store.saveCursor(now);
    // Copies made while paused stay local; deletions and clips the user
    // explicitly sent to a device still go out.
    final held = await _store.pendingOutbox(limit: 1 << 30);
    final local = [
      for (final i in held)
        if (!i.isDeleted && !i.isTargeted) i.id,
    ];
    await _store.keepLocal(local);
    _log(
      'resumed; skipped the paused period, kept ${local.length} clip(s) local',
    );
    onPausedChanged?.call(paused: false);
  }

  bool _isRollback(Device d) {
    final seen = _seenVersions[d.id];
    if (seen != null && d.membershipVersion < seen) {
      _log(
        'ignoring rolled-back membership for ${d.id} (v${d.membershipVersion} < v$seen)',
      );
      return true;
    }
    return false;
  }

  /// Installs the admin key sealed to us by [makeAdmin]. The row is
  /// verified by the caller; the key must also match the pinned admin key.
  Future<void> _acceptAdminKey(Device me) async {
    final env = me.adminEnvelope;
    final keys = identity;
    if (!me.admin || env == null || keys == null || adminKey != null) return;
    try {
      final envelope = KeyEnvelope.decode(env);
      if (envelope.version != 0) return;
      final encoded = await envelope.open(keys);
      final key = await AdminKey.decode(encoded);
      if (key.publicKey != trustedAdminPub) {
        _log('admin key envelope holds a different key; ignored');
        return;
      }
      await onAdminKeyReceived?.call(encoded);
      _log('received the group admin key');
    } catch (e) {
      _log('admin key envelope unreadable', error: e);
    }
  }

  Future<void> _acceptEnvelope(Device me) async {
    final env = me.keyEnvelope;
    final keys = identity;
    final ring = _ring;
    if (env == null || keys == null || ring == null) return;
    if (me.keyVersion <= ring.currentVersion) return;
    try {
      final passphrase = await KeyEnvelope.decode(env).open(keys);
      await onKeyReceived?.call(me.keyVersion, passphrase);
      _unreadableSince.clear();
      _log('received passphrase v${me.keyVersion}');
    } on EnvelopeException catch (e) {
      _log('key envelope rejected', error: e);
    } catch (e) {
      _log('key envelope unreadable', error: e);
    }
  }

  void _revoke(String reason) {
    _log('access revoked: $reason');
    _running = false;
    _cancelTimers();
    final sub = _watchSub;
    _watchSub = null;
    unawaited(sub?.cancel());
    _emit(
      _status.copyWith(
        phase: SyncPhase.revoked,
        revokedReason: reason,
        realtime: false,
        clearError: true,
      ),
    );
  }

  void _cancelTimers() {
    _pollTimer?.cancel();
    _heartbeatTimer?.cancel();
    _retryTimer?.cancel();
    _pollTimer = null;
    _heartbeatTimer = null;
    _retryTimer = null;
  }

  void _onError(String message, Object error, {bool isAuth = false}) {
    final msg = redactSecrets(message);
    _log('sync failed: $msg', error: error);
    _emit(
      _status.copyWith(
        phase: SyncPhase.error,
        lastError: msg,
        authFailed: isAuth,
      ),
    );
    if (isAuth || !_running) return;
    _failures++;
    final delay = Duration(
      milliseconds: min(60000, 1000 * pow(2, min(_failures, 6)).toInt()),
    );
    _retryTimer?.cancel();
    _retryTimer = Timer(delay, syncNow);
  }

  void _emit(SyncStatus s) {
    _status = s;
    if (!_statusCtl.isClosed) _statusCtl.add(s);
  }

  static void _noopLog(String message, {Object? error}) {}
}
