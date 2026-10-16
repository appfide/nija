import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:clipboard_watcher/clipboard_watcher.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:nija/core/logging.dart';
import 'package:nija/core/platform_info.dart';
import 'package:nija/platform/clipboard_hints.dart';
import 'package:nija_core/nija_core.dart';
import 'package:pasteboard/pasteboard.dart';
import 'package:uuid/uuid.dart';

/// What the clipboard currently holds, normalised.
class ClipboardSnapshot {
  /// Creates a snapshot.
  const ClipboardSnapshot({required this.type, required this.text, this.bytes});

  /// Payload kind.
  final ClipContentType type;

  /// Text content (empty for binary).
  final String text;

  /// Raw bytes for images.
  final Uint8List? bytes;
}

/// Outcome of a clipboard access check.
enum ClipboardAccess {
  /// Content was read.
  ok,

  /// Nothing on the clipboard; access itself is unknown.
  empty,

  /// Read failed or was denied.
  blocked,
}

/// Result of [ClipboardService.probe].
class ClipboardProbe {
  /// Creates a probe result.
  const ClipboardProbe(this.access, this.message);

  /// Outcome.
  final ClipboardAccess access;

  /// Human-readable detail.
  final String message;
}

/// Reads/writes the system clipboard and turns changes into [ClipItem]s.
///
/// * Desktop: `clipboard_watcher` fires on every change while the app runs in
///   the tray.
/// * Mobile: the OS blocks background reads, so [checkNow] runs on every
///   app resume and from the share/notification entry points.
///
/// Items this service itself wrote to the clipboard are remembered by hash so
/// they are not re-captured (echo suppression at the source).
///
/// Three filters run before anything is recorded: [paused] (nothing is
/// read at all), [skipSensitive] (OS "concealed / transient" hints from
/// password managers, checked *before* the read) and [skipSecretLike]
/// (text that matches credential patterns).
class ClipboardService with ClipboardListener, WidgetsBindingObserver {
  /// Creates a service; call [start].
  ClipboardService({
    required this.deviceId,
    required this.deviceName,
    required this.captureImages,
    required this.maxInlineBytes,
    this._paused = false,
    this.skipSensitive = true,
    this.skipSecretLike = false,
    this.skipUniversalClipboard = false,
  });

  /// This device (changes when a pairing code is adopted).
  String deviceId;

  /// Name stamped on captured items.
  String deviceName;

  /// Whether image payloads are captured.
  bool captureImages;

  /// Images larger than this are skipped.
  int maxInlineBytes;

  /// Honour OS sensitive-content hints.
  bool skipSensitive;

  /// Skip text that looks like a credential.
  bool skipSecretLike;

  /// Skip content that arrived from another Apple device through Universal
  /// Clipboard. Nija on that device syncs it under its own name; recording
  /// it here too would label it with this device's name, and the synced
  /// original would then be dropped as an echo.
  bool skipUniversalClipboard;

  bool _paused;

  /// Whether capture is paused. Resuming primes the last-seen hash so what
  /// was copied *while* paused is not recorded retroactively.
  bool get paused => _paused;
  set paused(bool value) {
    if (value == _paused) return;
    _paused = value;
    if (!value && _running) unawaited(_prime());
  }

  /// Reads the clipboard and records its hash without emitting.
  Future<void> _prime() async {
    try {
      final snap = await read();
      if (snap == null) return;
      _lastSeenHash = snap.bytes != null
          ? sha256HexBytes(snap.bytes!)
          : sha256Hex(snap.text);
    } catch (_) {
      // best effort
    }
  }

  final _captured = StreamController<ClipItem>.broadcast();
  String? _lastWrittenHash;
  String? _lastSeenHash;
  bool _running = false;
  bool _reading = false;

  /// Items captured from the clipboard.
  Stream<ClipItem> get captured => _captured.stream;

