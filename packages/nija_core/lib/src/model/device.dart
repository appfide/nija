import 'package:meta/meta.dart';
import 'package:nija_core/src/model/clip_item.dart';

/// Membership state of a device in the sync group.
///
/// Enforcement is cooperative unless the backend's rules also read this
/// field (see `docs/devices.md`): a well-behaved client that sees itself as
/// [blocked] or [removed] stops syncing and forgets its credentials.
enum DeviceStatus {
  /// Syncing normally.
  active('active'),

  /// Temporarily excluded: other devices ignore its clips; it must stop
  /// syncing. Can be re-activated.
  blocked('blocked'),

  /// Paused by the admin: the device keeps its credentials and keeps
  /// checking in, but sends and receives nothing. Clips written while it is
  /// paused never reach it, and what it captures meanwhile stays local.
  /// Older app versions read this as [active].
  paused('paused'),

  /// Permanently removed. The row stays as a tombstone so the device learns
  /// about its removal; *Forget* deletes the row afterwards.
  removed('removed');

  const DeviceStatus(this.wire);

  /// Value stored in the database.
  final String wire;

  /// Parses a wire value; unknown or missing values mean [active] so rows
  /// written by older app versions keep working.
  static DeviceStatus fromWire(String? v) => values.firstWhere(
    (s) => s.wire == v,
    orElse: () => DeviceStatus.active,
  );
}

/// What a device is allowed to do with the shared history.
enum DeviceRole {
  /// Sends and receives clips.
  full('full'),

  /// Only pushes its own clips; never pulls history (a guest machine).
  sendOnly('send_only'),

  /// Only receives clips; never pushes what it copies (a display / kiosk).
  receiveOnly('receive_only');

  const DeviceRole(this.wire);

  /// Value stored in the database.
  final String wire;

  /// Whether this role pulls other devices' clips.
  bool get canReceive => this != DeviceRole.sendOnly;

  /// Whether this role pushes its own clips.
  bool get canSend => this != DeviceRole.receiveOnly;

  /// Human-readable label.
  String get label => switch (this) {
    DeviceRole.full => 'Send & receive',
    DeviceRole.sendOnly => 'Send only',
    DeviceRole.receiveOnly => 'Receive only',
  };

  /// Parses a wire value; unknown or missing values mean [full].
  static DeviceRole fromWire(String? v) =>
      values.firstWhere((r) => r.wire == v, orElse: () => DeviceRole.full);
}

/// Extra powers the admin can grant a member without making it an admin.
enum DevicePermission {
  /// May delete every clip from the database (Settings → Data).
  clearHistory('clear_history');

  const DevicePermission(this.wire);

  /// Value stored in the database.
  final String wire;

  /// Human-readable label.
  String get label => switch (this) {
    DevicePermission.clearHistory => 'Delete database history',
  };

  /// Every name in the comma-separated wire form, known or not.
  static Set<String> names(Object? v) => v is String && v.isNotEmpty
      ? {
          for (final n in v.split(','))
            if (n.trim().isNotEmpty) n.trim(),
        }
      : const {};

  /// The permissions this version knows among [names]; the rest are kept
  /// by [Device] (they are signed) but grant nothing here.
  static Set<DevicePermission> known(Iterable<String> names) => {
    for (final p in values)
      if (names.contains(p.wire)) p,
  };

  /// Canonical wire form: sorted, comma-separated, empty when none.
  static String encode(Iterable<String> names) =>
      (names.toSet().toList()..sort()).join(',');
}

/// A device participating in a sync group.
///
/// Two kinds of fields live on a device row:
///
/// * **Presence** (`name`, `platform`, `last_seen`, `app_version`), written
///   by the device itself on every heartbeat via `SyncBackend.registerDevice`.
/// * **Membership** (`status`, `role`, `expires_at`, `paired_by`), written by
///   whichever device manages the group via `SyncBackend.updateDevice`. A
///   heartbeat must never overwrite these.
@immutable
class Device {
  /// Creates a device record.
  const Device({
    required this.id,
    required this.name,
    required this.platform,
    required this.lastSeen,
    this.status = DeviceStatus.active,
    this.role = DeviceRole.full,
    this.expiresAt,
    this.pairedBy,
    this.appVersion,
    this.signPub,
    this.boxPub,
    this.admin = false,
    this.adminPub,
    this.membershipVersion = 0,
    this.membershipSig,
    this.keyVersion = 0,
    this.keyEnvelope,
    this.permissionNames = const {},
    this.adminEnvelope,
    this.storesGrants = false,
  });

