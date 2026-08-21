import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:relay_app/config/theme.dart';
import 'package:relay_app/model/persistence/color_mode.dart';
import 'package:relay_app/model/persistence/quick_save_mode.dart';
import 'package:relay_app/model/persistence/relay_paired_address.dart';
import 'package:relay_app/model/ui/relay_capability_vm.dart';
import 'package:relay_app/model/ui/relay_device_vm.dart';
import 'package:relay_app/pages/gnome/gnome_shell.dart';
import 'package:relay_app/pages/relay_home_vm.dart';
import 'package:relay_app/provider/device_info_provider.dart';
import 'package:relay_app/provider/kdeconnect_provider.dart';
import 'package:relay_app/provider/persistence_provider.dart';
import 'package:relay_app/util/ui/dynamic_colors.dart';
import 'package:relay_app/widget/dialogs/kdeconnect_incoming_pair_dialog.dart';
import 'package:relay_isolates/isolate.dart';
import 'package:relay_isolates/model/device.dart';
import 'package:relay_isolates/model/device_info_result.dart';
import 'package:relay_isolates/model/dto/multicast_dto.dart';
import 'package:relay_isolates/model/stored_security_context.dart';

import '../mocks.mocks.dart';

class _TestPersistenceService extends MockPersistenceService {
  @override
  bool getRemoteRelayEnabled() => false;

  @override
  List<RelayPairedAddress> getRelayPairedAddresses() => const [];
}

class _TestIsolateController extends IsolateController {
  _TestIsolateController()
    : super(
        initialState: ParentIsolateState(
          syncState: SyncState(
            rootIsolateToken: Object(),
            securityContext: const StoredSecurityContext(
              privateKey: '',
              publicKey: '',
              certificate: '',
              certificateHash: '',
            ),
            deviceInfo: DeviceInfoResult(deviceType: DeviceType.desktop, deviceModel: 'Linux', androidSdkInt: null),
            alias: 'Fedora Workstation',
            port: 53317,
            networkWhitelist: null,
            networkBlacklist: null,
            protocol: ProtocolType.https,
            multicastGroup: '224.0.0.167',
            discoveryTimeout: 30,
            serverRunning: false,
            download: false,
          ),
          discovery: null,
          httpUpload: null,
          httpServer: null,
        ),
      );
}

