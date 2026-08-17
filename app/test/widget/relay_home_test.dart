import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_app/model/cross_file.dart';
import 'package:localsend_app/model/state/nearby_devices_state.dart';
import 'package:localsend_app/model/state/send/send_session_state.dart';
import 'package:localsend_app/model/state/send/sending_file.dart';
import 'package:localsend_app/model/ui/relay_device_vm.dart';
import 'package:localsend_app/pages/relay_home_vm.dart';
import 'package:localsend_app/provider/file_transfer_provider.dart';
import 'package:localsend_app/widget/relay/relay_shell.dart';
import 'package:localsend_isolates/model/device.dart';
import 'package:localsend_isolates/model/dto/file_dto.dart';
import 'package:localsend_isolates/model/file_status.dart';
import 'package:localsend_isolates/model/file_type.dart';
import 'package:localsend_isolates/model/session_status.dart';

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

  Widget app(RelayHomeVm relayVm, Size size, {bool animationsEnabled = false}) => MediaQuery(
    data: MediaQueryData(size: size),
    child: MaterialApp(
      theme: ThemeData.dark(useMaterial3: true),
      home: RelayShell(vm: relayVm, animationsEnabled: animationsEnabled, onSelectPayload: () {}),
    ),
  );

  testWidgets('self alias renders', (tester) async {
    await tester.pumpWidget(app(vm(), const Size(1280, 800)));

    expect(find.byKey(const ValueKey('relay-self-alias')), findsOneWidget);
    expect(find.text('My Linux'), findsOneWidget);
    expect(find.text('Offline'), findsOneWidget);
  });

  testWidgets('nearby device renders with its stable key', (tester) async {
    await tester.pumpWidget(app(vm(), const Size(1280, 800)));

    expect(find.byKey(const ValueKey('relay-device-pixel-fingerprint')), findsOneWidget);
    expect(find.text('Pixel'), findsOneWidget);
  });

  testWidgets('Relay home contains no HTTP or HTTPS jargon', (tester) async {
    await tester.pumpWidget(app(vm(), const Size(1280, 800)));

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
    await tester.pumpWidget(app(vm(files: [selectedFile(), selectedFile(), selectedFile()]), const Size(1280, 800)));

    expect(find.byKey(const ValueKey('relay-payload-summary')), findsOneWidget);
    expect(find.text('3 files · 36.0 MB'), findsOneWidget);
    expect(find.text('Choose a nearby device'), findsOneWidget);
  });

  testWidgets('animation-disabled rendering settles', (tester) async {
    await tester.pumpWidget(app(vm(), const Size(1280, 800), animationsEnabled: false));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  for (final size in [const Size(1280, 800), const Size(900, 700), const Size(360, 740)]) {
    testWidgets('Relay home has no overflow at ${size.width.toInt()}x${size.height.toInt()}', (tester) async {
      await tester.pumpWidget(app(vm(), size));
      await tester.pumpAndSettle();

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
}