  /// Parses the canonical map produced by [toMap]. Missing membership fields
  /// take their defaults so rows from older schemas still parse.
  factory Device.fromMap(Map<String, Object?> map) => Device(
    id: map['id']! as String,
    name: (map['name'] ?? '') as String,
    platform: (map['platform'] ?? '') as String,
    lastSeen:
        ClipItem.parseTimestamp(map['last_seen']) ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    status: DeviceStatus.fromWire(map['status'] as String?),
    role: DeviceRole.fromWire(map['role'] as String?),
    expiresAt: ClipItem.parseTimestamp(map['expires_at']),
    pairedBy: _nullIfEmpty(map['paired_by']),
    appVersion: _nullIfEmpty(map['app_version']),
    signPub: _nullIfEmpty(map['sign_pub']),
    boxPub: _nullIfEmpty(map['box_pub']),
    admin: map['admin'] == true,
    adminPub: _nullIfEmpty(map['admin_pub']),
    membershipVersion: _toInt(map['membership_version']),
    membershipSig: _nullIfEmpty(map['membership_sig']),
    keyVersion: _toInt(map['key_version']),
    keyEnvelope: _nullIfEmpty(map['key_envelope']),
    permissionNames: DevicePermission.names(map['permissions']),
    adminEnvelope: _nullIfEmpty(map['admin_envelope']),
    storesGrants:
        map.containsKey('permissions') || map.containsKey('admin_envelope'),
  );

  /// Stable UUID generated on first launch (or adopted from a pairing code)
  /// and kept in app preferences.
  final String id;

  /// User-visible name (hostname / model by default).
  final String name;

  /// `macos`, `windows`, `linux`, `android`, `ios`.
  final String platform;

  /// Last heartbeat (UTC).
  final DateTime lastSeen;

  /// Membership state.
  final DeviceStatus status;

  /// Permissions.
  final DeviceRole role;

  /// When membership ends (UTC), or `null` for permanent access.
  final DateTime? expiresAt;

  /// Id of the device that issued the pairing code, if any.
  final String? pairedBy;

  /// App version the device last reported.
  final String? appVersion;

  /// Ed25519 public key the device signs clips with, base64. `null` for
  /// devices running app versions before 0.2.
  final String? signPub;

  /// X25519 public key passphrase envelopes are sealed to, base64.
  final String? boxPub;

  /// Whether this device holds the group's admin key.
  final bool admin;

  /// Admin public key that signed this row's membership, base64.
  final String? adminPub;

  /// Monotonic counter bumped on every membership change; lets devices
  /// reject a rolled-back (older but validly signed) row.
  final int membershipVersion;

  /// Admin signature over the membership fields (see
  /// `ClipSigning.membershipBytes`), base64.
  final String? membershipSig;

  /// Passphrase version delivered in [keyEnvelope]; 0 = none.
  final int keyVersion;

  /// Sealed passphrase for this device (`KeyEnvelope.encode`), or `null`.
  final String? keyEnvelope;

  /// Permission names the admin granted this member, as stored and signed.
  /// Kept verbatim so a grant from a newer app version still verifies.
  final Set<String> permissionNames;

  /// The granted permissions this app version knows.
  Set<DevicePermission> get permissions =>
      DevicePermission.known(permissionNames);

  /// The group's admin key sealed to this device's [boxPub] when it was made
  /// an admin after pairing (`KeyEnvelope.encode`), or `null`.
  final String? adminEnvelope;

  /// Whether the row came from a database that already stores [grantKeys].
  /// Rows from schemas older than 0.5 do not, and [toMap] leaves those
  /// fields out until a grant is made so updates keep working there.
  final bool storesGrants;

  /// Whether [permission] was granted, or this device is an admin.
  bool may(DevicePermission permission) =>
      admin || permissions.contains(permission);

  /// Whether the row carries an admin signature.
  bool get isSigned => membershipSig != null && adminPub != null;

  /// Whether the device has published signing keys.
  bool get hasKeys => signPub != null && boxPub != null;

  /// Whether [expiresAt] has passed.
  bool isExpired(DateTime now) {
    final e = expiresAt;
    return e != null && !now.toUtc().isBefore(e);
  }

  /// Whether the device may sync at [now]: active and not expired.
  bool canSync(DateTime now) =>
      status == DeviceStatus.active && !isExpired(now);

  /// Whether the device is paused and not expired: out of sync for now, but
  /// still issued new passphrases so it can read clips once resumed.
  bool isHeld(DateTime now) => status == DeviceStatus.paused && !isExpired(now);

  /// Whether the device heartbeat is recent enough to count as online.
  bool isOnline(DateTime now, {Duration within = const Duration(minutes: 3)}) =>
      now.toUtc().difference(lastSeen) <= within;

  /// Whether the device has never sent a heartbeat (row pre-created by a
  /// pairing code that has not been used yet).
  bool get isPending => lastSeen.millisecondsSinceEpoch == 0;

  /// Keys of the presence fields (everything a heartbeat may write).
  /// `sign_pub` / `box_pub` are included only when the device publishes
  /// them itself (legacy groups without an admin); in signed groups they
  /// are covered by the admin signature and a mismatch invalidates it.
  static const Set<String> presenceKeys = {
    'id',
    'name',
    'platform',
    'last_seen',
    'app_version',
    'sign_pub',
    'box_pub',
  };

