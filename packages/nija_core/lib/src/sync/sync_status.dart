import 'package:meta/meta.dart';
import 'package:nija_core/src/model/device.dart';

/// Engine state.
enum SyncPhase {
  /// Not started or stopped.
  stopped,

  /// Connected, nothing in flight.
  idle,

  /// Push or pull in progress.
  syncing,

  /// Last operation failed; will retry unless [SyncStatus.authFailed].
  error,

  /// The group admin paused this device. Heartbeats continue so it notices
  /// the resume; nothing is pushed or pulled.
  paused,

  /// This device was blocked, removed, or its access expired. The engine
  /// has stopped itself; the app must forget the credentials.
  revoked,
}

/// Snapshot of engine state for the UI.
@immutable
class SyncStatus {
  /// Creates a status.
  const SyncStatus({
    required this.phase,
    this.lastSyncAt,
    this.lastError,
    this.pendingCount = 0,
    this.authFailed = false,
    this.realtime = false,
    this.role = DeviceRole.full,
    this.revokedReason,
    this.signedGroup = false,
    this.selfVerified = true,
    this.keyVersion = 0,
    this.keyDrift = false,
  });

  /// Initial status.
  const SyncStatus.stopped() : this(phase: SyncPhase.stopped);

  /// Current phase.
  final SyncPhase phase;

  /// Last successful push or pull (UTC).
  final DateTime? lastSyncAt;

  /// Redacted last error message.
  final String? lastError;

  /// Items waiting in the outbox.
  final int pendingCount;

  /// Credentials rejected; retries paused until settings change.
  final bool authFailed;

  /// Whether a realtime subscription is active.
  final bool realtime;

  /// Role the group assigned to this device (from its device row).
  final DeviceRole role;

  /// Why the engine stopped when [phase] is [SyncPhase.revoked].
  final String? revokedReason;

  /// Whether an admin key is pinned (membership and clips are verified).
  final bool signedGroup;

  /// In a signed group: whether this device's own row carries a valid admin
  /// signature. When false, other devices ignore this device's clips.
  final bool selfVerified;

  /// Newest passphrase version this device holds (0 = no encryption).
  final int keyVersion;

  /// Whether another member seems to hold a different encryption key, so
  /// clips between the two do not open. The group admin fixes it on its
  /// own by issuing a fresh key; the other devices wait for it.
  final bool keyDrift;

  /// Copy with fields replaced.
  SyncStatus copyWith({
    SyncPhase? phase,
    DateTime? lastSyncAt,
    String? lastError,
    int? pendingCount,
    bool? authFailed,
    bool? realtime,
    DeviceRole? role,
    String? revokedReason,
    bool? signedGroup,
    bool? selfVerified,
    int? keyVersion,
    bool? keyDrift,
    bool clearError = false,
  }) => SyncStatus(
    phase: phase ?? this.phase,
    lastSyncAt: lastSyncAt ?? this.lastSyncAt,
    lastError: clearError ? null : (lastError ?? this.lastError),
    pendingCount: pendingCount ?? this.pendingCount,
    authFailed: authFailed ?? this.authFailed,
    realtime: realtime ?? this.realtime,
    role: role ?? this.role,
    revokedReason: revokedReason ?? this.revokedReason,
    signedGroup: signedGroup ?? this.signedGroup,
    selfVerified: selfVerified ?? this.selfVerified,
    keyVersion: keyVersion ?? this.keyVersion,
    keyDrift: keyDrift ?? this.keyDrift,
  );

  @override
  String toString() =>
      'SyncStatus($phase, pending=$pendingCount'
      '${lastError != null ? ', error=$lastError' : ''})';
}
