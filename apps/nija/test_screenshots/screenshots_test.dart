// Renders every screen in both themes at desktop and phone sizes and writes
// PNGs to docs/screenshots/. Not part of `flutter test` (lives outside
// test/); regenerate with:
//   flutter test test_screenshots --update-goldens
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nija/app/app_shell.dart';
import 'package:nija/app/router.dart';
import 'package:nija/data/local/database.dart';
import 'package:nija/data/local/local_store.dart';
import 'package:nija/data/settings/app_settings.dart';
import 'package:nija/data/settings/secret_store.dart';
import 'package:nija/features/downloads/release_info.dart';
import 'package:nija/features/downloads/release_service.dart';
import 'package:nija/features/sync/sync_controller.dart';
import 'package:nija/providers.dart';
import 'package:nija/ui/app_theme.dart';
import 'package:nija_core/nija_core.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

class _LiveSync extends SyncController {
  @override
  SyncStatus build() => SyncStatus(
    phase: SyncPhase.idle,
    realtime: true,
    lastSyncAt: DateTime.now().toUtc(),
    signedGroup: true,
    keyVersion: 2,
  );

  @override
  bool get isAdmin => true;

  @override
  bool get isSignedGroup => true;

  @override
  bool get canEditMembership => true;

  @override
  String? get adminFingerprint => '7c3e 91a4';

  @override
  Set<String> get trustedDeviceIds => _devices
      .where((d) => d.status == DeviceStatus.active && !d.isPending)
      .map((d) => d.id)
      .toSet();
}

Future<void> _loadFonts() async {
  final inter = FontLoader('Inter');
  for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    inter.addFont(rootBundle.load('assets/fonts/Inter-$w.ttf'));
  }
  await inter.load();
  // The About page writes the app's name in Devanagari, which Inter does not
  // cover; without this the screenshots render it as tofu boxes.
  await (FontLoader('Noto Sans Devanagari')..addFont(
        rootBundle.load('assets/fonts/NotoSansDevanagari-Regular.ttf'),
      ))
      .load();
  final root = Platform.environment['FLUTTER_ROOT'] ?? '';
  final icons = File(
    p.join(
      root,
      'bin',
      'cache',
      'artifacts',
      'material_fonts',
      'MaterialIcons-Regular.otf',
    ),
  );
  if (icons.existsSync()) {
    final bytes = await icons.readAsBytes();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(Future.value(ByteData.view(bytes.buffer)))).load();
  }
}

ClipItem _clip(
  String id,
  String text, {
  required String device,
  required Duration ago,
  ClipContentType type = ClipContentType.text,
}) {
  final t = DateTime.now().toUtc().subtract(ago);
  return ClipItem.create(
    id: id,
    deviceId: device.toLowerCase(),
    deviceName: device,
    type: type,
    content: text,
    contentHash: sha256Hex(text),
    sizeBytes: text.length,
    now: t,
  );
}

Device _device(
  String id,
  String name,
  String platform, {
  required Duration ago,
  DeviceStatus status = DeviceStatus.active,
  DeviceRole role = DeviceRole.full,
  Duration? expiresIn,
  bool pending = false,
  bool admin = false,
}) => Device(
  id: id,
  name: name,
  platform: platform,
  lastSeen: pending
      ? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true)
      : DateTime.now().toUtc().subtract(ago),
  status: status,
  role: role,
  expiresAt: expiresIn == null ? null : DateTime.now().toUtc().add(expiresIn),
  appVersion: '0.2.0',
  admin: admin,
);

final List<Device> _devices = [
  _device(
    'macbook-pro',
    'MacBook Pro',
    'macos',
    ago: Duration.zero,
    admin: true,
  ),
  _device('pixel-9', 'Pixel 9', 'android', ago: const Duration(minutes: 1)),
  _device(
    'work-pc',
    'Work PC',
    'windows',
    ago: const Duration(hours: 1),
    role: DeviceRole.sendOnly,
    expiresIn: const Duration(hours: 5),
  ),
  _device('iphone', 'iPhone', 'ios', ago: const Duration(hours: 3)),
  _device(
    'living-room-tv',
    'Living room TV',
    'linux',
    ago: const Duration(days: 2),
    role: DeviceRole.receiveOnly,
  ),
  _device(
    'old-laptop',
    'Old laptop',
    'linux',
    ago: const Duration(days: 12),
    status: DeviceStatus.blocked,
  ),
  _device('pending', 'Pending device', '', ago: Duration.zero, pending: true),
];

