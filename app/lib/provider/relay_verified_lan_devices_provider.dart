import 'package:relay_isolates/model/device.dart';
import 'package:refena_flutter/refena_flutter.dart';

/// A live proof-backed association between a RelayId and a LAN observation.
///
/// This is deliberately not trust and is not created by discovery, an IP,
/// a display name, or a pairing address. It exists only after the LAN server
/// proves the RelayId while the HTTP client is pinned to that observation's
/// certificate. The current discovery observation is still required before it
/// can be offered as a LAN transport.
class RelayVerifiedLanDevice {
  final String relayId;
  final Device device;

  const RelayVerifiedLanDevice({required this.relayId, required this.device});
}

final relayVerifiedLanDevicesProvider = NotifierProvider<RelayVerifiedLanDevicesNotifier, Map<String, RelayVerifiedLanDevice>>((ref) {
  return RelayVerifiedLanDevicesNotifier();
});

class RelayVerifiedLanDevicesNotifier extends Notifier<Map<String, RelayVerifiedLanDevice>> {
  @override
  Map<String, RelayVerifiedLanDevice> init() => {};

  void record({required String relayId, required Device device}) {
    state = {
      ...state,
      relayId: RelayVerifiedLanDevice(relayId: relayId, device: device),
    };
  }
}
