import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nija/features/history/clip_text.dart';
import 'package:nija/features/history/history_keys.dart';

void main() {
  group('TextStats', () {
    test('counts characters, words and lines', () {
      final s = TextStats.of('one two\nthree\n\n');
      expect(s.characters, 15);
      expect(s.words, 3);
      expect(s.lines, 2, reason: 'trailing blank lines are not counted');
    });

    test('an emoji is one character', () {
      expect(TextStats.of('hi 👋').characters, 4);
    });

    test('empty text is all zeros', () {
      final s = TextStats.of('');
      expect([s.characters, s.words, s.lines], [0, 0, 0]);
    });
  });

  group('TextTransform', () {
    const text = '  first line  \n\tsecond   line\n\n';

    test('oneLine collapses every run of whitespace', () {
      expect(TextTransform.oneLine.apply(text), 'first line second line');
    });

    test('trimmed strips each line and the ends', () {
      expect(TextTransform.trimmed.apply(text), 'first line\nsecond   line');
    });

    test('case changes', () {
      expect(TextTransform.upper.apply('Nija'), 'NIJA');
      expect(TextTransform.lower.apply('Nija'), 'nija');
    });
  });

  group('parseColor', () {
    test('hex in every CSS length', () {
      expect(parseColor('#2563eb'), const Color(0xFF2563EB));
      expect(parseColor(' #FFF '), const Color(0xFFFFFFFF));
      expect(parseColor('#0f08'), const Color(0x8800FF00));
      expect(parseColor('#2563eb80'), const Color(0x802563EB));
    });

    test('rgb and rgba, comma or space separated', () {
      expect(parseColor('rgb(37, 99, 235)'), const Color(0xFF2563EB));
      expect(parseColor('RGBA(0 0 0 / 50%)'), const Color(0x80000000));
      expect(parseColor('rgba(255,255,255,0)'), const Color(0x00FFFFFF));
    });

    test('rejects anything that is not only a colour', () {
      for (final t in [
        '',
        '#12',
        '#12345',
        '#gggggg',
        'rgb(300, 0, 0)',
        'color: #fff',
        '#fff and more',
        'issue #123',
      ]) {
        expect(parseColor(t), isNull, reason: t);
      }
    });
  });

  group('matchRuns', () {
    test('marks every case-insensitive hit', () {
      expect(matchRuns('Sync the sync group', 'SYNC'), [
        ('Sync', true),
        (' the ', false),
        ('sync', true),
        (' group', false),
      ]);
    });

    test('no query or no hit gives the text back whole', () {
      expect(matchRuns('abc', ' '), [('abc', false)]);
      expect(matchRuns('abc', 'x'), [('abc', false)]);
    });
  });

  group('HistoryKeys.resolve', () {
    HistoryKeyAction? key(
      LogicalKeyboardKey k, {
      bool primary = false,
      bool shift = false,
      bool searchEmpty = true,
    }) => HistoryKeys.resolve(
      k,
      primary: primary,
      shift: shift,
      searchEmpty: searchEmpty,
    );

    test('plain keys move, copy, preview and dismiss', () {
      expect(key(LogicalKeyboardKey.arrowDown), HistoryKeyAction.down);
      expect(key(LogicalKeyboardKey.arrowUp), HistoryKeyAction.up);
      expect(key(LogicalKeyboardKey.enter), HistoryKeyAction.copy);
      expect(
        key(LogicalKeyboardKey.enter, shift: true),
        HistoryKeyAction.preview,
      );
      expect(key(LogicalKeyboardKey.escape), HistoryKeyAction.dismiss);
    });

    test('typing is left to the search field', () {
      expect(key(LogicalKeyboardKey.keyA), isNull);
      expect(key(LogicalKeyboardKey.digit1), isNull);
      expect(key(LogicalKeyboardKey.backspace), isNull);
    });

    test('primary chords', () {
      expect(
        key(LogicalKeyboardKey.digit3, primary: true),
        HistoryKeyAction.copyNth,
      );
      expect(HistoryKeys.digit(LogicalKeyboardKey.digit3), 3);
      expect(HistoryKeys.digit(LogicalKeyboardKey.digit0), isNull);
      expect(key(LogicalKeyboardKey.keyP, primary: true), HistoryKeyAction.pin);
      expect(
        key(LogicalKeyboardKey.keyF, primary: true),
        HistoryKeyAction.focusSearch,
      );
    });

    test('delete only fires while the search field is empty', () {
      expect(
        key(LogicalKeyboardKey.backspace, primary: true),
        HistoryKeyAction.delete,
      );
      expect(
        key(LogicalKeyboardKey.backspace, primary: true, searchEmpty: false),
        isNull,
      );
    });
  });
}
