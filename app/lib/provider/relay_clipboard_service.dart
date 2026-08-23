import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:logging/logging.dart';

final _logger = Logger('RelayClipboard');

const MethodChannel _channel = MethodChannel('com.foresight.app.relay/clipboard');

/// Largest clipboard text Relay will move, in UTF-8 bytes.
///
/// Mirrors `relay_core`'s `MAX_CLIPBOARD_BYTES`; the same bound is also enforced
/// natively and in Rust, so no single layer is load-bearing for it.
const int maxClipboardBytes = 64 * 1024;

/// Watches the Linux clipboard and applies remote clipboard values to it.
///
/// Clipboard access goes through GTK (see `linux/relay_clipboard_channel.cc`),
/// which is backed by the Wayland data-device protocol on a Wayland session —
/// so this works on Wayland without shelling out to `wl-copy`, `xclip` or
/// `xsel`, none of which are involved anywhere in this path.
///
/// # Platform limitation (measured, not assumed)
///
/// On a GNOME **Wayland** session a background application can neither observe
/// nor read the clipboard: `wl_data_device` offers go only to the focused
/// client, and GNOME does not implement `wlr-data-control`. Verified directly on
/// this platform — a minimal GTK watcher saw zero `owner-change` events for an
/// external copy, and an unfocused `wait_for_text()` returned null.
///
/// So automatic Desktop -> phone sync is **not** available in the background on
/// GNOME Wayland; it works while Relay has focus, and on X11/Xwayland sessions
/// where selections are not focus-gated. This mirrors the Android 10+
/// restriction in the other direction, and for the same privacy reason.
/// [autoSyncAvailable] reports which case applies rather than guessing.
///
/// Loop suppression deliberately does *not* live here. GTK's `owner-change`
/// signal fires for Relay's own writes too, and only `relay_core` can see both
/// directions at once, so this service reports every change and lets the core
/// decide. Content is never logged — only lengths.
class RelayClipboardService {
  final TargetPlatform targetPlatform;

  /// Invoked when the local clipboard changes. The callback decides whether the
  /// value is worth sending; this service makes no such judgement.
  final Future<void> Function(String text)? onLocalChange;

  bool _watching = false;

  RelayClipboardService({TargetPlatform? platform, this.onLocalChange})
    : targetPlatform = platform ?? defaultTargetPlatform {
    _channel.setMethodCallHandler(_handleMethodCall);
  }

  bool get isSupported => targetPlatform == TargetPlatform.linux;

  /// Whether unattended clipboard observation is possible in this session.
  ///
  /// False on Wayland, where only the focused client receives clipboard offers.
  /// Reported so the UI can describe what actually happens instead of implying
  /// background sync that the compositor will never deliver.
  bool get autoSyncAvailable {
    if (!isSupported) return false;
    final sessionType = _environment['XDG_SESSION_TYPE']?.toLowerCase();
    return sessionType != 'wayland';
  }

  /// Overridable for tests.
  Map<String, String> get _environment => environmentOverride ?? Platform.environment;

  /// Test seam for [autoSyncAvailable].
  Map<String, String>? environmentOverride;

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    if (call.method != 'clipboardChanged') return null;
    final text = call.arguments is Map ? (call.arguments as Map)['text'] as String? : null;
    if (text == null || text.isEmpty) return null;
    if (text.length > maxClipboardBytes) {
      _logger.fine('[Relay Clipboard] local change ignored, ${text.length} bytes');
      return null;
    }
    try {
      await onLocalChange?.call(text);
    } catch (error, stack) {
      _logger.warning('[Relay Clipboard] local change handler failed', error, stack);
    }
    return null;
  }

  /// Begins reporting local clipboard changes.
  Future<void> start() async {
    if (!isSupported || _watching) return;
    try {
      await _channel.invokeMethod('startWatching');
      _watching = true;
    } catch (error, stack) {
      _logger.fine('[Relay Clipboard] could not start watching', error, stack);
    }
  }

  Future<void> stop() async {
    if (!isSupported || !_watching) return;
    try {
      await _channel.invokeMethod('stopWatching');
    } catch (error, stack) {
      _logger.fine('[Relay Clipboard] could not stop watching', error, stack);
    }
    _watching = false;
  }

  /// Writes [text] to the local clipboard.
  ///
  /// Refuses empty or oversized text rather than truncating: a partial paste is
  /// worse than none, and an empty write would destroy what the user had.
  Future<bool> applyRemote(String text) async {
    if (!isSupported) return false;
    if (text.isEmpty || text.length > maxClipboardBytes) {
      _logger.fine('[Relay Clipboard] refused a remote value of ${text.length} bytes');
      return false;
    }
    try {
      await _channel.invokeMethod('setText', {'text': text});
      return true;
    } catch (error, stack) {
      _logger.warning('[Relay Clipboard] could not apply a remote value', error, stack);
      return false;
    }
  }

  /// The current clipboard text, or null when empty/unavailable.
  Future<String?> currentText() async {
    if (!isSupported) return null;
    try {
      return await _channel.invokeMethod<String>('getText');
    } catch (error, stack) {
      _logger.fine('[Relay Clipboard] could not read the clipboard', error, stack);
      return null;
    }
  }
}
