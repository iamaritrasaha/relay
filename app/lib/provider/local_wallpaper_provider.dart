import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:relay_app/provider/kdeconnect_provider.dart';
import 'package:relay_app/util/native/linux_wallpaper.dart';

/// Provides the local Linux PC wallpaper path asynchronously.
///
/// Fully decoupled from startup, KdeConnectStartAction, networking, and device state.
final localWallpaperProvider = NotifierProvider<LocalWallpaperService, String?>(
  (ref) => LocalWallpaperService(),
  debugLabel: 'localWallpaperProvider',
);

class LocalWallpaperService extends Notifier<String?> {
  bool _fetching = false;

  @override
  String? init() => null;

  /// Trigger asynchronous wallpaper discovery in the background.
  Future<void> fetchWallpaper({bool ignoreTestGate = false}) async {
    if (_fetching || !Platform.isLinux) return;
    if (!ignoreTestGate && Platform.environment.containsKey('FLUTTER_TEST')) return;
    _fetching = true;

    try {
      final path = await LinuxWallpaperService.discoverLocalWallpaper();
      if (path != null && path != state) {
        state = path;
        _syncToConnectedPeers();
      }
    } catch (_) {
      // Failure is invisible: state remains null / fallback gradient
    } finally {
      _fetching = false;
    }
  }

  /// Sets wallpaper path directly (useful for tests and user selection).
  void setWallpaperPath(String? path) {
    if (state != path) {
      state = path;
      _syncToConnectedPeers();
    }
  }

  void _syncToConnectedPeers() {
    try {
      final kdeState = ref.read(kdeConnectProvider);
      for (final device in kdeState.devices) {
        if (device.connected && device.paired && device.incomingCapabilities.contains('kdeconnect.relay.wallpaper')) {
          unawaited(ref.redux(kdeConnectProvider).dispatchAsync(KdeConnectSyncWallpaperAction(device.deviceId)));
        }
      }
    } catch (_) {}
  }

  /// Returns a [FileImage] provider if a valid local wallpaper is available, or null.
  ImageProvider? getImageProvider() {
    final current = state;
    if (current == null) return null;
    try {
      final file = File(current);
      if (file.existsSync()) {
        return FileImage(file);
      }
    } catch (_) {}
    return null;
  }
}
