import 'package:localsend_app/util/security/relay_server_signer_port.dart';
import 'package:test/test.dart';

void main() {
  test('server-start activation runs once for the current server instance', () async {
    var activations = 0;
    final controller = RelayServerSignerActivationController(
      activate: () async {
        activations++;
      },
    );

    await controller.onServerStarted();
    await controller.onServerStarted();

    expect(activations, 1);
  });

  test('activation failure does not fail ordinary server startup', () async {
    final controller = RelayServerSignerActivationController(
      activate: () async => throw StateError('secure store unavailable'),
    );

    await controller.onServerStarted();
  });

  test('a stopped and restarted server activates again without caching a secret', () async {
    var activations = 0;
    final controller = RelayServerSignerActivationController(
      activate: () async {
        activations++;
      },
    );

    await controller.onServerStarted();
    controller.onServerStopped();
    await controller.onServerStarted();

    expect(activations, 2);
  });
}
