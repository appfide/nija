import 'package:nija_core/nija_core.dart' show SyncEngine;
import 'package:nija_core/src/model/clip_item.dart';
import 'package:nija_core/src/sync/sync_engine.dart' show SyncEngine;

/// Local persistence the [SyncEngine] drives. The app implements this with
/// drift/SQLite; tests use an in-memory version.
///
/// Items live in one table; the *outbox* is the subset with
/// `synced == false`. The engine never deletes rows; retention does.
abstract class LocalStore {
  /// Items captured locally that have not been pushed yet, oldest first.
  Future<List<ClipItem>> pendingOutbox({int limit = 100});

  /// Marks [ids] as pushed.
  Future<void> markSynced(Iterable<String> ids);

  /// Takes [ids] out of the outbox for good: they stay on this device and
  /// [requeueOwn] never sends them.
  Future<void> keepLocal(Iterable<String> ids);

  /// Puts every live clip [deviceId] copied (not the copies it sent to one
  /// device) back in the outbox with `updated_at` = [now], so the next push
  /// seals it again with the current key and every device pulls it again.
  /// Returns how many.
  Future<int> requeueOwn(String deviceId, DateTime now);

  /// Applies items received from the backend. Must be last-writer-wins on
  /// `updated_at` and must set `synced = true` for these rows.
  Future<void> applyRemote(List<ClipItem> items);

  /// Whether a live (non-deleted) item with [contentHash] exists that was
  /// created after [since]. Used to suppress echo loops.
  Future<bool> hasRecentHash(String contentHash, DateTime since);

  /// Last remote `updated_at` fully applied, or `null` on first sync.
  Future<DateTime?> loadCursor();

  /// Persists the cursor.
  Future<void> saveCursor(DateTime cursor);
}
