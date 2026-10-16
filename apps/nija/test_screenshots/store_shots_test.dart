// Raw app screens for the App Store listing: iPhone 6.9", iPad 13" and Mac,
// dark theme, with demo data that shows only Apple devices (App Review
// rejects other platforms in screenshots). The store composer frames them.
// Not part of `flutter test`; regenerate with:
//   flutter test test_screenshots/store_shots_test.dart --update-goldens \
//     --dart-define=STORE_BUILD=true
// Output: build/store_shots/raw/<device>/<name>.png (gitignored).
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nija/app/router.dart';
import 'package:nija/data/local/database.dart';
import 'package:nija/data/local/local_store.dart';
import 'package:nija/data/settings/app_settings.dart';
import 'package:nija/data/settings/secret_store.dart';
import 'package:nija/features/sync/sync_controller.dart';
import 'package:nija/providers.dart';
import 'package:nija/ui/app_theme.dart';
import 'package:nija_core/nija_core.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

class _StoreSync extends SyncController {
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
  bool get canManageDevices => true;

  @override
  String? get adminFingerprint => '7c3e 91a4';

  @override
  List<Device> get knownDevices => _devices;

  @override
  Future<List<Device>> refreshDevices() async => _devices;

  @override
  Set<String> get trustedDeviceIds => _devices
      .where((d) => d.status == DeviceStatus.active && !d.isPending)
      .map((d) => d.id)
      .toSet();

  @override
  Future<PairingSession> createPairing({
    required DeviceRole role,
    DateTime? expiresAt,
    bool includePassphrase = false,
    bool grantAdmin = false,
    Duration validity = PairingCodec.defaultValidity,
  }) async => PairingSession(
    // Shaped like a real code; it opens nothing.
    code: 'NIJA1.${'q8Zr4Lw2Xp9Kc7Vt1Nf5Hb3Md6Gs0Ja' * 6}',
    pin: '48213067',
    deviceId: 'new-ipad',
    validUntil: DateTime.now().toUtc().add(validity),
    passphraseIncluded: false,
    encryption: true,
    grantsAdmin: grantAdmin,
  );
}

Future<void> _loadFonts() async {
  final inter = FontLoader('Inter');
  for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    inter.addFont(rootBundle.load('assets/fonts/Inter-$w.ttf'));
  }
  await inter.load();
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
    deviceId: device.toLowerCase().replaceAll(' ', '-'),
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
  DeviceRole role = DeviceRole.full,
  Duration? expiresIn,
  bool pending = false,
  bool admin = false,
  DeviceStatus status = DeviceStatus.active,
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
  appVersion: '0.5.0',
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
  _device('iphone', 'iPhone', 'ios', ago: const Duration(seconds: 20)),
  _device('ipad-pro', 'iPad Pro', 'ios', ago: const Duration(minutes: 4)),
  _device(
    'studio-mac-mini',
    'Studio Mac mini',
    'macos',
    ago: const Duration(minutes: 25),
    role: DeviceRole.sendOnly,
  ),
  _device(
    'family-imac',
    'Family iMac',
    'macos',
    ago: const Duration(hours: 2),
    role: DeviceRole.receiveOnly,
  ),
  _device(
    'guest-macbook-air',
    'Guest MacBook Air',
    'macos',
    ago: const Duration(hours: 1),
    expiresIn: const Duration(hours: 6),
  ),
  _device(
    'old-iphone',
    'Old iPhone',
    'ios',
    ago: const Duration(days: 9),
    status: DeviceStatus.paused,
  ),
];

Future<AppDatabase> _seededDb() async {
  final db = AppDatabase.withExecutor(NativeDatabase.memory());
  final store = DriftLocalStore(db);
  await store.applyRemote([
    _clip(
      '1',
      'https://github.com/appfide/nija',
      device: 'iPhone',
      ago: const Duration(minutes: 1),
      type: ClipContentType.url,
    ),
    _clip(
      '2',
      'Flight 504 to Dubai · Gate 14 · boarding 09:40',
      device: 'iPhone',
      ago: const Duration(minutes: 6),
    ),
    _clip(
      '3',
      'git commit -m "Ship the store build" && git push',
      device: 'MacBook Pro',
      ago: const Duration(minutes: 12),
    ),
    _clip(
      '4',
      '#2563eb',
      device: 'iPad Pro',
      ago: const Duration(minutes: 20),
    ),
    _clip(
      '5',
      'Dinner at 8. Table for four, booked under Das.',
      device: 'iPhone',
      ago: const Duration(hours: 1),
    ),
    _clip(
      '6',
      'Infopark Phase 2, Kakkanad, Kochi 682042',
      device: 'Studio Mac mini',
      ago: const Duration(hours: 2),
    ),
    _clip(
      '7',
      'Order 48213 ships Thursday. Tracking 1Z 999 AA1 01 2345 6784',
      device: 'MacBook Pro',
      ago: const Duration(hours: 5),
    ),
    _clip(
      '8',
      'https://developer.apple.com/design/human-interface-guidelines',
      device: 'iPad Pro',
      ago: const Duration(days: 1, hours: 2),
      type: ClipContentType.url,
    ),
    _clip(
      '9',
      'Wi-Fi for guests: Nija-Guest · password on the fridge',
      device: 'Family iMac',
      ago: const Duration(days: 1, hours: 6),
    ),
  ]);
  await store.setPinned('5', pinned: true);
  return db;
}

