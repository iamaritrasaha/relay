import 'dart:async';
import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:flutter/services.dart';
import 'package:logging/logging.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:relay_app/provider/persistence_provider.dart';
import 'package:relay_isolates/rust/api/kdeconnect.dart';

final _logger = Logger('KdeConnect');
final _smsLogger = Logger('RelaySmsBridge');

String kdeConnectDeviceIdFromKey(String key) => key.startsWith('kdeconnect:') ? key.substring('kdeconnect:'.length) : key;

class KdeConnectIncomingRequest {
  final String deviceId;
  final String name;

  const KdeConnectIncomingRequest({required this.deviceId, required this.name});
}

class KdeTelephonyState {
  final String event; // 'ringing', 'talking', 'missedCall'
  final bool isCancel;
  final String? phoneNumber;
  final String? contactName;
  final int timestamp;

  const KdeTelephonyState({
    required this.event,
    this.isCancel = false,
    this.phoneNumber,
    this.contactName,
    required this.timestamp,
  });
}

class KdeConnectState {
  final List<RsKdeConnectDevice> devices;
  final KdeConnectIncomingRequest? incoming;
  final Map<String, List<RsKdeNotification>> notifications;
  final Map<String, List<RsKdeSmsConversation>> smsConversations;
  final Map<String, Map<int, List<RsKdeSmsMessage>>> smsMessages;
  final Map<String, KdeTelephonyState?> activeCalls;
  final Map<String, List<KdeTelephonyState>> recentTelephonyEvents;
  final String? lastPingDeviceName;
  final String? lastPingMessage;
  final int lastPingTimestamp;

  const KdeConnectState({
    this.devices = const [],
    this.incoming,
    this.notifications = const {},
    this.smsConversations = const {},
    this.smsMessages = const {},
    this.activeCalls = const {},
    this.recentTelephonyEvents = const {},
    this.lastPingDeviceName,
    this.lastPingMessage,
    this.lastPingTimestamp = 0,
  });

  KdeConnectState copyWith({
    List<RsKdeConnectDevice>? devices,
    KdeConnectIncomingRequest? incoming,
    bool clearIncoming = false,
    Map<String, List<RsKdeNotification>>? notifications,
    Map<String, List<RsKdeSmsConversation>>? smsConversations,
    Map<String, Map<int, List<RsKdeSmsMessage>>>? smsMessages,
    Map<String, KdeTelephonyState?>? activeCalls,
    Map<String, List<KdeTelephonyState>>? recentTelephonyEvents,
    String? lastPingDeviceName,
    String? lastPingMessage,
    int? lastPingTimestamp,
  }) => KdeConnectState(
    devices: devices ?? this.devices,
    incoming: clearIncoming ? null : incoming ?? this.incoming,
    notifications: notifications ?? this.notifications,
    smsConversations: smsConversations ?? this.smsConversations,
    smsMessages: smsMessages ?? this.smsMessages,
    activeCalls: activeCalls ?? this.activeCalls,
    recentTelephonyEvents: recentTelephonyEvents ?? this.recentTelephonyEvents,
    lastPingDeviceName: lastPingDeviceName ?? this.lastPingDeviceName,
    lastPingMessage: lastPingMessage ?? this.lastPingMessage,
    lastPingTimestamp: lastPingTimestamp ?? this.lastPingTimestamp,
  );
}

typedef KdeConnectIdentityFactory = Future<RsKdeConnectIdentity> Function({required String deviceName});
typedef KdeConnectStarter = Future<RsKdeConnect> Function(RsKdeConnectIdentity identity, List<RsKdeConnectTrustedDevice> trusted);

final kdeConnectProvider = ReduxProvider<KdeConnectService, KdeConnectState>((ref) {
  return KdeConnectService(
    persistence: ref.read(persistenceProvider),
    generateIdentity: kdeconnectGenerateIdentity,
    startRuntime: (identity, trusted) => startKdeconnect(identity: identity, trusted: trusted),
  );
});

class KdeConnectService extends ReduxNotifier<KdeConnectState> {
  final PersistenceService persistence;
  final KdeConnectIdentityFactory generateIdentity;
  final KdeConnectStarter startRuntime;

  RsKdeConnect? _runtime;
  StreamSubscription<RsKdeConnectEvent>? _events;
  String? _lastReceivedClipboard;

  KdeConnectService({
    required this.persistence,
    required this.generateIdentity,
    required this.startRuntime,
  });

  @override
  KdeConnectState init() => const KdeConnectState();

