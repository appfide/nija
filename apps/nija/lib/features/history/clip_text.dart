import 'dart:ui';

/// Counts shown in the preview sheet.
class TextStats {
  /// Measures [text].
  factory TextStats.of(String text) {
    if (text.isEmpty) return const TextStats._(0, 0, 0);
    final words = RegExp(r'\S+').allMatches(text).length;
    final lines = '\n'.allMatches(text.trimRight()).length + 1;
    return TextStats._(text.runes.length, words, lines);
  }

  const TextStats._(this.characters, this.words, this.lines);

  /// Unicode code points, so an emoji counts once.
  final int characters;

  /// Runs of non-whitespace.
  final int words;

  /// Lines, ignoring trailing blank lines.
  final int lines;
}

/// Ways a text clip can be rewritten on its way to the clipboard.
enum TextTransform {
  /// Collapses every run of whitespace, newlines included, to one space.
  oneLine('As one line'),

  /// Strips leading and trailing whitespace from every line and drops
  /// blank lines at either end.
  trimmed('Trimmed'),

  /// Upper case.
  upper('UPPERCASE'),

  /// Lower case.
  lower('lowercase');

  const TextTransform(this.label);

  /// Menu label.
  final String label;

  /// Applies the transform.
  String apply(String text) => switch (this) {
    oneLine => text.trim().replaceAll(RegExp(r'\s+'), ' '),
    trimmed => text.split('\n').map((l) => l.trim()).join('\n').trim(),
    upper => text.toUpperCase(),
    lower => text.toLowerCase(),
  };
}

final _hex = RegExp(r'^#([0-9a-fA-F]{3,4}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$');
final _rgb = RegExp(
  r'^rgba?\(\s*(\d{1,3})\s*[, ]\s*(\d{1,3})\s*[, ]\s*(\d{1,3})\s*(?:[,/]\s*([\d.]+%?)\s*)?\)$',
  caseSensitive: false,
);

/// Parses a clip that is nothing but a CSS colour (`#1e40af`, `#fff`,
/// `rgb(30, 64, 175)`, `rgba(0 0 0 / 50%)`), or returns `null`.
Color? parseColor(String text) {
  final t = text.trim();
  if (t.length > 40) return null;
  final hex = _hex.firstMatch(t);
  if (hex != null) {
    var h = hex.group(1)!;
    if (h.length <= 4) h = h.split('').map((c) => '$c$c').join();
    // CSS puts alpha last; Flutter wants it first.
    final argb = h.length == 8 ? h.substring(6) + h.substring(0, 6) : 'ff$h';
    return Color(int.parse(argb, radix: 16));
  }
  final rgb = _rgb.firstMatch(t);
  if (rgb != null) {
    final c = [1, 2, 3].map((i) => int.parse(rgb.group(i)!)).toList();
    if (c.any((v) => v > 255)) return null;
    var a = 1.0;
    final alpha = rgb.group(4);
    if (alpha != null) {
      final pct = alpha.endsWith('%');
      final v = double.tryParse(
        pct ? alpha.substring(0, alpha.length - 1) : alpha,
      );
      if (v == null) return null;
      a = (pct ? v / 100 : v).clamp(0, 1).toDouble();
    }
    return Color.fromARGB((a * 255).round(), c[0], c[1], c[2]);
  }
  return null;
}

/// Splits [text] into alternating runs for highlighting every
/// case-insensitive occurrence of [query]. Each record says whether that
/// run matched.
List<(String, bool)> matchRuns(String text, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return [(text, false)];
  final lower = text.toLowerCase();
  // Lower-casing can change length for a few scripts; fall back to no
  // highlight rather than slicing at the wrong offsets.
  if (lower.length != text.length) return [(text, false)];
  final out = <(String, bool)>[];
  var from = 0;
  while (true) {
    final at = lower.indexOf(q, from);
    if (at < 0) break;
    if (at > from) out.add((text.substring(from, at), false));
    out.add((text.substring(at, at + q.length), true));
    from = at + q.length;
  }
  if (from < text.length) out.add((text.substring(from), false));
  return out;
}
