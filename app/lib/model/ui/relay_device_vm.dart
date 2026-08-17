import 'package:localsend_isolates/model/device.dart';

enum RelayDevicePhase {
  idle,
  waiting,
  verifying,
  sending,
  success,
  failed,
}

/// Immutable, presentation-only description of a nearby Relay target.
class RelayDeviceVm {
  final String key;
  final String alias;
  final DeviceType deviceType;
  final RelayDevicePhase phase;
  final double? progress;
  final String detail;

  const RelayDeviceVm({
    required this.key,
    required this.alias,
    required this.deviceType,
    required this.phase,
    required this.progress,
    required this.detail,
  });
}