  @override
  void dispose() {
    unawaited(_events?.cancel());
    final runtime = _runtime;
    if (runtime != null) {
      unawaited(runtime.stop());
    }
    super.dispose();
  }
}

class KdeConnectStartAction extends AsyncReduxAction<KdeConnectService, KdeConnectState> {
  final String deviceName;

  KdeConnectStartAction({required this.deviceName});

  @override
  Future<KdeConnectState> reduce() async {
    final persisted = notifier.persistence.getKdeConnectIdentity();
    final RsKdeConnectIdentity identity;
    if (persisted != null) {
      final persistedWanSecret = persisted['wanSecretKey'];
      final wanSecret = persistedWanSecret is List
          ? Uint8List.fromList(persistedWanSecret.cast<num>().map((value) => value.toInt()).toList())
          : await kdeconnectGenerateWanSecret();
      identity = RsKdeConnectIdentity(
        deviceId: persisted['deviceId'] as String,
        deviceName: persisted['deviceName'] as String? ?? deviceName,
        certificatePem: persisted['certificatePem'] as String,
        privateKeyPem: persisted['privateKeyPem'] as String,
        wanSecretKey: wanSecret,
      );
      if (persistedWanSecret == null) {
        await notifier.persistence.setKdeConnectIdentity({...persisted, 'wanSecretKey': wanSecret.toList()});
      }
    } else {
      identity = await notifier.generateIdentity(deviceName: deviceName);
      await notifier.persistence.setKdeConnectIdentity({
        'deviceId': identity.deviceId,
        'deviceName': identity.deviceName,
        'certificatePem': identity.certificatePem,
        'privateKeyPem': identity.privateKeyPem,
        'wanSecretKey': identity.wanSecretKey.toList(),
      });
    }
    final trusted = [
      for (final item in notifier.persistence.getKdeConnectTrustedDevices())
        RsKdeConnectTrustedDevice(
          deviceId: item['deviceId'] as String,
          certificatePem: item['certificatePem'] as String,
          name: item['name'] as String? ?? 'Phone',
          deviceType: item['deviceType'] as String? ?? 'phone',
          protocolVersion: (item['protocolVersion'] as num?)?.toInt() ?? 8,
          pairedAtUnix: (item['pairedAtUnix'] as num?)?.toInt() ?? 0,
          wanEndpointId: item['wanEndpointId'] as String?,
        ),
    ];
    final runtime = await notifier.startRuntime(identity, trusted);
    await notifier._events?.cancel();
    notifier._runtime = runtime;
    notifier._events = runtime.listen().listen(
      (event) {
        dispatch(KdeConnectApplyEventAction(event));
      },
      onError: (Object error, StackTrace stack) {
        _logger.warning('KDE Connect event stream failed', error, stack);
      },
    );
    return state;
  }
}

class KdeConnectRequestPairAction extends AsyncReduxAction<KdeConnectService, KdeConnectState> {
  final String deviceId;

  KdeConnectRequestPairAction(this.deviceId);

  @override
  Future<KdeConnectState> reduce() async {
    try {
      await notifier._runtime?.requestPair(deviceId: deviceId);
    } catch (error, stack) {
      _logger.warning('Pair request failed for device $deviceId', error, stack);
    }
    return state;
  }
}

class KdeConnectAcceptPairAction extends AsyncReduxAction<KdeConnectService, KdeConnectState> {
  final String deviceId;

  KdeConnectAcceptPairAction(this.deviceId);

  @override
  Future<KdeConnectState> reduce() async {
    try {
      await notifier._runtime?.acceptPair(deviceId: deviceId);
    } catch (error, stack) {
      _logger.warning('Accept pair failed for device $deviceId', error, stack);
    }
    return state.copyWith(clearIncoming: true);
  }
}

class KdeConnectRejectPairAction extends AsyncReduxAction<KdeConnectService, KdeConnectState> {
  final String deviceId;

  KdeConnectRejectPairAction(this.deviceId);

  @override
  Future<KdeConnectState> reduce() async {
    try {
      await notifier._runtime?.rejectPair(deviceId: deviceId);
    } catch (error, stack) {
      _logger.warning('Reject pair failed for device $deviceId', error, stack);
    }
    return state.copyWith(clearIncoming: true);
  }
}

class KdeConnectUnpairAction extends AsyncReduxAction<KdeConnectService, KdeConnectState> {
  final String deviceId;

  KdeConnectUnpairAction(this.deviceId);

