import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:logging/logging.dart';
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
class RelayDesktopNotificationService {
  final TargetPlatform targetPlatform;
  final Map<String, Set<String>> _seenIds = {};
  final Map<String, RsKdeNotification> _knownNotifications = {};
  StreamSubscription<void>? _subscription;
  bool _isInitialSync = true;

  RelayDesktopNotificationService({
    TargetPlatform? platform,
  }) : targetPlatform = platform ?? defaultTargetPlatform {
    _channel.setMethodCallHandler((call) async {
      try {
        if (call.method == 'notificationActivated') {
          final id = call.arguments is Map ? (call.arguments as Map)['id'] as String? : null;
          _logger.fine('[Relay Notification] id=$id op=activated');
          await showFromTray();
        }
      } catch (e, stack) {
        _logger.warning('Notification action ${call.method} failed', e, stack);
      }
      return null;
    });
  }

  void start(Stream<Map<String, List<RsKdeNotification>>> notificationsStream) {
    unawaited(_subscription?.cancel());
    _subscription = notificationsStream.listen(
      (notifications) {
        _processNotifications(notifications);
      },
      onError: (Object error, StackTrace stack) => _logger.fine('Relay notification stream failed', error, stack),
    );
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
  }

  void _processNotifications(Map<String, List<RsKdeNotification>> notifications) {
    if (_isInitialSync) {
      for (final entry in notifications.entries) {
        final deviceId = entry.key;
        final list = entry.value;
        _seenIds[deviceId] = list.map((e) => e.id).toSet();
        for (final n in list) {
          _knownNotifications['$deviceId:${n.id}'] = n;
        }
      }
      _isInitialSync = false;
      _logger.fine('[Relay Notification] initial sync complete count=${_knownNotifications.length}');
      return;
    }

    final newKnownNotifications = <String, RsKdeNotification>{};
    final newSeenIds = <String, Set<String>>{};

    for (final entry in notifications.entries) {
      final deviceId = entry.key;
      final currentList = entry.value;
      final currentIds = currentList.map((e) => e.id).toSet();
      newSeenIds[deviceId] = currentIds;

      final previousIds = _seenIds[deviceId] ?? {};

      for (final n in currentList) {
        final fullId = '$deviceId:${n.id}';
        newKnownNotifications[fullId] = n;

        final isNew = !previousIds.contains(n.id);
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

    // Handle removed devices
    for (final deviceId in _seenIds.keys) {
      if (!notifications.containsKey(deviceId)) {
        for (final oldId in _seenIds[deviceId]!) {
          final fullId = '$deviceId:$oldId';
          _logger.fine('[Relay Notification] id=$fullId op=withdraw deviceRemoved=true');
          _withdrawNotification(fullId);
        }
      }
    }

    _seenIds.clear();
    _seenIds.addAll(newSeenIds);
    _knownNotifications.clear();
    _knownNotifications.addAll(newKnownNotifications);
  }

  void _showNotification(String id, RsKdeNotification n) {
    if (targetPlatform != TargetPlatform.linux) return;
    unawaited(
      _channel
          .invokeMethod('showNotification', {
            'id': id,
            'appName': n.appName,
            'title': n.title,
            'body': n.text,
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
