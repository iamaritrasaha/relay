import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:relay_app/config/theme.dart';
import 'package:relay_app/model/persistence/color_mode.dart';
import 'package:relay_app/model/persistence/quick_save_mode.dart';
import 'package:relay_app/model/ui/relay_capability_vm.dart';
import 'package:relay_app/model/ui/relay_device_vm.dart';
import 'package:relay_app/pages/gnome/gnome_settings_view.dart';
import 'package:relay_app/pages/gnome/gnome_shell.dart';
import 'package:relay_app/pages/relay_home_vm.dart';
import 'package:relay_app/provider/device_info_provider.dart';
import 'package:relay_app/provider/persistence_provider.dart';
import 'package:relay_app/util/ui/dynamic_colors.dart';
import 'package:relay_app/widget/relay/relay_device_silhouette.dart';
import 'package:relay_isolates/isolate.dart';
import 'package:relay_isolates/model/device.dart';
import 'package:relay_isolates/model/device_info_result.dart';
import 'package:relay_isolates/model/dto/multicast_dto.dart';
import 'package:relay_isolates/model/stored_security_context.dart';

import '../../mocks.mocks.dart';

class _TestPersistenceService extends MockPersistenceService {
  @override
  bool getRemoteRelayEnabled() => false;
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
    when(mockPersistence.setAlias(any)).thenAnswer((_) async {});
    when(mockPersistence.setQuickSave(any)).thenAnswer((_) async {});
    when(mockPersistence.setEnableAnimations(any)).thenAnswer((_) async {});
    when(mockPersistence.setSaveToHistory(any)).thenAnswer((_) async {});
    when(mockPersistence.setAutoFinish(any)).thenAnswer((_) async {});
  });

  const testDevice = RelayDeviceVm(
    key: 'pixel-key',
    alias: 'Pixel 8 Pro',
    deviceType: DeviceType.mobile,
    phase: RelayDevicePhase.idle,
    progress: null,
    detail: 'Ready',
    targetKind: RelayDeviceTargetKind.verifiedRelay,
    relayId: 'relay-pixel-8',
    lanFingerprint: 'FP-PIXEL-8',
    connectionType: RelayConnectionType.local,
    securityState: RelaySecurityState.verifiedRelay,
    battery: RelayBatteryVm(percentage: 85, isCharging: true),
  );

  const testVm = RelayHomeVm(
    selfAlias: 'Fedora Workstation',
    selfDeviceType: DeviceType.desktop,
    presence: RelayPresence.ready,
    selection: RelayPayloadVm(fileCount: 0, totalBytes: 0),
    devices: [testDevice],
    incoming: RelayIncomingVm(hasActiveRequest: false),
    intents: RelayHomeIntents(canSelectPayload: true, canChooseTarget: true),
    activeTransfer: null,
  );

  testWidgets('GnomeShell renders sidebar, header, and device details', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

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
          home: const Scaffold(
            body: GnomeShell(
              vm: testVm,
              animationsEnabled: true,
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // Verify presence of sidebar, spatial scene and device details
    expect(find.text('NEARBY DEVICES'), findsOneWidget);
    expect(find.text('Pixel 8 Pro'), findsWidgets);
    expect(find.text('Send Files'), findsWidgets);
    expect(find.text('Send Folder'), findsOneWidget);
    expect(find.text('Clipboard'), findsWidgets);
    expect(find.text('Messages'), findsWidgets);
  });

  testWidgets('GnomeSettingsView renders all 5 reconstructed semantic groups with truthful labels', (tester) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

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
          home: const Scaffold(
            body: GnomeSettingsView(),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // 1. THIS DEVICE Hero (truthful identity, no false live readiness)
    expect(find.text('THIS DEVICE'), findsOneWidget);
    expect(find.byType(RelayDeviceSilhouette), findsOneWidget);
    expect(find.text('Fedora Workstation'), findsOneWidget);
    expect(find.text('Desktop · Relay Device'), findsOneWidget);
    expect(find.text('Ready on Local Network'), findsNothing);

    // 2. RELAY EXPERIENCE (truthful favorites semantics)
    expect(find.text('RELAY EXPERIENCE'), findsOneWidget);
    expect(find.text('Pair New Device'), findsOneWidget);
    expect(find.text('Quick Save'), findsOneWidget);
    expect(find.text('Quick Save from Favorites'), findsOneWidget);
    expect(find.text('Automatically accept transfers from devices marked as favorites'), findsOneWidget);
    expect(find.text('Quick Save from Paired Only'), findsNothing);
    expect(find.text('Auto-accept only from verified trusted peers'), findsNothing);
    expect(find.text('Spatial Animations'), findsOneWidget);

    // 3. TRANSFERS
    expect(find.text('TRANSFERS'), findsOneWidget);
    expect(find.text('Destination Directory'), findsOneWidget);
    expect(find.text('Save to History'), findsOneWidget);
    expect(find.text('Auto-Finish'), findsOneWidget);

    // 4. APPEARANCE
    expect(find.text('APPEARANCE'), findsOneWidget);
    expect(find.text('Theme'), findsOneWidget);
    expect(find.text('Color Theme'), findsOneWidget);
    expect(find.text('Language'), findsOneWidget);

    // 5. ABOUT RELAY
    expect(find.text('ABOUT RELAY'), findsOneWidget);
    expect(find.text('About'), findsOneWidget);
    expect(find.text('Changelog'), findsOneWidget);

    // Interactivity: Randomize alias writes to settings
    await tester.tap(find.byTooltip('Random Name'));
    await tester.pump();
    verify(mockPersistence.setAlias(any)).called(1);
  });
}