  @override
  Future<KdeConnectState> reduce() async {
    try {
      await notifier._runtime?.unpair(deviceId: deviceId);
    } catch (error, stack) {
      _logger.warning('Unpair failed for device $deviceId', error, stack);
    }
    return state.copyWith(clearIncoming: true);
  }
}

class KdeConnectPingAction extends AsyncReduxAction<KdeConnectService, KdeConnectState> {
  final String deviceId;
  final String? message;

  KdeConnectPingAction(this.deviceId, {this.message});

  @override
  Future<KdeConnectState> reduce() async {
    try {
      await notifier._runtime?.sendRelayPing(deviceId: deviceId);
      await notifier._runtime?.requestRelayDeviceState(deviceId: deviceId);
      await notifier._runtime?.sendPing(deviceId: deviceId, message: message);
    } catch (error, stack) {
      _logger.warning('Send ping failed for device $deviceId', error, stack);
    }
    return state;
  }
}

class KdeConnectFindPhoneAction extends AsyncReduxAction<KdeConnectService, KdeConnectState> {
  final String deviceId;

  KdeConnectFindPhoneAction(this.deviceId);

  @override
  Future<KdeConnectState> reduce() async {
    try {
      await notifier._runtime?.findPhone(deviceId: deviceId);
    } catch (error, stack) {
      _logger.warning('Find phone failed for device $deviceId', error, stack);
    }
    return state;
  }
}

class KdeConnectSendClipboardAction extends AsyncReduxAction<KdeConnectService, KdeConnectState> {
  final String content;

  KdeConnectSendClipboardAction(this.content);

  @override
  Future<KdeConnectState> reduce() async {
    if (content.isNotEmpty && content != notifier._lastReceivedClipboard) {
      try {
        await notifier._runtime?.sendClipboardToAllPaired(
          content: content,
          timestampMs: DateTime.now().millisecondsSinceEpoch,
        );
      } catch (error, stack) {
        _logger.warning('Send clipboard failed', error, stack);
      }
    }
    return state;
  }
}

class KdeConnectApplyEventAction extends ReduxAction<KdeConnectService, KdeConnectState> {
  final RsKdeConnectEvent event;

  KdeConnectApplyEventAction(this.event);

  @override
  KdeConnectState reduce() {
    switch (event) {
      case RsKdeConnectEvent_DevicesChanged(:final devices):
        return state.copyWith(devices: devices);
      case RsKdeConnectEvent_IncomingPair(:final deviceId, :final name):
        return state.copyWith(
          incoming: KdeConnectIncomingRequest(deviceId: deviceId, name: name),
        );
      case RsKdeConnectEvent_PairingFailed():
        return state.copyWith(clearIncoming: true);
      case RsKdeConnectEvent_TrustChanged(:final devices):
        unawaited(
          notifier.persistence.setKdeConnectTrustedDevices([
            for (final device in devices)
              {
                'deviceId': device.deviceId,
                'certificatePem': device.certificatePem,
                'name': device.name,
                'deviceType': device.deviceType,
                'protocolVersion': device.protocolVersion,
                'pairedAtUnix': device.pairedAtUnix,
                'wanEndpointId': device.wanEndpointId,
              },
          ]),
        );
        return state;
      case RsKdeConnectEvent_PingReceived(:final deviceId, :final message):
        final dev = state.devices.firstWhereOrNull((d) => d.deviceId == deviceId);
        final devName = dev?.name ?? 'Phone';
        return state.copyWith(
          lastPingDeviceName: devName,
          lastPingMessage: message,
          lastPingTimestamp: DateTime.now().millisecondsSinceEpoch,
        );
      case RsKdeConnectEvent_ClipboardReceived(:final content):
        if (content.isNotEmpty && content != notifier._lastReceivedClipboard) {
          notifier._lastReceivedClipboard = content;
          unawaited(Clipboard.setData(ClipboardData(text: content)));
        }
        return state;
      case RsKdeConnectEvent_NotificationsChanged(:final deviceId, :final notifications):
        return state.copyWith(
          notifications: {...state.notifications, deviceId: notifications},
        );
      case RsKdeConnectEvent_SmsChanged(:final deviceId, :final conversations, :final messages):
        final deviceMessages = Map<int, List<RsKdeSmsMessage>>.from(state.smsMessages[deviceId] ?? const {});
        for (final message in messages) {
          final threadList = (deviceMessages[message.threadId] ?? const <RsKdeSmsMessage>[])
              .where((item) => item.id > 0 || item.body != message.body)
              .toList();
          final current = Map<int, RsKdeSmsMessage>.fromEntries(
            threadList.map((item) => MapEntry(item.id, item)),
          );
          current[message.id] = message;
          final merged = current.values.toList()..sort((a, b) => a.date.compareTo(b.date));
          deviceMessages[message.threadId] = merged;
        }
        final nextState = state.copyWith(
          smsConversations: {...state.smsConversations, deviceId: conversations},
          smsMessages: {...state.smsMessages, deviceId: deviceMessages},
        );
        _smsLogger.info(
          'PROVIDER updated device=$deviceId conversations=${nextState.smsConversations[deviceId]?.length ?? 0} '
          'messages=${nextState.smsMessages[deviceId]?.values.fold<int>(0, (total, thread) => total + thread.length) ?? 0}',
        );
        return nextState;
      case RsKdeConnectEvent_TelephonyReceived(:final deviceId, :final event):
        final currentEvent = KdeTelephonyState(
          event: event.event,
          isCancel: event.isCancel,
          phoneNumber: event.phoneNumber,
          contactName: event.contactName,
          timestamp: DateTime.now().millisecondsSinceEpoch,
        );
        final recentList = List<KdeTelephonyState>.from(state.recentTelephonyEvents[deviceId] ?? const []);
        recentList.insert(0, currentEvent);
        if (recentList.length > 50) {
          recentList.removeLast();
        }

        final active = nextActiveCall(state.activeCalls[deviceId], currentEvent);

        return state.copyWith(
          activeCalls: {...state.activeCalls, deviceId: active},
          recentTelephonyEvents: {...state.recentTelephonyEvents, deviceId: recentList},
        );
    }
  }
}

