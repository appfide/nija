import 'dart:async';

import 'package:mongo_dart/mongo_dart.dart';
import 'package:nija_core/src/backend/backend_config.dart';
import 'package:nija_core/src/backend/backend_descriptor.dart';
import 'package:nija_core/src/backend/config_field.dart';
import 'package:nija_core/src/backend/sync_backend.dart';
import 'package:nija_core/src/model/clip_item.dart';
import 'package:nija_core/src/model/device.dart';
import 'package:nija_core/src/util/redact.dart';

/// MongoDB adapter using the wire protocol directly (`mongo_dart`).
///
/// MongoDB Atlas retired its serverless Data API in September 2025, so a
/// direct driver connection is the only way to reach MongoDB from a client
/// without running a server. Use a dedicated database user scoped to one
/// database (see `docs/backends/mongodb.md`). Polling only.
class MongoDbBackend implements SyncBackend {
  /// Creates an unconnected adapter.
  MongoDbBackend();

  /// Descriptor shared with the registry.
  static const BackendDescriptor descriptorStatic = BackendDescriptor(
    id: 'mongodb',
    displayName: 'MongoDB',
    description:
        'MongoDB Atlas or self-hosted, via direct driver connection over TLS.',
    docsPath: 'docs/backends/mongodb.md',
    configSchema: <ConfigField>[
      ConfigField(
        key: 'uri',
        label: 'Connection string',
        kind: ConfigFieldKind.secret,
        placeholder:
            'mongodb+srv://USER:PASSWORD@cluster0.xxxx.mongodb.net/nija',
        help:
            'Include the database name in the path. Stored in the OS keychain.',
      ),
      ConfigField(
        key: 'collection',
        label: 'Items collection',
        kind: ConfigFieldKind.text,
        defaultValue: 'clip_items',
      ),
      ConfigField(
        key: 'devices_collection',
        label: 'Devices collection',
        kind: ConfigFieldKind.text,
        defaultValue: 'devices',
      ),
    ],
  );

  Db? _db;
  late String _uri;
  late String _collection;
  late String _devicesCollection;

  @override
  BackendDescriptor get descriptor => descriptorStatic;

  @override
  Future<void> connect(BackendConfig config) async {
    _uri = config.require('uri');
    _collection = config.stringOr('collection', 'clip_items');
    _devicesCollection = config.stringOr('devices_collection', 'devices');
    if (!_uri.startsWith('mongodb://') && !_uri.startsWith('mongodb+srv://')) {
      throw BackendException(
        'Connection string must start with mongodb:// or mongodb+srv://',
        isAuth: true,
      );
    }
  }

  Future<Db> _open() async {
    final existing = _db;
    if (existing != null && existing.isConnected) return existing;
    try {
      final db = await Db.create(_uri);
      await db.open(
        secure:
            _uri.startsWith('mongodb+srv://') ||
            _uri.contains('tls=true') ||
            _uri.contains('ssl=true'),
      );
      _db = db;
      return db;
    } catch (e) {
      throw _wrap(e);
    }
  }

  DbCollection _items(Db db) => db.collection(_collection);

  @override
  Future<ConnectionCheck> testConnection() async {
    final sw = Stopwatch()..start();
    try {
      final db = await _open();
      final status = await db.runCommand({'ping': 1});
      if (status['ok'] != 1 && status['ok'] != 1.0) {
        return ConnectionCheck.failure(
          'MongoDB ping failed: ${redactSecrets(status.toString())}',
        );
      }
      return ConnectionCheck.success(
        'MongoDB connected (${db.databaseName})',
        latency: sw.elapsed,
      );
    } catch (e) {
      return ConnectionCheck.failure(_wrap(e).message);
    }
  }

  @override
  Future<SchemaCheck> verifySchema() async {
    try {
      final db = await _open();
      final names = (await db.getCollectionNames()).whereType<String>().toSet();
      final missing = <String>[
        for (final c in [_collection, _devicesCollection])
          if (!names.contains(c)) 'collection $c',
      ];
      if (missing.isEmpty) {
        final idx = await _items(db).getIndexes();
        final hasUpdated = idx.any(
          (i) => (i['key'] as Map?)?.containsKey('updated_at') ?? false,
        );
        if (!hasUpdated) missing.add('index $_collection.updated_at');
      }
      return missing.isEmpty
          ? const SchemaCheck.ready()
          : SchemaCheck(
              ok: false,
              missing: missing,
              hint: 'Run the mongosh script in ${descriptorStatic.docsPath}',
            );
    } catch (e) {
      throw _wrap(e);
    }
  }

