import 'package:drift/drift.dart';
import 'package:nija/data/local/database.dart';
import 'package:nija_core/nija_core.dart';

/// [LocalStore] over drift plus the history queries the UI needs.
class DriftLocalStore implements LocalStore {
  /// Creates a store on [db].
  DriftLocalStore(this.db);

  /// Underlying database.
  final AppDatabase db;

  static const _cursorKey = 'cursor';

  // --- LocalStore ----------------------------------------------------------

  @override
  Future<List<ClipItem>> pendingOutbox({int limit = 100}) async {
    final rows =
        await (db.select(db.clipItems)
              ..where((t) => t.synced.equals(false))
              ..orderBy([(t) => OrderingTerm.asc(t.updatedAt)])
              ..limit(limit))
            .get();
    return rows.map(_toItem).toList();
  }

  @override
  Future<void> markSynced(Iterable<String> ids) async {
    final list = ids.toList();
    if (list.isEmpty) return;
    await (db.update(db.clipItems)..where((t) => t.id.isIn(list))).write(
      const ClipItemsCompanion(synced: Value(true)),
    );
  }

  @override
  Future<void> applyRemote(List<ClipItem> items) async {
    if (items.isEmpty) return;
    await db.transaction(() async {
      for (final item in items) {
        final existing = await (db.select(
          db.clipItems,
        )..where((t) => t.id.equals(item.id))).getSingleOrNull();
        if (existing != null && existing.updatedAt.isAfter(item.updatedAt)) {
          continue; // local is newer (last-writer-wins)
        }
        await db
            .into(db.clipItems)
            .insertOnConflictUpdate(
              _toCompanion(
                item,
                synced: true,
                pinned: existing?.pinned ?? false,
              ),
            );
      }
    });
  }

  @override
  Future<bool> hasRecentHash(String contentHash, DateTime since) async {
    final row =
        await (db.select(db.clipItems)
              ..where(
                (t) =>
                    t.contentHash.equals(contentHash) &
                    t.deletedAt.isNull() &
                    t.createdAt.isBiggerThanValue(since),
              )
              ..limit(1))
            .getSingleOrNull();
    return row != null;
  }

  @override
  Future<DateTime?> loadCursor() async {
    final row = await (db.select(
      db.syncMeta,
    )..where((t) => t.key.equals(_cursorKey))).getSingleOrNull();
    return row == null ? null : DateTime.parse(row.value).toUtc();
  }

  @override
  Future<void> saveCursor(DateTime cursor) => db
      .into(db.syncMeta)
      .insertOnConflictUpdate(
        SyncMetaCompanion.insert(
          key: _cursorKey,
          value: cursor.toUtc().toIso8601String(),
        ),
      );

  /// Drops the cursor (after switching backends).
  Future<void> resetCursor() =>
      (db.delete(db.syncMeta)..where((t) => t.key.equals(_cursorKey))).go();

  // --- History -------------------------------------------------------------

  /// Inserts a locally captured item into the outbox. Returns false if an
  /// identical live item already sits at the top of the history.
  ///
  /// With [localOnly] the row is stored as already synced so it never leaves
  /// this device (receive-only role, or capture while paused from sync).
  Future<bool> capture(ClipItem item, {bool localOnly = false}) async {
    final top =
        await (db.select(db.clipItems)
              ..where((t) => t.deletedAt.isNull() & t.targetDeviceId.isNull())
              ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
              ..limit(1))
            .getSingleOrNull();
    if (top != null && top.contentHash == item.contentHash) return false;
    await db
        .into(db.clipItems)
        .insert(_toCompanion(item, synced: localOnly, pinned: false));
    return true;
  }

  /// Queues an item for push without the top-of-history de-duplication
  /// (used for "Send to device" copies, which carry a target).
  Future<void> enqueue(ClipItem item) => db
      .into(db.clipItems)
      .insert(_toCompanion(item, synced: false, pinned: false));

  /// Live history, newest first, optionally narrowed by [query] and
  /// [filter]. Targeted copies this device *sent* to another device are
  /// hidden (they are duplicates of the original); targeted items
  /// *received* are shown.
  Stream<List<HistoryEntry>> watchHistory({
    String query = '',
    HistoryFilter filter = HistoryFilter.all,
    int limit = 500,
    String? ownDeviceId,
  }) {
    final q = db.select(db.clipItems)
      ..where((t) => t.deletedAt.isNull())
      ..orderBy([
        (t) => OrderingTerm.desc(t.pinned),
        (t) => OrderingTerm.desc(t.createdAt),
      ])
      ..limit(limit);
    if (ownDeviceId != null) {
      q.where(
        (t) => t.targetDeviceId.isNull() | t.deviceId.equals(ownDeviceId).not(),
      );
    }
    if (query.trim().isNotEmpty) {
      q.where(
        (t) => t.content.like('%${query.trim()}%') & t.encrypted.equals(false),
      );
    }
    switch (filter) {
      case HistoryFilter.all:
        break;
      case HistoryFilter.pinned:
        q.where((t) => t.pinned.equals(true));
      case HistoryFilter.text:
      case HistoryFilter.links:
      case HistoryFilter.images:
        q.where((t) => t.contentType.isIn(filter.types.map((c) => c.wire)));
    }
    return q.watch().map(
      (rows) => rows
          .map(
            (r) => HistoryEntry(_toItem(r), pinned: r.pinned, synced: r.synced),
          )
          .toList(),
    );
  }

