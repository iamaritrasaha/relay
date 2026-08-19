import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

/// The Android side of continuity, as seen from Dart.
///
/// Everything privileged stays in Kotlin; this file only shuttles typed values.
/// On platforms without the channel every call degrades to an honest
/// "unavailable" rather than throwing.
class ContinuityChannel {
  static const _methods = MethodChannel('org.localsend.localsend_app/continuity');
  static const _events = EventChannel('org.localsend.localsend_app/continuity_events');

  const ContinuityChannel();

  bool get isSupported => Platform.isAndroid;

  Future<T?> _invoke<T>(String method, [Map<String, Object?>? arguments]) async {
    if (!isSupported) {
      return null;
    }
    try {
      return await _methods.invokeMethod<T>(method, arguments);
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// The honest capability state of this installation, from real permission
  /// checks on the platform side.
  Future<Map<String, PlatformCapabilityState>> capabilities() async {
    final raw = await _invoke<Map<Object?, Object?>>('capabilities');
    if (raw == null) {
      return const {};
    }
    final result = <String, PlatformCapabilityState>{};
    raw.forEach((key, value) {
      if (key is String && value is Map) {
        result[key] = PlatformCapabilityState.parse(value);
      }
    });
    return result;
  }

  /// Requests the runtime permissions a capability needs. Notification access
  /// is not a runtime permission and opens Android settings instead.
  Future<bool> requestPermissions(String capability) async =>
      await _invoke<bool>('requestPermissions', {'capability': capability}) ?? false;

  Future<void> openNotificationAccessSettings() => _invoke<void>('openNotificationAccessSettings');

  Future<PlatformBattery?> batterySnapshot() async {
    final raw = await _invoke<Map<Object?, Object?>>('batterySnapshot');
    return raw == null ? null : PlatformBattery.parse(raw);
  }

  Future<PlatformClipboardRead> clipboardRead() async {
    final raw = await _invoke<Map<Object?, Object?>>('clipboardRead');
    return raw == null ? const PlatformClipboardRead.empty() : PlatformClipboardRead.parse(raw);
  }

  Future<bool> clipboardWrite(String text) async =>
      await _invoke<bool>('clipboardWrite', {'text': text}) ?? false;

  Future<PlatformConversationsPage> conversations({required int limit, int? beforeMs}) async {
    final raw = await _invoke<Map<Object?, Object?>>('smsConversations', {
      'limit': limit,
      'beforeMs': beforeMs,
    });
    return raw == null ? const PlatformConversationsPage.empty() : PlatformConversationsPage.parse(raw);
  }

  Future<PlatformMessagesPage> messages({
    required String conversationId,
    required int limit,
    int? beforeMs,
  }) async {
    final raw = await _invoke<Map<Object?, Object?>>('smsMessages', {
      'conversationId': conversationId,
      'limit': limit,
      'beforeMs': beforeMs,
    });
    return raw == null
        ? PlatformMessagesPage(conversationId: conversationId, messages: const [], hasMore: false)
        : PlatformMessagesPage.parse(raw);
  }

  Future<PlatformOutcome> sendSms({required List<String> recipients, required String body}) async {
    final raw = await _invoke<Map<Object?, Object?>>('smsSend', {
      'recipients': recipients,
      'body': body,
    });
    return PlatformOutcome.parse(raw);
  }

  Future<PlatformCall?> callSnapshot() async {
    final raw = await _invoke<Map<Object?, Object?>>('callSnapshot');
    return raw == null ? null : PlatformCall.parse(raw);
  }

  Future<PlatformOutcome> callAction({required String action, String? address}) async {
    final raw = await _invoke<Map<Object?, Object?>>('callAction', {
      'action': action,
      'address': address,
    });
    return PlatformOutcome.parse(raw);
  }

  Future<void> dismissNotification(String key) => _invoke<void>('dismissNotification', {'key': key});

  /// Starts platform observation for exactly the capabilities named. Passing an
  /// empty list stops everything.
  Future<void> startObserving(List<String> capabilities) =>
      _invoke<void>('startObserving', {'capabilities': capabilities});

  Future<void> stopObserving() => _invoke<void>('stopObserving');

  /// The background connection service. Only started while continuity is on.
  Future<void> startBackgroundService() => _invoke<void>('startBackgroundService');

  Future<void> stopBackgroundService() => _invoke<void>('stopBackgroundService');

  /// Platform events. Nothing is emitted until [startObserving] is called.
  Stream<PlatformContinuityEvent> events() {
    if (!isSupported) {
      return const Stream<PlatformContinuityEvent>.empty();
    }
    return _events.receiveBroadcastStream().map((raw) {
      if (raw is Map) {
        return PlatformContinuityEvent.parse(raw);
      }
      return const PlatformContinuityEvent.unknown();
    }).where((event) => !event.isUnknown);
  }
}

class PlatformCapabilityState {
  final String state;
  final String? reason;

  const PlatformCapabilityState(this.state, this.reason);

  static PlatformCapabilityState parse(Map<Object?, Object?> raw) => PlatformCapabilityState(
        raw['state'] as String? ?? 'unavailable',
        raw['reason'] as String?,
      );

  bool get isAvailable => state == 'available' || state == 'limited';
  bool get needsPermission => state == 'permissionRequired';
}

class PlatformBattery {
  final int? percentage;
  final String charging;

  const PlatformBattery(this.percentage, this.charging);

  static PlatformBattery parse(Map<Object?, Object?> raw) => PlatformBattery(
        (raw['percentage'] as num?)?.toInt(),
        raw['charging'] as String? ?? 'unknown',
      );
}

class PlatformClipboardRead {
  final String? text;
  final String? unavailableReason;

  const PlatformClipboardRead(this.text, this.unavailableReason);
  const PlatformClipboardRead.empty()
      : text = null,
        unavailableReason = null;

  static PlatformClipboardRead parse(Map<Object?, Object?> raw) => switch (raw['state']) {
        'text' => PlatformClipboardRead(raw['text'] as String?, null),
        'requiresForeground' => PlatformClipboardRead(null, raw['reason'] as String?),
        _ => const PlatformClipboardRead.empty(),
      };
}

class PlatformConversation {
  final String conversationId;
  final String? displayName;
  final List<String> addresses;
  final String? snippet;
  final int lastMessageAtMs;
  final bool unread;

  const PlatformConversation({
    required this.conversationId,
    required this.displayName,
    required this.addresses,
    required this.snippet,
    required this.lastMessageAtMs,
    required this.unread,
  });

  static PlatformConversation parse(Map<Object?, Object?> raw) => PlatformConversation(
        conversationId: raw['conversationId'] as String? ?? '',
        displayName: raw['displayName'] as String?,
        addresses: (raw['addresses'] as List?)?.whereType<String>().toList() ?? const [],
        snippet: raw['snippet'] as String?,
        lastMessageAtMs: (raw['lastMessageAtMs'] as num?)?.toInt() ?? 0,
        unread: raw['unread'] == true,
      );
}

class PlatformConversationsPage {
  final List<PlatformConversation> conversations;
  final bool hasMore;

  const PlatformConversationsPage(this.conversations, this.hasMore);
  const PlatformConversationsPage.empty()
      : conversations = const [],
        hasMore = false;

  static PlatformConversationsPage parse(Map<Object?, Object?> raw) => PlatformConversationsPage(
        (raw['conversations'] as List?)
                ?.whereType<Map>()
                .map(PlatformConversation.parse)
                .toList() ??
            const [],
        raw['hasMore'] == true,
      );
}

class PlatformMessage {
  final String conversationId;
  final String messageId;
  final bool outgoing;
  final String? address;
  final String body;
  final int sentAtMs;
  final bool read;

  const PlatformMessage({
    required this.conversationId,
    required this.messageId,
    required this.outgoing,
    required this.address,
    required this.body,
    required this.sentAtMs,
    required this.read,
  });

  static PlatformMessage parse(Map<Object?, Object?> raw) => PlatformMessage(
        conversationId: raw['conversationId'] as String? ?? '',
        messageId: raw['messageId'] as String? ?? '',
        outgoing: raw['outgoing'] == true,
        address: raw['address'] as String?,
        body: raw['body'] as String? ?? '',
        sentAtMs: (raw['sentAtMs'] as num?)?.toInt() ?? 0,
        read: raw['read'] == true,
      );
}

class PlatformMessagesPage {
  final String conversationId;
  final List<PlatformMessage> messages;
  final bool hasMore;

  const PlatformMessagesPage({
    required this.conversationId,
    required this.messages,
    required this.hasMore,
  });

  static PlatformMessagesPage parse(Map<Object?, Object?> raw) => PlatformMessagesPage(
        conversationId: raw['conversationId'] as String? ?? '',
        messages: (raw['messages'] as List?)?.whereType<Map>().map(PlatformMessage.parse).toList() ?? const [],
        hasMore: raw['hasMore'] == true,
      );
}

class PlatformCall {
  final String phase;
  final String? address;
  final String? displayName;
  final int? activeDurationMs;

  const PlatformCall({
    required this.phase,
    required this.address,
    required this.displayName,
    required this.activeDurationMs,
  });

  static PlatformCall parse(Map<Object?, Object?> raw) => PlatformCall(
        phase: raw['phase'] as String? ?? 'unknown',
        address: raw['address'] as String?,
        displayName: raw['displayName'] as String?,
        activeDurationMs: (raw['activeDurationMs'] as num?)?.toInt(),
      );
}

/// The result of asking the platform to do something.
class PlatformOutcome {
  final String state;
  final String? reason;

  const PlatformOutcome(this.state, this.reason);

  static PlatformOutcome parse(Map<Object?, Object?>? raw) {
    if (raw == null) {
      return const PlatformOutcome('unsupported', 'This is only available on Android.');
    }
    return PlatformOutcome(raw['state'] as String? ?? 'failed', raw['reason'] as String?);
  }

  bool get succeeded => state == 'sent' || state == 'accepted';
}

/// A change the platform reported. Only emitted for capabilities the app asked
/// it to observe.
class PlatformContinuityEvent {
  final String kind;
  final Map<Object?, Object?> data;

  const PlatformContinuityEvent(this.kind, this.data);
  const PlatformContinuityEvent.unknown()
      : kind = '',
        data = const {};

  bool get isUnknown => kind.isEmpty;

  static PlatformContinuityEvent parse(Map<Object?, Object?> raw) =>
      PlatformContinuityEvent(raw['event'] as String? ?? '', raw);
}
