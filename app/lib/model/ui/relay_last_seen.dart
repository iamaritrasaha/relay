import 'package:relay_isolates/rust/api/kdeconnect.dart';

/// Physical form factor, already normalised by the core.
///
/// Kept distinct from `DeviceType`, which collapses phone and tablet into one
/// `mobile` value. That collapse is exactly what let a tablet take a connected
/// phone's place in the GNOME pill, so the surfaces that must tell them apart
/// read this instead.
enum RelayDeviceClass {
  desktop,
  laptop,
  phone,
  tablet,
  tv,
  other
  ;

  static RelayDeviceClass fromCore(RsRelayDeviceClass raw) => switch (raw) {
    RsRelayDeviceClass.desktop => RelayDeviceClass.desktop,
    RsRelayDeviceClass.laptop => RelayDeviceClass.laptop,
    RsRelayDeviceClass.phone => RelayDeviceClass.phone,
    RsRelayDeviceClass.tablet => RelayDeviceClass.tablet,
    RsRelayDeviceClass.tv => RelayDeviceClass.tv,
    RsRelayDeviceClass.other => RelayDeviceClass.other,
  };

  bool get isMobile => this == RelayDeviceClass.phone || this == RelayDeviceClass.tablet;

  String get label => switch (this) {
    RelayDeviceClass.desktop => 'Desktop',
    RelayDeviceClass.laptop => 'Laptop',
    RelayDeviceClass.phone => 'Phone',
    RelayDeviceClass.tablet => 'Tablet',
    RelayDeviceClass.tv => 'TV',
    RelayDeviceClass.other => 'Device',
  };
}

/// How long ago a device was last heard from, in the words a person uses.
///
/// Reads the Device Fabric's own timestamp — never a widget rebuild time, which
/// would make every device look freshly seen the moment the page was opened.
///
/// Deliberately coarse. A device last heard from two hours ago is "2 h ago";
/// exposing "2 h 14 min" implies a precision the route-freshness sampling does
/// not have, and nothing the user decides depends on the extra digits.
String relayLastSeenLabel(int? lastSeenUnix, {required DateTime now}) {
  if (lastSeenUnix == null) {
    return 'Never';
  }
  final seen = DateTime.fromMillisecondsSinceEpoch(lastSeenUnix * 1000, isUtc: true).toLocal();
  final elapsed = now.difference(seen);

  // A clock that has gone backwards (NTP correction, suspend/resume) must not
  // produce "in 3 minutes"; the honest reading is that it was just seen.
  if (elapsed.isNegative || elapsed.inMinutes < 1) {
    return 'Just now';
  }
  if (elapsed.inMinutes < 60) {
    return '${elapsed.inMinutes} min ago';
  }
  // Calendar days, not 24-hour blocks: 23:50 yesterday read at 00:10 today is
  // "Yesterday" to a person, however few hours have passed.
  final today = DateTime(now.year, now.month, now.day);
  final seenDay = DateTime(seen.year, seen.month, seen.day);
  final daysApart = today.difference(seenDay).inDays;
  if (daysApart == 0) {
    return '${elapsed.inHours} h ago';
  }
  if (daysApart == 1) {
    return 'Yesterday';
  }
  if (daysApart < 7) {
    return '$daysApart days ago';
  }
  return 'A long time ago';
}
