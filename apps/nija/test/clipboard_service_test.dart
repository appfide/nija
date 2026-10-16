import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nija/platform/clipboard_service.dart';
import 'package:nija_core/nija_core.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const hints = MethodChannel('com.appfide.nija/clipboard');
  var remote = false;
  var text = 'copied on the iPhone';

  setUp(() {
    remote = false;
    messenger
      ..setMockMethodCallHandler(hints, (call) async {
        if (call.method == 'isRemote') return remote;
        if (call.method == 'isSensitive') return false;
        return null;
      })
      ..setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.getData') return {'text': text};
        if (call.method == 'Clipboard.hasStrings') return {'value': true};
        return null;
      });
  });

  tearDown(() {
    messenger
      ..setMockMethodCallHandler(hints, null)
      ..setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Future<List<ClipItem>> capture({required bool skip}) async {
    final c = ClipboardService(
      deviceId: 'mac',
      deviceName: 'MacBook Pro',
      captureImages: false,
      maxInlineBytes: 1024 * 1024,
      skipUniversalClipboard: skip,
    );
    final got = <ClipItem>[];
    final sub = c.captured.listen(got.add);
    await c.start();
    await c.checkNow();
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();
    await c.dispose();
    return got;
  }

  test(
    'Universal Clipboard content is left to the device it came from',
    () async {
      remote = true;
      expect(await capture(skip: true), isEmpty);
    },
    skip: Platform.isMacOS ? false : 'Universal Clipboard is Apple-only',
  );

  test('it is recorded when the setting is off', () async {
    remote = true;
    text = 'recorded anyway';
    final got = await capture(skip: false);
    expect(got.map((i) => i.content), ['recorded anyway']);
    expect(got.single.deviceName, 'MacBook Pro');
  });

  test('local copies are recorded with the setting on', () async {
    text = 'copied on this Mac';
    final got = await capture(skip: true);
    expect(got.map((i) => i.content), ['copied on this Mac']);
  });
}
