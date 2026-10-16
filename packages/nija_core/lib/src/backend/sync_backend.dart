import 'package:meta/meta.dart';
import 'package:nija_core/src/backend/backend_config.dart';
import 'package:nija_core/src/backend/backend_descriptor.dart';
import 'package:nija_core/src/model/clip_item.dart';
import 'package:nija_core/src/model/device.dart';

/// Result of [SyncBackend.testConnection].
@immutable
class ConnectionCheck {
  /// Creates a check result.
  const ConnectionCheck({
    required this.ok,
    required this.message,
    this.latency,
  });

  /// Success.
  const ConnectionCheck.success(this.message, {this.latency}) : ok = true;

  /// Failure.
  const ConnectionCheck.failure(this.message) : ok = false, latency = null;

  /// Whether the backend answered with valid credentials.
  final bool ok;

  /// Human-readable detail (server version, error text).
  final String message;

  /// Round-trip time when measured.
  final Duration? latency;
}

/// Result of [SyncBackend.verifySchema].
@immutable
class SchemaCheck {
  /// Creates a schema check result.
  const SchemaCheck({
    required this.ok,
    this.missing = const [],
    this.hint,
    this.setupScript,
  });

  /// Everything the adapter needs exists.
  const SchemaCheck.ready()
    : ok = true,
      missing = const [],
      hint = null,
      setupScript = null;

  /// Whether the schema is complete.
  final bool ok;

  /// Names of missing tables / collections / indexes / rules.
  final List<String> missing;

  /// What to do about it (usually "run the SQL in docs/backends/x.md").
  final String? hint;

  /// Script that creates or upgrades the schema for the current settings,
  /// safe to run more than once, when the adapter can generate one.
  final String? setupScript;
}

/// Error raised by a backend adapter. `message` is already redacted.
class BackendException implements Exception {
  /// Creates an exception.
  BackendException(
    this.message, {
    this.cause,
    this.isAuth = false,
    this.isTransient = false,
  });

  /// Redacted, user-presentable message.
  final String message;

  /// Underlying error, if any.
  final Object? cause;

  /// Credentials rejected; do not retry until settings change.
  final bool isAuth;

  /// Network / 5xx: retry with backoff.
  final bool isTransient;

  @override
  String toString() => 'BackendException: $message';
}

/// Contract every database adapter implements.
///
/// Adapters talk **directly** to the user's database with the credentials in
/// [BackendConfig]; there is no intermediate server. Each adapter owns its
/// native schema (documented in `docs/backends/<id>.md`) and maps to/from the
/// canonical [ClipItem.toMap] shape.
///
/// Lifecycle: `connect` → (`testConnection` | `verifySchema`)? → use →
/// `dispose`. Adapters must be safe to `dispose` without `connect`.
abstract class SyncBackend {
  /// Static description used by the settings UI and registry.
  BackendDescriptor get descriptor;

  /// Opens the connection using [config]. Must not throw on bad credentials,
  /// those surface from [testConnection] or the first operation.
  Future<void> connect(BackendConfig config);

  /// Cheap round-trip that validates credentials and reachability.
  Future<ConnectionCheck> testConnection();

  /// Checks that tables / collections / indexes exist. Never creates them,
  /// the user provisions the database following the docs.
  Future<SchemaCheck> verifySchema();

  /// Inserts or replaces [items] by `id`. Must be idempotent.
  Future<void> upsert(List<ClipItem> items);

  /// Returns items with `updated_at > cursor` (all items when `null`),
  /// ordered by `updated_at` ascending, excluding those from
  /// [excludeDeviceId]. Includes tombstones. [limit] caps the page size.
  Future<List<ClipItem>> pullSince(
    DateTime? cursor, {
    required String excludeDeviceId,
    int limit = 500,
  });

  /// Live changes from other devices. Emits nothing when
  /// [BackendDescriptor.supportsRealtime] is false; the engine polls instead.
  Stream<ClipItem> watch({required String excludeDeviceId});

  /// Marks [id] as deleted (`deleted_at = now`). Idempotent; no error when
  /// the id is unknown.
  Future<void> tombstone(String id, DateTime now);

  /// Heartbeat: creates the device row if missing, otherwise refreshes
  /// **only** the presence fields ([Device.presenceMap]). Must never
  /// overwrite membership fields (`status`, `role`, `expires_at`,
  /// `paired_by`) that another device set with [updateDevice].
  Future<void> registerDevice(Device device);

  /// Writes the full device row: presence and membership fields. Used by
  /// the managing device to block, re-activate, change the role or expiry,
  /// mark as removed, or pre-create a row for a pairing code.
  Future<void> updateDevice(Device device);

  /// Physically deletes the device row ("Forget"). Idempotent.
  Future<void> deleteDevice(String id);

  /// Lists known devices, including blocked, removed and pending ones.
  Future<List<Device>> listDevices();

  /// Physically removes items and tombstones with `updated_at < before`.
  /// Used by retention. Returns the number removed (or -1 if unknown).
  Future<int> purgeBefore(DateTime before);

  /// Releases sockets / subscriptions.
  Future<void> dispose();
}
