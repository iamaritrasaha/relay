import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:logging/logging.dart';
import 'package:relay_app/provider/kdeconnect_provider.dart';
import 'package:relay_app/util/native/tray_helper.dart';
import 'package:relay_isolates/rust/api/kdeconnect.dart';

final _logger = Logger('RelayDesktopNotification');

const MethodChannel _channel = MethodChannel('com.foresight.app.relay/desktop_notifications');

/// Mirrors notifications from connected phones as native GNOME desktop notifications.
///
/// Ensures:
/// 1. Initial snapshot on connect does NOT spam desktop notifications (initial sync suppression).
/// 2. New live notifications trigger exactly one native desktop notification.
/// 3. Updates to existing notification IDs replace rather than duplicate.
/// 4. Dismissed/cancelled notifications on phone are withdrawn from desktop.
/// 5. Privacy: No notification bodies or private contents are ever logged.
/// 6. Every banner is attributed to the phone that produced it, and every
///    notification is tracked by `(deviceId, notificationId)` -- two phones may
///    legitimately use the same remote notification id.
class RelayDesktopNotificationService {
  final TargetPlatform targetPlatform;
  final Map<String, Set<String>> _seenIds = {};
  final Map<String, RsKdeNotification> _knownNotifications = {};
  StreamSubscription<void>? _subscription;

  /// Devices whose first snapshot has already been absorbed.
  ///
  /// Initial-sync suppression is *per device*, not global. A single flag meant
  /// only the first device to connect had its backlog absorbed silently; every
  /// device that connected afterwards had its entire existing notification list
  /// treated as brand new and fired as desktop toasts.
  final Set<String> _syncedDevices = {};

  /// Invoked when the user activates a banner, with the logical device that
  /// produced the notification and that device's own notification id. Actions
  /// are always routed back to the originating device -- never to whichever
  /// device happens to be focused.
  final void Function(String deviceId, String notificationId)? onActivated;

  RelayDesktopNotificationService({
    TargetPlatform? platform,
    this.onActivated,
  }) : targetPlatform = platform ?? defaultTargetPlatform {
    _channel.setMethodCallHandler((call) async {
      try {
        if (call.method == 'notificationActivated') {
          final id = call.arguments is Map ? (call.arguments as Map)['id'] as String? : null;
          _logger.fine('[Relay Notification] id=$id op=activated');
          final origin = splitNotificationKey(id);
          if (origin != null) {
            onActivated?.call(origin.deviceId, origin.notificationId);
          }
          await showFromTray();
        }
      } catch (e, stack) {
        _logger.warning('Notification action ${call.method} failed', e, stack);
      }
      return null;
    });
  }

  void start(Stream<List<RelayNotificationRecord>> notificationsStream) {
    unawaited(_subscription?.cancel());
    _subscription = notificationsStream.listen(
      (records) {
        _processNotifications(records);
      },
      onError: (Object error, StackTrace stack) => _logger.fine('Relay notification stream failed', error, stack),
    );
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
  }