/// The call state machine for one device.
///
/// Only the event that is actually live can end the call. Android sends the
/// ringing cancel around the same time as the talking event when a call is
/// answered, so a blanket "any cancel clears the call" rule tears down a call
/// that has just been picked up, and leaves ringing stuck when the order is
/// reversed. A repeat of the event already in progress keeps its original
/// timestamp, which is what makes an in-call duration measurable from the
/// moment talking actually began.
///
/// [previous] is the call currently held for the device, [incoming] the event
/// just received. Returns the call to hold next, or null for idle.
KdeTelephonyState? nextActiveCall(KdeTelephonyState? previous, KdeTelephonyState incoming) {
  // A missed call is a notification about a call that is already over.
  if (incoming.event == 'missedCall') return null;

  if (incoming.isCancel) {
    return (previous != null && previous.event == incoming.event) ? null : previous;
  }

  if (previous != null && previous.event == incoming.event) return previous;

  return incoming;
}

class KdeConnectUpdateMessagesAction extends ReduxAction<KdeConnectService, KdeConnectState> {
  final String deviceId;
  final Map<int, List<RsKdeSmsMessage>> messages;

  KdeConnectUpdateMessagesAction({required this.deviceId, required this.messages});

  @override
  KdeConnectState reduce() => state.copyWith(
    smsMessages: {...state.smsMessages, deviceId: messages},
  );
}

/// How many unreconciled outgoing bubbles a single thread may hold.
const int _maxPendingPerThread = 20;

class KdeConnectSendSmsAction extends AsyncReduxAction<KdeConnectService, KdeConnectState> {
  final String deviceId;
  final int threadId;
  final List<String> addresses;
  final String messageBody;
  final int? subId;

  KdeConnectSendSmsAction({
    required this.deviceId,
    required this.threadId,
    required this.addresses,
    required this.messageBody,
    this.subId,
  });

