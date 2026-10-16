import 'dart:async';

import 'package:dio/dio.dart';

import 'package:nija_core/src/backend/backend_config.dart';
import 'package:nija_core/src/backend/backend_descriptor.dart';
import 'package:nija_core/src/backend/config_field.dart';
import 'package:nija_core/src/backend/sync_backend.dart';
import 'package:nija_core/src/model/clip_item.dart';
import 'package:nija_core/src/model/device.dart';
import 'package:nija_core/src/util/redact.dart';
import 'package:supabase/supabase.dart';

/// Supabase (Postgres + PostgREST + Realtime) adapter.
///
/// Schema: two tables `clip_items` and `devices` (names configurable) with
/// row-level security; see `docs/backends/supabase.md`. Talks to the
/// project's public API with the publishable/anon key; optional email +
/// password sign-in scopes rows to that user via RLS.
class SupabaseBackend implements SyncBackend {
  /// Creates an unconnected adapter.
  SupabaseBackend();

  /// Descriptor shared with the registry.
  static const BackendDescriptor descriptorStatic = BackendDescriptor(
    id: 'supabase',
    displayName: 'Supabase',
    description:
        'Hosted or self-hosted Postgres with realtime. Free tier available.',
    docsPath: 'docs/backends/supabase.md',
    supportsRealtime: true,
    supportsBlobs: true,
    configSchema: <ConfigField>[
      ConfigField(
        key: 'url',
        label: 'Project URL',
        kind: ConfigFieldKind.url,
        placeholder: 'https://YOUR_PROJECT.supabase.co',
        help: 'Settings → API → Project URL',
      ),
      ConfigField(
        key: 'anon_key',
        label: 'Publishable (anon) key',
        kind: ConfigFieldKind.secret,
        help:
            'Settings → API → publishable key. Never use the secret/service_role key here.',
      ),
      ConfigField(
        key: 'email',
        label: 'Email (optional)',
        kind: ConfigFieldKind.text,
        required: false,
        help: 'Sign in as a Supabase Auth user so RLS scopes rows to you.',
      ),
      ConfigField(
        key: 'password',
        label: 'Password (optional)',
        kind: ConfigFieldKind.secret,
        required: false,
      ),
      ConfigField(
        key: 'table',
        label: 'Items table',
        kind: ConfigFieldKind.text,
        defaultValue: 'clip_items',
      ),
      ConfigField(
        key: 'devices_table',
        label: 'Devices table',
        kind: ConfigFieldKind.text,
        defaultValue: 'devices',
      ),
      ConfigField(
        key: 'bucket',
        label: 'Storage bucket (optional)',
        kind: ConfigFieldKind.text,
        required: false,
        help:
            'Bucket for large images/files. Leave empty to inline up to 1 MB.',
      ),
    ],
  );

  SupabaseClient? _client;
  late String _table;
  late String _devicesTable;
  String? _email;
  String? _password;
  RealtimeChannel? _channel;
  StreamController<ClipItem>? _watchCtl;

  @override
  BackendDescriptor get descriptor => descriptorStatic;

  SupabaseClient get _c =>
      _client ?? (throw BackendException('Supabase not connected'));

  @override
  Future<void> connect(BackendConfig config) async {
    _table = config.stringOr('table', 'clip_items');
    _devicesTable = config.stringOr('devices_table', 'devices');
    _email = config.string('email');
    _password = config.string('password');
    _client = SupabaseClient(config.require('url'), config.require('anon_key'));
  }

  Future<void> _ensureAuth() async {
    final email = _email;
    final password = _password;
    if (email == null || password == null) return;
    if (_c.auth.currentSession != null && !_c.auth.currentSession!.isExpired) {
      return;
    }
    try {
      await _c.auth.signInWithPassword(email: email, password: password);
    } on AuthException catch (e) {
      throw BackendException(
        'Supabase sign-in failed: ${e.message}',
        cause: e,
        isAuth: true,
      );
    }
  }

  @override
  Future<ConnectionCheck> testConnection() async {
    final sw = Stopwatch()..start();
    try {
      await _ensureAuth();
      await _c.from(_table).select('id').limit(1);
      return ConnectionCheck.success(
        'Connected to Supabase',
        latency: sw.elapsed,
      );
    } on PostgrestException catch (e) {
      // The server answered and accepted the key; only the tables are
      // missing. That is a schema problem, which verifySchema reports with
      // the SQL to run.
      if (_isMissingTable(e)) {
        return ConnectionCheck.success(
          'Connected to Supabase; tables not set up yet',
          latency: sw.elapsed,
        );
      }
      return ConnectionCheck.failure(_wrap(e).message);
    } catch (e) {
      return ConnectionCheck.failure(_wrap(e).message);
    }
  }

