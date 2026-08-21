import 'package:refena_flutter/refena_flutter.dart';

/// Tracks the currently focused/selected device in Relay's desktop UI.
final selectedDeviceProvider = NotifierProvider<SelectedDeviceService, String?>(
  (ref) => SelectedDeviceService(),
  debugLabel: 'selectedDeviceProvider',
);

class SelectedDeviceService extends PureNotifier<String?> {
  @override
  String? init() => null;

  void selectDevice(String? deviceKey) {
    if (state != deviceKey) {
      state = deviceKey;
    }
  }
}
