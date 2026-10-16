import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nija/core/build_info.dart';
import 'package:nija/features/sync/sync_controller.dart';
import 'package:nija/platform/clipboard_service.dart';
import 'package:nija/ui/app_theme.dart';
import 'package:nija/ui/widgets/section_card.dart';

/// Platform-specific clipboard access guidance plus a live test.
class PermissionsSection extends ConsumerStatefulWidget {
  /// Creates the section.
  const PermissionsSection({super.key});

  @override
  ConsumerState<PermissionsSection> createState() => _PermissionsSectionState();
}

class _PermissionsSectionState extends ConsumerState<PermissionsSection> {
  ClipboardProbe? _result;
  bool _busy = false;

  Future<void> _test() async {
    setState(() => _busy = true);
    final r = await ref.read(syncControllerProvider.notifier).probeClipboard();
    if (mounted) {
      setState(() {
        _busy = false;
        _result = r;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final scheme = Theme.of(context).colorScheme;
    final guidance = _guidance();
    final r = _result;
    final (icon, color, title) = switch (r?.access) {
      null => (Icons.content_paste_search_rounded, c.muted, 'Not tested yet'),
      ClipboardAccess.ok => (
        Icons.check_circle_rounded,
        c.success,
        'Clipboard access works',
      ),
      ClipboardAccess.empty => (
        Icons.info_outline_rounded,
        c.muted,
        'Clipboard empty',
      ),
      ClipboardAccess.blocked => (
        Icons.error_rounded,
        scheme.error,
        'Clipboard access blocked',
      ),
    };
    return SectionCard(
      title: 'Permissions',
      subtitle: 'What this platform allows and how to enable it',
      children: [
        SettingRow(
          icon: icon,
          tint: color,
          title: title,
          subtitle: r?.message ?? 'Copy some text, then run the test.',
          trailing: FilledButton.tonal(
            key: const ValueKey('test-clipboard'),
            onPressed: _busy ? null : _test,
            child: Text(_busy ? 'Testing…' : 'Test'),
          ),
        ),
        for (final g in guidance)
          SettingRow(
            icon: g.$1,
            tint: g.$4 ? c.warning : scheme.primary,
            title: g.$2,
            subtitle: g.$3,
          ),
      ],
    );
  }

  /// (icon, title, detail, isWarning)
  static List<(IconData, String, String, bool)> _guidance() {
    if (Platform.isMacOS) {
      return const [
        (
          Icons.content_paste_rounded,
          'Clipboard',
          'No permission needed. On macOS 26 and later the first read may show a one-time "wants to access the clipboard" prompt: choose Allow Always.',
          false,
        ),
        (
          Icons.keyboard_rounded,
          'Global hotkey',
          'Registered with the system directly; Accessibility access is not required.',
          false,
        ),
        if (!BuildInfo.storeBuild)
          (
            Icons.power_settings_new_rounded,
            'Start at login',
            'Adds a Launch Agent in ~/Library/LaunchAgents; remove it from System Settings → General → Login Items.',
            false,
          ),
        (
          Icons.wifi_rounded,
          'Local network',
          'Connecting to a database on your LAN triggers the Local Network prompt; allow it.',
          false,
        ),
      ];
    }
    if (Platform.isWindows) {
      return const [
        (
          Icons.content_paste_rounded,
          'Clipboard',
          'No permission needed. Windows notifies the app on every clipboard change.',
          false,
        ),
        (
          Icons.keyboard_rounded,
          'Global hotkey',
          'Registered with Windows directly. If another app already owns the shortcut, registration fails silently; see Diagnostics.',
          false,
        ),
        (
          Icons.power_settings_new_rounded,
          'Start at login',
          'Adds a Run entry for the current user; manage it in Task Manager → Startup apps.',
          false,
        ),
      ];
    }
    if (Platform.isLinux) {
      return const [
        (
          Icons.content_paste_rounded,
          'Clipboard',
          'Works on X11 and XWayland. Native Wayland only shares the clipboard with the focused window, so the app defaults to XWayland (override with GDK_BACKEND=wayland).',
          false,
        ),
        (
          Icons.keyboard_rounded,
          'Global hotkey',
          'X11 only (keybinder). Not available on native Wayland sessions.',
          true,
        ),
        (
          Icons.key_rounded,
          'Credential store',
          'Uses the Secret Service (GNOME Keyring / KWallet). Without one, credentials fall back to app preferences and a warning is shown above.',
          false,
        ),
      ];
    }
    if (Platform.isAndroid) {
      return const [
        (
          Icons.content_paste_rounded,
          'Clipboard',
          'Android 10+ only lets an app read the clipboard while it is in the foreground. Copy, then open the app or tap Capture. No system permission exists to grant.',
          true,
        ),
        (
          Icons.notifications_none_rounded,
          'Paste notice',
          'Android 12+ shows "Nija pasted from …" when the app reads the clipboard. This is expected.',
          false,
        ),
        (
          Icons.wifi_rounded,
          'Network',
          'Internet permission is declared. Nothing else is requested.',
          false,
        ),
      ];
    }
    if (Platform.isIOS) {
      return const [
        (
          Icons.content_paste_rounded,
          'Clipboard',
          'iOS asks "Allow Paste?" when the app reads content copied in another app. To stop the prompt: Settings → Nija → Paste from Other Apps → Allow.',
          true,
        ),
        (
          Icons.hourglass_bottom_rounded,
          'Background',
          'iOS never lets apps read the clipboard in the background. Open the app (or tap Capture) after copying.',
          false,
        ),
        (
          Icons.wifi_rounded,
          'Local network',
          'Connecting to a database on your LAN triggers the Local Network prompt; allow it.',
          false,
        ),
      ];
    }
    return const [];
  }
}
