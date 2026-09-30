import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nija/data/local/database.dart';
import 'package:nija/data/local/local_store.dart';
import 'package:nija_core/nija_core.dart';
import 'package:sqlite3/sqlite3.dart';

ClipItem _item(
  String text, {
  String device = 'me',
  DateTime? at,
  ClipContentType type = ClipContentType.text,
}) {
  final now = at ?? DateTime.now().toUtc();
  return ClipItem.create(
    id: 'id-${now.microsecondsSinceEpoch}-$text',
    deviceId: device,
    deviceName: device,
    type: type,
    content: text,
    contentHash: sha256Hex(text),
    sizeBytes: text.length,
    now: now,
  );
}

void main() {
  late AppDatabase db;
  late DriftLocalStore store;

  setUp(() {
    db = AppDatabase.withExecutor(NativeDatabase.memory());
    store = DriftLocalStore(db);
  });
  tearDown(() => db.close());

  test('capture goes to outbox, markSynced clears it', () async {
    expect(await store.capture(_item('a')), isTrue);
    expect(
      await store.capture(_item('a')),
      isFalse,
      reason: 'duplicate at top is ignored',
    );
    final pending = await store.pendingOutbox();
    expect(pending.length, 1);
    await store.markSynced(pending.map((i) => i.id));
    expect(await store.pendingOutbox(), isEmpty);
  });

  test('applyRemote is last-writer-wins and keeps pin', () async {
    final base = DateTime.utc(2026);
    final remote = _item('r', device: 'other', at: base);
    await store.applyRemote([remote]);
    await store.setPinned(remote.id, pinned: true);
    final older = remote.copyWith(
      content: 'stale',
      updatedAt: base.subtract(const Duration(minutes: 1)),
    );
    await store.applyRemote([older]);
    final newer = remote.copyWith(
      content: 'fresh',
      updatedAt: base.add(const Duration(minutes: 1)),
    );
    await store.applyRemote([newer]);
    final rows = await store.watchHistory().first;
    expect(rows.single.item.content, 'fresh');
    expect(rows.single.pinned, isTrue);
    expect(rows.single.synced, isTrue);
  });

  test('cursor round-trips with millisecond precision', () async {
    expect(await store.loadCursor(), isNull);
    final c = DateTime.utc(2026, 9, 8, 12, 0, 0, 123);
    await store.saveCursor(c);
    expect(await store.loadCursor(), c);
    await store.resetCursor();
    expect(await store.loadCursor(), isNull);
  });

  test('hasRecentHash respects window and tombstones', () async {
    final i = _item('echo');
    await store.capture(i);
    expect(
      await store.hasRecentHash(
        i.contentHash,
        DateTime.now().toUtc().subtract(const Duration(seconds: 5)),
      ),
      isTrue,
    );
    expect(
      await store.hasRecentHash(
        i.contentHash,
        DateTime.now().toUtc().add(const Duration(seconds: 5)),
      ),
      isFalse,
    );
    await store.delete(i.id, DateTime.now().toUtc());
    expect(
      await store.hasRecentHash(i.contentHash, DateTime.utc(2000)),
      isFalse,
    );
    expect((await store.pendingOutbox()).single.isDeleted, isTrue);
  });

  test('search filters by content and hides deleted', () async {
    await store.capture(_item('hello world'));
    await store.capture(_item('goodbye'));
    expect((await store.watchHistory(query: 'hello').first).length, 1);
    expect((await store.watchHistory().first).length, 2);
  });

  test('filters narrow by kind and combine with search', () async {
    final base = DateTime.utc(2026);
    final link = _item(
      'https://example.com/a',
      at: base,
      type: ClipContentType.url,
    );
    final note = _item('a note', at: base.add(const Duration(seconds: 1)));
    final markup = _item(
      '<b>a</b>',
      at: base.add(const Duration(seconds: 2)),
      type: ClipContentType.html,
    );
    final picture = _item(
      'aGVsbG8=',
      at: base.add(const Duration(seconds: 3)),
      type: ClipContentType.image,
    );
    await store.applyRemote([link, note, markup, picture]);
    await store.setPinned(note.id, pinned: true);

    Future<List<String>> ids(HistoryFilter f, [String q = '']) async =>
        (await store.watchHistory(filter: f, query: q).first)
            .map((r) => r.item.id)
            .toList();

    expect(await ids(HistoryFilter.all), hasLength(4));
    expect(await ids(HistoryFilter.text), [note.id, markup.id]);
    expect(await ids(HistoryFilter.links), [link.id]);
    expect(await ids(HistoryFilter.images), [picture.id]);
    expect(await ids(HistoryFilter.pinned), [note.id]);
    expect(await ids(HistoryFilter.text, 'note'), [note.id]);
    expect(await ids(HistoryFilter.links, 'note'), isEmpty);
  });

  test('purgeBefore keeps pinned and unsynced rows', () async {
    final old = _item('old', at: DateTime.utc(2000));
    final pinnedOld = _item('pinned', at: DateTime.utc(2000));
    await store.applyRemote([old, pinnedOld]);
    await store.setPinned(pinnedOld.id, pinned: true);
    await store.capture(_item('unsynced', at: DateTime.utc(2000)));
    final n = await store.purgeBefore(DateTime.utc(2001));
    expect(n, 1);
  });

  group('device features', _deviceFeatures);
}