  void _processNotifications(List<RelayNotificationRecord> records) {
    // Regroup by owning device. The records already carry device identity, so
    // grouping here can never merge two phones' notifications together even
    // when they share a remote notification id.
    final notifications = <String, List<RelayNotificationRecord>>{};
    for (final record in records) {
      (notifications[record.deviceId] ??= []).add(record);
    }

    final newKnownNotifications = <String, RsKdeNotification>{};
    final newSeenIds = <String, Set<String>>{};

    for (final entry in notifications.entries) {
      final deviceId = entry.key;
      final currentList = entry.value;
      final currentIds = currentList.map((e) => e.notificationId).toSet();
      newSeenIds[deviceId] = currentIds;

      // A device Relay has not seen before is delivering its backlog, not new
      // events -- absorb it silently. This is decided per device, so a phone
      // connecting later never replays as toasts, and never suppresses another
      // device's genuinely new notifications either.
      if (_syncedDevices.add(deviceId)) {
        for (final n in currentList) {
          newKnownNotifications[n.key] = n.notification;
        }
        _logger.fine('[Relay Notification] device sync complete count=${currentIds.length}');
        continue;
      }

      final previousIds = _seenIds[deviceId] ?? {};

      for (final n in currentList) {
        final fullId = n.key;
        newKnownNotifications[fullId] = n.notification;

        final isNew = !previousIds.contains(n.notificationId);
        final previousN = _knownNotifications[fullId];
        final isChanged = previousN != null && (previousN.title != n.title || previousN.text != n.text || previousN.appName != n.appName);

        if (isNew) {
          _logger.fine('[Relay Notification] id=$fullId op=new native=true count=${newKnownNotifications.length}');
          _showNotification(fullId, n);
        } else if (isChanged) {
          _logger.fine('[Relay Notification] id=$fullId op=update native=true count=${newKnownNotifications.length}');
          _showNotification(fullId, n);
        }
      }

      for (final oldId in previousIds) {
        if (!currentIds.contains(oldId)) {
          final fullId = '$deviceId:$oldId';
          _logger.fine('[Relay Notification] id=$fullId op=withdraw count=${newKnownNotifications.length}');
          _withdrawNotification(fullId);
        }
      }
    }

    // A device that disappeared from the map entirely: withdraw only *its*
    // toasts. Another device's records are never touched here.
    for (final deviceId in _seenIds.keys.toList()) {
      if (!notifications.containsKey(deviceId)) {
        for (final oldId in _seenIds[deviceId]!) {
          final fullId = '$deviceId:$oldId';
          _logger.fine('[Relay Notification] id=$fullId op=withdraw deviceRemoved=true');
          _withdrawNotification(fullId);
        }
        // Forget the sync marker too, so if it comes back its backlog is
        // absorbed silently rather than replayed as toasts.
        _syncedDevices.remove(deviceId);
      }
    }

    _seenIds.clear();
    _seenIds.addAll(newSeenIds);
    _knownNotifications.clear();
    _knownNotifications.addAll(newKnownNotifications);
  }

  void _showNotification(String id, RelayNotificationRecord n) {
    if (targetPlatform != TargetPlatform.linux) return;
    unawaited(
      _channel
          .invokeMethod('showNotification', {
            'id': id,
            'appName': n.appName,
            'title': n.title,
            'body': n.text,
            // The native banner renders "Relay · <deviceName>", which is the
            // only thing distinguishing two phones that both forwarded, say, a
            // WhatsApp message. Without it every banner reads identically and
            // the notifications look like they came from one device.
            'deviceName': n.deviceName,
          })
          .catchError((e, stack) {
            _logger.fine('Failed to show notification', e, stack);
          }),
    );
  }

  void _withdrawNotification(String id) {
    if (targetPlatform != TargetPlatform.linux) return;
    unawaited(
      _channel
          .invokeMethod('withdrawNotification', {
            'id': id,
          })
          .catchError((e, stack) {
            _logger.fine('Failed to withdraw notification', e, stack);
          }),
    );
  }
}

/// The logical device and remote notification id encoded in a banner key.
class RelayNotificationOrigin {
  final String deviceId;
  final String notificationId;

  const RelayNotificationOrigin({required this.deviceId, required this.notificationId});
}

/// Splits a `deviceId:notificationId` banner key back into its two halves.
///
/// Splits on the *first* separator only: a device id never contains `:`, but a
/// remote notification id may (Android uses keys like `0|com.whatsapp|42`, and
/// other senders are not constrained). Returns null for a key with no device
/// half, which must never be acted on -- an action with no owning device has
/// nowhere correct to go.
RelayNotificationOrigin? splitNotificationKey(String? key) {
  if (key == null) return null;
  final separator = key.indexOf(':');
  if (separator <= 0 || separator == key.length - 1) return null;
  return RelayNotificationOrigin(
    deviceId: key.substring(0, separator),
    notificationId: key.substring(separator + 1),
  );
}