  @override
  Future<void> upsert(List<ClipItem> items) async {
    if (items.isEmpty) return;
    try {
      final col = _items(await _open());
      for (final i in items) {
        await col.replaceOne(where.eq('_id', i.id), _doc(i), upsert: true);
      }
    } catch (e) {
      throw _wrap(e);
    }
  }

  @override
  Future<List<ClipItem>> pullSince(
    DateTime? cursor, {
    required String excludeDeviceId,
    int limit = 500,
  }) async {
    try {
      final col = _items(await _open());
      var sel = where
          .ne('device_id', excludeDeviceId)
          .sortBy('updated_at')
          .limit(limit);
      if (cursor != null) sel = sel.gt('updated_at', cursor.toUtc());
      final docs = await col.find(sel).toList();
      return docs.map(_toItem).toList();
    } catch (e) {
      throw _wrap(e);
    }
  }

  @override
  Stream<ClipItem> watch({required String excludeDeviceId}) =>
      const Stream.empty();

  @override
  Future<void> tombstone(String id, DateTime now) async {
    try {
      final col = _items(await _open());
      final ts = now.toUtc();
      await col.updateOne(
        where.eq('_id', id),
        modify.set('deleted_at', ts).set('updated_at', ts).set('content', ''),
      );
    } catch (e) {
      throw _wrap(e);
    }
  }

  Map<String, dynamic> _deviceDoc(Device d) => <String, dynamic>{
    ...d.toMap()..remove('id'),
    '_id': d.id,
    'last_seen': d.lastSeen.toUtc(),
    'expires_at': d.expiresAt?.toUtc(),
  };

  @override
  Future<void> registerDevice(Device device) async {
    try {
      final db = await _open();
      // $set presence; $setOnInsert membership defaults so an existing
      // row's status / role / expiry survive the heartbeat.
      final presence = device.presenceMap()
        ..remove('id')
        ..['last_seen'] = device.lastSeen.toUtc();
      final membership = <String, Object?>{
        for (final k in {...Device.membershipKeys, ...Device.grantKeys})
          k: device.toMap()[k],
      }..['expires_at'] = device.expiresAt?.toUtc();
      await db.collection(_devicesCollection).updateOne(
        where.eq('_id', device.id),
        {r'$set': presence, r'$setOnInsert': membership},
        upsert: true,
      );
    } catch (e) {
      throw _wrap(e);
    }
  }

  @override
  Future<void> updateDevice(Device device) async {
    try {
      final db = await _open();
      await db
          .collection(_devicesCollection)
          .replaceOne(
            where.eq('_id', device.id),
            _deviceDoc(device),
            upsert: true,
          );
    } catch (e) {
      throw _wrap(e);
    }
  }

  @override
  Future<void> deleteDevice(String id) async {
    try {
      final db = await _open();
      await db.collection(_devicesCollection).deleteOne(where.eq('_id', id));
    } catch (e) {
      throw _wrap(e);
    }
  }

  @override
  Future<List<Device>> listDevices() async {
    try {
      final db = await _open();
      final docs = await db
          .collection(_devicesCollection)
          .find(where.sortBy('last_seen', descending: true).limit(200))
          .toList();
      return docs
          .map(
            (d) => Device.fromMap(<String, Object?>{
              ...Map<String, Object?>.from(d),
              'id': d['_id'],
            }),
          )
          .toList();
    } catch (e) {
      throw _wrap(e);
    }
  }

  @override
  Future<int> purgeBefore(DateTime before) async {
    try {
      final col = _items(await _open());
      final r = await col.deleteMany(where.lt('updated_at', before.toUtc()));
      return r.nRemoved;
    } catch (e) {
      throw _wrap(e);
    }
  }

  @override
  Future<void> dispose() async {
    final db = _db;
    _db = null;
    if (db != null && db.isConnected) await db.close();
  }

  Map<String, dynamic> _doc(ClipItem i) {
    final m = i.toMap();
    return <String, dynamic>{
      '_id': i.id,
      ...m..remove('id'),
      // Native dates so range queries and TTL indexes work.
      'created_at': i.createdAt.toUtc(),
      'updated_at': i.updatedAt.toUtc(),
      'deleted_at': i.deletedAt?.toUtc(),
    };
  }

  static ClipItem _toItem(Map<String, dynamic> d) =>
      ClipItem.fromMap(<String, Object?>{
        ...Map<String, Object?>.from(d),
        'id': d['_id'],
      });

  BackendException _wrap(Object e) {
    if (e is BackendException) return e;
    final text = redactSecrets(e.toString());
    final auth =
        e is MongoDartError &&
        (text.contains('Authentication failed') || text.contains('auth'));
    return BackendException(
      'MongoDB: $text',
      cause: e,
      isAuth: auth,
      isTransient: !auth,
    );
  }
}
