import 'package:localsend_app/config/init.dart';
import 'package:test/test.dart';

void main() {
  test('starts networking when local network permission is granted', () async {
    var serverStarts = 0;
    var discoveryStarts = 0;
    final bootstrap = NetworkBootstrap(
      requestLocalNetworkPermission: () async => true,
      startServer: () async {
        serverStarts++;
      },
      startDiscoveryListener: () {
        discoveryStarts++;
      },
    );

    final result = await bootstrap.start();

    expect(result.localNetworkGranted, isTrue);
    expect(serverStarts, 1);
    expect(discoveryStarts, 1);
  });

  test('does not double-start networking for concurrent calls', () async {
    var serverStarts = 0;
    var discoveryStarts = 0;
    final bootstrap = NetworkBootstrap(
      startServer: () async {
        serverStarts++;
      },
      startDiscoveryListener: () {
        discoveryStarts++;
      },
    );

    await Future.wait([bootstrap.start(), bootstrap.start()]);

    expect(serverStarts, 1);
    expect(discoveryStarts, 1);
  });

  test('does not start networking when local network permission is denied', () async {
    var serverStarts = 0;
    var discoveryStarts = 0;
    final bootstrap = NetworkBootstrap(
      requestLocalNetworkPermission: () async => false,
      startServer: () async {
        serverStarts++;
      },
      startDiscoveryListener: () {
        discoveryStarts++;
      },
    );

    final result = await bootstrap.start();

    expect(result.localNetworkGranted, isFalse);
    expect(serverStarts, 0);
    expect(discoveryStarts, 0);
  });

  test('retries networking after local network permission is later granted', () async {
    var granted = false;
    var serverStarts = 0;
    var discoveryStarts = 0;
    final bootstrap = NetworkBootstrap(
      requestLocalNetworkPermission: () async => granted,
      startServer: () async {
        serverStarts++;
      },
      startDiscoveryListener: () {
        discoveryStarts++;
      },
    );

    expect((await bootstrap.start()).localNetworkGranted, isFalse);
    granted = true;
    expect((await bootstrap.start()).localNetworkGranted, isTrue);

    expect(serverStarts, 1);
    expect(discoveryStarts, 1);
  });
}