  /// Columns added after 0.1.0; checked so an old schema fails loudly
  /// instead of silently dropping device management data.
  static const _itemColumns = ['target_device_id', 'key_version', 'sig'];
  static const _deviceColumns = [
    'status',
    'role',
    'expires_at',
    'paired_by',
    'app_version',
    'sign_pub',
    'box_pub',
    'admin',
    'admin_pub',
    'membership_version',
    'membership_sig',
    'key_version',
    'key_envelope',
  ];

  @override
  Future<SchemaCheck> verifySchema() async {
    final missing = <String>[];
    for (final (t, cols) in [
      (_table, _itemColumns),
      (_devicesTable, _deviceColumns),
    ]) {
      try {
        await _ensureAuth();
        await _c.from(t).select('id').limit(1);
      } on PostgrestException catch (e) {
        if (_isMissingTable(e)) {
          missing.add('table $t');
          continue;
        }
        throw _wrap(e);
      }
      for (final col in cols) {
        try {
          await _c.from(t).select(col).limit(1);
        } on PostgrestException catch (e) {
          // 42703 = undefined_column.
          if (e.code == '42703' || e.code == 'PGRST204') {
            missing.add('column $t.$col');
          } else {
            throw _wrap(e);
          }
        }
      }
    }
    return missing.isEmpty
        ? const SchemaCheck.ready()
        : SchemaCheck(
            ok: false,
            missing: missing,
            hint:
                'Copy the setup SQL, run it in the Supabase SQL editor '
                '(Dashboard → SQL → New query), then test again.',
            setupScript: setupSql(
              items: _table,
              devices: _devicesTable,
              signedIn: _email != null && _password != null,
            ),
          );
  }

  @override
  Future<void> upsert(List<ClipItem> items) async {
    if (items.isEmpty) return;
    try {
      await _ensureAuth();
      await _c
          .from(_table)
          .upsert(items.map((i) => i.toMap()).toList(), onConflict: 'id');
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
      await _ensureAuth();
      var q = _c.from(_table).select().neq('device_id', excludeDeviceId);
      if (cursor != null) {
        q = q.gt('updated_at', cursor.toUtc().toIso8601String());
      }
      final rows = await q.order('updated_at', ascending: true).limit(limit);
      return rows
          .map((r) => ClipItem.fromMap(Map<String, Object?>.from(r)))
          .toList();
    } catch (e) {
      throw _wrap(e);
    }
  }

  @override
  Stream<ClipItem> watch({required String excludeDeviceId}) {
    final ctl = _watchCtl ??= StreamController<ClipItem>.broadcast(
      onListen: () {
        _channel = _c
            .channel('nija:$_table')
            .onPostgresChanges(
              event: PostgresChangeEvent.all,
              schema: 'public',
              table: _table,
              callback: (payload) {
                final row = payload.newRecord;
                if (row.isEmpty || row['device_id'] == excludeDeviceId) return;
                try {
                  _watchCtl?.add(
                    ClipItem.fromMap(Map<String, Object?>.from(row)),
                  );
                } catch (e) {
                  _watchCtl?.addError(_wrap(e));
                }
              },
            )
            .subscribe();
      },
      onCancel: () async {
        final ch = _channel;
        _channel = null;
        if (ch != null) await _c.removeChannel(ch);
      },
    );
    return ctl.stream;
  }

  @override
  Future<void> tombstone(String id, DateTime now) async {
    try {
      await _ensureAuth();
      final ts = now.toUtc().toIso8601String();
      await _c
          .from(_table)
          .update({'deleted_at': ts, 'updated_at': ts, 'content': ''})
          .eq('id', id);
    } catch (e) {
      throw _wrap(e);
    }
  }

  @override
  Future<void> registerDevice(Device device) async {
    try {
      await _ensureAuth();
      // PostgREST merges only the columns present in the body, so membership
      // columns keep whatever the managing device wrote (or their defaults
      // on insert).
      await _c
          .from(_devicesTable)
          .upsert(device.presenceMap(), onConflict: 'id');
    } catch (e) {
      throw _wrap(e);
    }
  }

