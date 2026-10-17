import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:nija_core/src/crypto/device_keys.dart';
import 'package:nija_core/src/pairing/pairing_payload.dart';

/// What the admin device publishes about the group's admin key, so other
/// devices can follow a change of that key without trusting the database.
///
/// It lives in the `admin_envelope` field of the admin's own device row,
/// which is otherwise empty there: that field carries a sealed admin key
/// only on the row of a device being made admin. The row is signed by the
/// current admin key like every other membership field.
///
/// * [links] prove a planned change: each is signed by the key it
///   replaces, so a device that trusts any earlier key can follow the
///   chain to the current one.
/// * [code] lets a device that cannot follow the chain (the old key was
///   lost) check the new key against an 8-digit code shown on the admin
///   device.
class AdminNotice {
  /// Creates a notice.
  const AdminNotice({this.links = const [], this.code});

  /// Prefix that tells a notice from a sealed admin key.
  static const String prefix = 'NOTICE1.';

  /// Links kept: enough for a device that missed several changes.
  static const int maxLinks = 8;

  /// Planned changes, oldest first.
  final List<AdminLink> links;

  /// One-time code currently offered, if any.
  final AdminCode? code;

  /// Copy with [link] appended (dropping the oldest beyond [maxLinks]).
  AdminNotice withLink(AdminLink link) {
    final all = [...links, link];
    return AdminNotice(
      links: all.length > maxLinks ? all.sublist(all.length - maxLinks) : all,
      code: code,
    );
  }

  /// Copy offering [code], or none.
  AdminNotice withCode(AdminCode? code) =>
      AdminNotice(links: links, code: code);

  /// Whether [links] lead from [trusted] to [current], every step signed
  /// by the key it replaces.
  Future<bool> leadsFrom(String trusted, String current) async {
    var at = trusted;
    for (var hops = 0; hops < maxLinks && at != current; hops++) {
      final next = links.where((l) => l.from == at).lastOrNull;
      if (next == null || !await next.verify()) return false;
      at = next.to;
    }
    return at == current;
  }

  /// Stored form.
  String encode() =>
      '$prefix${base64Url.encode(utf8.encode(jsonEncode({
        'links': [for (final l in links) l.toJson()],
        if (code != null) 'code': code!.toJson(),
      })))}';

  /// Parses a stored notice; `null` for anything else (a sealed admin key,
  /// an empty field, a damaged value).
  static AdminNotice? tryDecode(String? stored) {
    if (stored == null || !stored.startsWith(prefix)) return null;
    try {
      final m = Map<String, Object?>.from(
        jsonDecode(
              utf8.decode(
                base64Url.decode(_pad(stored.substring(prefix.length))),
              ),
            )
            as Map,
      );
      final code = m['code'];
      return AdminNotice(
        links: [
          for (final l in (m['links'] as List? ?? const []))
            AdminLink.fromJson(Map<String, Object?>.from(l as Map)),
        ],
        code: code == null
            ? null
            : AdminCode.fromJson(Map<String, Object?>.from(code as Map)),
      );
    } catch (_) {
      return null;
    }
  }
}

/// One planned change of admin key, signed by the key it replaces.
class AdminLink {
  /// Creates a link.
  const AdminLink({required this.from, required this.to, required this.sig});

  /// Parses [toJson] output.
  factory AdminLink.fromJson(Map<String, Object?> m) => AdminLink(
    from: m['from']! as String,
    to: m['to']! as String,
    sig: m['sig']! as String,
  );

  /// Signs the change from [from] to [to].
  static Future<AdminLink> create(AdminKey from, String to) async => AdminLink(
    from: from.publicKey,
    to: to,
    sig: await from.sign(_bytes(from.publicKey, to)),
  );

  /// Replaced key.
  final String from;

  /// New key.
  final String to;

  /// Signature by [from].
  final String sig;

  /// Whether [from] signed this link.
  Future<bool> verify() =>
      DeviceKeys.verify(_bytes(from, to), signature: sig, publicKey: from);

  /// JSON form.
  Map<String, Object?> toJson() => {'from': from, 'to': to, 'sig': sig};

  static List<int> _bytes(String from, String to) =>
      utf8.encode('nija-admin-rollover-v1|$from|$to');
}

/// The admin public key sealed under an 8-digit code, for [validFor].
///
/// The code is shown only on the admin device. Someone who can write to
/// the database can replace this with their own, but cannot make it open
/// with the code the user reads off their admin device; trying every code
/// against a copy takes one Argon2id derivation each, about a second.
class AdminCode {
  /// Creates a sealed code.
  const AdminCode({
    required this.salt,
    required this.nonce,
    required this.box,
    required this.until,
  });

  /// Parses [toJson] output.
  factory AdminCode.fromJson(Map<String, Object?> m) => AdminCode(
    salt: m['s']! as String,
    nonce: m['n']! as String,
    box: m['c']! as String,
    until: DateTime.parse(m['until']! as String).toUtc(),
  );

  /// How long a code stays valid.
  static const Duration validFor = Duration(minutes: 10);

  static final AesGcm _aes = AesGcm.with256bits();
  static final Random _random = Random.secure();
  static const String _domain = 'nija-admin-code-v1|';

  /// Random salt, base64url.
  final String salt;

  /// AES-GCM nonce, base64url.
  final String nonce;

  /// Ciphertext and tag, base64url.
  final String box;

  /// End of validity.
  final DateTime until;

  /// Seals [adminPub] under [pin] until [until].
  static Future<AdminCode> seal(
    String adminPub,
    String pin, {
    required DateTime until,
  }) async {
    final salt = Uint8List.fromList(
      List.generate(16, (_) => _random.nextInt(256)),
    );
    final key = await pinKey(pin, salt, domain: _domain);
    final until0 = until.toUtc();
    final out = await _aes.encrypt(
      utf8.encode(adminPub),
      secretKey: key,
      aad: utf8.encode('$_domain${until0.toIso8601String()}'),
    );
    return AdminCode(
      salt: base64Url.encode(salt),
      nonce: base64Url.encode(out.nonce),
      box: base64Url.encode([...out.cipherText, ...out.mac.bytes]),
      until: until0,
    );
  }

  /// The admin public key, when [pin] is right and the code has not
  /// expired at [now]; otherwise `null`.
  Future<String?> open(String pin, {required DateTime now}) async {
    if (!now.toUtc().isBefore(until)) return null;
    try {
      final blob = base64Url.decode(_pad(box));
      final key = await pinKey(
        pin.replaceAll(RegExp(r'\s'), ''),
        base64Url.decode(_pad(salt)),
        domain: _domain,
      );
      final clear = await _aes.decrypt(
        SecretBox(
          blob.sublist(0, blob.length - 16),
          nonce: base64Url.decode(_pad(nonce)),
          mac: Mac(blob.sublist(blob.length - 16)),
        ),
        secretKey: key,
        aad: utf8.encode('$_domain${until.toIso8601String()}'),
      );
      return utf8.decode(clear);
    } catch (_) {
      return null;
    }
  }

  /// JSON form.
  Map<String, Object?> toJson() => {
    's': salt,
    'n': nonce,
    'c': box,
    'until': until.toIso8601String(),
  };
}

String _pad(String b64) => b64.length % 4 == 0
    ? b64
    : b64.padRight(b64.length + (4 - b64.length % 4), '=');
