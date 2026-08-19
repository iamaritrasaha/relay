import 'package:relay_app/model/persistence/relay_continuity_settings.dart';
import 'package:relay_app/util/native/continuity_channel.dart';

/// Live, presentation-facing continuity state. Nothing here is persisted, and
/// nothing here is authorization: it only describes what is currently true.

/// How a capability stands on a peer, as that peer honestly advertised it.
class RemoteCapabilityState {
  final String state;
  final String? reason;

  const RemoteCapabilityState(this.state, [this.reason]);

  bool get isAvailable => state == 'available';
  bool get isLimited => state == 'limited';
  bool get needsPermission => state == 'permissionRequired';
  bool get isUsable => isAvailable || isLimited;

  String get label => switch (state) {
    'available' => 'Available',
    'limited' => 'Limited',
    'permissionRequired' => 'Permission required',
    _ => 'Unavailable',
  };
}

class RemoteBattery {
  final int? percentage;
  final String charging;
  final DateTime observedAt;

  const RemoteBattery({
    required this.percentage,
    required this.charging,
    required this.observedAt,
  });

  bool get isCharging => charging == 'charging' || charging == 'full';
  bool get isFull => charging == 'full';

  /// Whether the reading is old enough that it should not be shown as live.
  ///
  /// A device that went away keeps its last reading visible, but marked stale
  /// rather than presented as current.
  bool isStale(DateTime now) => now.difference(observedAt) > const Duration(minutes: 10);

  String summary(DateTime now) {
    if (percentage == null) {
      return 'Battery unknown';
    }
    if (isStale(now)) {
      return '$percentage% · last known';
    }
    if (isFull) {
      return '$percentage% · Charged';
    }
    return isCharging ? '$percentage% · Charging' : '$percentage%';
  }
}

class MirroredNotification {
  final String key;
  final String appLabel;
  final String? title;
  final String? body;
  final DateTime postedAt;
  final bool clearable;

  const MirroredNotification({
    required this.key,
    required this.appLabel,
    required this.title,
    required this.body,
    required this.postedAt,
    required this.clearable,
  });
}

class RemoteConversation {
  final String conversationId;
  final String? displayName;
  final List<String> addresses;
  final String? snippet;
  final DateTime lastMessageAt;
  final bool unread;

  const RemoteConversation({
    required this.conversationId,
    required this.displayName,
    required this.addresses,
    required this.snippet,
    required this.lastMessageAt,
    required this.unread,
  });

  String get title => displayName ?? (addresses.isNotEmpty ? addresses.first : 'Unknown');
}

class RemoteMessage {
  final String conversationId;
  final String messageId;
  final bool outgoing;
  final String? address;
  final String body;
  final DateTime sentAt;

  const RemoteMessage({
    required this.conversationId,
    required this.messageId,
    required this.outgoing,
    required this.address,
    required this.body,
    required this.sentAt,
  });
}

enum RemoteCallPhase { idle, ringing, dialing, active, ended, unknown }

class RemoteCall {
  final RemoteCallPhase phase;
  final String? address;
  final String? displayName;
  final Duration? activeDuration;

  const RemoteCall({
    required this.phase,
    required this.address,
    required this.displayName,
    required this.activeDuration,
  });

  static RemoteCallPhase parsePhase(String raw) => switch (raw) {
    'ringing' => RemoteCallPhase.ringing,
    'dialing' => RemoteCallPhase.dialing,
    'active' => RemoteCallPhase.active,
    'ended' => RemoteCallPhase.ended,
    'idle' => RemoteCallPhase.idle,
    _ => RemoteCallPhase.unknown,
  };

  bool get isIdle => phase == RemoteCallPhase.idle || phase == RemoteCallPhase.ended;

  String get title => displayName ?? address ?? 'Unknown caller';

  String get statusLabel => switch (phase) {
    RemoteCallPhase.ringing => 'Incoming call',
    RemoteCallPhase.dialing => 'Calling…',
    RemoteCallPhase.active => 'On a call',
    RemoteCallPhase.ended => 'Call ended',
    RemoteCallPhase.idle => 'No active call',
    RemoteCallPhase.unknown => 'Call status unknown',
  };
}

/// Clipboard content a peer offered but has not been applied.
class ClipboardOffer {
  final String text;
  final bool explicit;
  final DateTime receivedAt;

  const ClipboardOffer({
    required this.text,
    required this.explicit,
    required this.receivedAt,
  });
}

/// One line of continuity activity.
///
/// Deliberately metadata only: what happened, with which device, and when.
/// Clipboard text, message bodies, notification contents, phone numbers and
/// contact names are never recorded here, and this feed is never persisted —
/// it lives for the session and is gone on restart.
class ContinuityActivityEntry {
  final String relayId;
  final String deviceLabel;
  final ContinuityActivityKind kind;
  final DateTime at;

  const ContinuityActivityEntry({
    required this.relayId,
    required this.deviceLabel,
    required this.kind,
    required this.at,
  });