  @override
  Future<void> updateDevice(Device device) async {
    try {
      await _ensureAuth();
      await _c.from(_devicesTable).upsert(device.toMap(), onConflict: 'id');
    } catch (e) {
      throw _wrap(e);
    }
  }

  @override
  Future<void> deleteDevice(String id) async {
    try {
      await _ensureAuth();
      await _c.from(_devicesTable).delete().eq('id', id);
    } catch (e) {
      throw _wrap(e);
    }
  }

  @override
  Future<List<Device>> listDevices() async {
    try {
      await _ensureAuth();
      final rows = await _c
          .from(_devicesTable)
          .select()
          .order('last_seen', ascending: false);
      return rows
          .map((r) => Device.fromMap(Map<String, Object?>.from(r)))
          .toList();
    } catch (e) {
      throw _wrap(e);
    }
  }

  @override
  Future<int> purgeBefore(DateTime before) async {
    try {
      await _ensureAuth();
      final rows = await _c
          .from(_table)
          .delete()
          .lt('updated_at', before.toUtc().toIso8601String())
          .select('id');
      return rows.length;
    } catch (e) {
      throw _wrap(e);
    }
  }

  @override
  Future<void> dispose() async {
    await _watchCtl?.close();
    _watchCtl = null;
    final ch = _channel;
    _channel = null;
    if (ch != null) await _client?.removeChannel(ch);
    await _client?.dispose();
    _client = null;
  }

  static const _itemColumnTypes = <(String, String)>[
    ('owner_id', 'uuid default auth.uid()'),
    ('device_id', "text not null default ''"),
    ('device_name', "text not null default ''"),
    ('content_type', "text not null default 'text'"),
    ('content', "text not null default ''"),
    ('blob_ref', 'text'),
    ('content_hash', "text not null default ''"),
    ('size_bytes', 'integer not null default 0'),
    ('encrypted', 'boolean not null default false'),
    ('nonce', 'text'),
    ('created_at', 'timestamptz not null default now()'),
    ('updated_at', 'timestamptz not null default now()'),
    ('deleted_at', 'timestamptz'),
    ('target_device_id', 'text'),
    ('key_version', 'integer not null default 0'),
    ('sig', 'text'),
  ];

  static const _deviceColumnTypes = <(String, String)>[
    ('owner_id', 'uuid default auth.uid()'),
    ('name', "text not null default ''"),
    ('platform', "text not null default ''"),
    ('last_seen', 'timestamptz not null default now()'),
    ('app_version', 'text'),
    ('status', "text not null default 'active'"),
    ('role', "text not null default 'full'"),
    ('expires_at', 'timestamptz'),
    ('paired_by', 'text'),
    ('sign_pub', 'text'),
    ('box_pub', 'text'),
    ('admin', 'boolean not null default false'),
    ('admin_pub', 'text'),
    ('membership_version', 'integer not null default 0'),
    ('membership_sig', 'text'),
    ('key_version', 'integer not null default 0'),
    ('key_envelope', 'text'),
    ('permissions', 'text'),
    ('admin_envelope', 'text'),
  ];

  static String _ident(String name) => '"${name.replaceAll('"', '""')}"';

  /// SQL that creates the tables (or adds missing columns to existing
  /// ones), turns on row level security with a policy for [signedIn] or
  /// anon-key access, and adds [items] to the realtime publication. Every
  /// statement is idempotent, so it is safe to run again.
  static String setupSql({
    required String items,
    required String devices,
    required bool signedIn,
  }) {
    final out = StringBuffer(
      '-- Nija setup for Supabase. Safe to run more than once.\n',
    );
    for (final (table, key, keyType, cols) in [
      (items, 'id', 'uuid', _itemColumnTypes),
      (devices, 'id', 'text', _deviceColumnTypes),
    ]) {
      final t = 'public.${_ident(table)}';
      out
        ..writeln()
        ..writeln('create table if not exists $t ($key $keyType primary key);')
        ..writeln('alter table $t');
      for (final (i, (name, type)) in cols.indexed) {
        final end = i == cols.length - 1 ? ';' : ',';
        out.writeln('  add column if not exists $name $type$end');
      }
      final policy = _ident('nija ${signedIn ? 'owner' : 'anon'} access');
      out
        ..writeln('alter table $t enable row level security;')
        ..writeln('drop policy if exists $policy on $t;')
        ..writeln(
          signedIn
              ? 'create policy $policy on $t for all to authenticated '
                    'using (owner_id = auth.uid()) '
                    'with check (owner_id = auth.uid());'
              : 'create policy $policy on $t for all to anon '
                    'using (true) with check (true);',
        );
    }
    final t = 'public.${_ident(items)}';
    final lit = "'${items.replaceAll("'", "''")}'";
    out
      ..writeln()
      ..writeln(
        'create index if not exists '
        '${_ident('${items}_updated_at_idx')} on $t (updated_at);',
      )
      ..writeln(r'do $$')
      ..writeln('begin')
      ..writeln('  if not exists (')
      ..writeln('    select 1 from pg_publication_tables')
      ..writeln(
        "    where pubname = 'supabase_realtime' and schemaname = 'public' "
        'and tablename = $lit',
      )
      ..writeln('  ) then')
      ..writeln('    alter publication supabase_realtime add table $t;')
      ..writeln('  end if;')
      ..writeln(r'end $$;')
      ..writeln("notify pgrst, 'reload schema';");
    return out.toString();
  }

