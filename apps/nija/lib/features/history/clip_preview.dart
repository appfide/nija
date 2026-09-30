import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:nija/features/history/clip_text.dart';
import 'package:nija/ui/app_theme.dart';
import 'package:nija_core/nija_core.dart';

/// Shows the whole of [item]: a dialog on wide screens, a sheet on phones.
///
/// [onCopy] puts the clip back on the clipboard as it is; [onCopyText]
/// receives a rewritten version picked from *Copy as*.
Future<void> showClipPreview(
  BuildContext context, {
  required ClipItem item,
  required Future<void> Function() onCopy,
  required Future<void> Function(String text) onCopyText,
}) {
  final body = _PreviewBody(
    item: item,
    onCopy: onCopy,
    onCopyText: onCopyText,
  );
  final wide = MediaQuery.sizeOf(context).width >= AppTokens.desktopBreakpoint;
  if (wide) {
    return showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640, maxHeight: 560),
          child: body,
        ),
      ),
    );
  }
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(ctx).height * 0.8,
      ),
      child: SafeArea(child: body),
    ),
  );
}

class _PreviewBody extends StatelessWidget {
  const _PreviewBody({
    required this.item,
    required this.onCopy,
    required this.onCopyText,
  });

  final ClipItem item;
  final Future<void> Function() onCopy;
  final Future<void> Function(String text) onCopyText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = context.colors;
    final isText = !item.type.isBinary;
    final color = isText ? parseColor(item.content) : null;
    final when = DateFormat.yMMMd().add_jm().format(item.createdAt.toLocal());

    final String facts;
    if (isText) {
      final stats = TextStats.of(item.content);
      facts =
          '${_count(stats.characters, 'character')} · '
          '${_count(stats.words, 'word')} · ${_count(stats.lines, 'line')}';
    } else {
      facts = '${(item.sizeBytes / 1024).toStringAsFixed(0)} KB';
    }

    return Column(
      key: const ValueKey('clip-preview'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 4),
          child: Text(
            item.deviceName.isEmpty ? when : '${item.deviceName} · $when',
            style: theme.textTheme.titleMedium,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
          child: Text(
            facts,
            key: const ValueKey('clip-preview-facts'),
            style: theme.textTheme.bodySmall,
          ),
        ),
        if (color != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
            child: Container(
              height: 56,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(AppTokens.radius),
                border: Border.all(color: c.border),
              ),
            ),
          ),
        Flexible(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 24),
            decoration: BoxDecoration(
              color: c.surfaceSunken,
              borderRadius: BorderRadius.circular(AppTokens.radius),
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(14),
              child: item.type == ClipContentType.image
                  ? Image.memory(
                      base64Decode(item.content),
                      fit: BoxFit.contain,
                    )
                  : SelectableText(
                      isText ? item.content : '${item.type.wire} data',
                      style: theme.textTheme.bodyMedium,
                    ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (isText)
                PopupMenuButton<TextTransform>(
                  key: const ValueKey('copy-as'),
                  tooltip: 'Copy a rewritten version',
                  onSelected: (t) async {
                    Navigator.pop(context);
                    await onCopyText(t.apply(item.content));
                  },
                  itemBuilder: (_) => [
                    for (final t in TextTransform.values)
                      PopupMenuItem(value: t, child: Text(t.label)),
                  ],
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Copy as'),
                        SizedBox(width: 4),
                        Icon(Icons.expand_more_rounded, size: 18),
                      ],
                    ),
                  ),
                ),
              const SizedBox(width: 8),
              FilledButton.icon(
                key: const ValueKey('preview-copy'),
                onPressed: () async {
                  Navigator.pop(context);
                  await onCopy();
                },
                icon: const Icon(Icons.copy_rounded, size: 18),
                label: const Text('Copy'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  static String _count(int n, String noun) =>
      '${NumberFormat.decimalPattern().format(n)} $noun${n == 1 ? '' : 's'}';
}
