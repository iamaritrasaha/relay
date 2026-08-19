import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:logging/logging.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:relay_app/model/ui/relay_device_vm.dart';
import 'package:relay_app/model/ui/relay_phone_shell_status.dart';
import 'package:relay_app/pages/relay_home_vm.dart';
import 'package:relay_app/provider/kdeconnect_provider.dart';
import 'package:relay_app/util/native/tray_helper.dart';

final _logger = Logger('RelayShellStatus');

const MethodChannel _channel = MethodChannel('com.foresight.app.relay/relay_shell_status');

const String _methodPublish = 'relayShellStatusPublish';
const String _methodActivate = 'relayShellActivate';
const String _methodQuit = 'relayShellQuit';
const String _methodFindPhone = 'relayShellFindPhone';
const String _methodSurfaceChanged = 'relayShellSurfaceChanged';
const String _methodSurfaceQuery = 'relayShellSurfaceQuery';

/// Prefix Relay's device keys carry for KDE Connect targets.
const String _kdeConnectKeyPrefix = 'kdeconnect:';

/// Publishes Relay's primary-phone status to the desktop shell.
///
/// The shell never talks to KDE Connect, LocalSend or Relay's own transports.
/// It sees one sanitized snapshot derived from the same canonical device model
/// the app renders, pushed only when that state actually changes, and it can
/// ask Relay to perform a small set of actions it already implements.
///
/// Nothing here polls: the bridge listens to Relay's device state and forwards
/// changes, so an idle Relay produces no shell traffic at all.
class RelayShellStatusBridge {
  final Future<void> Function(Map<String, Object?>? snapshot) _publish;
  final Future<void> Function() _activate;
  final Future<void> Function() _quit;
  final Future<void> Function(String deviceId) _findPhone;
  final Future<void> Function(bool attached) _shellSurfaceChanged;
  final DateTime Function() _now;

  final List<StreamSubscription<void>> _subscriptions = [];
  RelayPhoneShellStatus? _published;
  bool _hasPublished = false;

  List<RelayDeviceVm> _devices = const [];
  Map<String, int> _notificationCounts = const {};

  RelayShellStatusBridge({
    required Future<void> Function(Map<String, Object?>? snapshot) publish,
    required Future<void> Function() activate,
    required Future<void> Function() quit,
    required Future<void> Function(String deviceId) findPhone,
    required Future<void> Function(bool attached) shellSurfaceChanged,
    DateTime Function() now = DateTime.now,
  }) : _publish = publish,
       _activate = activate,
       _quit = quit,
       _findPhone = findPhone,
       _shellSurfaceChanged = shellSurfaceChanged,
       _now = now;

  /// The snapshot most recently handed to the platform bridge.
  @visibleForTesting
  RelayPhoneShellStatus? get published => _published;

  /// Recomputes the snapshot and pushes it only when it differs.
  ///
  /// Transfer progress and discovery churn constantly rebuild the device list
  /// while describing the very same phone, so identical snapshots are dropped
  /// here rather than being turned into shell repaints.
  Future<void> apply({List<RelayDeviceVm>? devices, Map<String, int>? notificationCounts}) async {
    _devices = devices ?? _devices;
    _notificationCounts = notificationCounts ?? _notificationCounts;

    final next = RelayPhoneShellStatus.select(
      devices: _devices,
      now: _now(),
      preferredDeviceId: _published?.deviceId,
      notificationCounts: _notificationCounts,
    );
    if (_hasPublished && (next == null) == (_published == null) && (next == null || next.sameStateAs(_published))) {
      return;
    }
    _published = next;
    _hasPublished = true;
    try {
      await _publish(next?.toBridgeMap());
    } catch (e) {
      _logger.fine('Publishing shell status failed', e);
    }
  }

  /// Runs an action the shell asked for, addressed by the phone it is showing.
  ///
  /// A stale device id — the shell acting on a phone Relay has since dropped —
  /// is ignored rather than dispatched blindly.
  Future<void> handleAction(String method, Object? argument) async {
    switch (method) {
      case _methodActivate:
        await _activate();
      case _methodQuit:
        await _quit();
      case _methodSurfaceChanged:
        await _shellSurfaceChanged(argument == true);
      case _methodFindPhone:
        final current = _published;
        final deviceId = argument is String ? argument : null;
        if (current == null || deviceId == null || current.deviceId != deviceId || !current.supportsFindDevice) {
          return;
        }
        await _findPhone(deviceId);
      default:
        return;
    }
  }