  /// Project ref of a hosted project URL (`https://<ref>.supabase.co`), or
  /// `null` for a custom domain or self-hosted instance.
  static String? projectRefOf(String url) {
    final host = Uri.tryParse(url.trim())?.host ?? '';
    final m = RegExp(r'^([a-z0-9]{20})\.supabase\.(co|in)$').firstMatch(host);
    return m?.group(1);
  }

  /// Runs [sql] (normally [setupSql]) on the project through the Supabase
  /// Management API. [accessToken] is a personal access token with database
  /// write access; it is sent only to api.supabase.com, for this request,
  /// and never stored. Throws [BackendException] with a readable message.
  static Future<void> runSetup({
    required String projectRef,
    required String accessToken,
    required String sql,
    Dio? dio,
  }) async {
    final client =
        dio ??
        Dio(
          BaseOptions(
            baseUrl: 'https://api.supabase.com',
            connectTimeout: const Duration(seconds: 15),
            receiveTimeout: const Duration(seconds: 60),
          ),
        );
    try {
      await client.post<Object?>(
        '/v1/projects/$projectRef/database/query',
        data: {'query': sql},
        options: Options(
          headers: {'Authorization': 'Bearer ${accessToken.trim()}'},
        ),
      );
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      final body = e.response?.data;
      final detail = body is Map ? (body['message'] ?? body['error']) : body;
      throw BackendException(
        redactSecrets(switch (status) {
          401 => 'Supabase rejected the access token.',
          403 =>
            'This access token may not change the database of project '
                '$projectRef. Create one with database write access.',
          404 => 'No Supabase project $projectRef for this access token.',
          429 => 'Supabase is rate limiting requests; try again in a minute.',
          _ =>
            'Supabase could not run the setup'
                '${status == null ? '' : ' (HTTP $status)'}'
                '${detail == null ? '' : ': $detail'}',
        }),
        cause: e,
        isAuth: status == 401 || status == 403,
        isTransient: status == null || status == 429 || status >= 500,
      );
    } finally {
      if (dio == null) client.close();
    }
  }

  /// 42P01 = undefined_table; PGRST205 = table not in PostgREST's schema
  /// cache (dropped, or never created).
  static bool _isMissingTable(PostgrestException e) =>
      e.code == '42P01' || e.code == 'PGRST205' || e.code == '404';

  BackendException _wrap(Object e) {
    if (e is BackendException) return e;
    if (e is PostgrestException && _isMissingTable(e)) {
      return BackendException(
        redactSecrets(
          'Supabase: the Nija tables are missing (${e.message}). Open '
          'Settings → Database and test the connection to set them up.',
        ),
        cause: e,
      );
    }
    if (e is PostgrestException) {
      final code = e.code ?? '';
      final auth =
          code == '401' ||
          code == '403' ||
          code == '42501' ||
          code.startsWith('PGRST30');
      return BackendException(
        redactSecrets(
          'Supabase: ${e.message}${code.isNotEmpty ? ' [$code]' : ''}',
        ),
        cause: e,
        isAuth: auth,
        isTransient: code.startsWith('5') || code == '503',
      );
    }
    if (e is AuthException) {
      return BackendException(
        redactSecrets('Supabase auth: ${e.message}'),
        cause: e,
        isAuth: true,
      );
    }
    return BackendException(
      redactSecrets('Supabase: $e'),
      cause: e,
      isTransient: true,
    );
  }
}
