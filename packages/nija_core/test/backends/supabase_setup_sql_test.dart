import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:nija_core/nija_core.dart';
import 'package:test/test.dart';

/// Answers every request with [status] and records what was sent.
class _Adapter implements HttpClientAdapter {
  _Adapter(this.status, [this.body = const {}]);
  final int status;
  final Map<String, Object?> body;
  RequestOptions? last;
  Object? sent;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    last = options;
    sent = options.data;
    return ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// Built at runtime so secret scanners do not flag a literal token.
final String _token = ['sbp', '0123456789abcdef' * 2 + '01234567'].join('_');

Dio _dio(_Adapter a) =>
    Dio(BaseOptions(baseUrl: 'https://api.supabase.com'))
      ..httpClientAdapter = a;

void main() {
  test('setup SQL covers both tables, every column and realtime', () {
    final sql = SupabaseBackend.setupSql(
      items: 'clip_items',
      devices: 'devices',
      signedIn: true,
    );
    for (final col in [...Device.membershipKeys, ...Device.grantKeys]) {
      if (col == 'id') continue;
      expect(sql, contains('add column if not exists $col '));
    }
    expect(sql, contains('create table if not exists public."clip_items"'));
    expect(sql, contains('create table if not exists public."devices"'));
    expect(sql, contains('to authenticated'));
    expect(sql, isNot(contains('to anon')));
    expect(sql, contains('alter publication supabase_realtime add table'));
  });

  test('anon-key setups get an anon policy', () {
    final sql = SupabaseBackend.setupSql(
      items: 'clip_items',
      devices: 'devices',
      signedIn: false,
    );
    expect(sql, contains('to anon using (true)'));
    expect(sql, isNot(contains('to authenticated')));
  });

  test('custom table names are quoted, never spliced raw', () {
    final sql = SupabaseBackend.setupSql(
      items: 'x"; drop table users; --',
      devices: "d'evs",
      signedIn: false,
    );
    expect(sql, contains('public."x""; drop table users; --"'));
    expect(sql, contains("tablename = 'x\"; drop table users; --'"));
    expect(sql, contains('public."d\'evs"'));
  });

  test('the project ref comes from a hosted project URL only', () {
    expect(
      SupabaseBackend.projectRefOf('https://utvktjzckbfymptciylj.supabase.co'),
      'utvktjzckbfymptciylj',
    );
    expect(
      SupabaseBackend.projectRefOf(
        ' https://utvktjzckbfymptciylj.supabase.co/ ',
      ),
      'utvktjzckbfymptciylj',
    );
    expect(SupabaseBackend.projectRefOf('https://db.example.com'), isNull);
    expect(SupabaseBackend.projectRefOf('http://localhost:54321'), isNull);
  });

  test('setup runs the SQL through the Management API', () async {
    final a = _Adapter(201);
    await SupabaseBackend.runSetup(
      projectRef: 'abcdefghijklmnopqrst',
      accessToken: ' $_token ',
      sql: 'select 1;',
      dio: _dio(a),
    );
    expect(a.last!.method, 'POST');
    expect(a.last!.path, '/v1/projects/abcdefghijklmnopqrst/database/query');
    expect(
      a.last!.headers['Authorization'],
      'Bearer $_token',
    );
    expect(a.sent, {'query': 'select 1;'});
  });

  test('a rejected token is reported plainly and never echoed', () async {
    final token = _token;
    for (final (status, text) in [
      (401, 'rejected the access token'),
      (403, 'database write access'),
      (404, 'No Supabase project'),
    ]) {
      await expectLater(
        SupabaseBackend.runSetup(
          projectRef: 'abcdefghijklmnopqrst',
          accessToken: token,
          sql: 'select 1;',
          dio: _dio(_Adapter(status, {'message': 'bad $token'})),
        ),
        throwsA(
          isA<BackendException>()
              .having((e) => e.message, 'message', contains(text))
              .having((e) => e.message, 'message', isNot(contains(token))),
        ),
      );
    }
  });

  test('a failing statement surfaces the database message', () async {
    await expectLater(
      SupabaseBackend.runSetup(
        projectRef: 'abcdefghijklmnopqrst',
        accessToken: 'sbp_x',
        sql: 'nonsense',
        dio: _dio(_Adapter(400, {'message': 'syntax error at "nonsense"'})),
      ),
      throwsA(
        isA<BackendException>().having(
          (e) => e.message,
          'message',
          contains('syntax error'),
        ),
      ),
    );
  });

  test('personal access tokens count as secrets', () {
    expect(
      looksLikeSecret(_token),
      isTrue,
    );
  });
}
