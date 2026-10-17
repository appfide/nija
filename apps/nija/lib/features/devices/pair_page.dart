import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nija/core/relative_time.dart';
import 'package:nija/features/devices/device_widgets.dart';
import 'package:nija/features/sync/sync_controller.dart';
import 'package:nija/providers.dart';
import 'package:nija/ui/app_theme.dart';
import 'package:nija/ui/widgets/section_card.dart';
import 'package:nija_core/nija_core.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// Host side of pairing: choose what the new device may do, then show the
/// QR code / text code and the PIN.
class PairPage extends ConsumerStatefulWidget {
  /// Creates the page.
  const PairPage({super.key});

  @override
  ConsumerState<PairPage> createState() => _PairPageState();
}

class _PairPageState extends ConsumerState<PairPage> {
  DeviceRole _role = DeviceRole.full;
  Duration? _access;
  late bool _includePassphrase = ref.read(settingsProvider).encryptionEnabled;
  bool _grantAdmin = false;
  bool _busy = false;
  PairingSession? _session;
  Timer? _tick;
  Duration _left = Duration.zero;
  String? _error;

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _generate() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final session = await ref
          .read(syncControllerProvider.notifier)
          .createPairing(
            role: _role,
            expiresAt: _access == null
                ? null
                : DateTime.now().toUtc().add(_access!),
            includePassphrase: _includePassphrase,
            grantAdmin: _grantAdmin,
          );
      _tick?.cancel();
      _tick = Timer.periodic(const Duration(seconds: 1), (_) => _countdown());
      setState(() {
        _session = session;
        _countdown();
      });
    } on BackendException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _countdown() {
    final s = _session;
    if (s == null) return;
    final left = s.validUntil.difference(DateTime.now().toUtc());
    if (mounted) setState(() => _left = left);
    if (left.isNegative) _tick?.cancel();
  }

  Future<void> _cancelInvite() async {
    final s = _session;
    if (s == null) return;
    setState(() => _busy = true);
    try {
      await ref.read(syncControllerProvider.notifier).forgetDevice(s.deviceId);
    } catch (_) {
      // Best effort; the pending row can be forgotten from the list later.
    }
    if (!mounted) return;
    setState(() {
      _session = null;
      _busy = false;
    });
    _tick?.cancel();
  }

  Future<void> _copy() async {
    final s = _session;
    if (s == null) return;
    await ref.read(syncControllerProvider.notifier).copyTextUnrecorded(s.code);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        const SnackBar(
          content: Text('Pairing code copied: it is not added to history'),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final c = context.colors;
    final session = _session;

    return Scaffold(
      appBar: AppBar(title: const Text('Add a device')),
      body: ContentColumn(
        maxWidth: 560,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
          children: [
            if (session == null) ...[
              Text(
                'The new device gets this database’s settings and joins the group with the access you choose here.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              SectionCard(
                title: 'Access for the new device',
                children: [
                  ListTile(
                    leading: LeadingIcon(
                      icon: Icons.swap_vert_rounded,
                      color: scheme.primary,
                    ),
                    title: const Text('Role'),
                    subtitle: Text(_role.label),
                    trailing: Icon(Icons.chevron_right_rounded, color: c.muted),
                    onTap: () async {
                      final r = await pickRole(context, _role);
                      if (r != null) setState(() => _role = r);
                    },
                  ),
                  ListTile(
                    leading: LeadingIcon(
                      icon: Icons.schedule_rounded,
                      color: scheme.primary,
                    ),
                    title: const Text('Access duration'),
                    subtitle: Text(accessDurations[_access]!),
                    trailing: Icon(Icons.chevron_right_rounded, color: c.muted),
                    onTap: () async {
                      final p = await pickAccessDuration(context);
                      if (p != null) setState(() => _access = p.$1);
                    },
                  ),
                  if (settings.encryptionEnabled)
                    SwitchRow(
                      icon: Icons.key_rounded,
                      title: 'Share encryption passphrase',
                      subtitle: _includePassphrase
                          ? 'Sealed to the new device’s key and delivered through its device row, never inside the code.'
                          : 'Off: you will type the passphrase on the new device.',
                      value: _includePassphrase,
                      onChanged: (v) => setState(() => _includePassphrase = v),
                    ),
                  if (ref.read(syncControllerProvider.notifier).isAdmin)
                    SwitchRow(
                      icon: Icons.shield_rounded,
                      title: 'Can manage devices',
                      subtitle: _grantAdmin
                          ? 'The admin key travels in this code. The new device can add, block and remove devices and rotate keys.'
                          : 'Off: the new device is a member only.',
                      value: _grantAdmin,
                      onChanged: (v) => setState(() => _grantAdmin = v),
                    ),
                ],
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    _error!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.error,
                    ),
                  ),
                ),
              FilledButton.icon(
                key: const ValueKey('generate-code'),
                onPressed: _busy ? null : _generate,
                icon: _busy
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.qr_code_2_rounded, size: 18),
                label: Text(_busy ? 'Preparing…' : 'Show pairing code'),
              ),
            ] else ...[
              _CodeCard(
                session: session,
                left: _left,
                onCopy: _copy,
              ),
              const SizedBox(height: 16),
              _Steps(session: session),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: c.warning.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(AppTokens.radius),
                  border: Border.all(color: c.warning.withValues(alpha: 0.3)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.shield_outlined, size: 18, color: c.warning),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'The code contains your database credentials, protected by the PIN. Show it only to the device you are adding and do not share screenshots.',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  TextButton(
                    onPressed: _busy ? null : _cancelInvite,
                    child: Text(
                      'Cancel invitation',
                      style: TextStyle(color: scheme.error),
                    ),
                  ),
                  const Spacer(),
                  if (_left.isNegative)
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _generate,
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: const Text('New code'),
                    )
                  else
                    FilledButton(
                      onPressed: () => context.pop(),
                      child: const Text('Done'),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CodeCard extends StatelessWidget {
  const _CodeCard({
    required this.session,
    required this.left,
    required this.onCopy,
  });
  final PairingSession session;
  final Duration left;
  final Future<void> Function() onCopy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final c = context.colors;
    final expired = left.isNegative;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(AppTokens.radius),
              ),
              child: Opacity(
                opacity: expired ? 0.25 : 1,
                child: QrImageView(
                  key: const ValueKey('pairing-qr'),
                  data: session.code,
                  size: 220,
                  errorCorrectionLevel: QrErrorCorrectLevel.M,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text('PIN', style: theme.textTheme.labelMedium),
            const SizedBox(height: 4),
            SelectableText(
              PairingCodec.formatPin(session.pin),
              key: const ValueKey('pairing-pin'),
              style: theme.textTheme.headlineMedium?.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              expired
                  ? 'Code expired'
                  : 'Code valid for ${RelativeTime.countdown(left)}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: expired ? scheme.error : c.muted,
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              key: const ValueKey('copy-code'),
              onPressed: expired ? null : onCopy,
              icon: const Icon(Icons.copy_rounded, size: 18),
              label: const Text('Copy code instead'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Steps extends StatelessWidget {
  const _Steps({required this.session});
  final PairingSession session;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final steps = <String>[
      'On the new device open Settings → Devices → Join another group.',
      'Scan the QR code, or paste the copied code.',
      'Type the PIN.',
      if (session.encryption && !session.passphraseIncluded)
        'Enter the encryption passphrase when asked.',
      if (session.grantsAdmin)
        'That device becomes an admin; treat the code accordingly.',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < steps.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${i + 1}.  ', style: theme.textTheme.bodySmall),
                Expanded(
                  child: Text(steps[i], style: theme.textTheme.bodySmall),
                ),
              ],
            ),
          ),
        // Step 1 assumes the app is already installed over there.
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: const ValueKey('pair-get-app'),
            onPressed: () => context.push('/about/downloads'),
            icon: const Icon(Icons.devices_rounded, size: 18),
            label: const Text('That device does not have the app yet'),
          ),
        ),
      ],
    );
  }
}
