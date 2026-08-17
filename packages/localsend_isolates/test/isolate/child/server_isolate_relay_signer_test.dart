import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_isolates/model/device.dart';
import 'package:localsend_isolates/model/device_info_result.dart';
import 'package:localsend_isolates/model/dto/multicast_dto.dart';
import 'package:localsend_isolates/model/stored_security_context.dart';
import 'package:localsend_isolates/src/isolate/child/server_isolate.dart';
import 'package:localsend_isolates/src/isolate/child/sync_provider.dart';
import 'package:localsend_isolates/src/isolate/dto/send_to_isolate_data.dart';
import 'package:localsend_isolates/src/isolate/parent/actions.dart';
import 'package:localsend_isolates/src/isolate/parent/parent_isolate_provider.dart';
import 'package:localsend_isolates/src/task/server/http_server.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:typed_isolates/typed_isolates.dart';

void main() {
  group('Relay signer server tasks', () {
    test('install forwards the expected RelayId and returns the derived RelayId', () async {
      final privateKey = Uint8List.fromList([80, 69, 77, 45, 83, 69, 67, 82, 69, 84]);
      final service = _FakeHttpServerService(installedRelayId: 'derived-relay-id');
      final task = HttpServerInstallRelaySignerTask(
        privateKey: privateKey,
        expectedRelayId: 'expected-relay-id',
      );

      final event = await executeHttpServerRelaySignerTask(
        service: service,
        task: task,
      );

      expect(service.receivedPrivateKey, same(privateKey));
      expect(service.receivedExpectedRelayId, 'expected-relay-id');
      expect(event, isA<HttpServerRelaySignerInstalledEvent>());
      expect((event as HttpServerRelaySignerInstalledEvent).relayId, 'derived-relay-id');
    });

    test('revoke reaches the service and returns whether a signer was present', () async {
      final service = _FakeHttpServerService(hadSigner: true);

      final event = await executeHttpServerRelaySignerTask(
        service: service,
        task: HttpServerRevokeRelaySignerTask(),
      );

      expect(service.revokeCalls, 1);
      expect(event, isA<HttpServerRelaySignerRevokedEvent>());
      expect((event as HttpServerRelaySignerRevokedEvent).hadSigner, isTrue);
    });

    test('a server that is not running fails deterministically', () async {
      final service = HttpServerService();

      expect(
        () => service.installRelaySigner(
          privateKey: Uint8List.fromList([1]),
          expectedRelayId: 'relay-id',
        ),
        throwsA(isA<StateError>().having((error) => error.message, 'message', 'Server is not running')),
      );
      expect(
        service.revokeRelaySigner,
        throwsA(isA<StateError>().having((error) => error.message, 'message', 'Server is not running')),
      );
    });

    test('install task debug output redacts private key bytes', () {
      final task = HttpServerInstallRelaySignerTask(
        privateKey: Uint8List.fromList([80, 69, 77, 45, 83, 69, 67, 82, 69, 84]),
        expectedRelayId: 'public-relay-id',
      );

      final debug = task.toString();

      expect(debug, contains('expectedRelayId: public-relay-id'));
      expect(debug, contains('privateKey: <redacted>'));
      expect(debug, isNot(contains('PEM-SECRET')));
      expect(debug, isNot(contains('[80')));
    });

    test('install uses a one-shot envelope with no SyncState', () {
      final task = HttpServerInstallRelaySignerTask(
        privateKey: Uint8List.fromList([1]),
        expectedRelayId: 'relay-id',
      );
      final envelope = SendToIsolateData(
        syncState: null,
        data: IsolateTask(data: task),
      );

      expect(envelope.syncState, isNull);
      expect(envelope.data!.data, same(task));
    });

    test('parent actions use the one-shot connector and discard the install key', () async {
      final connection =
          await TypedIsolates.startIsolate<IsolateTaskStreamResult<HttpServerEvent>, SendToIsolateData<IsolateTask<BaseHttpServerTask>>, Object?>(
            task: _setupFakeHttpServerIsolate,
            param: null,
          );
      addTearDown(connection.isolate.kill);

      final container = RefenaContainer();
      container.set(
        parentIsolateProvider.overrideWithNotifier(
          (ref) => IsolateController(
            initialState: ParentIsolateState(
              syncState: _syncState(),
              discovery: null,
              httpUpload: null,
              httpServer: connection,
            ),
          ),
        ),
      );
      final controller = container.redux(parentIsolateProvider);
      final install = IsolateHttpServerInstallRelaySignerAction(
        privateKey: Uint8List.fromList([1]),
        expectedRelayId: 'expected-relay-id',
      );

      expect(await controller.dispatchAsyncTakeResult(install), 'expected-relay-id');
      expect(await controller.dispatchAsyncTakeResult(IsolateHttpServerRevokeRelaySignerAction()), isTrue);
      await expectLater(
        controller.dispatchAsyncTakeResult(install),
        throwsA(isA<StateError>().having((error) => error.message, 'message', 'Relay signer install action has already completed')),
      );
    });

    test('result events expose only public install and revoke results', () {
      final installed = HttpServerRelaySignerInstalledEvent(relayId: 'public-relay-id');
      final revoked = HttpServerRelaySignerRevokedEvent(hadSigner: false);

      expect(installed.relayId, 'public-relay-id');
      expect(revoked.hadSigner, isFalse);
      expect(installed.toString(), isNot(contains('privateKey')));
      expect(revoked.toString(), isNot(contains('privateKey')));
    });
  });
}

