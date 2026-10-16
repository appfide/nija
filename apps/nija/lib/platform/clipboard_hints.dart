import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart';
import 'package:nija/core/logging.dart';
import 'package:win32/win32.dart';

/// Reads the "do not record this" hints that password managers attach to
/// clipboard content, so the app can honour them.
///
/// | Platform | Hint |
/// |---|---|
/// | macOS | `org.nspasteboard.ConcealedType` / `TransientType` pasteboard types (nspasteboard.org) |
/// | Windows | `ExcludeClipboardContentFromMonitorProcessing` clipboard format |
/// | Android 13+ | `ClipDescription.EXTRA_IS_SENSITIVE` |
/// | Linux, iOS | no standard hint: always `false` |
abstract final class ClipboardHints {
  static const MethodChannel _channel = MethodChannel(
    'com.appfide.nija/clipboard',
  );

  /// Whether the current clipboard content is flagged as sensitive or
  /// transient by the app that wrote it. Never throws.
  static Future<bool> isSensitive() async {
    try {
      if (Platform.isWindows) return _windows();
      if (Platform.isMacOS || Platform.isAndroid) {
        return await _channel.invokeMethod<bool>('isSensitive') ?? false;
      }
    } on MissingPluginException {
      // Native side not compiled in (tests, unsupported build).
    } on PlatformException catch (e) {
      log.d('clipboard hint check failed: ${e.message}');
    } catch (e) {
      log.d('clipboard hint check failed: $e');
    }
    return false;
  }

  /// Whether the current clipboard content came from another Apple device
  /// through Universal Clipboard (macOS and iOS mark it with the
  /// `com.apple.is-remote-clipboard` type). Never throws.
  static Future<bool> isRemote() async {
    try {
      if (Platform.isMacOS || Platform.isIOS) {
        return await _channel.invokeMethod<bool>('isRemote') ?? false;
      }
    } on MissingPluginException {
      // Native side not compiled in (tests, unsupported build).
    } on PlatformException catch (e) {
      log.d('universal clipboard check failed: ${e.message}');
    } catch (e) {
      log.d('universal clipboard check failed: $e');
    }
    return false;
  }

  static bool _windows() {
    final name = 'ExcludeClipboardContentFromMonitorProcessing'.toNativeUtf16();
    try {
      final format = RegisterClipboardFormat(PCWSTR(name)).value;
      if (format == 0) return false;
      return IsClipboardFormatAvailable(format).value;
    } finally {
      calloc.free(name);
    }
  }
}