  @override
  Future<KdeConnectState> reduce() async {
    final pendingId = -DateTime.now().millisecondsSinceEpoch;
    final pendingMessage = RsKdeSmsMessage(
      id: pendingId,
      threadId: threadId,
      addresses: addresses,
      body: messageBody,
      date: DateTime.now().millisecondsSinceEpoch,
      messageType: 2, // outgoing
      read: true,
      attachments: const [],
    );

    final deviceMessages = Map<int, List<RsKdeSmsMessage>>.from(state.smsMessages[deviceId] ?? const {});
    var currentList = List<RsKdeSmsMessage>.from(deviceMessages[threadId] ?? const []);

    // A pending bubble is cleared when Android echoes the canonical message
    // back. If that echo never comes the entry would otherwise sit in the
    // thread forever, so the oldest unreconciled ones are dropped.
    final pendingCount = currentList.where((message) => message.id < 0).length;
    if (pendingCount >= _maxPendingPerThread) {
      var toDrop = pendingCount - _maxPendingPerThread + 1;
      currentList = currentList.where((message) {
        if (message.id >= 0 || toDrop <= 0) return true;
        toDrop--;
        return false;
      }).toList();
    }

    currentList.add(pendingMessage);
    deviceMessages[threadId] = currentList;

    dispatch(KdeConnectUpdateMessagesAction(deviceId: deviceId, messages: deviceMessages));

    try {
      await notifier._runtime?.sendSms(
        deviceId: deviceId,
        addresses: addresses,
        body: messageBody,
        subId: subId,
      );
    } catch (error, stack) {
      _logger.warning('Send SMS failed for device $deviceId', error, stack);
      final updatedMessages = Map<int, List<RsKdeSmsMessage>>.from(state.smsMessages[deviceId] ?? const {});
      final list = List<RsKdeSmsMessage>.from(updatedMessages[threadId] ?? const []);
      list.removeWhere((m) => m.id == pendingId);
      updatedMessages[threadId] = list;
      return state.copyWith(smsMessages: {...state.smsMessages, deviceId: updatedMessages});
    }
    return state;
  }
}

class KdeConnectMuteCallAction extends AsyncReduxAction<KdeConnectService, KdeConnectState> {
  final String deviceId;
  KdeConnectMuteCallAction(this.deviceId);

  @override
  Future<KdeConnectState> reduce() async {
    try {
      await notifier._runtime?.muteCall(deviceId: deviceId);
    } catch (error, stack) {
      _logger.warning('Mute call failed for device $deviceId', error, stack);
    }
    return state;
  }
}

class KdeConnectRequestSmsConversationsAction extends AsyncReduxAction<KdeConnectService, KdeConnectState> {
  final String deviceId;
  KdeConnectRequestSmsConversationsAction(this.deviceId);
  @override
  Future<KdeConnectState> reduce() async {
    final runtime = notifier._runtime;
    if (runtime == null) {
      _smsLogger.warning('REQUEST skipped device=$deviceId packetType=kdeconnect.sms.request_conversations runtimeAvailable=false');
      return state;
    }
    _smsLogger.info('REQUEST action device=$deviceId packetType=kdeconnect.sms.request_conversations');
    try {
      await runtime.requestSmsConversations(deviceId: deviceId);
      _smsLogger.info('REQUEST bridged device=$deviceId packetType=kdeconnect.sms.request_conversations');
    } catch (error, stack) {
      _logger.warning('SMS conversation request failed for device $deviceId', error, stack);
      _smsLogger.warning('REQUEST failed device=$deviceId packetType=kdeconnect.sms.request_conversations reason=${error.runtimeType}');
    }
    return state;
  }
}

class KdeConnectRequestSmsConversationAction extends AsyncReduxAction<KdeConnectService, KdeConnectState> {
  final String deviceId;
  final int threadId;
  final int? beforeTimestamp;
  KdeConnectRequestSmsConversationAction(this.deviceId, this.threadId, {this.beforeTimestamp});
  @override
  Future<KdeConnectState> reduce() async {
    final runtime = notifier._runtime;
    if (runtime == null) {
      _smsLogger.warning(
        'REQUEST skipped device=$deviceId packetType=kdeconnect.sms.request_conversation threadId=$threadId runtimeAvailable=false',
      );
      return state;
    }
    _smsLogger.info('REQUEST action device=$deviceId packetType=kdeconnect.sms.request_conversation threadId=$threadId');
    try {
      await runtime.requestSmsConversation(deviceId: deviceId, threadId: threadId, before: beforeTimestamp);
      _smsLogger.info('REQUEST bridged device=$deviceId packetType=kdeconnect.sms.request_conversation threadId=$threadId');
    } catch (error, stack) {
      _logger.warning('SMS history request failed for device $deviceId', error, stack);
      _smsLogger.warning(
        'REQUEST failed device=$deviceId packetType=kdeconnect.sms.request_conversation threadId=$threadId reason=${error.runtimeType}',
      );
    }
    return state;
  }
}

class KdeConnectReplaceDevicesAction extends ReduxAction<KdeConnectService, KdeConnectState> {
  final List<RsKdeConnectDevice> devices;
  final KdeConnectIncomingRequest? incoming;
  final bool clearIncoming;

  KdeConnectReplaceDevicesAction({required this.devices, this.incoming, this.clearIncoming = false});

  @override
  KdeConnectState reduce() => state.copyWith(devices: devices, incoming: incoming, clearIncoming: clearIncoming);
}