void main() {
  final darkTheme = getTheme(ColorMode.relay, Colors.teal, Brightness.dark, null);
  late _TestPersistenceService mockPersistence;

  setUp(() {
    mockPersistence = _TestPersistenceService();
    when(mockPersistence.getReceiveHistory()).thenReturn([]);
    when(mockPersistence.getShowToken()).thenReturn('test-token');
    when(mockPersistence.getAlias()).thenReturn('Fedora Workstation');
    when(mockPersistence.getTheme()).thenReturn(ThemeMode.system);
    when(mockPersistence.getColorMode()).thenReturn(ColorMode.relay);
    when(mockPersistence.getPort()).thenReturn(53317);
    when(mockPersistence.getNetworkWhitelist()).thenReturn([]);
    when(mockPersistence.getNetworkBlacklist()).thenReturn([]);
    when(mockPersistence.getMulticastGroup()).thenReturn('224.0.0.167');
    when(mockPersistence.getDestination()).thenReturn(null);
    when(mockPersistence.getQuickSave()).thenReturn(QuickSaveMode.off);
    when(mockPersistence.isSaveToGallery()).thenReturn(false);
    when(mockPersistence.isSaveToHistory()).thenReturn(true);
    when(mockPersistence.isAutoFinish()).thenReturn(false);
    when(mockPersistence.isMinimizeToTray()).thenReturn(false);
    when(mockPersistence.isHttps()).thenReturn(true);
    when(mockPersistence.getSaveWindowPlacement()).thenReturn(false);
    when(mockPersistence.getEnableAnimations()).thenReturn(true);
    when(mockPersistence.getDeviceType()).thenReturn(DeviceType.desktop);
    when(mockPersistence.getShareViaLinkAutoAccept()).thenReturn(false);
    when(mockPersistence.getReceiveViaLinkAutoAccept()).thenReturn(false);
    when(mockPersistence.getCreateChecksums()).thenReturn(true);
    when(mockPersistence.getVerifyChecksums()).thenReturn(true);
    when(mockPersistence.getAdvancedSettingsEnabled()).thenReturn(false);
  });

  const nearbyPhone = RelayDeviceVm(
    key: 'kdeconnect:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    alias: 'Pixel',
    deviceType: DeviceType.mobile,
    phase: RelayDevicePhase.idle,
    progress: null,
    detail: 'Nearby',
    targetKind: RelayDeviceTargetKind.kdeConnect,
  );

  const pairedPhone = RelayDeviceVm(
    key: 'kdeconnect:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    alias: 'Pixel',
    deviceType: DeviceType.mobile,
    phase: RelayDevicePhase.idle,
    progress: null,
    detail: 'Paired',
    targetKind: RelayDeviceTargetKind.kdeConnect,
  );

  const pairedPhoneNoBattery = RelayDeviceVm(
    key: 'kdeconnect:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    alias: 'Pixel',
    deviceType: DeviceType.mobile,
    phase: RelayDevicePhase.idle,
    progress: null,
    detail: 'Connected',
    targetKind: RelayDeviceTargetKind.kdeConnect,
    battery: RelayBatteryVm(percentage: null, isCharging: false, isFull: false, isStale: false),
  );

  const pairedPhoneCharging = RelayDeviceVm(
    key: 'kdeconnect:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    alias: 'Pixel',
    deviceType: DeviceType.mobile,
    phase: RelayDevicePhase.idle,
    progress: null,
    detail: 'Connected',
    targetKind: RelayDeviceTargetKind.kdeConnect,
    battery: RelayBatteryVm(percentage: 76, isCharging: true, isFull: false, isStale: false),
  );

  const pairedPhoneUnplugged = RelayDeviceVm(
    key: 'kdeconnect:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    alias: 'Pixel',
    deviceType: DeviceType.mobile,
    phase: RelayDevicePhase.idle,
    progress: null,
    detail: 'Connected',
    targetKind: RelayDeviceTargetKind.kdeConnect,
    battery: RelayBatteryVm(percentage: 76, isCharging: false, isFull: false, isStale: false),
  );

  const pairedPhoneStale = RelayDeviceVm(
    key: 'kdeconnect:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    alias: 'Pixel',
    deviceType: DeviceType.mobile,
    phase: RelayDevicePhase.idle,
    progress: null,
    detail: 'Paired',
    targetKind: RelayDeviceTargetKind.kdeConnect,
    battery: RelayBatteryVm(percentage: 76, isCharging: false, isFull: false, isStale: true),
  );

  const relayDevice = RelayDeviceVm(
    key: 'relay:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
    alias: 'Redmi',
    deviceType: DeviceType.mobile,
    phase: RelayDevicePhase.idle,
    progress: null,
    detail: 'Nearby',
    targetKind: RelayDeviceTargetKind.verifiedRelay,
    relayId: 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
  );

  RelayHomeVm vm(List<RelayDeviceVm> devices) => RelayHomeVm(
    selfAlias: 'Fedora Workstation',
    selfDeviceType: DeviceType.desktop,
    presence: RelayPresence.ready,
    selection: const RelayPayloadVm(fileCount: 0, totalBytes: 0),
    devices: devices,
    incoming: const RelayIncomingVm(hasActiveRequest: false),
    intents: const RelayHomeIntents(canSelectPayload: true, canChooseTarget: true),
    activeTransfer: null,
  );

  Future<void> pumpShell(WidgetTester tester, RelayHomeVm home) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      RefenaScope(
        overrides: [
          persistenceProvider.overrideWithValue(mockPersistence),
          dynamicColorsProvider.overrideWithValue(null),
          deviceRawInfoProvider.overrideWithValue(
            DeviceInfoResult(deviceType: DeviceType.desktop, deviceModel: 'Linux', androidSdkInt: null),
          ),
          parentIsolateProvider.overrideWithNotifier((ref) => _TestIsolateController()),
        ],
        child: MaterialApp(
          theme: darkTheme,
          home: Scaffold(body: GnomeShell(vm: home, animationsEnabled: false)),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }

  testWidgets('Nearby KDE Connect phone shows Pair', (tester) async {
    await pumpShell(tester, vm([nearbyPhone]));
    expect(find.text('Pixel'), findsWidgets);
    expect(find.text('Nearby'), findsWidgets);
    expect(find.byKey(const ValueKey('kdeconnect-pair-device')), findsOneWidget);
    expect(find.byKey(const ValueKey('gnome-send-files-button')), findsNothing);
  });

  testWidgets('paired KDE Connect phone shows Remove Device', (tester) async {
    await pumpShell(tester, vm([pairedPhone]));
    expect(find.text('Paired'), findsWidgets);
    expect(find.byKey(const ValueKey('kdeconnect-remove-device')), findsOneWidget);
  });

  testWidgets('incoming request shows accept and reject', (tester) async {
    await tester.pumpWidget(
      RefenaScope(
        child: MaterialApp(
          theme: darkTheme,
          home: const KdeConnectIncomingPairDialog(
            request: KdeConnectIncomingRequest(deviceId: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', name: 'Pixel'),
          ),
        ),
      ),
    );
    expect(find.text('Pixel wants to pair with Relay'), findsOneWidget);
    expect(find.text('Accept'), findsOneWidget);
    expect(find.text('Reject'), findsOneWidget);
  });

  testWidgets('Relay-native device still shows Send Files beside a KDE Connect phone', (tester) async {
    await pumpShell(tester, vm([nearbyPhone, relayDevice]));
    expect(find.text('Pixel'), findsWidgets);
    expect(find.text('Redmi'), findsWidgets);
    await tester.tap(find.text('Redmi').first);
    await tester.pump();
    expect(find.text('Send Files'), findsWidgets);
  });

  testWidgets('paired KDE Connect phone with no battery shows Waiting for battery status', (tester) async {
    await pumpShell(tester, vm([pairedPhoneNoBattery]));
    expect(find.text('Pixel'), findsWidgets);
    expect(find.text('Battery'), findsWidgets);
    expect(find.text('Waiting for battery status'), findsOneWidget);
    expect(find.text('—'), findsWidgets);
  });

  testWidgets('paired KDE Connect phone with charging battery shows percentage and Charging', (tester) async {
    await pumpShell(tester, vm([pairedPhoneCharging]));
    expect(find.text('Pixel'), findsWidgets);
    expect(find.text('Battery'), findsWidgets);
    expect(find.text('76%'), findsWidgets);
    expect(find.text('Charging'), findsOneWidget);
  });

  testWidgets('paired KDE Connect phone with unplugged battery shows percentage and On battery', (tester) async {
    await pumpShell(tester, vm([pairedPhoneUnplugged]));
    expect(find.text('Pixel'), findsWidgets);
    expect(find.text('Battery'), findsWidgets);
    expect(find.text('76%'), findsWidgets);
    expect(find.text('On battery'), findsOneWidget);
  });

  testWidgets('disconnected KDE Connect phone shows stale battery subtitle', (tester) async {
    await pumpShell(tester, vm([pairedPhoneStale]));
    expect(find.text('Pixel'), findsWidgets);
    expect(find.text('Battery'), findsWidgets);
    expect(find.text('76%'), findsWidgets);
    expect(find.text('Last known before disconnecting'), findsOneWidget);
  });

  testWidgets('paired KDE Connect phone exposes compact ping and find-phone actions', (tester) async {
    await pumpShell(tester, vm([pairedPhoneCharging]));
    expect(find.text('Ping'), findsOneWidget);
    expect(find.text('Find Phone'), findsOneWidget);
  });
}
