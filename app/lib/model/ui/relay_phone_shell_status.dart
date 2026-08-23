import 'package:collection/collection.dart';
import 'package:relay_app/model/ui/relay_capability_vm.dart';
import 'package:relay_app/model/ui/relay_last_seen.dart';
import 'package:relay_app/model/ui/relay_device_vm.dart';
import 'package:relay_isolates/model/device.dart';

/// Presentation-only snapshot of the user's primary phone, shaped for desktop
/// shell surfaces such as the GNOME Shell panel.
///
/// This is deliberately protocol independent. Whichever transport told Relay
/// about the phone — KDE Connect today, a future Relay-native Android client —
/// the shell sees the same fields, so a shell surface never learns which
/// backend produced them.
///
/// Every capability-derived field is genuinely optional. A missing value means
/// "Relay does not know", which is a different statement from a zero value:
/// `batteryPercentage == 0` is a flat phone, `batteryPercentage == null` is a
/// phone that has not reported its battery. Consumers must not collapse the
/// two.
class RelayPhoneShellStatus {
  /// Stable identity of the phone inside Relay. Opaque to the shell.
  final String deviceId;

  /// What the user calls this phone.
  final String displayName;

  /// Relay's device classification, as the plain enum name.
  final String deviceType;

  /// Whether a live link to the phone exists right now.
  final bool connected;

  /// Whether the phone is a trusted, paired Relay target.
  final bool paired;

  /// 0-100, or null when no battery reading has ever arrived.
  final int? batteryPercentage;

  /// Null whenever [batteryPercentage] is null: charge state without a reading
  /// is not something Relay can honestly claim.
  final bool? batteryIsCharging;
  final bool? batteryIsFull;

  /// Whether the battery reading is the last known one rather than a live one.
  final bool batteryIsStale;

  /// Coarse network family, e.g. `cellular` or `wifi`. Null until a Relay
  /// capability genuinely reports the phone's network.
  final String? networkKind;

  /// Short human label for the network, e.g. `5G`. Null when unreported.
  final String? networkLabel;

  /// Signal strength bucket, 0-4. Null when unreported.
  final int? signalLevel;

  /// Unread message count. Null until a Relay capability genuinely reports it;
  /// zero is a real answer meaning "nothing unread".
  final int? unreadMessageCount;

  /// Standing notifications mirrored from the phone. Only how many: a shell
  /// surface never sees a title, a body or who sent it.
  final int? notificationCount;

  final bool supportsFindDevice;
  final bool supportsClipboard;
  final bool supportsMessages;
  final bool supportsNotifications;

  /// Whether the network type (LTE, 5G) should be shown in the shell.
  final bool showNetworkLabel;

  /// Whether numerical battery percentage should be shown in the shell.
  final bool showBatteryPercentage;

  /// Whether notification indicator should be shown in the shell.
  final bool showNotifications;

  /// Whether charging warmth animation is enabled.
  final bool chargingAnimationEnabled;

  /// Whether signal icon should be shown in the shell.
  final bool showSignal;

  /// How many phones were eligible when this snapshot was taken, so a shell
  /// surface can say "1 of 2" without Relay having to expose the other phones.
  final int phoneCount;

  final DateTime lastUpdated;

  const RelayPhoneShellStatus._({
    required this.deviceId,
    required this.displayName,
    required this.deviceType,
    required this.connected,
    required this.paired,
    required this.batteryPercentage,
    required this.batteryIsCharging,
    required this.batteryIsFull,
    required this.batteryIsStale,
    required this.networkKind,
    required this.networkLabel,
    required this.signalLevel,
    required this.unreadMessageCount,
    required this.notificationCount,
    required this.supportsFindDevice,
    required this.supportsClipboard,
    required this.supportsMessages,
    required this.supportsNotifications,
    required this.showNetworkLabel,
    required this.showBatteryPercentage,
    required this.showNotifications,
    required this.chargingAnimationEnabled,
    required this.showSignal,
    required this.phoneCount,
    required this.lastUpdated,
  });