/// iOS-style status bar, drawn into the top safe area of phone and tablet
/// shots so the frame shows 9:41 like Apple's own marketing.
class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.height, required this.tablet});
  final double height;
  final bool tablet;

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(
      fontFamily: 'Inter',
      fontWeight: FontWeight.w600,
      fontSize: 16,
      color: Colors.white,
      decoration: TextDecoration.none,
    );
    return SizedBox(
      height: height,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          tablet ? 24 : 34,
          tablet ? 6 : 18,
          tablet ? 24 : 30,
          0,
        ),
        child: Row(
          crossAxisAlignment: tablet
              ? CrossAxisAlignment.center
              : CrossAxisAlignment.start,
          children: [
            Text(tablet ? '9:41  Mon 13 Oct' : '9:41', style: style),
            const Spacer(),
            const Icon(
              Icons.signal_cellular_alt_rounded,
              size: 18,
              color: Colors.white,
            ),
            const SizedBox(width: 5),
            const Icon(Icons.wifi_rounded, size: 18, color: Colors.white),
            const SizedBox(width: 5),
            const Icon(
              Icons.battery_full_rounded,
              size: 20,
              color: Colors.white,
            ),
          ],
        ),
      ),
    );
  }
}

enum _Device {
  iphone(Size(430, 932), 3, 59, 34),
  ipad(Size(1032, 1376), 2, 24, 20),
  mac(Size(1440, 900), 2, 0, 0);

  const _Device(this.size, this.dpr, this.top, this.bottom);
  final Size size;
  final double dpr;
  final double top;
  final double bottom;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(_loadFonts);

  Future<void> shot(
    WidgetTester tester, {
    required _Device device,
    required String name,
    required String location,
    Future<void> Function(WidgetTester t)? act,
  }) async {
    tester.view
      ..physicalSize = device.size * device.dpr
      ..devicePixelRatio = device.dpr
      ..padding = FakeViewPadding(
        top: device.top * device.dpr,
        bottom: device.bottom * device.dpr,
      );
    addTearDown(tester.view.reset);
    // This suite lives outside test/, so the analyzer does not treat it as a
    // test file.
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final db = await _seededDb();
    const settings = AppSettings(
      deviceId: 'macbook-pro',
      deviceName: 'MacBook Pro',
      onboarded: true,
      backendId: 'supabase',
      backendValues: {
        'url': 'https://abcdefghijklmnopqrst.supabase.co',
        'anon_key': 'sb_publishable_xxxxxxxxxxxxxxxx',
        'table': 'clip_items',
        'devices_table': 'devices',
      },
      encryptionEnabled: true,
      themeMode: 'dark',
    );
    final router = buildAppRouter(onboarded: true, initialLocation: location);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          databaseProvider.overrideWithValue(db),
          settingsProvider.overrideWith(() => SeededSettings(settings)),
          syncControllerProvider.overrideWith(_StoreSync.new),
          deviceListProvider.overrideWith((ref) => Stream.value(_devices)),
          routerProvider.overrideWithValue(router),
        ],
        child: MaterialApp.router(
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: ThemeMode.dark,
          debugShowCheckedModeBanner: false,
          routerConfig: router,
          builder: (context, child) => device.top == 0
              ? child!
              : Stack(
                  children: [
                    child!,
                    _StatusBar(
                      height: device.top,
                      tablet: device == _Device.ipad,
                    ),
                  ],
                ),
        ),
      ),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    if (act != null) await act(tester);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile(
        '../../../build/store_shots/raw/${device.name}/$name.png',
      ),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(SecretStore.defaultTimeout + const Duration(seconds: 1));
    await tester.runAsync(db.close);
  }

  Future<void> search(WidgetTester t) async {
    await t.enterText(find.byType(TextField).first, 'Kochi');
    await t.pump(const Duration(milliseconds: 400));
  }

  Future<void> pair(WidgetTester t) async {
    await t.tap(find.byKey(const ValueKey('generate-code')));
    // The countdown ticks every second, so never pumpAndSettle here.
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  final screens = <(String, String, Future<void> Function(WidgetTester)?)>[
    ('01-history', '/', null),
    ('02-search', '/', search),
    ('03-devices', '/settings/devices', null),
    ('04-databases', '/settings/backend', null),
    ('05-pair', '/settings/devices/pair', pair),
    ('06-settings', '/settings', null),
  ];

  for (final device in _Device.values) {
    for (final (name, location, act) in screens) {
      testWidgets(
        '${device.name} $name',
        timeout: const Timeout(Duration(seconds: 90)),
        (t) => shot(
          t,
          device: device,
          name: name,
          location: location,
          act: act,
        ),
      );
    }
  }
}
