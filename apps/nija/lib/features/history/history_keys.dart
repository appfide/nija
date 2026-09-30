import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nija/ui/app_theme.dart';

/// What a key press on the history page asks for.
enum HistoryKeyAction {
  /// Move the selection down.
  down,

  /// Move the selection up.
  up,

  /// Copy the selected clip (the newest when nothing is selected).
  copy,

  /// Open the selected clip in the preview.
  preview,

  /// Copy the clip at the position of the digit pressed (1 to 9).
  copyNth,

  /// Pin or unpin the selected clip.
  pin,

  /// Delete the selected clip everywhere.
  delete,

  /// Put the cursor in the search field.
  focusSearch,

  /// Clear the search, or hide the window when it is already clear.
  dismiss,
}

/// Keyboard map for the history page.
///
/// The search field keeps focus the whole time, so every binding either
/// uses a key a single-line field has no use for (arrows, Enter, Escape) or
/// holds the platform's primary modifier: ⌘ on macOS, Ctrl elsewhere.
abstract final class HistoryKeys {
  static final List<LogicalKeyboardKey> _digits = [
    LogicalKeyboardKey.digit1,
    LogicalKeyboardKey.digit2,
    LogicalKeyboardKey.digit3,
    LogicalKeyboardKey.digit4,
    LogicalKeyboardKey.digit5,
    LogicalKeyboardKey.digit6,
    LogicalKeyboardKey.digit7,
    LogicalKeyboardKey.digit8,
    LogicalKeyboardKey.digit9,
  ];

  /// Label of the primary modifier on this platform.
  static String get primaryLabel => Platform.isMacOS ? '⌘' : 'Ctrl+';

  /// Reads the modifiers from [keyboard] and resolves [key].
  static HistoryKeyAction? match(
    LogicalKeyboardKey key,
    HardwareKeyboard keyboard, {
    required bool searchEmpty,
  }) => resolve(
    key,
    primary: Platform.isMacOS
        ? keyboard.isMetaPressed
        : keyboard.isControlPressed,
    shift: keyboard.isShiftPressed,
    searchEmpty: searchEmpty,
  );

  /// Resolves [key] given which modifiers are held. Deleting needs an empty
  /// search, because with text in the field the same chord edits the text.
  static HistoryKeyAction? resolve(
    LogicalKeyboardKey key, {
    required bool primary,
    required bool shift,
    required bool searchEmpty,
  }) {
    if (primary) {
      if (_digits.contains(key)) return HistoryKeyAction.copyNth;
      if (key == LogicalKeyboardKey.keyP) return HistoryKeyAction.pin;
      if (key == LogicalKeyboardKey.keyF) return HistoryKeyAction.focusSearch;
      if (searchEmpty &&
          (key == LogicalKeyboardKey.backspace ||
              key == LogicalKeyboardKey.delete)) {
        return HistoryKeyAction.delete;
      }
      return null;
    }
    if (key == LogicalKeyboardKey.arrowDown) return HistoryKeyAction.down;
    if (key == LogicalKeyboardKey.arrowUp) return HistoryKeyAction.up;
    if (key == LogicalKeyboardKey.escape) return HistoryKeyAction.dismiss;
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      return shift ? HistoryKeyAction.preview : HistoryKeyAction.copy;
    }
    return null;
  }

  /// 1 to 9 for a digit key, otherwise `null`.
  static int? digit(LogicalKeyboardKey key) {
    final i = _digits.indexOf(key);
    return i < 0 ? null : i + 1;
  }
}

/// Lists the history shortcuts.
Future<void> showHistoryKeysHelp(BuildContext context) {
  final p = HistoryKeys.primaryLabel;
  final rows = [
    ('↑  ↓', 'Move through the list'),
    ('Enter', 'Copy the selected clip'),
    ('Shift+Enter', 'Preview the selected clip'),
    ('${p}1 to ${p}9', 'Copy the first nine clips'),
    ('${p}P', 'Pin or unpin'),
    (
      Platform.isMacOS ? '⌘⌫' : 'Ctrl+Backspace',
      'Delete (search field empty)',
    ),
    ('${p}F', 'Search'),
    ('Esc', 'Clear the search, then hide the window'),
  ];
  return showDialog<void>(
    context: context,
    builder: (ctx) {
      final theme = Theme.of(ctx);
      return AlertDialog(
        title: const Text('Keyboard shortcuts'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final (keys, what) in rows)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Container(
                        width: 144,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: ctx.colors.surfaceSunken,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: ctx.colors.border),
                        ),
                        child: Text(
                          keys,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.labelMedium,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text(what, style: theme.textTheme.bodyMedium),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      );
    },
  );
}
