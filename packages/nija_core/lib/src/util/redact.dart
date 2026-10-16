/// Masks credentials before they reach logs or bug reports.
///
/// Applied to every log line and to the diagnostics export in the app.
String redactSecrets(String input) {
  var out = input;
  for (final re in _patterns) {
    out = out.replaceAllMapped(re, (m) => _mask(m.group(0)!));
  }
  return out;
}

/// Whether [text] looks like a credential (API key, token, private key,
/// connection string with a password…). Used by the capture filter so such
/// clips never leave the device; deliberately conservative, plain prose is
/// never flagged.
bool looksLikeSecret(String text) {
  if (text.length > 64 * 1024) return false;
  if (_pemKey.hasMatch(text)) return true;
  for (final re in _patterns) {
    if (re.hasMatch(text)) return true;
  }
  return false;
}

final RegExp _pemKey = RegExp('-----BEGIN [A-Z ]*PRIVATE KEY-----');

String _mask(String s) {
  if (s.length <= 8) return '***';
  return '${s.substring(0, 4)}…${s.substring(s.length - 2)}';
}

final List<RegExp> _patterns = <RegExp>[
  // JWTs (Supabase legacy keys, Firebase id tokens, PocketBase tokens).
  RegExp(r'eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}'),
  // Supabase new-style keys and personal access tokens.
  RegExp('sb_(publishable|secret)_[A-Za-z0-9_-]{20,}'),
  RegExp('sbp_[A-Za-z0-9]{20,}'),
  // Google / Firebase API keys.
  RegExp('AIza[0-9A-Za-z_-]{35}'),
  // AWS access key ids, GitHub tokens, Slack tokens, `sk-` style API keys.
  RegExp('AKIA[0-9A-Z]{16}'),
  RegExp('gh[pousr]_[A-Za-z0-9]{36,}'),
  RegExp('xox[baprs]-[A-Za-z0-9-]{10,}'),
  RegExp(r'\bsk-[A-Za-z0-9_-]{20,}'),
  // Credentials embedded in URLs (mongodb://u:p@, https://u:p@couch).
  RegExp(r'(?<=://)[^\s:/@]+:[^\s@]+(?=@)'),
  // Bearer / Basic auth headers.
  RegExp('(?<=(Bearer|Basic) )[A-Za-z0-9+/=_.-]{8,}'),
  // Generic key=value secrets.
  RegExp(
    r'(?<=(password|passwd|secret|token|api[_-]?key|anon[_-]?key)["\s]*[:=]["\s]*)[^\s"&,]{4,}',
    caseSensitive: false,
  ),
];