/// A stand-in release, so the download shot never reaches for the network.
final _release = ReleaseInfo(
  version: '0.2.1',
  htmlUrl: 'https://github.com/appfide/nija/releases/tag/v0.2.1',
  publishedAt: DateTime.now().toUtc().subtract(const Duration(days: 3)),
  checksumsUrl:
      'https://github.com/appfide/nija/releases/download/v0.2.1/SHA256SUMS.txt',
  assets: [
    for (final (name, size) in [
      ('Nija-0.2.1-macos.dmg', 41943040),
      ('Nija-0.2.1-windows.exe', 33554432),
      ('Nija-0.2.1-windows.zip', 31457280),
      ('Nija-0.2.1-linux.deb', 29360128),
      ('Nija-0.2.1-linux.AppImage', 52428800),
      ('Nija-0.2.1-android.apk', 25165824),
      ('Nija-0.2.1-ios-unsigned.ipa', 27262976),
    ])
      ReleaseInfo.fromJson({
        'tag_name': 'v0.2.1',
        'assets': [
          {
            'name': name,
            'size': size,
            'browser_download_url':
                'https://github.com/appfide/nija/releases/download/v0.2.1/$name',
          },
        ],
      }).assets.single,
  ],
);

Future<AppDatabase> _seededDb() async {
  final db = AppDatabase.withExecutor(NativeDatabase.memory());
  final store = DriftLocalStore(db);
  await store.applyRemote([
    _clip(
      '1',
      'https://github.com/appfide/nija/pull/42',
      device: 'MacBook Pro',
      ago: const Duration(minutes: 2),
      type: ClipContentType.url,
    ),
    _clip(
      '2',
      'Deploy notes: bump version, run release workflow, verify SHA256SUMS before announcing.',
      device: 'Pixel 9',
      ago: const Duration(minutes: 14),
    ),
    _clip(
      '3',
      'SELECT id, updated_at FROM clip_items WHERE device_id <> :me ORDER BY updated_at ASC LIMIT 500;',
      device: 'Work PC',
      ago: const Duration(hours: 1),
    ),
    _clip(
      '9',
      '#2563eb',
      device: 'MacBook Pro',
      ago: const Duration(minutes: 30),
    ),
    _clip(
      '4',
      'Meeting moved to 15:30, same room. Bring the packaging checklist.',
      device: 'iPhone',
      ago: const Duration(hours: 3),
    ),
    _clip(
      '5',
      'sk-…redacted… (never paste secrets into a shared clipboard)',
      device: 'MacBook Pro',
      ago: const Duration(hours: 5),
    ),
    _clip(
      '6',
      'https://docs.flutter.dev/platform-integration/desktop',
      device: 'Work PC',
      ago: const Duration(days: 1, hours: 2),
      type: ClipContentType.url,
    ),
    _clip(
      '7',
      'Kerala Startup Mission, Kinfra Hi-Tech Park, Kalamassery, Kochi 683503',
      device: 'iPhone',
      ago: const Duration(days: 1, hours: 6),
    ),
  ]);
  await store.setPinned('4', pinned: true);
  await store.capture(
    _clip(
      '8',
      'Just copied on this Mac, waiting to sync',
      device: 'MacBook Pro',
      ago: Duration.zero,
    ),
  );
  return db;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // A page that never settles must fail fast, not hang the run.
  setUpAll(_loadFonts);

  Future<void> shot(
    WidgetTester tester, {
    required String name,
    required String location,
    required ThemeMode mode,
    required Size size,
    double dpr = 2,
    bool onboarded = true,
  }) async {
    tester.view
      ..physicalSize = size * dpr
      ..devicePixelRatio = dpr;
    addTearDown(tester.view.reset);
    // This suite lives outside test/ so the analyzer does not treat it as a test.
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final db = await _seededDb();
    final settings = AppSettings(
      deviceId: 'macbook-pro',
      deviceName: 'MacBook Pro',
      onboarded: onboarded,
      backendId: 'supabase',
      backendValues: const {
        'url': 'https://abcdefghij.supabase.co',
        'anon_key': 'sb_publishable_xxxxxxxx',
        'table': 'clip_items',
        'devices_table': 'devices',
      },
      encryptionEnabled: true,
      themeMode: mode.name,
    );
    final router = buildAppRouter(
      onboarded: onboarded,
      initialLocation: location,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          databaseProvider.overrideWithValue(db),
          settingsProvider.overrideWith(() => SeededSettings(settings)),
          syncControllerProvider.overrideWith(_LiveSync.new),
          deviceListProvider.overrideWith((ref) => Stream.value(_devices)),
          routerProvider.overrideWithValue(router),
          latestReleaseProvider.overrideWith((ref) async => _release),
        ],
        child: MaterialApp.router(
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: mode,
          debugShowCheckedModeBanner: false,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../../../docs/screenshots/$name.png'),
    );
    // Drift schedules zero-duration timers when the last stream listener goes
    // away and close() waits on them; under the fake test clock they only
    // fire on pump. So: dispose the tree, pump to run those timers, then
    // close on the real event loop.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    // Credential-store reads are bounded by a 10 s timeout; let it elapse
    // under the fake clock so no timer outlives the test.
    await tester.pump(SecretStore.timeout + const Duration(seconds: 1));
    await tester.runAsync(db.close);
  }

  const desktop = Size(1120, 720);
  const phone = Size(390, 844);

  testWidgets(
    'history desktop light',
    timeout: const Timeout(Duration(seconds: 60)),
    (t) => shot(
      t,
      name: 'history-desktop-light',
      location: '/',
      mode: ThemeMode.light,
      size: desktop,
    ),
  );
  testWidgets(
    'history desktop dark',
    timeout: const Timeout(Duration(seconds: 60)),
    (t) => shot(
      t,
      name: 'history-desktop-dark',
      location: '/',
      mode: ThemeMode.dark,
      size: desktop,
    ),
  );
  testWidgets(
    'settings desktop light',
    timeout: const Timeout(Duration(seconds: 60)),
    (t) => shot(
      t,
      name: 'settings-desktop-light',
      location: '/settings',
      mode: ThemeMode.light,
      size: desktop,
    ),
  );
  testWidgets(
    'settings desktop dark',
    timeout: const Timeout(Duration(seconds: 60)),
    (t) => shot(
      t,
      name: 'settings-desktop-dark',
      location: '/settings',
      mode: ThemeMode.dark,
      size: desktop,
    ),
  );
  testWidgets(
    'backend desktop light',
    timeout: const Timeout(Duration(seconds: 60)),
    (t) => shot(
      t,
      name: 'backend-desktop-light',
      location: '/settings/backend',
      mode: ThemeMode.light,
      size: desktop,
    ),
  );
  testWidgets(
    'devices desktop light',
    timeout: const Timeout(Duration(seconds: 60)),
    (t) => shot(
      t,
      name: 'devices-desktop-light',
      location: '/settings/devices',
      mode: ThemeMode.light,
      size: desktop,
    ),
  );
  testWidgets(
    'devices phone dark',
    timeout: const Timeout(Duration(seconds: 60)),
    (t) => shot(
      t,
      name: 'devices-phone-dark',
      location: '/settings/devices',
      mode: ThemeMode.dark,
      size: phone,
      dpr: 3,
    ),
  );
  testWidgets(
    'about desktop light',
    timeout: const Timeout(Duration(seconds: 60)),
    (t) => shot(
      t,
      name: 'about-desktop-light',
      location: '/about',
      mode: ThemeMode.light,
      size: desktop,
    ),
  );
  testWidgets(
    'about desktop dark',
    timeout: const Timeout(Duration(seconds: 60)),
    (t) => shot(
      t,
      name: 'about-desktop-dark',
      location: '/about',
      mode: ThemeMode.dark,
      size: desktop,
    ),
  );
  testWidgets(
    'downloads desktop light',
    timeout: const Timeout(Duration(seconds: 60)),
    (t) => shot(
      t,
      name: 'downloads-desktop-light',
      location: '/about/downloads',
      mode: ThemeMode.light,
      size: desktop,
    ),
  );
  testWidgets(
    'onboarding phone light',
    timeout: const Timeout(Duration(seconds: 60)),
    (t) => shot(
      t,
      name: 'onboarding-phone-light',
      location: '/onboarding',
      mode: ThemeMode.light,
      size: phone,
      dpr: 3,
      onboarded: false,
    ),
  );
  testWidgets(
    'history phone dark',
    timeout: const Timeout(Duration(seconds: 60)),
    (t) => shot(
      t,
      name: 'history-phone-dark',
      location: '/',
      mode: ThemeMode.dark,
      size: phone,
      dpr: 3,
    ),
  );
  testWidgets(
    'settings phone light',
    timeout: const Timeout(Duration(seconds: 60)),
    (t) => shot(
      t,
      name: 'settings-phone-light',
      location: '/settings',
      mode: ThemeMode.light,
      size: phone,
      dpr: 3,
    ),
  );

  test(
    'AppShell breakpoint constant is sane',
    () => expect(AppTokens.desktopBreakpoint, lessThan(desktop.width)),
  );
  test(
    'shell widget exists',
    () => expect(const AppShell(child: SizedBox()), isA<Widget>()),
  );
}