  String get summary => switch (kind) {
    ContinuityActivityKind.connected => 'Connected to $deviceLabel',
    ContinuityActivityKind.disconnected => 'Disconnected from $deviceLabel',
    ContinuityActivityKind.clipboardShared => 'Clipboard shared with $deviceLabel',
    ContinuityActivityKind.clipboardReceived => 'Clipboard received from $deviceLabel',
    ContinuityActivityKind.messageSent => 'Message sent from $deviceLabel',
    ContinuityActivityKind.callPlaced => 'Call placed on $deviceLabel',
  };
}

enum ContinuityActivityKind {
  connected,
  disconnected,
  clipboardShared,
  clipboardReceived,
  messageSent,
  callPlaced,
}

/// Everything currently known about one paired device's continuity.
class DeviceContinuity {
  final String relayId;
  final bool connected;
  final bool directPath;
  final String? remoteLabel;
  final Map<ContinuityCapabilityKind, RemoteCapabilityState> remoteCapabilities;
  final RemoteBattery? battery;
  final List<MirroredNotification> notifications;
  final List<RemoteConversation> conversations;
  final bool conversationsHasMore;
  final Map<String, List<RemoteMessage>> messages;
  final Map<String, bool> messagesHasMore;
  final RemoteCall? call;
  final ClipboardOffer? clipboardOffer;
  final String? lastClipboardText;
  final String? lastError;

  const DeviceContinuity({
    required this.relayId,
    this.connected = false,
    this.directPath = false,
    this.remoteLabel,
    this.remoteCapabilities = const {},
    this.battery,
    this.notifications = const [],
    this.conversations = const [],
    this.conversationsHasMore = false,
    this.messages = const {},
    this.messagesHasMore = const {},
    this.call,
    this.clipboardOffer,
    this.lastClipboardText,
    this.lastError,
  });

  DeviceContinuity copyWith({
    bool? connected,
    bool? directPath,
    String? remoteLabel,
    Map<ContinuityCapabilityKind, RemoteCapabilityState>? remoteCapabilities,
    RemoteBattery? battery,
    List<MirroredNotification>? notifications,
    List<RemoteConversation>? conversations,
    bool? conversationsHasMore,
    Map<String, List<RemoteMessage>>? messages,
    Map<String, bool>? messagesHasMore,
    RemoteCall? call,
    ClipboardOffer? clipboardOffer,
    bool clearClipboardOffer = false,
    String? lastClipboardText,
    String? lastError,
    bool clearError = false,
  }) {
    return DeviceContinuity(
      relayId: relayId,
      connected: connected ?? this.connected,
      directPath: directPath ?? this.directPath,
      remoteLabel: remoteLabel ?? this.remoteLabel,
      remoteCapabilities: remoteCapabilities ?? this.remoteCapabilities,
      battery: battery ?? this.battery,
      notifications: notifications ?? this.notifications,
      conversations: conversations ?? this.conversations,
      conversationsHasMore: conversationsHasMore ?? this.conversationsHasMore,
      messages: messages ?? this.messages,
      messagesHasMore: messagesHasMore ?? this.messagesHasMore,
      call: call ?? this.call,
      clipboardOffer: clearClipboardOffer ? null : (clipboardOffer ?? this.clipboardOffer),
      lastClipboardText: lastClipboardText ?? this.lastClipboardText,
      lastError: clearError ? null : (lastError ?? this.lastError),
    );
  }
}

/// The whole continuity picture the UI renders from.
class RelayContinuityState {
  /// Per-device consent. The source of truth for what is allowed.
  final Map<String, RelayContinuitySettings> settings;

  /// Per-device live state.
  final Map<String, DeviceContinuity> devices;

  /// What *this* installation can do, from real platform checks.
  final Map<String, PlatformCapabilityState> localCapabilities;

  /// Whether the Android background connection service is running.
  final bool backgroundServiceRunning;

  /// Recent continuity activity, newest first. Metadata only, never persisted.
  final List<ContinuityActivityEntry> activity;

  const RelayContinuityState({
    this.settings = const {},
    this.devices = const {},
    this.localCapabilities = const {},
    this.backgroundServiceRunning = false,
    this.activity = const [],
  });

  RelayContinuitySettings settingsFor(String relayId) => settings[relayId] ?? RelayContinuitySettings(relayId: relayId);

  DeviceContinuity deviceFor(String relayId) => devices[relayId] ?? DeviceContinuity(relayId: relayId);

  /// Whether any device has any capability enabled. Drives whether a background
  /// service should exist at all.
  bool get anyCapabilityEnabled => settings.values.any((entry) => entry.hasAnyCapability);

  RelayContinuityState copyWith({
    Map<String, RelayContinuitySettings>? settings,
    Map<String, DeviceContinuity>? devices,
    Map<String, PlatformCapabilityState>? localCapabilities,
    bool? backgroundServiceRunning,
    List<ContinuityActivityEntry>? activity,
  }) {
    return RelayContinuityState(
      settings: settings ?? this.settings,
      devices: devices ?? this.devices,
      localCapabilities: localCapabilities ?? this.localCapabilities,
      backgroundServiceRunning: backgroundServiceRunning ?? this.backgroundServiceRunning,
      activity: activity ?? this.activity,
    );
  }

  /// Appends an activity line, keeping the feed bounded.
  RelayContinuityState withActivity(ContinuityActivityEntry entry) {
    return copyWith(activity: [entry, ...activity].take(50).toList());
  }
}
