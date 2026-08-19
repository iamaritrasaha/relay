import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:relay_app/model/continuity/continuity_runtime.dart';
import 'package:relay_app/model/cross_file.dart';
import 'package:relay_app/model/persistence/relay_paired_address.dart';
import 'package:relay_app/model/state/nearby_devices_state.dart';
import 'package:relay_app/model/state/send/send_session_state.dart';
import 'package:relay_app/model/state/send/sending_file.dart';
import 'package:relay_app/model/ui/relay_device_vm.dart';
import 'package:relay_app/pages/relay_home_vm.dart';
import 'package:relay_app/provider/file_transfer_provider.dart';
import 'package:relay_app/provider/relay_verified_lan_devices_provider.dart';
import 'package:relay_app/widget/relay/relay_shell.dart';
import 'package:relay_isolates/model/device.dart';
import 'package:relay_isolates/model/dto/file_dto.dart';
import 'package:relay_isolates/model/file_status.dart';
import 'package:relay_isolates/model/file_type.dart';
import 'package:relay_isolates/model/session_status.dart';

void main() {
  const device = Device(
    signalingId: null,
    ip: '192.168.1.4',
    version: '2.1',
    port: 53317,
    https: true,
    fingerprint: 'pixel-fingerprint',
    alias: 'Pixel',
    deviceModel: null,
    deviceType: DeviceType.mobile,
    download: false,
    channels: [],
  );

  NearbyDevicesState nearby([Device? found = device]) => NearbyDevicesState(
    runningFavoriteScan: false,
    runningIps: const {},
    devices: found == null ? const {} : {found.fingerprint: found},
    signalingDevices: const {},
  );

  CrossFile selectedFile({int size = 12000000}) => CrossFile(
    name: 'file.txt',
    fileType: FileType.other,
    size: size,
    thumbnail: null,
    asset: null,
    path: null,
    bytes: null,
    lastModified: null,
    lastAccessed: null,
  );

  SendSessionState session({required SessionStatus status, int hashedFileCount = 1, String? errorMessage}) => SendSessionState(
    sessionId: 'session-id',
    remoteSessionId: null,
    background: true,
    status: status,
    target: device,
    files: {
      'file-id': SendingFile(
        file: const FileDto(
          id: 'file-id',
          fileName: 'file.txt',
          size: 100,
          fileType: FileType.other,
          hash: null,
          preview: null,
          metadata: null,
        ),
        token: null,
        thumbnail: null,
        asset: null,
        path: null,
        bytes: null,
        errorMessage: null,
      ),
    },
    hashedFileCount: hashedFileCount,
    startTime: null,
    endTime: null,
    sendingTasks: null,
    errorMessage: errorMessage,
  );

  RelayHomeVm vm({
    NearbyDevicesState? nearbyState,
    Map<String, SendSessionState> sessions = const {},
    FileTransferNotifier? transfers,
    List<CrossFile> files = const [],
  }) => RelayHomeVm.fromState(
    configuredAlias: 'My Linux',
    selfDeviceType: DeviceType.desktop,
    server: null,
    nearby: nearbyState ?? nearby(),
    sendSessions: sessions,
    transfers: transfers ?? FileTransferNotifier(),
    selectedFiles: files,
  );

  Widget app(RelayHomeVm relayVm, {bool animationsEnabled = false}) => MaterialApp(
    theme: ThemeData.dark(useMaterial3: true),
    home: RelayShell(vm: relayVm, animationsEnabled: animationsEnabled, onSelectPayload: () {}),
  );

  /// The shell reads its own constraints, so the surface has to be sized for
  /// real rather than through a MediaQuery override.
  Future<void> pump(WidgetTester tester, RelayHomeVm relayVm, Size size, {bool animationsEnabled = false}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app(relayVm, animationsEnabled: animationsEnabled));
    await tester.pumpAndSettle();
  }

  testWidgets('self alias renders', (tester) async {
    await pump(tester, vm(), const Size(1280, 800));

    // Presence and alias are one rich line, so match the rendered string.
    final identity = tester.widget<Text>(find.byKey(const ValueKey('relay-self-alias')));
    expect(identity.textSpan!.toPlainText(), 'Offline as My Linux');
  });

  testWidgets('nearby device renders with its stable key', (tester) async {
    await pump(tester, vm(), const Size(1280, 800));

    expect(find.byKey(const ValueKey('relay-device-pixel-fingerprint')), findsOneWidget);
    expect(find.text('Pixel'), findsOneWidget);
  });

  testWidgets('Relay home contains no HTTP or HTTPS jargon', (tester) async {
    await pump(tester, vm(), const Size(1280, 800));

    expect(find.text('HTTP'), findsNothing);
    expect(find.text('HTTPS'), findsNothing);
  });

  test('waiting session maps to waiting', () {
    final relayVm = vm(sessions: {'session-id': session(status: SessionStatus.waiting)});

    expect(relayVm.devices.single.phase, RelayDevicePhase.waiting);
    expect(relayVm.devices.single.detail, 'Waiting');
  });

  test('sending session maps to sending with weighted progress', () {
    final transfers = FileTransferNotifier()..setProgress(sessionId: 'session-id', fileId: 'file-id', progress: 0.25);
    final relayVm = vm(
      sessions: {'session-id': session(status: SessionStatus.sending)},
      transfers: transfers,
    );

    expect(relayVm.devices.single.phase, RelayDevicePhase.sending);
    expect(relayVm.devices.single.progress, 0.25);
  });

  test('finished session maps to success', () {
    final relayVm = vm(sessions: {'session-id': session(status: SessionStatus.finished)});

    expect(relayVm.devices.single.phase, RelayDevicePhase.success);
    expect(relayVm.devices.single.progress, 1);
  });

  test('existing failed terminal state maps to failed', () {
    final relayVm = vm(sessions: {'session-id': session(status: SessionStatus.finishedWithErrors)});

    expect(relayVm.devices.single.phase, RelayDevicePhase.failed);
  });

  testWidgets('selected payload summary renders', (tester) async {
    await pump(tester, vm(files: [selectedFile(), selectedFile(), selectedFile()]), const Size(1280, 800));

    expect(find.byKey(const ValueKey('relay-payload-summary')), findsOneWidget);
    expect(find.text('3 files · 36.0 MB'), findsOneWidget);
    expect(find.text('Choose a nearby device'), findsOneWidget);
  });

  testWidgets('animation-disabled rendering settles', (tester) async {
    await pump(tester, vm(), const Size(1280, 800));

    expect(tester.takeException(), isNull);
  });

  for (final size in [const Size(1280, 800), const Size(900, 700), const Size(360, 740)]) {
    testWidgets('Relay home has no overflow at ${size.width.toInt()}x${size.height.toInt()}', (tester) async {
      await pump(tester, vm(), size);

      expect(tester.takeException(), isNull);
    });
  }

  test('verifying takes precedence while hashes are incomplete', () {
    final relayVm = vm(sessions: {'session-id': session(status: SessionStatus.sending, hashedFileCount: 0)});

    expect(relayVm.devices.single.phase, RelayDevicePhase.verifying);
  });

  test('failed file status maps to failed', () {
    final transfers = FileTransferNotifier()..setStatus(sessionId: 'session-id', fileId: 'file-id', status: FileStatus.failed);
    final relayVm = vm(
      sessions: {'session-id': session(status: SessionStatus.sending)},
      transfers: transfers,
    );

    expect(relayVm.devices.single.phase, RelayDevicePhase.failed);
  });

  test('a proof-backed LAN observation and paired route render as one Relay device', () {
    const relayId = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';
    final relayVm = RelayHomeVm.fromState(
      configuredAlias: 'My Linux',
      selfDeviceType: DeviceType.desktop,
      server: null,
      nearby: nearby(),
      sendSessions: const {},
      transfers: FileTransferNotifier(),
      selectedFiles: const [],
      pairedRoutes: [
        RelayPairedAddress(
          relayId: relayId,
          displayLabel: 'Pixel Relay',
          relayAddress: 'RELAY1.test',
          updatedAt: DateTime.utc(2026),
        ),
      ],
      verifiedLanDevices: const {
        relayId: RelayVerifiedLanDevice(relayId: relayId, device: device),
      },
    );

    expect(relayVm.devices, hasLength(1));
    expect(relayVm.devices.single.key, 'relay:$relayId');
    expect(relayVm.devices.single.targetKind, RelayDeviceTargetKind.verifiedRelay);
    expect(relayVm.devices.single.alias, 'Pixel Relay');
  });

  test('a paired Relay route remains visible when transient LAN discovery disappears', () {
    const relayId = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';
    final relayVm = RelayHomeVm.fromState(
      configuredAlias: 'My Linux',
      selfDeviceType: DeviceType.desktop,
      server: null,
      nearby: nearby(null),
      sendSessions: const {},
      transfers: FileTransferNotifier(),
      selectedFiles: const [],
      pairedRoutes: [
        RelayPairedAddress(relayId: relayId, displayLabel: 'Linux', relayAddress: 'RELAY1.test', updatedAt: DateTime.utc(2026)),
      ],
    );

    expect(relayVm.devices.single.key, 'relay:$relayId');
    expect(relayVm.devices.single.isPairedRelay, isTrue);
  });

  test('a verified LAN Relay device has one RelayId-based identity', () {
    const relayId = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';
    final relayVm = RelayHomeVm.fromState(
      configuredAlias: 'My Linux',
      selfDeviceType: DeviceType.desktop,
      server: null,
      nearby: nearby(),
      sendSessions: const {},
      transfers: FileTransferNotifier(),
      selectedFiles: const [],
      verifiedLanDevices: const {relayId: RelayVerifiedLanDevice(relayId: relayId, device: device)},
    );

    expect(relayVm.devices, hasLength(1));
    expect(relayVm.devices.single.key, 'relay:$relayId');
    expect(relayVm.devices.single.isVerifiedRelay, isTrue);
  });

  test('reconnecting a verified paired Relay device does not duplicate it', () {
    const relayId = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';
    final route = RelayPairedAddress(relayId: relayId, displayLabel: 'Linux', relayAddress: 'RELAY1.test', updatedAt: DateTime.utc(2026));
    final relayVm = RelayHomeVm.fromState(
      configuredAlias: 'My Linux',
      selfDeviceType: DeviceType.desktop,
      server: null,
      nearby: nearby(),
      sendSessions: const {},
      transfers: FileTransferNotifier(),
      selectedFiles: const [],
      pairedRoutes: [route, route],
      verifiedLanDevices: const {relayId: RelayVerifiedLanDevice(relayId: relayId, device: device)},
    );

    expect(relayVm.devices, hasLength(1));
    expect(relayVm.devices.single.key, 'relay:$relayId');
  });

  test('an authenticated continuity connection is reflected in the paired device VM', () {
    const relayId = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';
    final relayVm = RelayHomeVm.fromState(
      configuredAlias: 'My Linux',
      selfDeviceType: DeviceType.desktop,
      server: null,
      nearby: nearby(null),
      sendSessions: const {},
      transfers: FileTransferNotifier(),
      selectedFiles: const [],
      pairedRoutes: [
        RelayPairedAddress(relayId: relayId, displayLabel: 'Linux', relayAddress: 'RELAY1.test', updatedAt: DateTime.utc(2026)),
      ],
      continuity: const RelayContinuityState(devices: {relayId: DeviceContinuity(relayId: relayId, connected: true)}),
    );

    expect(relayVm.devices.single.continuityConnected, isTrue);
  });

  test('a compatibility peer remains outside authenticated Relay identity', () {
    final relayVm = vm();

    expect(relayVm.devices.single.isCompatibilityPeer, isTrue);
    expect(relayVm.devices.single.isAuthenticatedRelay, isFalse);
    expect(relayVm.devices.single.relayId, isNull);
  });
}