  /// Starts watching (desktop) or observing lifecycle (mobile).
  Future<void> start() async {
    if (_running) return;
    _running = true;
    WidgetsBinding.instance.addObserver(this);
    if (PlatformInfo.isDesktop) {
      try {
        clipboardWatcher.addListener(this);
        await clipboardWatcher.start();
      } on MissingPluginException catch (e) {
        log.w('clipboard watcher unavailable', error: e);
      }
      unawaited(checkNow());
    } else if (Platform.isAndroid) {
      // Android needs window focus first; read once the UI is up.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Future<void>.delayed(const Duration(seconds: 1), checkNow);
      });
    }
    // iOS: no read at launch. Its "Allow Paste?" alert is modal on the main
    // thread and would greet every cold start; capture happens on resume
    // (when the user has actually copied something) or via the Capture
    // button instead.
  }

  /// Stops watching.
  Future<void> stop() async {
    if (!_running) return;
    _running = false;
    WidgetsBinding.instance.removeObserver(this);
    if (PlatformInfo.isDesktop) {
      clipboardWatcher.removeListener(this);
      try {
        await clipboardWatcher.stop();
      } on MissingPluginException {
        // never started
      }
    }
  }

  /// Releases resources.
  Future<void> dispose() async {
    await stop();
    await _captured.close();
  }

  @override
  void onClipboardChanged() => unawaited(checkNow());

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_checkAfterResume());
  }

  /// Android 10+ only serves clipboard reads to the focused window, and focus
  /// lands a beat after `resumed`; iOS is similar. Wait briefly, then retry
  /// once if the first read came back empty.
  Future<void> _checkAfterResume() async {
    if (!PlatformInfo.isMobile) return checkNow();
    await Future<void>.delayed(const Duration(milliseconds: 400));
    final before = _lastSeenHash;
    await checkNow();
    if (_lastSeenHash == before) {
      await Future<void>.delayed(const Duration(milliseconds: 900));
      await checkNow();
    }
  }

  /// Reads the clipboard and emits a [ClipItem] if it changed.
  Future<void> checkNow() async {
    if (!_running || _reading || _paused) return;
    _reading = true;
    try {
      if (skipSensitive && await ClipboardHints.isSensitive()) {
        log.i('clipboard content flagged sensitive by its source, skipped');
        return;
      }
      if (skipUniversalClipboard && await ClipboardHints.isRemote()) {
        log.i('clipboard content came through Universal Clipboard, skipped');
        return;
      }
      final snap = await read();
      if (snap == null) return;
      final payload = snap.bytes != null
          ? base64Encode(snap.bytes!)
          : snap.text;
      if (payload.isEmpty) return;
      final hash = snap.bytes != null
          ? sha256HexBytes(snap.bytes!)
          : sha256Hex(snap.text);
      if (hash == _lastSeenHash) return;
      _lastSeenHash = hash;
      if (hash == _lastWrittenHash) return; // we put it there
      if (!snap.type.isBinary && PairingCodec.looksLikeCode(snap.text)) {
        log.i('pairing code on clipboard, never recorded');
        return;
      }
      if (skipSecretLike && !snap.type.isBinary && looksLikeSecret(snap.text)) {
        log.i('clipboard text looks like a credential, skipped');
        return;
      }
      final size = snap.bytes?.length ?? utf8.encode(snap.text).length;
      if (snap.type.isBinary && size > maxInlineBytes) {
        log.i('clipboard image ${size ~/ 1024} KB exceeds inline cap, skipped');
        return;
      }
      _captured.add(
        ClipItem.create(
          id: const Uuid().v4(),
          deviceId: deviceId,
          deviceName: deviceName,
          type: snap.type,
          content: payload,
          contentHash: hash,
          sizeBytes: size,
          now: DateTime.now().toUtc(),
        ),
      );
    } catch (e, st) {
      log
        ..w('clipboard read failed', error: e)
        ..d(st.toString());
    } finally {
      _reading = false;
    }
  }

  /// Reads the current clipboard without emitting.
  Future<ClipboardSnapshot?> read() async {
    if (Platform.isIOS && !captureImages && !(await Clipboard.hasStrings())) {
      return null; // avoids the iOS "Allow paste?" prompt for an empty board
    }
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text != null && text.isNotEmpty) {
      final uri = Uri.tryParse(text.trim());
      final isUrl =
          uri != null &&
          uri.hasScheme &&
          uri.host.isNotEmpty &&
          !text.trim().contains(RegExp(r'\s'));
      return ClipboardSnapshot(
        type: isUrl ? ClipContentType.url : ClipContentType.text,
        text: text,
      );
    }
    if (captureImages) {
      try {
        final img = await Pasteboard.image;
        if (img != null && img.isNotEmpty) {
          return ClipboardSnapshot(
            type: ClipContentType.image,
            text: '',
            bytes: img,
          );
        }
      } on MissingPluginException {
        // pasteboard not available on this platform build
      }
    }
    return null;
  }

  /// Checks whether the clipboard can be read right now. Used by the
  /// Permissions section in Settings.
  Future<ClipboardProbe> probe() async {
    try {
      final snap = await read();
      if (snap == null) {
        final hasText = await Clipboard.hasStrings();
        return hasText
            ? const ClipboardProbe(
                ClipboardAccess.blocked,
                'The clipboard has text but it could not be read. Check the permission for this platform below.',
              )
            : const ClipboardProbe(
                ClipboardAccess.empty,
                'Clipboard is empty. Copy some text and test again.',
              );
      }
      final what = snap.type.isBinary
          ? 'an image (${(snap.bytes!.length / 1024).toStringAsFixed(0)} KB)'
          : '${snap.text.length} characters of ${snap.type.wire}';
      return ClipboardProbe(ClipboardAccess.ok, 'Read $what successfully.');
    } on PlatformException catch (e) {
      return ClipboardProbe(
        ClipboardAccess.blocked,
        'Clipboard read failed: ${e.message ?? e.code}',
      );
    } on MissingPluginException {
      return const ClipboardProbe(
        ClipboardAccess.blocked,
        'Clipboard plugin unavailable in this build.',
      );
    }
  }

  /// Puts [text] on the clipboard without recording it (pairing codes).
  Future<void> writeText(String text) async {
    final hash = sha256Hex(text);
    _lastWrittenHash = hash;
    _lastSeenHash = hash;
    await Clipboard.setData(ClipboardData(text: text));
  }

  /// Puts [item] on the clipboard and suppresses the resulting echo.
  Future<void> write(ClipItem item) async {
    _lastWrittenHash = item.contentHash;
    _lastSeenHash = item.contentHash;
    if (item.type.isBinary) {
      await Pasteboard.writeImage(base64Decode(item.content));
    } else {
      await Clipboard.setData(ClipboardData(text: item.content));
    }
  }
}
