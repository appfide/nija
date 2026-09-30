import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nija/data/local/database.dart';
import 'package:nija/data/local/local_store.dart';
import 'package:nija/data/settings/app_settings.dart';
import 'package:nija/features/history/history_page.dart';
import 'package:nija/features/sync/sync_controller.dart';
import 'package:nija/providers.dart';
import 'package:nija/ui/app_theme.dart';
import 'package:nija_core/nija_core.dart';

/// Records what would have gone to the clipboard.
class _RecordingSync extends SyncController {
  final copied = <String>[];
  final copiedText = <String>[];

  @override
  SyncStatus build() => const SyncStatus.stopped();

  @override
  Future<void> copyToClipboard(ClipItem item) async => copied.add(item.id);

  @override
  Future<void> copyTextUnrecorded(String text) async => copiedText.add(text);

  @override
  Future<void> delete(String id) =>
      ref.read(localStoreProvider).delete(id, DateTime.now().toUtc());
}

ClipItem _clip(
  String id,
  String text,
  int minutesAgo, {
  ClipContentType type = ClipContentType.text,
}) => ClipItem.create(
  id: id,
  deviceId: 'other',
  deviceName: 'Other',
  type: type,
  content: text,
  contentHash: sha256Hex(text),
  sizeBytes: text.length,
  now: DateTime.now().toUtc().subtract(Duration(minutes: minutesAgo)),
);

void main() {
  late AppDatabase db;
  late _RecordingSync sync;

  Future<void> pumpPage(WidgetTester tester) async {
    tester.view
      ..physicalSize = const Size(1120, 720)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    db = AppDatabase.withExecutor(NativeDatabase.memory());
    await tester.runAsync(
      () => DriftLocalStore(db).applyRemote([
        _clip('a', '  first\n  clip  ', 1),
        _clip('b', 'https://example.com', 2, type: ClipContentType.url),
        _clip('c', '#2563eb', 3),
      ]),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          settingsProvider.overrideWith(
            () => SeededSettings(
              const AppSettings(deviceId: 'me', deviceName: 'Me'),
            ),
          ),
          syncControllerProvider.overrideWith(() => sync = _RecordingSync()),
          deviceListProvider.overrideWith((ref) => Stream.value(const [])),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const HistoryPage(),
        ),
      ),
    );
    await _settle(tester);
  }

  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 50));
    await tester.runAsync(db.close);
  }

  testWidgets('arrows select, Enter copies the selection', (tester) async {
    await pumpPage(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(sync.copied, ['a', 'b', 'a']);
    await dispose(tester);
  });

  testWidgets(
    'keys keep working after clicking a filter',
    (tester) async {
      await pumpPage(tester);
      await tester.tap(find.byKey(const ValueKey('filter-text')));
      await _settle(tester);
      await tester.tap(find.byKey(const ValueKey('filter-all')));
      await _settle(tester);
      // No arrow first: an arrow's focus traversal would mask a lost focus.
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(sync.copied, ['a']);
      await dispose(tester);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets('primary+digit copies by position', (tester) async {
    await pumpPage(tester);
    final primary = Platform.isMacOS
        ? LogicalKeyboardKey.metaLeft
        : LogicalKeyboardKey.controlLeft;
    await tester.sendKeyDownEvent(primary);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit3);
    await tester.sendKeyUpEvent(primary);
    await tester.pump();
    expect(sync.copied, ['c']);
    await dispose(tester);
  });

  testWidgets('filter chips narrow the list', (tester) async {
    await pumpPage(tester);
    await tester.tap(find.byKey(const ValueKey('filter-links')));
    await _settle(tester);
    expect(find.byKey(const ValueKey('clip-b')), findsOneWidget);
    expect(find.byKey(const ValueKey('clip-a')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('filter-pinned')));
    await _settle(tester);
    expect(find.text('No matches'), findsOneWidget);
    await dispose(tester);
  });

  testWidgets('colour clips get a swatch', (tester) async {
    await pumpPage(tester);
    expect(find.byKey(const ValueKey('color-swatch')), findsOneWidget);
    await dispose(tester);
  });

  testWidgets('Shift+Enter previews, Copy as rewrites', (tester) async {
    await pumpPage(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await _settle(tester);
    expect(find.byKey(const ValueKey('clip-preview')), findsOneWidget);
    expect(find.text('16 characters · 2 words · 2 lines'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('copy-as')));
    await _settle(tester);
    await tester.tap(find.text('As one line').last);
    await _settle(tester);
    expect(sync.copiedText, ['first clip']);
    expect(find.byKey(const ValueKey('clip-preview')), findsNothing);
    await dispose(tester);
  });
}

/// Drift streams deliver on the real event loop; let them, then pump.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump(const Duration(milliseconds: 250));
  }
}
