// Controller-level scenarios for deleting history (one clip, this device,
// the whole database) and for turning database sync off on one device.
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nija/data/local/database.dart';
import 'package:nija/data/settings/app_settings.dart';
import 'package:nija/features/sync/sync_controller.dart';
import 'package:nija/providers.dart';
import 'package:nija_core/nija_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _TestDb extends MemoryBackend {
  _TestDb(MemoryStore shared) : super(shared: shared);
  static const descriptorStatic = BackendDescriptor(
    id: 'testdb',
    displayName: 'Test database',
    description: 'in-memory',
    docsPath: 'docs/backends/memory.md',
    supportsRealtime: true,
    configSchema: <ConfigField>[
      ConfigField(key: 'url', label: 'URL', kind: ConfigFieldKind.url),
    ],
  );
  @override
  BackendDescriptor get descriptor => descriptorStatic;
}

class _Node {
  _Node(this.c, this.db);
  final ProviderContainer c;
  final AppDatabase db;
  SyncController get sync => c.read(syncControllerProvider.notifier);
  SyncStatus get status => c.read(syncControllerProvider);
  Future<void> dispose() async {
    c.dispose();
    await db.close();
  }
}

Future<_Node> _boot(AppSettings seed, MemoryStore shared) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final registry = BackendRegistry.builtIn()
    ..register(_TestDb.descriptorStatic, () => _TestDb(shared));
  final db = AppDatabase.withExecutor(NativeDatabase.memory());
  final c = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      databaseProvider.overrideWithValue(db),
      backendRegistryProvider.overrideWithValue(registry),
      settingsProvider.overrideWith(() => SeededSettings(seed)),
    ],
  );
  await c.read(settingsRepositoryProvider).save(seed);
  return _Node(c, db);
}

ClipItem _clip(String text, {required String device}) => ClipItem.create(
  id: 'clip-$device-${text.hashCode}',
  deviceId: device,
  deviceName: device,
  type: ClipContentType.text,
  content: text,
  contentHash: sha256Hex(text),
  sizeBytes: text.length,
  now: DateTime.now().toUtc(),
);

Future<List<String>> _history(_Node n) async =>
    (await n.c.read(localStoreProvider).watchHistory().first)
        .map((r) => r.item.content)
        .toList();

const _seed = AppSettings(
  deviceId: 'host-id',
  deviceName: 'Host',
  onboarded: true,
  backendId: 'testdb',
  backendValues: {'url': 'https://db.example.com'},
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MemoryStore shared;
  late _Node node;

  setUp(() async {
    shared = MemoryStore();
    node = await _boot(_seed, shared);
    await node.sync.start();
  });

  tearDown(() => node.dispose());

  test(
    'a clip is deleted everywhere only by the device that copied it',
    () async {
      final store = node.c.read(localStoreProvider);
      final mine = _clip('mine', device: 'host-id');
      await store.capture(mine);
      await node.sync.syncNow();
      final theirs = _clip('theirs', device: 'other-id');
      shared.items[theirs.id] = theirs;
      await node.sync.syncNow();
      expect(await _history(node), unorderedEquals(['mine', 'theirs']));
      expect(node.sync.owns(mine), isTrue);
      expect(node.sync.owns(theirs), isFalse);

      await node.sync.delete(mine);
      await node.sync.delete(theirs);
      await node.sync.syncNow();

      expect(await _history(node), isEmpty);
      expect(shared.items[mine.id]!.isDeleted, isTrue);
      expect(shared.items[mine.id]!.content, isEmpty);
      // Another device's clip stays in the group.
      expect(shared.items[theirs.id]!.isDeleted, isFalse);
      expect(shared.items[theirs.id]!.content, 'theirs');
    },
  );

  test(
    'deleting local history keeps the database and does not re-download',
    () async {
      final store = node.c.read(localStoreProvider);
      await store.capture(_clip('mine', device: 'host-id'));
      final theirs = _clip('theirs', device: 'other-id');
      shared.items[theirs.id] = theirs;
      await node.sync.syncNow();
      expect(await _history(node), hasLength(2));

      expect(await node.sync.deleteLocalHistory(), 2);
      await node.sync.syncNow();

      expect(await _history(node), isEmpty);
      expect(shared.items, hasLength(2));
    },
  );

  test('deleting database history removes every clip, keeps devices', () async {
    final store = node.c.read(localStoreProvider);
    await store.capture(_clip('mine', device: 'host-id'));
    await node.sync.syncNow();
    for (var i = 0; i < 3; i++) {
      final c = _clip('theirs $i', device: 'other-id');
      shared.items[c.id] = c;
    }
    expect(node.sync.canDeleteRemoteHistory, isTrue);

    expect(await node.sync.deleteRemoteHistory(), 4);

    expect(shared.items, isEmpty);
    expect(shared.devices.keys, contains('host-id'));
    // The engine came back up and keeps syncing.
    expect(node.status.phase, isNot(SyncPhase.stopped));
    await store.capture(_clip('after', device: 'host-id'));
    await node.sync.syncNow();
    expect(shared.items.values.map((i) => i.content), ['after']);
  });

  test(
    'only the admin may delete database history in a signed group',
    () async {
      await node.c
          .read(settingsRepositoryProvider)
          .saveTrustedAdminPub(_seed.backendScope, 'someone-else');
      await node.sync.restart();
      expect(node.sync.isSignedGroup, isTrue);
      expect(node.sync.isAdmin, isFalse);
      expect(node.sync.canDeleteRemoteHistory, isFalse);
      await expectLater(node.sync.deleteRemoteHistory(), throwsStateError);
    },
  );

  test('turning database sync off keeps clips local', () async {
    await node.c
        .read(settingsProvider.notifier)
        .update((x) => x.copyWith(remoteSyncEnabled: false));
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(node.status.phase, SyncPhase.paused);
    expect(node.sync.backend, isNull);

    await node.c
        .read(settingsProvider.notifier)
        .update((x) => x.copyWith(remoteSyncEnabled: true));
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(node.sync.backend, isNotNull);
    expect(node.status.phase, isNot(SyncPhase.paused));
  });
}
