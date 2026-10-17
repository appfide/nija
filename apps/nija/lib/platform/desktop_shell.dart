import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:nija/core/logging.dart';
import 'package:nija/core/platform_info.dart';
import 'package:nija_core/nija_core.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

/// Tray icon, hide-to-tray window behaviour and the global hotkey.
///
/// No-op on mobile.
class DesktopShell with WindowListener {
  /// Creates the shell; call [init] after `runApp`.
  DesktopShell({
    required this.onSyncNow,
    required this.onOpenSettings,
    required this.onQuit,
    required this.onTogglePause,
    required this.onCopyClip,
  });

  /// Tray "Sync now".
  final Future<void> Function() onSyncNow;

  /// Tray "Pause capture" / "Resume capture".
  final Future<void> Function() onTogglePause;

  /// Tray "Settings…".
  final void Function() onOpenSettings;

  /// Tray "Quit".
  final Future<void> Function() onQuit;

  /// A recent clip picked from the tray menu.
  final Future<void> Function(ClipItem item) onCopyClip;

  /// Longest clip label shown in the tray menu.
  static const recentLabelLength = 40;

  bool _initialised = false;
  bool _paused = false;
  List<ClipItem> _recent = const [];
  TrayIcon? _tray;
  Image? _trayImage;
  ListenerId? _trayListener;
  _TrayMenu? _trayMenu;
  HotKey? _hotKey;

  /// Prepares the window before the first frame. Call in `main()` before
  /// `runApp` on desktop.
  static Future<void> prepareWindow({required bool startHidden}) async {
    if (!PlatformInfo.isDesktop) return;
    await windowManager.ensureInitialized();
    const options = WindowOptions(
      size: Size(1040, 720),
      minimumSize: Size(400, 520),
      center: true,
      title: 'Nija',
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.normal,
    );
    await windowManager.waitUntilReadyToShow(options, () async {
      if (!startHidden) {
        await windowManager.show();
        await windowManager.focus();
      }
    });
  }

  /// Sets up tray, close-to-tray and hotkey.
  Future<void> init({required bool hotkeyEnabled, bool paused = false}) async {
    if (!PlatformInfo.isDesktop || _initialised) return;
    _initialised = true;
    _paused = paused;
    await windowManager.setPreventClose(true);
    windowManager.addListener(this);

    try {
      _createTray();
    } catch (e) {
      log.w('tray unavailable', error: e);
      _disposeTray();
    }

    await setHotkeyEnabled(enabled: hotkeyEnabled);
  }

  void _createTray() {
    final tray = TrayIcon.create();
    if (tray == null) throw StateError('tray icon could not be created');
    _tray = tray;
    final image = ImageAsset.fromAsset(
      Platform.isWindows ? 'assets/icons/tray.ico' : 'assets/icons/tray.png',
    );
    if (image == null) throw StateError('tray icon image missing');
    _trayImage = image;
    tray
      ..isIconTemplate = Platform.isMacOS
      ..icon = image
      ..setTooltip('Nija')
      // Left click opens the window, right click the menu. Linux panels
      // report no clicks and open the menu themselves.
      ..setContextMenuTrigger(ContextMenuTrigger.rightClicked);
    _trayListener = tray.addListener((event) {
      if (event is TrayIconClickedEvent) unawaited(showWindow());
    });
    _rebuildMenu();
    tray.setVisible(true);
  }

  void _rebuildMenu() {
    final tray = _tray;
    if (tray == null) return;
    final menu = _TrayMenu()..add('Open Nija', () => unawaited(showWindow()));
    if (_recent.isNotEmpty) {
      menu.separator();
      for (final item in _recent) {
        menu.add(
          // Windows menus read `&` as a mnemonic marker; `&&` is a literal.
          Platform.isWindows
              ? recentLabel(item).replaceAll('&', '&&')
              : recentLabel(item),
          () => unawaited(onCopyClip(item)),
        );
      }
      menu.separator();
    }
    menu
      ..add('Sync now', () => unawaited(onSyncNow()))
      ..add(
        _paused ? 'Resume capture' : 'Pause capture',
        () => unawaited(onTogglePause()),
      )
      ..add('Settings…', () {
        unawaited(showWindow());
        onOpenSettings();
      })
      ..separator()
      ..add('Quit', () => unawaited(onQuit()));
    tray.setContextMenu(menu.menu);
    final previous = _trayMenu;
    _trayMenu = menu;
    // A rebuild can run inside a menu item's own click callback, so the old
    // items have to outlive the current event.
    if (previous != null) Timer.run(previous.dispose);
  }

