import 'dart:convert';

import 'package:nija_core/src/crypto/device_keys.dart';
import 'package:nija_core/src/model/clip_item.dart';
import 'package:nija_core/src/model/device.dart';

/// Canonical byte strings and sign / verify helpers for clips and device
/// membership.
///
/// Canonical form is JSON with keys in a fixed order and no whitespace, so
/// every backend (which may reorder or retype fields) round-trips to the
/// same bytes.
abstract final class ClipSigning {
  /// Bytes a device signs for one clip: the *stored* form (ciphertext when
  /// encrypted), so the signature is checked before decryption.
  static List<int> itemBytes(ClipItem i) => utf8.encode(
    jsonEncode(<String, Object?>{
      'v': 1,
      'id': i.id,
      'device_id': i.deviceId,
      'content_type': i.type.wire,
      'content': i.content,
      'blob_ref': i.blobRef,
      'content_hash': i.contentHash,
      'size_bytes': i.sizeBytes,
      'encrypted': i.encrypted,
      'nonce': i.nonce,
      'created_at': i.createdAt.toUtc().toIso8601String(),
      'updated_at': i.updatedAt.toUtc().toIso8601String(),
      'deleted_at': i.deletedAt?.toUtc().toIso8601String(),
      'target_device_id': i.targetDeviceId,
      'key_version': i.keyVersion,
    }),
  );

  /// [t] at millisecond precision. PocketBase and MongoDB keep only
  /// milliseconds, so a signature over microseconds never verifies once
  /// the row comes back from them. Every signed time is cut to that first.
  static DateTime _ms(DateTime t) => DateTime.fromMillisecondsSinceEpoch(
    t.millisecondsSinceEpoch,
    isUtc: true,
  );

  /// Signs [item] with [keys]. Returns the item as it must be stored: its
  /// times at millisecond precision, with the signature.
  static Future<ClipItem> signItem(ClipItem item, DeviceKeys keys) async {
    final deleted = item.deletedAt;
    final i = item.copyWith(
      createdAt: _ms(item.createdAt),
      updatedAt: _ms(item.updatedAt),
      deletedAt: deleted == null ? null : _ms(deleted),
    );
    return i.copyWith(sig: await keys.sign(itemBytes(i)));
  }

  /// Verifies [item]'s signature against [signPub] (base64).
  static Future<bool> verifyItem(ClipItem item, String signPub) async {
    final sig = item.sig;
    if (sig == null) return false;
    return DeviceKeys.verify(
      itemBytes(item),
      signature: sig,
      publicKey: signPub,
    );
  }

  /// Bytes the admin signs for one device row: everything that decides
  /// what the device may do and which keys speak for it. Presence fields
  /// are excluded so heartbeats never invalidate the signature.
  static List<int> membershipBytes(Device d) => utf8.encode(
    jsonEncode(<String, Object?>{
      'v': 1,
      'id': d.id,
      'status': d.status.wire,
      'role': d.role.wire,
      'expires_at': d.expiresAt?.toUtc().toIso8601String(),
      'sign_pub': d.signPub,
      'box_pub': d.boxPub,
      'admin': d.admin,
      'admin_pub': d.adminPub,
      'membership_version': d.membershipVersion,
      'key_version': d.keyVersion,
      'key_envelope': d.keyEnvelope,
      // Added in 0.5. Present only when set, so rows signed before then
      // still verify.
      if (d.permissionNames.isNotEmpty)
        'permissions': DevicePermission.encode(d.permissionNames),
      if (d.adminEnvelope != null) 'admin_envelope': d.adminEnvelope,
    }),
  );

  /// Bumps the version, stamps [admin]'s public key and signs [device].
  static Future<Device> signMembership(Device device, AdminKey admin) async {
    final expires = device.expiresAt;
    final d = device.copyWith(
      expiresAt: expires == null ? null : _ms(expires),
      adminPub: admin.publicKey,
      membershipVersion: device.membershipVersion + 1,
    );
    return d.copyWith(membershipSig: await admin.sign(membershipBytes(d)));
  }

  /// Whether [device]'s membership was signed by [adminPub] (base64).
  static Future<bool> verifyMembership(Device device, String adminPub) async {
    final sig = device.membershipSig;
    if (sig == null || device.adminPub != adminPub) return false;
    return DeviceKeys.verify(
      membershipBytes(device),
      signature: sig,
      publicKey: adminPub,
    );
  }
}
