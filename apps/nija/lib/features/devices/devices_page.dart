import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nija/features/devices/admin_check.dart';
import 'package:nija/features/devices/device_widgets.dart';
import 'package:nija/features/sync/sync_controller.dart';
import 'package:nija/providers.dart';
import 'package:nija/ui/app_theme.dart';
import 'package:nija/ui/widgets/empty_state.dart';
import 'package:nija/ui/widgets/section_card.dart';
import 'package:nija_core/nija_core.dart';

/// Every device in the sync group with block / role / expiry / remove
/// actions, plus entry points to add or join.
class DevicesPage extends ConsumerStatefulWidget {
  /// Creates the page.
  const DevicesPage({super.key});

  @override
  ConsumerState<DevicesPage> createState() => _DevicesPageState();
}

class _DevicesPageState extends ConsumerState<DevicesPage> {
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
  }

  Future<void> _refresh() async {
    final controller = ref.read(syncControllerProvider.notifier);
    if (!controller.canManageDevices) return;
    setState(() => _busy = true);
    try {
      await controller.refreshDevices();
    } catch (e) {
      _toast('Could not load devices: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _run(Future<void> Function() op, String done) async {
    setState(() => _busy = true);
    try {
      await op();
      _toast(done);
    } on BackendException catch (e) {
      _toast(e.message);
    } catch (e) {
      _toast('$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _onAction(Device d, String action) async {
    final controller = ref.read(syncControllerProvider.notifier);
    // Blocking or removing hands the others a fresh key (see SyncController).
    final rekeys =
        ref.read(settingsProvider).encryptionEnabled &&
        controller.isSignedGroup &&
        controller.isAdmin;
    switch (action) {
      case 'block':
        final ok = await confirm(
          context,
          title: 'Block ${d.name}?',
          message:
              'Other devices will ignore its clips. The next time it checks in (about a minute) it stops syncing and forgets the database credentials, so it has to be paired again.'
              '${rekeys ? ' The other devices get a new encryption key, so it cannot read what is copied from now on.' : ''}'
              ' To stop it for a while instead, pause it.',
          action: 'Block',
          destructive: true,
        );
        if (ok) {
          await _run(() => controller.blockDevice(d.id), 'Blocked ${d.name}');
        }
      case 'unblock':
        await _run(() => controller.unblockDevice(d.id), 'Unblocked ${d.name}');
      case 'pause':
        final ok = await confirm(
          context,
          title: 'Pause ${d.name}?',
          message:
              'On its next check-in (about a minute) it stops sending and receiving but stays paired. Clips copied on other devices while it is paused never reach it, and what it copies meanwhile stays on it. Like every device setting this is honoured by the app: devices on Nija 0.4.2 or older ignore it. Resume it whenever you like.',
          action: 'Pause',
        );
        if (ok) {
          await _run(() => controller.pauseDevice(d.id), 'Paused ${d.name}');
        }
      case 'resume':
        await _run(() => controller.resumeDevice(d.id), 'Resumed ${d.name}');
      case 'role':
        final role = await pickRole(context, d.role);
        if (role != null && role != d.role) {
          await _run(
            () => controller.setDeviceRole(d.id, role),
            '${d.name}: ${role.label}',
          );
        }
      case 'expiry':
        final picked = await pickAccessDuration(context);
        if (picked == null) return;
        final dur = picked.$1;
        await _run(
          () => controller.setDeviceExpiry(
            d.id,
            dur == null ? null : DateTime.now().toUtc().add(dur),
          ),
          dur == null
              ? '${d.name}: no expiry'
              : '${d.name}: access ends in ${accessDurations[dur]!.toLowerCase()}',
        );
      case 'permissions':
        final perms = await pickPermissions(context, d);
        if (perms == null) return;
        await _run(
          () => controller.setDevicePermissions(d.id, perms),
          'Updated permissions for ${d.name}',
        );
      case 'admin':
        final ok = await confirm(
          context,
          title: 'Make ${d.name} an admin?',
          message:
              'It receives the group admin key on its next check-in (about a minute) and can then do everything this device can: add, pause, block and remove devices, grant permissions, rotate the encryption key and delete the database history. This cannot be taken back: the device keeps the key even if you remove it later.',
          action: 'Make admin',
          destructive: true,
        );
        if (ok) {
          await _run(
            () => controller.makeAdmin(d.id),
            '${d.name} will become an admin',
          );
        }
      case 'remove':
        final deleteClips = await confirmRemove(
          context,
          name: d.name,
          encrypted: rekeys,
        );
        if (deleteClips != null) {
          await _run(
            () => controller.removeDevice(d.id, deleteClips: deleteClips),
            deleteClips
                ? 'Removed ${d.name} and deleted its clips'
                : 'Removed ${d.name}',
          );
        }
      case 'forget':
        final ok =
            d.isPending ||
            await confirm(
              context,
              title: 'Forget ${d.name}?',
              message:
                  'Deletes the entry. If the device is still running it will notice on its next check-in and disconnect.',
              action: 'Forget',
              destructive: true,
            );
        if (ok) {
          await _run(() => controller.forgetDevice(d.id), 'Forgot ${d.name}');
        }
    }
  }

  Future<void> _secure() async {
    final ok = await confirm(
      context,
      title: 'Secure this group?',
      message:
          'This device becomes the group admin: it generates a signing key, signs every current device, and from now on only it can add, block or remove devices. Other devices will ask you to confirm the key fingerprint once. Keep this device; losing it means setting the group up again.',
      action: 'Secure',
    );
    if (!ok) return;
    await _run(
      () => ref.read(syncControllerProvider.notifier).secureGroup(),
      'Group secured: check the fingerprint on your other devices',
    );
  }

  Future<void> _changeAdminKey() async {
    final ok = await confirm(
      context,
      title: 'Change the admin key?',
      message:
          'This device makes a new admin key and signs every device again with it. The current key signs the change, so the other devices switch on their next check-in without a question. Devices that are offline switch when they come back. Other admin devices receive the new key sealed to them.',
      action: 'Change key',
    );
    if (!ok) return;
    await _run(() async {
      final kept = await ref
          .read(syncControllerProvider.notifier)
          .changeAdminKey();
      _toast(
        kept
            ? 'Admin key changed. Other devices follow on their next check-in.'
            : 'Admin key changed, but the database did not keep the signed change. '
                  'Each device will ask to check the new key: use Check admin key.',
      );
    }, '');
  }

  Future<void> _rotate() async {
    final ok = await confirm(
      context,
      title: 'Rotate the encryption key?',
      message:
          'A new random passphrase is issued to every verified, active device. Devices that were blocked or removed cannot read anything copied after this point. History already synced stays readable on the devices that had the old key.',
      action: 'Rotate',
    );
    if (!ok) return;
    await _run(() async {
      final v = await ref
          .read(syncControllerProvider.notifier)
          .rotatePassphrase();
      _toast('Encryption key rotated to version $v');
    }, '');
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(settingsProvider);
    final devices = ref.watch(deviceListProvider).value ?? const <Device>[];
    final status = ref.watch(syncControllerProvider);
    final controller = ref.read(syncControllerProvider.notifier);
    final theme = Theme.of(context);
    final c = context.colors;
    final connected = s.syncsRemotely && status.phase != SyncPhase.stopped;
    final signed = status.signedGroup;
    final canEdit = connected && controller.canEditMembership;
    final trusted = controller.trustedDeviceIds;

    final sorted = [...devices]
      ..sort((a, b) {
        int rank(Device d) => d.id == s.deviceId
            ? 0
            : switch (d.status) {
                DeviceStatus.active => d.isPending ? 2 : 1,
                DeviceStatus.paused => 3,
                DeviceStatus.blocked => 4,
                DeviceStatus.removed => 5,
              };
        final r = rank(a).compareTo(rank(b));
        return r != 0 ? r : b.lastSeen.compareTo(a.lastSeen);
      });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Devices'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _busy || !connected ? null : _refresh,
            icon: _busy
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: !s.syncsRemotely
          ? EmptyState(
              icon: Icons.devices_rounded,
              title: 'No sync group yet',
              message:
                  'Connect a database, or join a group from a device that already has one.',
              action: Wrap(
                spacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: () => context.push('/settings/backend'),
                    icon: const Icon(Icons.storage_rounded, size: 18),
                    label: const Text('Choose a database'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => context.push('/settings/devices/join'),
                    icon: const Icon(Icons.qr_code_scanner_rounded, size: 18),
                    label: const Text('Join with a code'),
                  ),
                ],
              ),
            )
          : ContentColumn(
              child: RefreshIndicator(
                onRefresh: _refresh,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.icon(
                          key: const ValueKey('add-device'),
                          onPressed: canEdit
                              ? () => context.push('/settings/devices/pair')
                              : null,
                          icon: const Icon(Icons.qr_code_2_rounded, size: 18),
                          label: const Text('Add a device'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () =>
                              context.push('/settings/devices/join'),
                          icon: const Icon(
                            Icons.qr_code_scanner_rounded,
                            size: 18,
                          ),
                          label: const Text('Join another group'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    if (!connected)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          status.lastError ??
                              'Not connected: device management needs a working connection.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.error,
                          ),
                        ),
                      ),
                    _SecurityCard(
                      signed: signed,
                      isAdmin: controller.isAdmin,
                      selfVerified: status.selfVerified,
                      fingerprint: controller.adminFingerprint,
                      adminName: devices
                          .where((d) => d.admin)
                          .map((d) => d.name)
                          .firstOrNull,
                      encryption: s.encryptionEnabled,
                      keyVersion: status.keyVersion,
                      busy: _busy || !connected,
                      onSecure: _secure,
                      onRotate: _rotate,
                      onCheck: () => unawaited(showAdminCheck(context, ref)),
                      onChangeKey: _changeAdminKey,
                      onReview: ref.watch(pendingTrustProvider) == null
                          ? null
                          : () => unawaited(
                              reviewAdminChange(
                                context,
                                ref,
                                ref.read(pendingTrustProvider)!,
                              ),
                            ),
                    ),
                    SectionCard(
                      title: 'In this group',
                      subtitle: sorted.isEmpty
                          ? null
                          : '${sorted.length} device${sorted.length == 1 ? '' : 's'}',
                      children: sorted.isEmpty
                          ? [
                              Padding(
                                padding: const EdgeInsets.all(20),
                                child: Text(
                                  _busy ? 'Loading…' : 'No devices found.',
                                  style: theme.textTheme.bodySmall,
                                ),
                              ),
                            ]
                          : [
                              for (final d in sorted)
                                DeviceTile(
                                  device: d,
                                  isSelf: d.id == s.deviceId,
                                  verified: signed
                                      ? trusted.contains(d.id) ||
                                            (d.id == s.deviceId &&
                                                status.selfVerified)
                                      : null,
                                  onAction: d.id == s.deviceId || !canEdit
                                      ? null
                                      : (a) => _onAction(d, a),
                                  canGrant: signed && controller.isAdmin,
                                ),
                            ],
                    ),
                    EnforcementNote(signed: signed),
                    const SizedBox(height: 12),
                    Text(
                      'Rename this device under Settings → Devices → This device.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: c.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

class _SecurityCard extends StatelessWidget {
  const _SecurityCard({
    required this.signed,
    required this.isAdmin,
    required this.selfVerified,
    required this.fingerprint,
    required this.adminName,
    required this.encryption,
    required this.keyVersion,
    required this.busy,
    required this.onSecure,
    required this.onRotate,
    required this.onCheck,
    required this.onChangeKey,
    required this.onReview,
  });
  final bool signed;
  final bool isAdmin;
  final bool selfVerified;
  final String? fingerprint;
  final String? adminName;
  final bool encryption;
  final int keyVersion;
  final bool busy;
  final VoidCallback onSecure;
  final VoidCallback onRotate;
  final VoidCallback onCheck;
  final VoidCallback onChangeKey;

  /// Set while another admin key waits for this device to check it.
  final VoidCallback? onReview;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final c = context.colors;
    final tint = !signed
        ? c.warning
        : (selfVerified ? c.success : scheme.error);
    final title = !signed
        ? 'Not secured'
        : (selfVerified ? 'Secured' : 'Secured: this device is unverified');
    final detail = !signed
        ? 'Membership is cooperative: anyone with the database credentials can pose as a device.'
        : selfVerified
        ? 'Managed by ${adminName ?? 'the admin device'} · key ${fingerprint ?? ''}'
              '${isAdmin ? ' · this device is an admin' : ''}'
              '${encryption ? ' · encryption key v$keyVersion' : ''}'
        : onReview != null
        ? 'The admin key changed. Until you check the new one, this device sends nothing and cannot read the other devices.'
        : 'Other devices ignore this device’s clips until the admin re-adds it with a new pairing code.';
    return SectionCard(
      title: 'Group security',
      children: [
        ListTile(
          key: const ValueKey('security-card'),
          leading: LeadingIcon(
            icon: !signed
                ? Icons.gpp_maybe_rounded
                : (selfVerified
                      ? Icons.verified_user_rounded
                      : Icons.gpp_bad_rounded),
            color: tint,
          ),
          title: Text(title),
          subtitle: Text(detail),
          isThreeLine: true,
        ),
        if (!signed)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                key: const ValueKey('secure-group'),
                onPressed: busy ? null : onSecure,
                icon: const Icon(Icons.shield_rounded, size: 18),
                label: const Text('Secure this group'),
              ),
            ),
          ),
        if (signed && (isAdmin || onReview != null))
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (onReview != null)
                  FilledButton.icon(
                    key: const ValueKey('review-admin-key'),
                    onPressed: onReview,
                    icon: const Icon(Icons.qr_code_scanner_rounded, size: 18),
                    label: const Text('Check new admin key'),
                  ),
                if (isAdmin) ...[
                  OutlinedButton.icon(
                    key: const ValueKey('check-admin-key'),
                    onPressed: busy ? null : onCheck,
                    icon: const Icon(Icons.qr_code_rounded, size: 18),
                    label: const Text('Check admin key'),
                  ),
                  if (encryption)
                    OutlinedButton.icon(
                      key: const ValueKey('rotate-key'),
                      onPressed: busy ? null : onRotate,
                      icon: const Icon(Icons.autorenew_rounded, size: 18),
                      label: const Text('Rotate encryption key'),
                    ),
                  OutlinedButton.icon(
                    key: const ValueKey('change-admin-key'),
                    onPressed: busy ? null : onChangeKey,
                    icon: const Icon(Icons.key_rounded, size: 18),
                    label: const Text('Change admin key'),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}
