import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:nija/core/platform_info.dart';
import 'package:nija/data/local/local_store.dart';
import 'package:nija/features/devices/device_picker.dart';
import 'package:nija/features/history/clip_preview.dart';
import 'package:nija/features/history/clip_text.dart';
import 'package:nija/features/history/history_keys.dart';
import 'package:nija/features/sync/sync_controller.dart';
import 'package:nija/providers.dart';
import 'package:nija/ui/app_theme.dart';
import 'package:nija/ui/widgets/empty_state.dart';
import 'package:nija/ui/widgets/section_card.dart';
import 'package:nija/ui/widgets/status_pill.dart';
import 'package:nija_core/nija_core.dart';

/// Main screen: searchable clipboard history grouped by day.
///
/// On desktop the list is driven from the keyboard as well: the search
/// field keeps focus while the arrow keys move a selection through the
/// list (see [HistoryKeys]).
class HistoryPage extends ConsumerStatefulWidget {
  /// Creates the page.
  const HistoryPage({super.key});

  @override
  ConsumerState<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends ConsumerState<HistoryPage> {
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  final GlobalKey _selectedKey = GlobalKey();
  int? _selected;

  @override
  void dispose() {
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  List<HistoryEntry> get _rows => ref.read(historyProvider).value ?? const [];

  void _select(int? index) {
    setState(() => _selected = index);
    if (index == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _selectedKey.currentContext;
      if (ctx != null && ctx.mounted) {
        // One call per edge: the first scrolls a clip below the fold up
        // into view, the second one above it down; a visible clip stays put.
        unawaited(
          Scrollable.ensureVisible(
            ctx,
            alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
            duration: AppTokens.fast,
          ),
        );
        unawaited(
          Scrollable.ensureVisible(
            ctx,
            alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtStart,
            duration: AppTokens.fast,
          ),
        );
      }
    });
  }

  void _setQuery(String q) {
    ref.read(historyQueryProvider.notifier).query = q;
    setState(() => _selected = null);
  }

  void _setFilter(HistoryFilter f) {
    ref.read(historyFilterProvider.notifier).filter = f;
    setState(() => _selected = null);
  }

  Future<void> _copy(ClipItem item) async {
    await ref.read(syncControllerProvider.notifier).copyToClipboard(item);
    await _afterCopy();
  }

  Future<void> _copyText(String text) async {
    await ref.read(syncControllerProvider.notifier).copyTextUnrecorded(text);
    await _afterCopy();
  }

  Future<void> _afterCopy() async {
    final shell = ref.read(desktopShellProvider);
    if (shell != null && ref.read(settingsProvider).hideAfterCopy) {
      await shell.hideWindow();
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        const SnackBar(
          content: Text('Copied to clipboard'),
          duration: Duration(seconds: 1),
        ),
      );
  }

  Future<void> _preview(ClipItem item) => showClipPreview(
    context,
    item: item,
    onCopy: () => _copy(item),
    onCopyText: _copyText,
  );

  KeyEventResult _onKey(FocusNode _, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final action = HistoryKeys.match(
      event.logicalKey,
      HardwareKeyboard.instance,
      searchEmpty: _search.text.isEmpty,
    );
    if (action == null) return KeyEventResult.ignored;
    final rows = _rows;
    final current = _selected == null || _selected! >= rows.length
        ? null
        : _selected;
    HistoryEntry? target() => rows.isEmpty ? null : rows[current ?? 0];

    switch (action) {
      case HistoryKeyAction.down:
        if (rows.isEmpty) return KeyEventResult.handled;
        _select(current == null ? 0 : (current + 1).clamp(0, rows.length - 1));
      case HistoryKeyAction.up:
        if (rows.isEmpty) return KeyEventResult.handled;
        _select(current == null ? 0 : (current - 1).clamp(0, rows.length - 1));
      case HistoryKeyAction.copy:
        final t = target();
        if (t != null) unawaited(_copy(t.item));
      case HistoryKeyAction.preview:
        final t = target();
        if (t != null) unawaited(_preview(t.item));
      case HistoryKeyAction.pin:
        final t = target();
        if (t != null) {
          unawaited(
            ref
                .read(localStoreProvider)
                .setPinned(t.item.id, pinned: !t.pinned),
          );
        }
      case HistoryKeyAction.delete:
        final t = target();
        if (t == null || current == null) return KeyEventResult.ignored;
        unawaited(ref.read(syncControllerProvider.notifier).delete(t.item.id));
        if (current >= rows.length - 1) {
          _select(rows.length > 1 ? rows.length - 2 : null);
        }
      case HistoryKeyAction.focusSearch:
        _searchFocus.requestFocus();
        _search.selection = TextSelection(
          baseOffset: 0,
          extentOffset: _search.text.length,
        );
      case HistoryKeyAction.dismiss:
        if (_search.text.isNotEmpty) {
          _search.clear();
          _setQuery('');
        } else {
          final shell = ref.read(desktopShellProvider);
          if (shell == null) return KeyEventResult.ignored;
          unawaited(shell.hideWindow());
        }
      case HistoryKeyAction.copyNth:
        final n = HistoryKeys.digit(event.logicalKey);
        if (n != null && n <= rows.length) unawaited(_copy(rows[n - 1].item));
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final history = ref.watch(historyProvider);
    final status = ref.watch(syncControllerProvider);
    final pending = ref.watch(pendingCountProvider).value ?? 0;
    final filter = ref.watch(historyFilterProvider);
    final query = ref.watch(historyQueryProvider);
    final controller = ref.read(syncControllerProvider.notifier);
    final wide =
        MediaQuery.sizeOf(context).width >= AppTokens.desktopBreakpoint;
    final theme = Theme.of(context);
    final narrowed = query.trim().isNotEmpty || filter != HistoryFilter.all;

    Future<void> syncNow() async {
      await controller.captureNow();
      await controller.syncNow();
    }

    return Scaffold(
      body: SafeArea(
        child: Focus(
          canRequestFocus: false,
          skipTraversal: true,
          onKeyEvent: _onKey,
          child: ContentColumn(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'History',
                              style: theme.textTheme.headlineSmall,
                            ),
                            Text(
                              history.value == null
                                  ? ' '
                                  : '${history.value!.length} item${history.value!.length == 1 ? '' : 's'}',
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      if (!wide)
                        Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: StatusPill(
                            status: status,
                            pending: pending,
                            onTap: () => context.go('/settings/backend'),
                          ),
                        ),
                      if (PlatformInfo.isDesktop && wide)
                        IconButton(
                          key: const ValueKey('shortcuts-help'),
                          tooltip: 'Keyboard shortcuts',
                          icon: const Icon(Icons.keyboard_outlined),
                          onPressed: () => showHistoryKeysHelp(context),
                        ),
                      IconButton(
                        tooltip: PlatformInfo.isMobile
                            ? 'Capture clipboard & sync'
                            : 'Sync now',
                        icon: const Icon(Icons.sync_rounded),
                        onPressed: syncNow,
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                  child: TextField(
                    key: const ValueKey('search'),
                    controller: _search,
                    focusNode: _searchFocus,
                    autofocus: PlatformInfo.isDesktop,
                    // Desktop fields drop focus on any click elsewhere, which
                    // would take the list's keyboard control with them.
                    onTapOutside: PlatformInfo.isDesktop ? (_) {} : null,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search_rounded),
                      hintText: 'Search history',
                      isDense: true,
                    ),
                    onChanged: _setQuery,
                  ),
                ),
                _FilterBar(selected: filter, onSelected: _setFilter),
                Expanded(
                  child: history.when(
                    loading: () => const _Skeleton(),
                    error: (e, _) => EmptyState(
                      icon: Icons.error_outline_rounded,
                      title: 'Could not load history',
                      message: '$e',
                    ),
                    data: (rows) => rows.isEmpty
                        ? narrowed
                              ? EmptyState(
                                  icon: Icons.search_off_rounded,
                                  title: 'No matches',
                                  message: filter == HistoryFilter.all
                                      ? 'Nothing in your history contains that text.'
                                      : 'Nothing under ${filter.label} matches. Try All.',
                                )
                              : EmptyState(
                                  icon: Icons.content_paste_search_rounded,
                                  title: 'Nothing here yet',
                                  message: PlatformInfo.isDesktop
                                      ? 'Copy anything: it shows up here and syncs to your other devices.'
                                      : 'Copy something, then open the app or tap Capture.',
                                  action: PlatformInfo.isMobile
                                      ? FilledButton.icon(
                                          onPressed: syncNow,
                                          icon: const Icon(
                                            Icons.content_paste_rounded,
                                          ),
                                          label: const Text(
                                            'Capture clipboard',
                                          ),
                                        )
                                      : null,
                                )
                        : _GroupedList(
                            rows,
                            query: query,
                            selected: _selected,
                            selectedKey: _selectedKey,
                            onCopy: _copy,
                            onPreview: _preview,
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      floatingActionButton: PlatformInfo.isMobile
          ? FloatingActionButton.extended(
              onPressed: syncNow,
              icon: const Icon(Icons.content_paste_rounded),
              label: const Text('Capture'),
            )
          : null,
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({required this.selected, required this.onSelected});

  final HistoryFilter selected;
  final void Function(HistoryFilter) onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
        children: [
          for (final f in HistoryFilter.values)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                key: ValueKey('filter-${f.name}'),
                label: Text(f.label),
                selected: f == selected,
                showCheckmark: false,
                visualDensity: VisualDensity.compact,
                selectedColor: scheme.primary.withValues(alpha: 0.14),
                labelStyle: f == selected
                    ? TextStyle(
                        color: scheme.primary,
                        fontWeight: FontWeight.w600,
                      )
                    : null,
                side: f == selected
                    ? BorderSide(color: scheme.primary.withValues(alpha: 0.5))
                    : null,
                onSelected: (_) => onSelected(f),
              ),
            ),
        ],
      ),
    );
  }
}

class _GroupedList extends StatelessWidget {
  const _GroupedList(
    this.rows, {
    required this.query,
    required this.selected,
    required this.selectedKey,
    required this.onCopy,
    required this.onPreview,
  });
  final List<HistoryEntry> rows;
  final String query;
  final int? selected;
  final GlobalKey selectedKey;
  final Future<void> Function(ClipItem) onCopy;
  final Future<void> Function(ClipItem) onPreview;

  @override
  Widget build(BuildContext context) {
    final items = <Object>[];
    String? last;
    for (final (i, r) in rows.indexed) {
      final label = r.pinned ? 'Pinned' : _dayLabel(r.item.createdAt);
      if (label != last) {
        items.add(label);
        last = label;
      }
      items.add((i, r));
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
      itemCount: items.length,
      itemBuilder: (context, i) {
        final it = items[i];
        if (it is String) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
            child: Text(
              it.toUpperCase(),
              style: Theme.of(
                context,
              ).textTheme.labelMedium?.copyWith(color: context.colors.muted),
            ),
          );
        }
        final (index, entry) = it as (int, HistoryEntry);
        final isSelected = index == selected;
        return Padding(
          key: isSelected ? selectedKey : null,
          padding: const EdgeInsets.only(bottom: 8),
          child: _ClipCard(
            entry,
            query: query,
            selected: isSelected,
            onCopy: () => onCopy(entry.item),
            onPreview: () => onPreview(entry.item),
          ),
        );
      },
    );
  }

