import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:nija/core/platform_info.dart';
import 'package:nija/features/sync/sync_controller.dart';
import 'package:nija/ui/app_theme.dart';
import 'package:nija_core/nija_core.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// Admin side: shows the QR code and, on request, a one-time code that
/// another device uses to check this group's admin key after it changed.
Future<void> showAdminCheck(BuildContext context, WidgetRef ref) =>
    showDialog<void>(
      context: context,
      builder: (_) => const _AdminCheckDialog(),
    );

class _AdminCheckDialog extends ConsumerStatefulWidget {
  const _AdminCheckDialog();

  @override
  ConsumerState<_AdminCheckDialog> createState() => _AdminCheckDialogState();
}

class _AdminCheckDialogState extends ConsumerState<_AdminCheckDialog> {
  String? _pin;
  DateTime? _until;
  String? _error;
  bool _busy = false;

  Future<void> _issue() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final pin = await ref
          .read(syncControllerProvider.notifier)
          .issueAdminCode();
      if (!mounted) return;
      setState(() {
        _pin = pin;
        _until = DateTime.now().add(AdminCode.validFor);
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.read(syncControllerProvider.notifier);
    final theme = Theme.of(context);
    final qr = controller.adminQrText;
    final until = _until;
    return AlertDialog(
      key: const ValueKey('admin-check-dialog'),
      title: const Text('Check the admin key on another device'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'When a device says the admin key changed, scan this code with it, or type the one-time code below.',
              ),
              const SizedBox(height: 16),
              if (qr != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(AppTokens.radius),
                  ),
                  child: QrImageView(
                    key: const ValueKey('admin-qr'),
                    data: qr,
                    size: 200,
                  ),
                ),
              const SizedBox(height: 8),
              Text(
                'Key ${controller.adminFingerprint ?? ''}',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              if (_pin == null)
                OutlinedButton.icon(
                  key: const ValueKey('admin-code-issue'),
                  onPressed: _busy ? null : _issue,
                  icon: const Icon(Icons.pin_outlined, size: 18),
                  label: Text(_busy ? 'Preparing…' : 'Show a one-time code'),
                )
              else ...[
                SelectableText(
                  PairingCodec.formatPin(_pin!),
                  key: const ValueKey('admin-code'),
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                    letterSpacing: 2,
                  ),
                ),
                if (until != null)
                  Text(
                    'Valid until ${TimeOfDay.fromDateTime(until).format(context)}',
                    style: theme.textTheme.bodySmall,
                  ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Done'),
        ),
      ],
    );
  }
}

enum _Check { scan, code, compare }

/// Member side: the admin key of this group changed and the old key did
/// not sign it. Asks for proof from the admin device: its QR code, its
/// one-time code, or (as a last resort) a fingerprint compared by eye.
Future<void> reviewAdminChange(
  BuildContext context,
  WidgetRef ref,
  PendingTrust t,
) async {
  final who = t.adminDeviceName.isEmpty
      ? 'the admin device'
      : t.adminDeviceName;
  final choice = await showDialog<_Check>(
    context: context,
    builder: (ctx) => AlertDialog(
      key: const ValueKey('trust-dialog'),
      icon: Icon(
        Icons.shield_rounded,
        color: Theme.of(ctx).colorScheme.primary,
      ),
      title: const Text("This group's admin key changed"),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Text(
          '${t.adminDeviceName.isEmpty ? 'A device' : t.adminDeviceName} now signs this group with a different admin key from the one this device trusts. '
          'Until you check it, this device sends nothing and cannot read the other devices. '
          'This happens when the admin device lost its keys and secured the group again.\n\n'
          'On $who open Settings → Devices → Check admin key, then scan its QR code or type its one-time code here. '
          'If you did not reset anything, do not continue: someone with your database credentials may be trying to take over the group.',
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('trust-compare'),
          onPressed: () => Navigator.pop(ctx, _Check.compare),
          child: const Text('Compare fingerprint'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Not now'),
        ),
        if (PlatformInfo.isMobile)
          OutlinedButton(
            key: const ValueKey('trust-scan'),
            onPressed: () => Navigator.pop(ctx, _Check.scan),
            child: const Text('Scan QR'),
          ),
        FilledButton(
          key: const ValueKey('trust-code'),
          onPressed: () => Navigator.pop(ctx, _Check.code),
          child: const Text('Enter code'),
        ),
      ],
    ),
  );
  if (choice == null || !context.mounted) return;
  final controller = ref.read(syncControllerProvider.notifier);
  var ok = false;
  switch (choice) {
    case _Check.scan:
      final v = await _scan(context);
      ok = v != null && await controller.trustAdminFromQr(v);
    case _Check.code:
      ok = await _askCode(context, controller);
    case _Check.compare:
      ok = await _compare(context, t);
      if (ok) await controller.trustAdmin(t.adminPub);
  }
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'Admin key checked. Syncing again.'
              : choice == _Check.scan
              ? 'That QR code is not the admin key this group changed to.'
              : 'Not checked. Open Settings → Devices to try again.',
        ),
      ),
    );
}