  void attachTo({required Stream<List<RelayDeviceVm>> devices, required Stream<Map<String, int>> notificationCounts}) {
    unawaited(dispose());
    _subscriptions.add(
      devices.listen(
        (list) => unawaited(apply(devices: list)),
        onError: (Object error, StackTrace stack) => _logger.fine('Relay device stream failed', error, stack),
      ),
    );
    _subscriptions.add(
      notificationCounts.listen(
        (counts) => unawaited(apply(notificationCounts: counts)),
        onError: (Object error, StackTrace stack) => _logger.fine('Relay notification stream failed', error, stack),
      ),
    );
  }

  Future<void> dispose() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
  }
}

/// How many notifications each phone is currently mirroring, by device key.
///
/// Only the count crosses into the shell layer. Titles, bodies and senders stay
/// inside Relay.
Map<String, int> relayNotificationCounts(Map<String, List<Object?>> notifications) => {
  for (final entry in notifications.entries) '$_kdeConnectKeyPrefix${entry.key}': entry.value.length,
};

/// Reads the platform-side ShellSurface watch before Relay creates its tray.
///
/// The native runner starts watching as soon as the Flutter engine exists, so
/// this query is authoritative even when the extension appeared before Dart's
/// method handler was installed. Failure safely falls back to the normal tray.
Future<bool> isRelayShellSurfaceAttached() async {
  if (defaultTargetPlatform != TargetPlatform.linux) {
    return false;
  }
  try {
    return await _channel.invokeMethod<bool>(_methodSurfaceQuery) ?? false;
  } catch (e) {
    _logger.fine('Querying the initial shell surface failed', e);
    return false;
  }
}

/// Starts the minimal surface/tray handler needed during early application
/// bootstrap, before Refena and the full phone-status bridge exist.
///
/// Installing the handler before querying closes the appear-between-query-and-
/// tray-create race. [startRelayShellStatusBridge] later replaces this handler
/// and immediately re-queries the native cached state, so the handoff is also
/// authoritative.
Future<bool> prepareRelayShellSurfaceTraySync() async {
  if (defaultTargetPlatform != TargetPlatform.linux) {
    return false;
  }
  _channel.setMethodCallHandler((call) async {
    if (call.method == _methodSurfaceChanged) {
      if (call.arguments == true) {
        await hideTrayIcon();
      } else {
        await restoreTrayIcon();
      }
    }
    return null;
  });
  return isRelayShellSurfaceAttached();
}

/// Starts the shell status bridge for the current desktop session.
///
/// Failure is never fatal: a desktop without the bridge simply has no shell
/// surface, which must not stop Relay from running.
Future<RelayShellStatusBridge?> startRelayShellStatusBridge(Ref ref) async {
  if (defaultTargetPlatform != TargetPlatform.linux) {
    return null;
  }

  final bridge = RelayShellStatusBridge(
    publish: (snapshot) => _channel.invokeMethod<void>(_methodPublish, snapshot),
    activate: showFromTray,
    quit: () async {
      await destroyTray();
      exit(0);
    },
    findPhone: (deviceId) async {
      // The shell addresses the phone by Relay's device key, which carries the
      // transport prefix the KDE Connect runtime does not use.
      if (!deviceId.startsWith(_kdeConnectKeyPrefix)) {
        return;
      }
      await ref.redux(kdeConnectProvider).dispatchAsync(KdeConnectFindPhoneAction(deviceId.substring(_kdeConnectKeyPrefix.length)));
    },
    // A shell surface presents everything Relay's tray icon does and more, so
    // Relay steps out of the notification area while one is attached rather
    // than sitting in the panel twice.
    shellSurfaceChanged: (attached) => attached ? hideTrayIcon() : restoreTrayIcon(),
  );

  _channel.setMethodCallHandler((call) async {
    try {
      await bridge.handleAction(call.method, call.arguments);
    } catch (e, stack) {
      _logger.warning('Shell action ${call.method} failed', e, stack);
    }
    return null;
  });

  // The platform side may have noticed a shell surface before this handler
  // existed, so the current answer is asked for rather than waited for.
  try {
    await bridge.handleAction(_methodSurfaceChanged, await _channel.invokeMethod<bool>(_methodSurfaceQuery));
  } catch (e) {
    _logger.fine('Querying the shell surface failed', e);
  }

  bridge.attachTo(
    devices: ref.stream(relayHomeVmProvider).map((event) => event.next.devices),
    notificationCounts: ref.stream(kdeConnectProvider).map((event) => relayNotificationCounts(event.next.notifications)),
  );
  await bridge.apply(
    devices: ref.read(relayHomeVmProvider).devices,
    notificationCounts: relayNotificationCounts(ref.read(kdeConnectProvider).notifications),
  );
  return bridge;
}