void _deviceFeatures() {
  late AppDatabase db;
  late DriftLocalStore store;

  setUp(() {
    db = AppDatabase.withExecutor(NativeDatabase.memory());
    store = DriftLocalStore(db);
  });
  tearDown(() => db.close());

  test('localOnly capture never enters the outbox', () async {
    expect(await store.capture(_item('secret'), localOnly: true), isTrue);
    expect(await store.pendingOutbox(), isEmpty);
    final rows = await store.watchHistory().first;
    expect(rows.single.item.content, 'secret');
    expect(rows.single.synced, isTrue);
  });

  test(
    'targeted copies are queued, hidden from the sender, shown to the receiver',
    () async {
      final original = _item('hello');
      await store.capture(original);
      final copy = ClipItem.create(
        id: 'copy-1',
        deviceId: 'me',
        deviceName: 'me',
        type: ClipContentType.text,
        content: 'hello',
        contentHash: original.contentHash,
        sizeBytes: 5,
        now: DateTime.now().toUtc().add(const Duration(seconds: 1)),
        targetDeviceId: 'them',
      );
      await store.enqueue(copy);
      expect(
        (await store.pendingOutbox()).map((i) => i.id),
        contains('copy-1'),
      );
      // Sender view: the duplicate is hidden.
      final mine = await store.watchHistory(ownDeviceId: 'me').first;
      expect(mine.map((r) => r.item.id), [original.id]);
      // Receiver view: a targeted item from another device is shown.
      final incoming = ClipItem.create(
        id: 'for-me',
        deviceId: 'them',
        deviceName: 'them',
        type: ClipContentType.text,
        content: 'for you',
        contentHash: sha256Hex('for you'),
        sizeBytes: 7,
        now: DateTime.now().toUtc().add(const Duration(seconds: 2)),
        targetDeviceId: 'me',
      );
      await store.applyRemote([incoming]);
      final view = await store.watchHistory(ownDeviceId: 'me').first;
      expect(view.map((r) => r.item.id), containsAll(['for-me', original.id]));
      expect(view.map((r) => r.item.id), isNot(contains('copy-1')));
      expect(
        view.firstWhere((r) => r.item.id == 'for-me').item.isTargeted,
        isTrue,
      );
      // Top-of-history de-duplication ignores targeted rows.
      expect(await store.capture(_item('hello')), isFalse);
    },
  );

  test('schema v1 database upgrades to v2 keeping rows', () async {
    final raw = sqlite3.openInMemory()
      ..execute('''
      CREATE TABLE clip_items (
        id TEXT NOT NULL PRIMARY KEY, device_id TEXT NOT NULL,
        device_name TEXT NOT NULL DEFAULT '', content_type TEXT NOT NULL DEFAULT 'text',
        content TEXT NOT NULL DEFAULT '', blob_ref TEXT NULL, content_hash TEXT NOT NULL,
        size_bytes INTEGER NOT NULL DEFAULT 0, encrypted INTEGER NOT NULL DEFAULT 0,
        nonce TEXT NULL, created_at TEXT NOT NULL, updated_at TEXT NOT NULL,
        deleted_at TEXT NULL, synced INTEGER NOT NULL DEFAULT 0,
        pinned INTEGER NOT NULL DEFAULT 0)''')
      ..execute(
        'CREATE TABLE sync_meta (key TEXT NOT NULL PRIMARY KEY, value TEXT NOT NULL)',
      )
      ..execute(
        "INSERT INTO clip_items (id, device_id, content, content_hash, created_at, updated_at, synced) VALUES ('old', 'me', 'kept', 'h', '2026-01-01T00:00:00.000Z', '2026-01-01T00:00:00.000Z', 1)",
      )
      ..execute('PRAGMA user_version = 1');

    final upgraded = AppDatabase.withExecutor(NativeDatabase.opened(raw));
    final rows = await upgraded.select(upgraded.clipItems).get();
    expect(rows.single.id, 'old');
    expect(rows.single.content, 'kept');
    expect(rows.single.targetDeviceId, isNull);
    expect(raw.userVersion, 2);
    await DriftLocalStore(upgraded).enqueue(
      ClipItem.create(
        id: 'new',
        deviceId: 'me',
        deviceName: 'me',
        type: ClipContentType.text,
        content: 'x',
        contentHash: 'hx',
        sizeBytes: 1,
        now: DateTime.now().toUtc(),
        targetDeviceId: 'them',
      ),
    );
    final all = await upgraded.select(upgraded.clipItems).get();
    expect(all.firstWhere((r) => r.id == 'new').targetDeviceId, 'them');
    await upgraded.close();
  });
}
