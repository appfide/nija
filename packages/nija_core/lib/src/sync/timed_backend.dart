import 'dart:async';

import 'package:nija_core/src/backend/backend_config.dart';
import 'package:nija_core/src/backend/backend_descriptor.dart';
import 'package:nija_core/src/backend/sync_backend.dart';
import 'package:nija_core/src/model/clip_item.dart';
import 'package:nija_core/src/model/device.dart';

/// Puts a deadline on every request the sync engine makes. Some database
/// clients wait forever on a connection that went away (a Mac that woke up
/// or booted before its network did), and one such request used to hold the
/// engine for good: no heartbeat, no push, no pull, while the app still
/// said *Synced*. A request past its deadline fails as a transient error,
/// so the engine retries it like any other network failure.
class TimedBackend implements SyncBackend {
  /// Wraps [inner]. [deviceTimeout] covers the small device-row requests,
  /// [dataTimeout] the clip transfers, which may carry images.
  TimedBackend(
    this.inner, {
    this.deviceTimeout = const Duration(seconds: 20),
    this.dataTimeout = const Duration(minutes: 2),
  });

  /// The backend doing the work.
  final SyncBackend inner;

  /// Deadline for device-row requests.
  final Duration deviceTimeout;

  /// Deadline for clip transfers.
  final Duration dataTimeout;

  Future<T> _within<T>(Duration limit, String what, Future<T> request) =>
      request.timeout(
        limit,
        onTimeout: () => throw BackendException(
          '$what timed out after ${limit.inSeconds} s',
          isTransient: true,
        ),
      );

  @override
  BackendDescriptor get descriptor => inner.descriptor;

  @override
  Future<void> connect(BackendConfig config) => inner.connect(config);

  @override
  Future<ConnectionCheck> testConnection() => inner.testConnection();

  @override
  Future<SchemaCheck> verifySchema() => inner.verifySchema();

  @override
  Future<void> upsert(List<ClipItem> items) =>
      _within(dataTimeout, 'Sending clips', inner.upsert(items));

  @override
  Future<List<ClipItem>> pullSince(
    DateTime? cursor, {
    required String excludeDeviceId,
    int limit = 500,
  }) => _within(
    dataTimeout,
    'Fetching clips',
    inner.pullSince(cursor, excludeDeviceId: excludeDeviceId, limit: limit),
  );

  @override
  Stream<ClipItem> watch({required String excludeDeviceId}) =>
      inner.watch(excludeDeviceId: excludeDeviceId);

  @override
  Future<void> tombstone(String id, DateTime now) =>
      _within(dataTimeout, 'Deleting a clip', inner.tombstone(id, now));

  @override
  Future<void> registerDevice(Device device) => _within(
    deviceTimeout,
    'Updating this device',
    inner.registerDevice(device),
  );

  @override
  Future<void> updateDevice(Device device) =>
      _within(deviceTimeout, 'Updating a device', inner.updateDevice(device));

  @override
  Future<void> deleteDevice(String id) =>
      _within(deviceTimeout, 'Removing a device', inner.deleteDevice(id));

  @override
  Future<List<Device>> listDevices() =>
      _within(deviceTimeout, 'Listing devices', inner.listDevices());

  @override
  Future<int> purgeBefore(DateTime before) =>
      _within(dataTimeout, 'Removing old clips', inner.purgeBefore(before));

  @override
  Future<void> dispose() => inner.dispose();
}
