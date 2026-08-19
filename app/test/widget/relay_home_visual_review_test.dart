import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:relay_app/config/theme.dart';
import 'package:relay_app/model/cross_file.dart';
import 'package:relay_app/model/persistence/color_mode.dart';
import 'package:relay_app/model/state/nearby_devices_state.dart';
import 'package:relay_app/model/state/send/send_session_state.dart';
import 'package:relay_app/model/state/send/sending_file.dart';
import 'package:relay_app/model/state/server/server_state.dart';
import 'package:relay_app/pages/relay_home_vm.dart';
import 'package:relay_app/provider/file_transfer_provider.dart';
import 'package:relay_app/widget/relay/relay_shell.dart';
import 'package:relay_isolates/model/device.dart';
import 'package:relay_isolates/model/dto/file_dto.dart';
import 'package:relay_isolates/model/file_type.dart';
import 'package:relay_isolates/model/session_status.dart';

void main() {
  const selfAlias = 'My Linux';

  Device device(String alias, String fingerprint) => Device(
    signalingId: null,
    ip: '192.168.1.${fingerprint == 'redmi' ? 4 : 5}',
    version: '2.1',
    port: 53317,
    https: true,
    fingerprint: fingerprint,
    alias: alias,
    deviceModel: null,
    deviceType: DeviceType.mobile,
    download: false,
    channels: const [],
  );

  final redmi = device('Redmi', 'redmi');
  final pixel = device('Pixel', 'pixel');

  NearbyDevicesState nearby(Iterable<Device> devices) => NearbyDevicesState(
    runningFavoriteScan: false,
    runningIps: const {},
    devices: {for (final device in devices) device.fingerprint: device},
    signalingDevices: const {},
  );

  CrossFile selectedFile() => const CrossFile(
    name: 'photo.jpg',
    fileType: FileType.image,
    size: 8000000,
    thumbnail: null,
    asset: null,
    path: null,
    bytes: null,
    lastModified: null,
    lastAccessed: null,
  );

  SendSessionState sendingSession(Device target) => SendSessionState(
    sessionId: 'pixel-session',
    remoteSessionId: null,
    background: true,
    status: SessionStatus.sending,
    target: target,
    files: {
      'photo': const SendingFile(
        file: FileDto(
          id: 'photo',
          fileName: 'photo.jpg',
          size: 1000,
          fileType: FileType.image,
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
    hashedFileCount: 1,
    startTime: null,
    endTime: null,
    sendingTasks: null,
    errorMessage: null,
  );

  RelayHomeVm relayVm({
    Iterable<Device> devices = const [],
    Map<String, SendSessionState> sessions = const {},
    FileTransferNotifier? transfers,
    List<CrossFile> selectedFiles = const [],
  }) => RelayHomeVm.fromState(
    configuredAlias: selfAlias,
    selfDeviceType: DeviceType.desktop,
    server: const ServerState(
      alias: selfAlias,
      port: 53317,
      https: true,
      session: null,
      webSendState: null,
      webUpload: false,
      webPin: null,
    ),
    nearby: nearby(devices),
    sendSessions: sessions,
    transfers: transfers ?? FileTransferNotifier(),
    selectedFiles: selectedFiles,
  );

  Future<void> render(WidgetTester tester, RelayHomeVm vm) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: getTheme(ColorMode.relay, Colors.blue, Brightness.dark, null),
        home: RelayShell(vm: vm, animationsEnabled: false, onSelectPayload: () {}),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }

  testWidgets('idle desktop visual review', (tester) async {
    await render(tester, relayVm());

    await expectLater(find.byType(RelayShell), matchesGoldenFile('goldens/relay_review/idle.png'));
  });

  testWidgets('nearby desktop visual review', (tester) async {
    await render(tester, relayVm(devices: [redmi, pixel]));

    await expectLater(find.byType(RelayShell), matchesGoldenFile('goldens/relay_review/nearby.png'));
  });

  testWidgets('selected desktop visual review', (tester) async {
    await render(tester, relayVm(devices: [redmi, pixel], selectedFiles: [selectedFile(), selectedFile(), selectedFile()]));

    await expectLater(find.byType(RelayShell), matchesGoldenFile('goldens/relay_review/selected.png'));
  });

  testWidgets('sending desktop visual review', (tester) async {
    final transfers = FileTransferNotifier()..setProgress(sessionId: 'pixel-session', fileId: 'photo', progress: 0.64);
    await render(tester, relayVm(devices: [redmi, pixel], sessions: {'pixel-session': sendingSession(pixel)}, transfers: transfers));

    await expectLater(find.byType(RelayShell), matchesGoldenFile('goldens/relay_review/sending.png'));
  });
}