  void _disposeTray() {
    final tray = _tray;
    final listener = _trayListener;
    if (tray != null && listener != null) tray.removeListener(listener);
    tray?.setContextMenu(null);
    _trayMenu?.dispose();
    _trayImage?.dispose();
    tray?.dispose();
    _tray = null;
    _trayImage = null;
    _trayListener = null;
    _trayMenu = null;
  }

  /// Menu text for [item]: its first line, whitespace collapsed, cut to
  /// [recentLabelLength] characters.
  static String recentLabel(ClipItem item) {
    if (item.type.isBinary) {
      return '${item.type == ClipContentType.image ? 'Image' : 'File'}'
          ' · ${(item.sizeBytes / 1024).toStringAsFixed(0)} KB';
    }
    final line = item.content
        .trim()
        .split('\n')
        .first
        .replaceAll(RegExp(r'\s+'), ' ');
    final chars = line.runes.toList();
    return chars.length <= recentLabelLength
        ? line
        : '${String.fromCharCodes(chars.take(recentLabelLength - 1))}…';
  }

  /// Replaces the recent clips listed in the tray menu.
  Future<void> setRecent(List<ClipItem> items) async {
    if (!PlatformInfo.isDesktop) return;
    final same =
        items.length == _recent.length &&
        [
          for (var i = 0; i < items.length; i++)
            items[i].id == _recent[i].id &&
                items[i].contentHash == _recent[i].contentHash,
        ].every((e) => e);
    if (same) return;
    _recent = List.unmodifiable(items);
    try {
      _rebuildMenu();
    } catch (e) {
      log.w('tray update failed', error: e);
    }
  }

  /// Reflects the pause state in the tray menu and tooltip.
  Future<void> setPaused({required bool paused}) async {
    if (!PlatformInfo.isDesktop || _paused == paused) return;
    _paused = paused;
    try {
      _rebuildMenu();
      _tray?.setTooltip(paused ? 'Nija: capture paused' : 'Nija');
    } catch (e) {
      log.w('tray update failed', error: e);
    }
  }

  /// Registers or unregisters the global hotkey (Ctrl/Cmd+Shift+V).
  Future<void> setHotkeyEnabled({required bool enabled}) async {
    if (!PlatformInfo.isDesktop) return;
    try {
      await hotKeyManager.unregisterAll();
      _hotKey = null;
      if (!enabled) return;
      final hk = HotKey(
        key: PhysicalKeyboardKey.keyV,
        modifiers: [
          if (Platform.isMacOS) HotKeyModifier.meta else HotKeyModifier.control,
          HotKeyModifier.shift,
        ],
      );
      await hotKeyManager.register(hk, keyDownHandler: (_) => showWindow());
      _hotKey = hk;
    } catch (e) {
      log.w('hotkey registration failed', error: e);
    }
  }

  /// Human-readable hotkey label.
  String get hotkeyLabel => Platform.isMacOS ? '⌘⇧V' : 'Ctrl+Shift+V';

  /// Brings the window to front.
  Future<void> showWindow() async {
    if (!PlatformInfo.isDesktop) return;
    await windowManager.show();
    await windowManager.focus();
  }

  /// Hides the window to the tray.
  Future<void> hideWindow() async {
    if (!PlatformInfo.isDesktop) return;
    await windowManager.hide();
  }

  /// Tears down tray/hotkey (before quitting).
  Future<void> dispose() async {
    if (!_initialised) return;
    windowManager.removeListener(this);
    await hotKeyManager.unregisterAll();
    _disposeTray();
    _initialised = false;
  }

  @override
  void onWindowClose() => unawaited(hideWindow());

  /// Whether a hotkey is registered.
  bool get hotkeyActive => _hotKey != null;
}

/// One tray context menu and the native items it owns.
class _TrayMenu {
  _TrayMenu() : menu = Menu.create()!;

  final Menu menu;
  final List<(MenuItem, ListenerId)> _items = [];

  void add(String label, void Function() onClick) {
    final item = MenuItem.createWithLabelAndType(label, MenuItemType.normal)!;
    final id = item.addListener((event) {
      if (event is MenuItemClickedEvent) onClick();
    });
    _items.add((item, id));
    menu.addItem(item);
  }

  void separator() => menu.addSeparator();

  void dispose() {
    for (final (item, id) in _items) {
      item
        ..removeListener(id)
        ..dispose();
    }
    _items.clear();
    menu.dispose();
  }
}