Future<String?> _scan(BuildContext context) => showDialog<String>(
  context: context,
  builder: (ctx) {
    var done = false;
    return AlertDialog(
      title: const Text('Scan the admin QR code'),
      content: SizedBox(
        width: 280,
        height: 280,
        child: MobileScanner(
          onDetect: (capture) {
            final v = capture.barcodes
                .map((b) => b.rawValue)
                .whereType<String>()
                .firstOrNull;
            if (v == null || done) return;
            done = true;
            Navigator.pop(ctx, v);
          },
          errorBuilder: (_, error) => Center(
            child: Text(
              'Camera unavailable (${error.errorCode.name}). Use the one-time code instead.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
      ],
    );
  },
);

Future<bool> _askCode(BuildContext context, SyncController controller) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (_) => _CodeDialog(controller),
  );
  return result ?? false;
}

class _CodeDialog extends StatefulWidget {
  const _CodeDialog(this.controller);
  final SyncController controller;

  @override
  State<_CodeDialog> createState() => _CodeDialogState();
}

class _CodeDialogState extends State<_CodeDialog> {
  final _pin = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    final bad = PairingCodec.validatePin(_pin.text);
    if (bad != null) {
      setState(() => _error = bad);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final ok = await widget.controller.trustAdminWithCode(_pin.text);
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context, true);
      return;
    }
    setState(() {
      _busy = false;
      _error =
          'That code does not match, or it expired. Show a new one on the admin device.';
    });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('One-time code'),
    content: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 360),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Type the 8-digit code shown under Check admin key on the admin device.',
          ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('trust-code-field'),
            controller: _pin,
            autofocus: true,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              hintText: '1234 5678',
              errorText: _error,
              errorMaxLines: 3,
            ),
            onSubmitted: (_) => unawaited(_check()),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: _busy ? null : () => Navigator.pop(context, false),
        child: const Text('Cancel'),
      ),
      FilledButton(
        key: const ValueKey('trust-code-check'),
        onPressed: _busy ? null : _check,
        child: Text(_busy ? 'Checking…' : 'Check'),
      ),
    ],
  );
}

Future<bool> _compare(BuildContext context, PendingTrust t) async {
  final theme = Theme.of(context);
  final yes = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Compare the fingerprint'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Only if you cannot scan or type a code: compare this with the key shown in Settings → Devices on the admin device. All eight characters must match.',
            ),
            const SizedBox(height: 16),
            SelectableText(
              t.fingerprint,
              key: const ValueKey('trust-fingerprint'),
              style: theme.textTheme.headlineSmall?.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
                letterSpacing: 2,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('trust-accept'),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Fingerprint matches, trust'),
        ),
      ],
    ),
  );
  return yes ?? false;
}
