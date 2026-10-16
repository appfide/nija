import 'dart:async';

import 'package:nija_core/src/backend/backend_config.dart';
import 'package:nija_core/src/backend/backend_descriptor.dart';
import 'package:nija_core/src/backend/config_field.dart';
import 'package:nija_core/src/backend/sync_backend.dart';
import 'package:nija_core/src/model/clip_item.dart';
import 'package:nija_core/src/model/device.dart';
import 'package:nija_core/src/util/redact.dart';
import 'package:pocketbase/pocketbase.dart';

/// PocketBase adapter (self-hosted single binary, SSE realtime).
///
/// PocketBase generates its own 15-char record ids, so our UUID lives in a
/// `clip_id` field with a unique index; upsert = lookup by `clip_id` then
/// create or update. Schema import JSON in `docs/backends/pocketbase.md`.
class PocketBaseBackend implements SyncBackend {
  /// Creates an unconnected adapter.
  PocketBaseBackend();

  /// Descriptor shared with the registry.
  static const BackendDescriptor descriptorStatic = BackendDescriptor(
    id: 'pocketbase',
    displayName: 'PocketBase',
    description:
        'Self-hosted single-binary backend with realtime. Runs anywhere.',
    docsPath: 'docs/backends/pocketbase.md',
    supportsRealtime: true,
    supportsBlobs: true,
    configSchema: <ConfigField>[
      ConfigField(
        key: 'url',
        label: 'Server URL',
        kind: ConfigFieldKind.url,
        placeholder: 'https://pb.example.com',
      ),
      ConfigField(
        key: 'auth_collection',
        label: 'Auth collection',
        kind: ConfigFieldKind.text,
        defaultValue: 'users',
        help: 'Collection to sign in against (users or _superusers).',
      ),
      ConfigField(
        key: 'identity',
        label: 'Email / username',
        kind: ConfigFieldKind.text,
        required: false,
        help:
            'Leave empty only if the collections allow public access (not recommended).',
      ),
      ConfigField(
        key: 'password',
        label: 'Password',
        kind: ConfigFieldKind.secret,
        required: false,
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

  PocketBase? _pb;
  late String _collection;
  late String _devicesCollection;
  late String _authCollection;
  String? _identity;
  String? _password;
  UnsubscribeFunc? _unsubscribe;
  StreamController<ClipItem>? _watchCtl;

  @override
  BackendDescriptor get descriptor => descriptorStatic;

  PocketBase get _c =>
      _pb ?? (throw BackendException('PocketBase not connected'));

  @override
  Future<void> connect(BackendConfig config) async {
    _collection = config.stringOr('collection', 'clip_items');
    _devicesCollection = config.stringOr('devices_collection', 'devices');
    _authCollection = config.stringOr('auth_collection', 'users');
    _identity = config.string('identity');
    _password = config.string('password');
    _pb = PocketBase(config.require('url'));
  }

  Future<void> _ensureAuth() async {
    final id = _identity;
    final pw = _password;
    if (id == null || pw == null) return;
    if (_c.authStore.isValid) return;
    try {
      await _c.collection(_authCollection).authWithPassword(id, pw);
    } on ClientException catch (e) {
      throw BackendException(
        'PocketBase sign-in failed: ${_detail(e)}',
        cause: e,
        isAuth: true,
      );
    }
  }

  @override
  Future<ConnectionCheck> testConnection() async {
    final sw = Stopwatch()..start();
    try {
      final h = await _c.health.check();
      await _ensureAuth();
      return ConnectionCheck.success(
        'PocketBase ok (${h.message})',
        latency: sw.elapsed,
      );
    } catch (e) {
      return ConnectionCheck.failure(_wrap(e).message);
    }
  }

  @override
  Future<SchemaCheck> verifySchema() async {
    final missing = <String>[];
    try {
      await _ensureAuth();
      for (final (c, field) in [
        (_collection, 'sig'),
        (_devicesCollection, 'membership_sig'),
      ]) {
        try {
          final page = await _c
              .collection(c)
              .getList(perPage: 1, skipTotal: true);
          // Fields can only be inspected on an existing record; an empty
          // collection is verified on first write instead.
          if (page.items.isNotEmpty &&
              !page.items.first.data.containsKey(field)) {
            missing.add('field $c.$field');
          }
        } on ClientException catch (e) {
          if (e.statusCode == 404) {
            missing.add('collection $c');
          } else {
            rethrow;
          }
        }
      }
    } catch (e) {
      throw _wrap(e);
    }
    return missing.isEmpty
        ? const SchemaCheck.ready()
        : SchemaCheck(
            ok: false,
            missing: missing,
            hint:
                'Import the collections JSON from ${descriptorStatic.docsPath}',
          );
  }

  /// Signed-in record id, used to stamp `owner` so collection rules can
  /// scope rows per user.
  String? get _ownerId => _c.authStore.record?.id;

  Map<String, dynamic> _body(ClipItem i) => <String, dynamic>{
    ...i.toMap()..remove('id'),
    'clip_id': i.id,
    if (_ownerId != null) 'owner': _ownerId,
  };

  bool _itemSchemaChecked = false;

  @override
  Future<void> upsert(List<ClipItem> items) async {
    try {
      await _ensureAuth();
      final col = _c.collection(_collection);
      for (final item in items) {
        final existing = await _findByClipId(item.id);
        final rec = existing == null
            ? await col.create(body: _body(item))
            : await col.update(existing.id, body: _body(item));
        if (!_itemSchemaChecked) {
          _assertField(rec, 'target_device_id', _collection);
          _assertField(rec, 'sig', _collection);
          _itemSchemaChecked = true;
        }
      }
    } catch (e) {
      throw _wrap(e);
    }
  }

  Future<RecordModel?> _findByClipId(String clipId) async {
    try {
      return await _c
          .collection(_collection)
          .getFirstListItem('clip_id = "$clipId"');
    } on ClientException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }

  @override
  Future<List<ClipItem>> pullSince(
    DateTime? cursor, {
    required String excludeDeviceId,
    int limit = 500,
  }) async {
    try {
      await _ensureAuth();
      final filters = <String>['device_id != "$excludeDeviceId"'];
      if (cursor != null) {
        // PocketBase stores dates as "YYYY-MM-DD HH:MM:SS.sssZ".
        filters.add('updated_at > "${_pbDate(cursor)}"');
      }
      final res = await _c
          .collection(_collection)
          .getList(
            perPage: limit,
            skipTotal: true,
            filter: filters.join(' && '),
            sort: '+updated_at',
          );
      return res.items.map(_toItem).toList();
    } catch (e) {
      throw _wrap(e);
    }
  }

  @override
  Stream<ClipItem> watch({required String excludeDeviceId}) {
    final ctl = _watchCtl ??= StreamController<ClipItem>.broadcast(
      onListen: () async {
        try {
          await _ensureAuth();
          _unsubscribe = await _c.collection(_collection).subscribe('*', (e) {
            final r = e.record;
            if (r == null || r.getStringValue('device_id') == excludeDeviceId) {
              return;
            }
            try {
              _watchCtl?.add(_toItem(r));
            } catch (err) {
              _watchCtl?.addError(_wrap(err));
            }
          });
        } catch (e) {
          _watchCtl?.addError(_wrap(e));
        }
      },
      onCancel: () async {
        await _unsubscribe?.call();
        _unsubscribe = null;
      },
    );
    return ctl.stream;
  }

  @override
  Future<void> tombstone(String id, DateTime now) async {
    try {
      await _ensureAuth();
      final rec = await _findByClipId(id);
      if (rec == null) return;
      final ts = now.toUtc().toIso8601String();
      await _c
          .collection(_collection)
          .update(
            rec.id,
            body: {'deleted_at': ts, 'updated_at': ts, 'content': ''},
          );
    } catch (e) {
      throw _wrap(e);
    }
  }

  Future<RecordModel?> _findDevice(String id) async {
    try {
      return await _c
          .collection(_devicesCollection)
          .getFirstListItem('device_id = "$id"');
    } on ClientException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }

  /// PocketBase silently drops fields the collection does not declare, which
  /// would turn "block" into a no-op. Fail loudly instead.
  static void _assertField(RecordModel r, String field, String collection) {
    if (!r.data.containsKey(field)) {
      throw BackendException(
        'PocketBase collection "$collection" has no "$field" field; import the upgraded schema from ${descriptorStatic.docsPath}',
        isAuth: true,
      );
    }
  }

  @override
  Future<void> registerDevice(Device device) async {
    try {
      await _ensureAuth();
      final col = _c.collection(_devicesCollection);
      final existing = await _findDevice(device.id);
      if (existing == null) {
        await col.create(
          body: <String, dynamic>{
            ...device.toMap()..remove('id'),
            'device_id': device.id,
            if (_ownerId != null) 'owner': _ownerId,
          },
        );
      } else {
        // Presence only: never touch status / role / expires_at / paired_by.
        await col.update(
          existing.id,
          body: <String, dynamic>{...device.presenceMap()..remove('id')},
        );
      }
    } catch (e) {
      throw _wrap(e);
    }
  }

  @override
  Future<void> updateDevice(Device device) async {
    try {
      await _ensureAuth();
      final col = _c.collection(_devicesCollection);
      final body = <String, dynamic>{
        ...device.toMap()..remove('id'),
        'device_id': device.id,
        if (_ownerId != null) 'owner': _ownerId,
      };
      final existing = await _findDevice(device.id);
      final rec = existing == null
          ? await col.create(body: body)
          : await col.update(existing.id, body: body);
      _assertField(rec, 'status', _devicesCollection);
      _assertField(rec, 'membership_sig', _devicesCollection);
      if (device.permissionNames.isNotEmpty) {
        _assertField(rec, 'permissions', _devicesCollection);
      }
      if (device.adminEnvelope != null) {
        _assertField(rec, 'admin_envelope', _devicesCollection);
      }
    } catch (e) {
      throw _wrap(e);
    }
  }

  @override
  Future<void> deleteDevice(String id) async {
    try {
      await _ensureAuth();
      final existing = await _findDevice(id);
      if (existing != null) {
        await _c.collection(_devicesCollection).delete(existing.id);
      }
    } catch (e) {
      throw _wrap(e);
    }
  }

  @override
  Future<List<Device>> listDevices() async {
    try {
      await _ensureAuth();
      final res = await _c
          .collection(_devicesCollection)
          .getList(perPage: 200, sort: '-last_seen');
      return res.items
          .map(
            (r) => Device.fromMap(<String, Object?>{
              'id': r.getStringValue('device_id'),
              for (final k in const [
                'name',
                'platform',
                'last_seen',
                'status',
                'role',
                'expires_at',
                'paired_by',
                'app_version',
                'sign_pub',
                'box_pub',
                'admin_pub',
                'membership_sig',
                'key_envelope',
              ])
                k: _nullIfEmpty(r.get<Object?>(k)),
              for (final k in Device.grantKeys)
                if (r.data.containsKey(k)) k: r.get<Object?>(k),
              'admin': r.get<Object?>('admin') == true,
              'membership_version': r.get<Object?>('membership_version'),
              'key_version': r.get<Object?>('key_version'),
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
      await _ensureAuth();
      final col = _c.collection(_collection);
      var n = 0;
      while (true) {
        final page = await col.getList(
          perPage: 100,
          skipTotal: true,
          filter: 'updated_at < "${_pbDate(before)}"',
        );
        if (page.items.isEmpty) return n;
        for (final r in page.items) {
          await col.delete(r.id);
          n++;
        }
      }
    } catch (e) {
      throw _wrap(e);
    }
  }

  @override
  Future<void> dispose() async {
    await _watchCtl?.close();
    _watchCtl = null;
    await _unsubscribe?.call();
    _unsubscribe = null;
    _pb?.close();
    _pb = null;
  }

  ClipItem _toItem(RecordModel r) {
    final m = <String, Object?>{
      for (final k in const [
        'device_id',
        'device_name',
        'content_type',
        'content',
        'blob_ref',
        'content_hash',
        'nonce',
        'created_at',
        'updated_at',
        'deleted_at',
        'target_device_id',
        'sig',
      ])
        k: _nullIfEmpty(r.get<Object?>(k)),
      'id': r.getStringValue('clip_id'),
      'size_bytes': r.get<Object?>('size_bytes'),
      'key_version': r.get<Object?>('key_version'),
      'encrypted': r.get<Object?>('encrypted') == true,
    };
    return ClipItem.fromMap(m);
  }

  static Object? _nullIfEmpty(Object? v) =>
      (v is String && v.isEmpty) ? null : v;

  static String _pbDate(DateTime d) =>
      d.toUtc().toIso8601String().replaceFirst('T', ' ');

  static String _detail(ClientException e) {
    final msg = e.response['message'];
    return msg is String && msg.isNotEmpty ? msg : 'HTTP ${e.statusCode}';
  }

  BackendException _wrap(Object e) {
    if (e is BackendException) return e;
    if (e is ClientException) {
      return BackendException(
        redactSecrets('PocketBase: ${_detail(e)}'),
        cause: e,
        isAuth: e.statusCode == 401 || e.statusCode == 403,
        isTransient: e.statusCode == 0 || e.statusCode >= 500,
      );
    }
    return BackendException(
      redactSecrets('PocketBase: $e'),
      cause: e,
      isTransient: true,
    );
  }
}
