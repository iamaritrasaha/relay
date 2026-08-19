import 'package:collection/collection.dart';
import 'package:relay_app/model/ui/relay_capability_vm.dart';
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
      // A signal bucket without a network to attach it to would render as a
      // free-floating set of bars, so it travels with the network fields.
      signalLevel: network == null || signalLevel == null || signalLevel < 0 || signalLevel > 4 ? null : signalLevel,
      unreadMessageCount: unreadMessageCount == null || unreadMessageCount < 0 ? null : unreadMessageCount,
      notificationCount: notificationCount == null || notificationCount < 0 ? null : notificationCount,
      supportsFindDevice: supportsFindDevice,
      supportsClipboard: supportsClipboard,
      supportsMessages: supportsMessages,
      supportsNotifications: supportsNotifications,
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
  /// Only paired phones qualify: an unpaired handset that happens to be on the
  /// network is a discovery result, not "the user's phone". Ordering is
  /// connected first and then by key, which makes the choice deterministic
  /// rather than dependent on arrival order. [preferredDeviceId] keeps a phone
  /// that is still just as good as the best candidate, so a second phone
  /// briefly connecting never yanks the pill away from the one in use.
  static RelayPhoneShellStatus? select({
    required List<RelayDeviceVm> devices,
    required DateTime now,
    String? preferredDeviceId,
    Map<String, int> notificationCounts = const {},
  }) {
    final candidates = devices.where(isEligiblePhone).toList()
      ..sort((a, b) {
        final connectedComparison = _boolRank(isConnected(b)).compareTo(_boolRank(isConnected(a)));
        return connectedComparison != 0 ? connectedComparison : a.key.compareTo(b.key);
      });
    if (candidates.isEmpty) {
      return null;
    }

    final best = candidates.first;
    final preferred = preferredDeviceId == null ? null : candidates.firstWhereOrNull((device) => device.key == preferredDeviceId);
    final chosen = preferred != null && isConnected(preferred) == isConnected(best) ? preferred : best;

    return fromDevice(chosen, now: now, phoneCount: candidates.length, notificationCount: notificationCounts[chosen.key]);
  }

  /// Whether this device is a phone Relay is entitled to present in the shell.
  static bool isEligiblePhone(RelayDeviceVm device) => device.deviceType == DeviceType.mobile && device.isPaired;

  /// Whether a live link exists, across every transport Relay speaks.
  static bool isConnected(RelayDeviceVm device) => device.isKdeConnect ? device.detail == 'Connected' : device.continuityConnected;

  static int _boolRank(bool value) => value ? 1 : 0;

  /// Maps Relay's canonical device model onto the shell snapshot.
  ///
  /// Network and unread-message state have no source in Relay yet, so they stay
  /// absent here. When a Relay capability starts reporting them this mapping
  /// gains the fields and every shell surface picks them up unchanged.
  static RelayPhoneShellStatus fromDevice(RelayDeviceVm device, {required DateTime now, int phoneCount = 1, int? notificationCount}) {
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
      // Ringing a phone needs a live link to carry the request, so the action is
      // only advertised while one exists.
      supportsFindDevice: device.isKdeConnect && device.isPaired && connected,
      supportsClipboard: _isUsable(capabilities[RelayCapability.clipboard]),
      supportsMessages: _isUsable(capabilities[RelayCapability.messages]),
      supportsNotifications: notifications,
      // A count only means something while the mirror is live; a phone that
      // went away is not still holding three notifications for the user.
      notificationCount: notifications && connected ? notificationCount ?? 0 : null,
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
        phoneCount == other.phoneCount;
  }
}