  static String _dayLabel(DateTime t) {
    final local = t.toLocal();
    final now = DateTime.now();
    final d = DateTime(local.year, local.month, local.day);
    final today = DateTime(now.year, now.month, now.day);
    final diff = today.difference(d).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    if (diff < 7) return DateFormat.EEEE().format(local);
    return DateFormat.yMMMd().format(local);
  }
}

class _ClipCard extends ConsumerStatefulWidget {
  const _ClipCard(
    this.entry, {
    required this.query,
    required this.selected,
    required this.onCopy,
    required this.onPreview,
  });
  final HistoryEntry entry;
  final String query;
  final bool selected;
  final Future<void> Function() onCopy;
  final Future<void> Function() onPreview;

  @override
  ConsumerState<_ClipCard> createState() => _ClipCardState();
}

class _ClipCardState extends ConsumerState<_ClipCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final item = entry.item;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final c = context.colors;
    final controller = ref.read(syncControllerProvider.notifier);
    final store = ref.read(localStoreProvider);
    final ownId = ref.watch(settingsProvider.select((s) => s.deviceId));
    final targets = sendTargets(
      ref.watch(deviceListProvider).value ?? const [],
      ownId,
    );

    Future<void> sendTo() async {
      final id = await pickDevice(context, targets);
      if (id == null) return;
      await controller.sendToDevice(item, id);
      if (context.mounted) {
        final name = targets.firstWhere((d) => d.id == id).name;
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(
            SnackBar(
              content: Text('Sent to $name'),
              duration: const Duration(seconds: 2),
            ),
          );
      }
    }

    final preview = item.type.isBinary
        ? '${item.type.wire} · ${(item.sizeBytes / 1024).toStringAsFixed(0)} KB'
        : item.content.trim().replaceAll(RegExp(r'\s+'), ' ');

    final baseStyle = item.type == ClipContentType.url
        ? theme.textTheme.bodyMedium?.copyWith(
            color: scheme.primary,
            fontFeatures: const [FontFeature.tabularFigures()],
          )
        : theme.textTheme.bodyMedium;
    final highlight = TextStyle(
      backgroundColor: scheme.primary.withValues(alpha: 0.16),
      fontWeight: FontWeight.w600,
    );

    final card = Card(
      key: ValueKey('clip-${item.id}'),
      color: _hover || widget.selected
          ? scheme.surfaceContainer
          : c.surfaceRaised,
      shape: widget.selected
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppTokens.radiusLg),
              side: BorderSide(color: scheme.primary, width: 1.5),
            )
          : null,
      child: InkWell(
        onTap: widget.onCopy,
        onLongPress: widget.onPreview,
        borderRadius: BorderRadius.circular(AppTokens.radiusLg),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _TypeBadge(item),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text.rich(
                      TextSpan(
                        children: [
                          for (final (run, hit)
                              in item.type.isBinary
                                  ? [(preview, false)]
                                  : matchRuns(preview, widget.query))
                            TextSpan(text: run, style: hit ? highlight : null),
                        ],
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: baseStyle,
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(
                          _platformIcon(item.deviceName),
                          size: 14,
                          color: c.muted,
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            item.deviceName,
                            style: theme.textTheme.bodySmall,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          '  ·  ${_ago(item.createdAt)}',
                          style: theme.textTheme.bodySmall,
                        ),
                        if (!entry.synced) ...[
                          const SizedBox(width: 8),
                          Icon(
                            Icons.cloud_upload_outlined,
                            size: 14,
                            color: c.warning,
                          ),
                        ],
                        if (item.encrypted) ...[
                          const SizedBox(width: 6),
                          Icon(
                            Icons.lock_outline_rounded,
                            size: 14,
                            color: c.muted,
                          ),
                        ],
                        if (item.isTargeted) ...[
                          const SizedBox(width: 6),
                          Tooltip(
                            message: 'Sent only to this device',
                            child: Icon(
                              Icons.send_rounded,
                              size: 14,
                              color: scheme.primary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              AnimatedOpacity(
                duration: AppTokens.fast,
                opacity: _hover || PlatformInfo.isMobile ? 1 : 0.55,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (entry.pinned)
                      Icon(
                        Icons.push_pin_rounded,
                        size: 16,
                        color: scheme.primary,
                      ),
                    PopupMenuButton<String>(
                      tooltip: 'More',
                      icon: const Icon(Icons.more_horiz_rounded),
                      onSelected: (v) async {
                        switch (v) {
                          case 'copy':
                            await widget.onCopy();
                          case 'preview':
                            await widget.onPreview();
                          case 'send':
                            await sendTo();
                          case 'pin':
                            await store.setPinned(
                              item.id,
                              pinned: !entry.pinned,
                            );
                          case 'delete':
                            await controller.delete(item.id);
                        }
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(
                          value: 'copy',
                          child: _MenuRow(Icons.copy_rounded, 'Copy'),
                        ),
                        const PopupMenuItem(
                          value: 'preview',
                          child: _MenuRow(
                            Icons.visibility_outlined,
                            'Preview',
                          ),
                        ),
                        if (targets.isNotEmpty)
                          const PopupMenuItem(
                            value: 'send',
                            child: _MenuRow(Icons.send_rounded, 'Send to…'),
                          ),
                        PopupMenuItem(
                          value: 'pin',
                          child: _MenuRow(
                            entry.pinned
                                ? Icons.push_pin_outlined
                                : Icons.push_pin_rounded,
                            entry.pinned ? 'Unpin' : 'Pin',
                          ),
                        ),
                        PopupMenuItem(
                          value: 'delete',
                          child: _MenuRow(
                            Icons.delete_outline_rounded,
                            'Delete everywhere',
                            color: scheme.error,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: PlatformInfo.isMobile
          ? Dismissible(
              key: ValueKey('dismiss-${item.id}'),
              direction: DismissDirection.endToStart,
              background: Container(
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 20),
                decoration: BoxDecoration(
                  color: scheme.errorContainer,
                  borderRadius: BorderRadius.circular(AppTokens.radiusLg),
                ),
                child: Icon(
                  Icons.delete_outline_rounded,
                  color: scheme.onErrorContainer,
                ),
              ),
              onDismissed: (_) => controller.delete(item.id),
              child: card,
            )
          : card,
    );
  }

  static IconData _platformIcon(String deviceName) {
    final n = deviceName.toLowerCase();
    if (n.contains('iphone') || n.contains('ipad')) {
      return Icons.phone_iphone_rounded;
    }
    if (n.contains('android')) return Icons.phone_android_rounded;
    if (n.contains('mac')) return Icons.laptop_mac_rounded;
    return Icons.computer_rounded;
  }

  static String _ago(DateTime t) {
    final d = DateTime.now().toUtc().difference(t);
    if (d.inSeconds < 60) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes} min ago';
    if (d.inHours < 24) return '${d.inHours} h ago';
    return DateFormat.jm().format(t.toLocal());
  }
}

class _TypeBadge extends StatelessWidget {
  const _TypeBadge(this.item);
  final ClipItem item;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (item.type == ClipContentType.image) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.memory(
          base64Decode(item.content),
          width: 40,
          height: 40,
          fit: BoxFit.cover,
          gaplessPlayback: true,
        ),
      );
    }
    final swatch = item.type == ClipContentType.text
        ? parseColor(item.content)
        : null;
    if (swatch != null) {
      return Container(
        key: const ValueKey('color-swatch'),
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: swatch,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: context.colors.border),
        ),
      );
    }
    final (icon, color) = switch (item.type) {
      ClipContentType.url => (Icons.link_rounded, scheme.primary),
      ClipContentType.html => (Icons.code_rounded, AppTokens.amber600),
      ClipContentType.file => (
        Icons.insert_drive_file_outlined,
        scheme.secondary,
      ),
      ClipContentType.image ||
      ClipContentType.text => (Icons.notes_rounded, scheme.secondary),
    };
    return LeadingIcon(icon: icon, color: color, size: 40);
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow(this.icon, this.label, {this.color});
  final IconData icon;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 18, color: color ?? context.colors.muted),
      const SizedBox(width: 10),
      Text(label, style: TextStyle(color: color)),
    ],
  );
}

class _Skeleton extends StatelessWidget {
  const _Skeleton();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget bar(double w, double h) => Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        color: c.surfaceSunken,
        borderRadius: BorderRadius.circular(6),
      ),
    );
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: 6,
      itemBuilder: (_, _) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                bar(40, 40),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      bar(double.infinity, 14),
                      const SizedBox(height: 8),
                      bar(140, 12),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