  /// Keys of the membership fields (written only by `updateDevice`).
  static const Set<String> membershipKeys = {
    'status',
    'role',
    'expires_at',
    'paired_by',
    'admin',
    'admin_pub',
    'membership_version',
    'membership_sig',
    'key_version',
    'key_envelope',
  };

  /// Keys of the grant fields, added in 0.5. Written with the membership
  /// fields, but only once a row uses them (see [storesGrants]).
  static const Set<String> grantKeys = {'permissions', 'admin_envelope'};

  /// Whether [toMap] includes [grantKeys].
  bool get _writesGrants =>
      storesGrants || permissionNames.isNotEmpty || adminEnvelope != null;

  /// Canonical document shape shared by all backends.
  Map<String, Object?> toMap() => <String, Object?>{
    ...presenceMap(),
    'status': status.wire,
    'role': role.wire,
    'expires_at': expiresAt?.toUtc().toIso8601String(),
    'paired_by': pairedBy,
    'admin': admin,
    'admin_pub': adminPub,
    'membership_version': membershipVersion,
    'membership_sig': membershipSig,
    'key_version': keyVersion,
    'key_envelope': keyEnvelope,
    if (_writesGrants) ...{
      'permissions': DevicePermission.encode(permissionNames),
      'admin_envelope': adminEnvelope,
    },
  };

  /// Only the presence fields, what a heartbeat is allowed to write.
  /// Public keys are included only when set and [includeKeys] is true.
  Map<String, Object?> presenceMap({bool includeKeys = true}) =>
      <String, Object?>{
        'id': id,
        'name': name,
        'platform': platform,
        'last_seen': lastSeen.toUtc().toIso8601String(),
        'app_version': appVersion,
        if (includeKeys && signPub != null) 'sign_pub': signPub,
        if (includeKeys && boxPub != null) 'box_pub': boxPub,
      };

  /// Copy with fields replaced. `clearExpiresAt` removes the expiry.
  Device copyWith({
    String? name,
    String? platform,
    DateTime? lastSeen,
    DeviceStatus? status,
    DeviceRole? role,
    DateTime? expiresAt,
    String? pairedBy,
    String? appVersion,
    String? signPub,
    String? boxPub,
    bool? admin,
    String? adminPub,
    int? membershipVersion,
    String? membershipSig,
    int? keyVersion,
    String? keyEnvelope,
    Set<DevicePermission>? permissions,
    String? adminEnvelope,
    bool clearAdminEnvelope = false,
    bool clearExpiresAt = false,
    bool clearSignature = false,
    bool clearEnvelope = false,
  }) => Device(
    id: id,
    name: name ?? this.name,
    platform: platform ?? this.platform,
    lastSeen: lastSeen ?? this.lastSeen,
    status: status ?? this.status,
    role: role ?? this.role,
    expiresAt: clearExpiresAt ? null : (expiresAt ?? this.expiresAt),
    pairedBy: pairedBy ?? this.pairedBy,
    appVersion: appVersion ?? this.appVersion,
    signPub: signPub ?? this.signPub,
    boxPub: boxPub ?? this.boxPub,
    admin: admin ?? this.admin,
    adminPub: clearSignature ? null : (adminPub ?? this.adminPub),
    membershipVersion: membershipVersion ?? this.membershipVersion,
    membershipSig: clearSignature
        ? null
        : (membershipSig ?? this.membershipSig),
    keyVersion: clearEnvelope ? 0 : (keyVersion ?? this.keyVersion),
    keyEnvelope: clearEnvelope ? null : (keyEnvelope ?? this.keyEnvelope),
    // Replacing the known permissions keeps names this version does not
    // know, so an older admin cannot silently drop a newer grant.
    permissionNames: permissions == null
        ? permissionNames
        : {
            ...permissionNames.where(
              (n) => DevicePermission.known([n]).isEmpty,
            ),
            for (final p in permissions) p.wire,
          },
    adminEnvelope: clearAdminEnvelope
        ? null
        : (adminEnvelope ?? this.adminEnvelope),
    storesGrants: storesGrants,
  );

  /// Returns a copy with presence fields taken from [presence] and
  /// membership fields kept, how backends merge a heartbeat into an
  /// existing row.
  Device withPresence(Device presence) => copyWith(
    name: presence.name,
    platform: presence.platform,
    lastSeen: presence.lastSeen,
    appVersion: presence.appVersion,
    signPub: presence.signPub,
    boxPub: presence.boxPub,
  );

  static String? _nullIfEmpty(Object? v) =>
      v is String && v.isNotEmpty ? v : null;

  static int _toInt(Object? v) => switch (v) {
    null => 0,
    final int i => i,
    final num n => n.toInt(),
    final String s => int.tryParse(s) ?? 0,
    _ => 0,
  };

  @override
  bool operator ==(Object other) => other is Device && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Device($name/$platform, ${status.wire}, ${role.wire})';
}
