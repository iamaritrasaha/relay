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
import 'package:relay_app/widget/gnome/relay_connection_status.dart';
import 'package:relay_isolates/isolate.dart';
import 'package:relay_isolates/model/device.dart';
import 'package:relay_isolates/model/device_info_result.dart';
import 'package:relay_isolates/model/dto/multicast_dto.dart';
import 'package:relay_isolates/model/stored_security_context.dart';
import 'package:yaru/yaru.dart';

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
  final lightTheme = getTheme(ColorMode.relay, Colors.teal, Brightness.light, null);
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

  Future<void> pumpShell(WidgetTester tester, RelayHomeVm home, {ThemeData? theme, Size size = const Size(1200, 800)}) async {
    tester.view.physicalSize = size;
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
          theme: theme ?? darkTheme,
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

  testWidgets('device information uses joined groups with a separate destructive action', (tester) async {
    await pumpShell(tester, vm([pairedPhoneNoBattery]));

    final statusGroup = find.byKey(const ValueKey('device-status-group'));
    final detailsGroup = find.byKey(const ValueKey('device-details-group'));
    final remove = find.byKey(const ValueKey('kdeconnect-remove-device'));

    expect(statusGroup, findsOneWidget);
    expect(detailsGroup, findsOneWidget);
    expect(find.descendant(of: statusGroup, matching: find.text('Device Status')), findsNothing);
    expect(find.descendant(of: detailsGroup, matching: find.text('Device Details')), findsNothing);
    expect(find.byKey(const ValueKey('device-relationship-section')), findsOneWidget);
    expect(remove, findsOneWidget);
    expect(find.descendant(of: statusGroup, matching: remove), findsNothing);
    expect(find.descendant(of: detailsGroup, matching: remove), findsNothing);
    expect(find.byKey(const ValueKey('device-actions-section')), findsNothing);
    expect(find.byKey(const ValueKey('device-actions-group')), findsNothing);
    expect(find.text('Device'), findsOneWidget, reason: 'only the Device Status row label remains; the redundant section title is gone');
    expect(find.byType(RelayConnectionStatus), findsWidgets);

    final detailsBottom = tester.getBottomLeft(detailsGroup).dy;
    final removeTop = tester.getTopLeft(remove).dy;
    expect(removeTop, greaterThan(detailsBottom));

    final hoverRegion = tester.widget<AnimatedContainer>(
      find.descendant(of: remove, matching: find.byKey(const ValueKey('device-maintenance-hover-region'))),
    );
    final decoration = hoverRegion.decoration! as BoxDecoration;
    expect(decoration.color, Colors.transparent);
    expect(decoration.border, isNull);
    expect(tester.getSize(remove).height, inInclusiveRange(36, 40));

    for (final group in [statusGroup, detailsGroup]) {
      final material = tester.widget<Material>(find.descendant(of: group, matching: find.byType(Material)).first);
      expect((material.shape! as RoundedRectangleBorder).side, BorderSide.none);
      expect(material.clipBehavior, Clip.antiAlias);
    }

    final connectedLabels = tester.widgetList<Text>(find.textContaining('Connected'));
    final success = YaruColors.of(tester.element(find.textContaining('Connected').first)).success;
    expect(connectedLabels, isNotEmpty);
    for (final label in connectedLabels) {
      expect(label.style?.color, isNot(success));
    }
  });

  testWidgets('device information groups build with Yaru light colors', (tester) async {
    await pumpShell(tester, vm([pairedPhoneNoBattery]), theme: lightTheme);
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('device-status-group')), findsOneWidget);
    expect(find.byKey(const ValueKey('device-details-group')), findsOneWidget);
    expect(find.byKey(const ValueKey('kdeconnect-remove-device')), findsOneWidget);
  });

  testWidgets('Overview wide layout uses one 7:5 master grid and consistent full-width edges', (tester) async {
    await pumpShell(tester, vm([pairedPhoneNoBattery, relayDevice]), size: const Size(1440, 1000));

    final master = find.byKey(const ValueKey('overview-master-content'));
    final wideGrid = find.byKey(const ValueKey('overview-primary-grid-wide'));
    final left = find.byKey(const ValueKey('overview-left-column'));
    final right = find.byKey(const ValueKey('overview-right-column'));
    final activity = find.byKey(const ValueKey('recent-activity-section'));
    final notifications = find.byKey(const ValueKey('notifications-section'));
    final status = find.byKey(const ValueKey('device-status-section'));
    final details = find.byKey(const ValueKey('device-details-section'));
    final remove = find.byKey(const ValueKey('kdeconnect-remove-device'));

    expect(tester.widget<ConstrainedBox>(master).constraints.maxWidth, 1080);
    expect(wideGrid, findsOneWidget);
    expect(find.byKey(const ValueKey('overview-primary-grid-narrow')), findsNothing);
    expect(find.descendant(of: left, matching: activity), findsOneWidget);
    expect(find.descendant(of: left, matching: notifications), findsOneWidget);
    expect(find.descendant(of: right, matching: status), findsOneWidget);
    expect(find.descendant(of: right, matching: remove), findsNothing);
    expect(find.descendant(of: wideGrid, matching: details), findsNothing);
    expect(find.descendant(of: wideGrid, matching: remove), findsNothing);
    expect(tester.getTopLeft(remove).dy, greaterThan(tester.getBottomLeft(find.byKey(const ValueKey('device-details-group'))).dy));

    final leftRect = tester.getRect(left);
    final rightRect = tester.getRect(right);
    expect(leftRect.width / rightRect.width, closeTo(7 / 5, 0.02));
    expect(rightRect.left - leftRect.right, closeTo(18, 0.01));

    final headerRect = tester.getRect(find.byKey(const ValueKey('selected-device-edge-sweep')));
    final selectorRect = tester.getRect(find.byKey(const ValueKey('overview-device-selector')));
    final actionsRect = tester.getRect(find.byKey(const ValueKey('overview-quick-actions')));
    final gridRect = tester.getRect(wideGrid);
    final detailsRect = tester.getRect(find.byKey(const ValueKey('device-details-group')));
    expect(selectorRect.left, closeTo(headerRect.left, 0.01));
    expect(actionsRect.left, closeTo(headerRect.left, 0.01));
    expect(gridRect.left, closeTo(headerRect.left, 0.01));
    expect(detailsRect.left, closeTo(headerRect.left, 0.01));
    expect(gridRect.right, closeTo(headerRect.right, 0.01));
    expect(detailsRect.right, closeTo(headerRect.right, 0.01));

    expect(find.descendant(of: find.byKey(const ValueKey('recent-activity-panel')), matching: find.text('Recent Activity')), findsNothing);
    expect(find.descendant(of: find.byKey(const ValueKey('notifications-panel')), matching: find.text('Notifications')), findsNothing);
    expect(tester.getSize(find.byKey(const ValueKey('recent-activity-panel'))).height, lessThan(140));
    expect(tester.getSize(find.byKey(const ValueKey('notifications-panel'))).height, lessThan(140));
  });

  testWidgets('Overview narrow layout collapses to one ordered document', (tester) async {
    await pumpShell(tester, vm([pairedPhoneNoBattery]), size: const Size(700, 1200));
    await tester.tap(find.text('Pixel').first);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('overview-primary-grid-wide')), findsNothing);
    expect(find.byKey(const ValueKey('overview-primary-grid-narrow')), findsOneWidget);

    final activity = tester.getTopLeft(find.byKey(const ValueKey('recent-activity-section')));
    final notifications = tester.getTopLeft(find.byKey(const ValueKey('notifications-section')));
    final status = tester.getTopLeft(find.byKey(const ValueKey('device-status-section')));
    final details = tester.getTopLeft(find.byKey(const ValueKey('device-details-section')));
    final remove = tester.getTopLeft(find.byKey(const ValueKey('kdeconnect-remove-device')));

    expect(activity.dy, lessThan(notifications.dy));
    expect(notifications.dy, lessThan(status.dy));
    expect(status.dy, lessThan(details.dy));
    expect(details.dy, lessThan(remove.dy));
    expect(activity.dx, closeTo(status.dx, 0.01));
    expect(status.dx, closeTo(details.dx, 0.01));
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