class _FakeHttpServerService extends HttpServerService {
  final String installedRelayId;
  final bool hadSigner;
  Uint8List? receivedPrivateKey;
  String? receivedExpectedRelayId;
  int revokeCalls = 0;

  _FakeHttpServerService({
    this.installedRelayId = 'relay-id',
    this.hadSigner = false,
  });

  @override
  Future<String> installRelaySigner({
    required Uint8List privateKey,
    required String expectedRelayId,
  }) async {
    receivedPrivateKey = privateKey;
    receivedExpectedRelayId = expectedRelayId;
    return installedRelayId;
  }

  @override
  Future<bool> revokeRelaySigner() async {
    revokeCalls++;
    return hadSigner;
  }
}

SyncState _syncState() {
  return SyncState(
    rootIsolateToken: Object(),
    securityContext: const StoredSecurityContext(
      privateKey: '',
      publicKey: '',
      certificate: '',
      certificateHash: '',
    ),
    deviceInfo: DeviceInfoResult(
      deviceType: DeviceType.desktop,
      deviceModel: null,
      androidSdkInt: null,
    ),
    alias: 'test',
    port: 0,
    networkWhitelist: null,
    networkBlacklist: null,
    protocol: ProtocolType.http,
    multicastGroup: '',
    discoveryTimeout: 0,
    serverRunning: false,
    download: false,
  );
}

Future<void> _setupFakeHttpServerIsolate(
  Stream<SendToIsolateData<IsolateTask<BaseHttpServerTask>>> receiveFromMain,
  void Function(IsolateTaskStreamResult<HttpServerEvent>) sendToMain,
  Object? _,
) async {
  await for (final envelope in receiveFromMain) {
    final task = envelope.data!;
    if (envelope.syncState != null) {
      sendToMain(
        IsolateTaskStreamResult.error(
          id: task.id,
          error: 'Relay signer task must not include SyncState',
        ),
      );
      continue;
    }
    switch (task.data) {
      case HttpServerInstallRelaySignerTask(:final expectedRelayId):
        sendToMain(
          IsolateTaskStreamResult.event(
            id: task.id,
            data: HttpServerRelaySignerInstalledEvent(relayId: expectedRelayId),
          ),
        );
      case HttpServerRevokeRelaySignerTask _:
        sendToMain(
          IsolateTaskStreamResult.event(
            id: task.id,
            data: HttpServerRelaySignerRevokedEvent(hadSigner: true),
          ),
        );
      default:
        sendToMain(
          IsolateTaskStreamResult.error(
            id: task.id,
            error: 'Unexpected task',
          ),
        );
        continue;
    }
    sendToMain(IsolateTaskStreamResult.done(id: task.id));
  }
}