  /// Builds a snapshot, dropping every field whose value is out of range.
  ///
  /// Nothing here guesses: a rejected value becomes absent rather than clamped,
  /// because a clamped number would read as a real measurement downstream.
  factory RelayPhoneShellStatus({
    required String deviceId,
    required String displayName,
    required String deviceType,
    required bool connected,
    required bool paired,
    required DateTime lastUpdated,
    int? batteryPercentage,
    bool? batteryIsCharging,
    bool? batteryIsFull,
    bool batteryIsStale = false,
    String? networkKind,
    String? networkLabel,
    int? signalLevel,
    int? unreadMessageCount,
    int? notificationCount,
    bool supportsFindDevice = false,
    bool supportsClipboard = false,
    bool supportsMessages = false,
    bool supportsNotifications = false,
    bool showNetworkLabel = true,
    bool showBatteryPercentage = true,
    bool showNotifications = true,
    bool chargingAnimationEnabled = true,
    bool showSignal = true,
    int phoneCount = 1,
  }) {
    final battery = batteryPercentage != null && batteryPercentage >= 0 && batteryPercentage <= 100 ? batteryPercentage : null;
    final name = displayName.trim();
    final network = _nonEmpty(networkKind);
    final label = _nonEmpty(networkLabel);
    return RelayPhoneShellStatus._(
      deviceId: deviceId,
      displayName: name.isEmpty ? _fallbackName : name,
      deviceType: deviceType,
      connected: connected,
      paired: paired,
      batteryPercentage: battery,
      batteryIsCharging: battery == null ? null : (batteryIsCharging ?? false),
      batteryIsFull: battery == null ? null : (batteryIsFull ?? false),
      batteryIsStale: battery == null ? false : batteryIsStale,
      networkKind: network,
      networkLabel: label,
      // Signal is independently useful. A connectivity provider may know the
      // level before a carrier label, and the shell can present that honest
      // partial answer without inventing a network kind.
      signalLevel: signalLevel == null || signalLevel < 0 || signalLevel > 4 ? null : signalLevel,
      unreadMessageCount: unreadMessageCount == null || unreadMessageCount < 0 ? null : unreadMessageCount,
      notificationCount: notificationCount == null || notificationCount < 0 ? null : notificationCount,
      supportsFindDevice: supportsFindDevice,
      supportsClipboard: supportsClipboard,
      supportsMessages: supportsMessages,
      supportsNotifications: supportsNotifications,
      showNetworkLabel: showNetworkLabel,
      showBatteryPercentage: showBatteryPercentage,
      showNotifications: showNotifications,
      chargingAnimationEnabled: chargingAnimationEnabled,
      showSignal: showSignal,
      phoneCount: phoneCount < 1 ? 1 : phoneCount,
      lastUpdated: lastUpdated,
    );
  }

  static const String _fallbackName = 'Phone';