  /// Number of unsynced rows.
  Stream<int> watchPendingCount() {
    final count = db.clipItems.id.count();
    final q = db.selectOnly(db.clipItems)
      ..addColumns([count])
      ..where(db.clipItems.synced.equals(false));
    return q.watchSingle().map((r) => r.read(count) ?? 0);
  }

  /// Toggles pin (local only, never synced).
  Future<void> setPinned(String id, {required bool pinned}) =>
      (db.update(db.clipItems)..where((t) => t.id.equals(id))).write(
        ClipItemsCompanion(pinned: Value(pinned)),
      );

  /// Tombstones an item locally and queues the tombstone for push.
  Future<void> delete(String id, DateTime now) =>
      (db.update(db.clipItems)..where((t) => t.id.equals(id))).write(
        ClipItemsCompanion(
          deletedAt: Value(now.toUtc()),
          updatedAt: Value(now.toUtc()),
          content: const Value(''),
          synced: const Value(false),
        ),
      );

  /// Tombstones every live item (Clear history).
  Future<void> deleteAll(DateTime now) =>
      (db.update(db.clipItems)..where((t) => t.deletedAt.isNull())).write(
        ClipItemsCompanion(
          deletedAt: Value(now.toUtc()),
          updatedAt: Value(now.toUtc()),
          content: const Value(''),
          synced: const Value(false),
        ),
      );

  /// Physically removes synced rows older than [before] that are not pinned.
  Future<int> purgeBefore(DateTime before) =>
      (db.delete(db.clipItems)..where(
            (t) =>
                t.updatedAt.isSmallerThanValue(before.toUtc()) &
                t.pinned.equals(false) &
                t.synced.equals(true),
          ))
          .go();

  /// Deletes everything (used when switching backend with "start fresh").
  Future<void> wipe() async {
    await db.delete(db.clipItems).go();
    await db.delete(db.syncMeta).go();
  }

  // --- mapping -------------------------------------------------------------

  static ClipItem _toItem(ClipRow r) => ClipItem(
    id: r.id,
    deviceId: r.deviceId,
    deviceName: r.deviceName,
    type: ClipContentType.fromWire(r.contentType),
    content: r.content,
    blobRef: r.blobRef,
    contentHash: r.contentHash,
    sizeBytes: r.sizeBytes,
    encrypted: r.encrypted,
    nonce: r.nonce,
    createdAt: r.createdAt.toUtc(),
    updatedAt: r.updatedAt.toUtc(),
    deletedAt: r.deletedAt?.toUtc(),
    targetDeviceId: r.targetDeviceId,
  );

  static ClipItemsCompanion _toCompanion(
    ClipItem i, {
    required bool synced,
    required bool pinned,
  }) => ClipItemsCompanion(
    id: Value(i.id),
    deviceId: Value(i.deviceId),
    deviceName: Value(i.deviceName),
    contentType: Value(i.type.wire),
    content: Value(i.content),
    blobRef: Value(i.blobRef),
    contentHash: Value(i.contentHash),
    sizeBytes: Value(i.sizeBytes),
    encrypted: Value(i.encrypted),
    nonce: Value(i.nonce),
    createdAt: Value(i.createdAt.toUtc()),
    updatedAt: Value(i.updatedAt.toUtc()),
    deletedAt: Value(i.deletedAt?.toUtc()),
    synced: Value(synced),
    pinned: Value(pinned),
    targetDeviceId: Value(i.targetDeviceId),
  );
}

/// Narrows the history list to one kind of clip.
enum HistoryFilter {
  /// Everything.
  all('All', []),

  /// Plain text and HTML.
  text('Text', [ClipContentType.text, ClipContentType.html]),

  /// Single URLs.
  links('Links', [ClipContentType.url]),

  /// Images.
  images('Images', [ClipContentType.image]),

  /// Pinned items of any kind.
  pinned('Pinned', []);

  const HistoryFilter(this.label, this.types);

  /// Chip label.
  final String label;

  /// Content types this filter keeps; empty when it does not filter by type.
  final List<ClipContentType> types;
}

/// A history row with local-only flags.
class HistoryEntry {
  /// Creates an entry.
  const HistoryEntry(this.item, {required this.pinned, required this.synced});

  /// The clip.
  final ClipItem item;

  /// Pinned locally.
  final bool pinned;

  /// Pushed to the backend.
  final bool synced;
}
