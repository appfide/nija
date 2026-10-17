import 'package:flutter/material.dart';
import 'package:nija/ui/app_theme.dart';
import 'package:nija_core/nija_core.dart';

/// Compact sync status indicator: coloured dot + label.
class StatusPill extends StatelessWidget {
  /// Creates the pill.
  const StatusPill({
    required this.status,
    this.pending = 0,
    this.onTap,
    this.compact = false,
    super.key,
  });

  /// Engine status.
  final SyncStatus status;

  /// Unsynced items.
  final int pending;

  /// Tap handler (e.g. open backend settings on error).
  final VoidCallback? onTap;

  /// Narrow variant for the navigation rail: short labels, fits 80 px.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final c = context.colors;
    final (color, label) = switch (status.phase) {
      SyncPhase.stopped => (c.muted, 'Local only'),
      SyncPhase.idle when status.waitingForKey => (
        c.warning,
        compact ? 'No key' : 'Waiting for key',
      ),
      SyncPhase.idle =>
        pending > 0
            ? (c.warning, compact ? 'Pending' : '$pending pending')
            : (c.success, status.realtime ? 'Live' : 'Synced'),
      SyncPhase.syncing => (scheme.primary, 'Syncing'),
      SyncPhase.paused => (c.muted, compact ? 'Paused' : 'Sync paused'),
      SyncPhase.error => (
        scheme.error,
        status.authFailed
            ? (compact ? 'Error' : 'Needs attention')
            : 'Retrying',
      ),
      SyncPhase.revoked => (
        scheme.error,
        compact ? 'Removed' : 'Access removed',
      ),
    };
    return Semantics(
      label: 'Sync status: $label',
      button: onTap != null,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: AnimatedContainer(
          duration: AppTokens.fast,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: color.withValues(alpha: 0.25)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _Dot(color: color, pulse: status.phase == SyncPhase.syncing),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.labelMedium?.copyWith(color: color),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Dot extends StatefulWidget {
  const _Dot({required this.color, required this.pulse});
  final Color color;
  final bool pulse;

  @override
  State<_Dot> createState() => _DotState();
}

class _DotState extends State<_Dot> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void initState() {
    super.initState();
    if (widget.pulse) _c.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant _Dot old) {
    super.didUpdateWidget(old);
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (widget.pulse && !reduce) {
      _c.repeat(reverse: true);
    } else {
      _c
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: Tween<double>(
      begin: 1,
      end: 0.35,
    ).animate(CurvedAnimation(parent: _c, curve: Curves.easeInOut)),
    child: Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
    ),
  );
}