  static String? _nonEmpty(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  bool get hasBattery => batteryPercentage != null;

  bool get hasNetwork => networkKind != null || networkLabel != null;

  /// Picks the phone a shell surface should present, or null when Relay has no
  /// phone worth showing.
  ///
  /// Only paired phones qualify. When [pinnedDeviceId] is set, the panel remains
  /// pinned to that specific device (and reports its disconnected state if offline).
  /// When [pinnedDeviceId] is null, the panel follows Relay's [focusedDeviceId],
  /// falling back to the primary connected phone if none is focused.
  static RelayPhoneShellStatus? select({
    required List<RelayDeviceVm> devices,
    required DateTime now,
    String? pinnedDeviceId,
    String? focusedDeviceId,
    bool showNetworkLabel = true,
    bool showBatteryPercentage = true,
    bool showNotifications = true,
    bool chargingAnimationEnabled = true,
    bool showSignal = true,
    Map<String, int> notificationCounts = const {},
    Map<String, int> unreadMessageCounts = const {},
  }) {
    final candidates = devices.where(isEligiblePhone).toList()..sort(_byPrimaryPreference);

    RelayDeviceVm? chosen;

    if (pinnedDeviceId != null && pinnedDeviceId.isNotEmpty) {
      // User-pinned device: strictly stay bound to this device.
      // Even if disconnected, do NOT jump to another connected phone.
      chosen = devices.firstWhereOrNull((device) => device.key == pinnedDeviceId);
      if (chosen == null) {
        return null;
      }
    } else {
      // Follow selected / focused device:
      if (focusedDeviceId != null) {
        chosen = candidates.firstWhereOrNull((device) => device.key == focusedDeviceId);
      }
      // Fallback if focused device is not an eligible phone:
      chosen ??= candidates.firstOrNull;
    }

    if (chosen == null) {
      return null;
    }

    return fromDevice(
      chosen,
      now: now,
      phoneCount: candidates.length,
      notificationCount: notificationCounts[chosen.key],
      unreadMessageCount: unreadMessageCounts[chosen.key],
      showNetworkLabel: showNetworkLabel,
      showBatteryPercentage: showBatteryPercentage,
      showNotifications: showNotifications,
      chargingAnimationEnabled: chargingAnimationEnabled,
      showSignal: showSignal,
    );
  }

  /// Whether this device is a phone Relay is entitled to present in the shell.
  static bool isEligiblePhone(RelayDeviceVm device) => device.deviceType == DeviceType.mobile && device.isPaired;

  /// Whether a live link exists, across every transport Relay speaks.
  static bool isConnected(RelayDeviceVm device) => device.isKdeConnect ? device.connectionState.isConnected : device.continuityConnected;

  /// The core's primary-device preference, applied to the shell's candidates.
  ///
  /// Showing one device is a deliberate presentation choice, so the choice is
  /// explicit and total rather than falling out of iteration order. A connected
  /// phone and a connected tablet are separate ranks, not one "connected mobile"
  /// bucket: without that, a tablet that happened to be more recently active
  /// took the place of the phone the user actually meant.
  static int _byPrimaryPreference(RelayDeviceVm a, RelayDeviceVm b) {
    final rankComparison = _primaryRank(a).compareTo(_primaryRank(b));
    if (rankComparison != 0) {
      return rankComparison;
    }
    // Most recently active first; a device with no timestamp sorts last.
    final recency = (b.lastSeenUnix ?? -1).compareTo(a.lastSeenUnix ?? -1);
    // Falling through to the id keeps the answer stable across rebuilds.
    return recency != 0 ? recency : a.key.compareTo(b.key);
  }

  static int _primaryRank(RelayDeviceVm device) {
    final connected = isConnected(device);
    return switch (device.deviceClass) {
      RelayDeviceClass.phone => connected ? 0 : 3,
      RelayDeviceClass.tablet => connected ? 1 : 4,
      // A device with no fabric class is still rankable by connectivity alone.
      _ => connected ? 2 : 5,
    };
  }

  /// Maps Relay's canonical device model onto the shell snapshot.
  ///
  /// Network and unread-message state have no source in Relay yet, so they stay
  /// absent here. When a Relay capability starts reporting them this mapping
  /// gains the fields and every shell surface picks them up unchanged.
  static RelayPhoneShellStatus fromDevice(
    RelayDeviceVm device, {
    required DateTime now,
    int phoneCount = 1,
    int? notificationCount,
    int? unreadMessageCount,
    bool showNetworkLabel = true,
    bool showBatteryPercentage = true,
    bool showNotifications = true,
    bool chargingAnimationEnabled = true,
    bool showSignal = true,
  }) {
    final capabilities = device.capabilityStatuses;
    final battery = device.battery;
    final connected = isConnected(device);
    final notifications = _isUsable(capabilities[RelayCapability.notifications]);
    return RelayPhoneShellStatus(
      deviceId: device.key,
      displayName: device.alias,
      deviceType: device.deviceType.name,
      connected: connected,
      paired: device.isPaired,
      batteryPercentage: battery.percentage,
      batteryIsCharging: battery.isCharging,
      batteryIsFull: battery.isFull,
      batteryIsStale: battery.isStale || (battery.percentage != null && !connected),
      networkKind: device.networkType == null ? null : 'cellular',
      networkLabel: device.networkType,
      signalLevel: device.connectivityStale ? null : device.signalLevel,
      // Ringing a phone needs a live link to carry the request, so the action is
      // only advertised while one exists.
      supportsFindDevice: device.isKdeConnect && device.canFindDevice && connected,
      supportsClipboard: _isUsable(capabilities[RelayCapability.clipboard]),
      supportsMessages: _isUsable(capabilities[RelayCapability.messages]),
      supportsNotifications: notifications,
      // A count only means something while the mirror is live; a phone that
      // went away is not still holding three notifications for the user.
      notificationCount: notifications && connected ? notificationCount ?? 0 : null,
      unreadMessageCount: _isUsable(capabilities[RelayCapability.messages]) && connected ? unreadMessageCount ?? 0 : null,
      showNetworkLabel: showNetworkLabel,
      showBatteryPercentage: showBatteryPercentage,
      showNotifications: showNotifications,
      chargingAnimationEnabled: chargingAnimationEnabled,
      showSignal: showSignal,
      phoneCount: phoneCount,
      lastUpdated: now,
    );
  }

  static bool _isUsable(CapabilityStatus? status) => status == CapabilityStatus.available || status == CapabilityStatus.limited;

  /// The wire form handed to the platform bridge.
  ///
  /// Optional fields are omitted rather than sent as a sentinel, so "unknown"
  /// survives the trip as a missing key. Only presentation state appears here:
  /// message bodies, notification text, clipboard contents, phone numbers,
  /// contacts and every piece of trust material stay inside Relay.
  Map<String, Object?> toBridgeMap() => <String, Object?>{
    'deviceId': deviceId,
    'displayName': displayName,
    'deviceType': deviceType,
    'connected': connected,
    'paired': paired,
    if (batteryPercentage != null) 'batteryPercentage': batteryPercentage,
    if (batteryIsCharging != null) 'batteryIsCharging': batteryIsCharging,
    if (batteryIsFull != null) 'batteryIsFull': batteryIsFull,
    'batteryIsStale': batteryIsStale,
    if (networkKind != null) 'networkKind': networkKind,
    if (networkLabel != null) 'networkLabel': networkLabel,
    if (signalLevel != null) 'signalLevel': signalLevel,
    if (unreadMessageCount != null) 'unreadMessageCount': unreadMessageCount,
    if (notificationCount != null) 'notificationCount': notificationCount,
    'supportsFindDevice': supportsFindDevice,
    'supportsClipboard': supportsClipboard,
    'supportsMessages': supportsMessages,
    'supportsNotifications': supportsNotifications,
    'showNetworkLabel': showNetworkLabel,
    'showBatteryPercentage': showBatteryPercentage,
    'showNotifications': showNotifications,
    'chargingAnimationEnabled': chargingAnimationEnabled,
    'showSignal': showSignal,
    'phoneCount': phoneCount,
    'lastUpdated': lastUpdated.millisecondsSinceEpoch,
  };

  /// Whether two snapshots describe the same phone state.
  ///
  /// [lastUpdated] is excluded on purpose: it moves on every rebuild and would
  /// turn an idle app into a stream of identical shell updates.
  bool sameStateAs(RelayPhoneShellStatus? other) {
    if (other == null) {
      return false;
    }
    return deviceId == other.deviceId &&
        displayName == other.displayName &&
        deviceType == other.deviceType &&
        connected == other.connected &&
        paired == other.paired &&
        batteryPercentage == other.batteryPercentage &&
        batteryIsCharging == other.batteryIsCharging &&
        batteryIsFull == other.batteryIsFull &&
        batteryIsStale == other.batteryIsStale &&
        networkKind == other.networkKind &&
        networkLabel == other.networkLabel &&
        signalLevel == other.signalLevel &&
        unreadMessageCount == other.unreadMessageCount &&
        notificationCount == other.notificationCount &&
        supportsFindDevice == other.supportsFindDevice &&
        supportsClipboard == other.supportsClipboard &&
        supportsMessages == other.supportsMessages &&
        supportsNotifications == other.supportsNotifications &&
        showNetworkLabel == other.showNetworkLabel &&
        showBatteryPercentage == other.showBatteryPercentage &&
        showNotifications == other.showNotifications &&
        chargingAnimationEnabled == other.chargingAnimationEnabled &&
        showSignal == other.showSignal &&
        phoneCount == other.phoneCount;
  }
}
