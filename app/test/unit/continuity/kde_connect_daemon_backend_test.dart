import 'dart:async';
import 'dart:io';

import 'package:localsend_app/continuity/continuity_backend.dart';
import 'package:localsend_app/continuity/kde_connect_daemon_backend.dart';
import 'package:localsend_app/continuity/kde_connect_dbus_boundary.dart';
import 'package:test/test.dart';

void main() {
  group('KdeConnectDaemonBackend health', () {
    test('reports daemon missing without peers', () async {
      final fake = FakeKdeConnectDbus()..presence = KdeConnectDaemonPresence.notInstalled;
      final backend = await startBackend(fake);
      addTearDown(backend.close);

      expect(backend.snapshot.health.status, ContinuityBackendHealthStatus.notInstalled);
      expect(backend.snapshot.peers, isEmpty);
    });

    test('distinguishes an installed but stopped daemon', () async {
      final fake = FakeKdeConnectDbus()..presence = KdeConnectDaemonPresence.stopped;
      final backend = await startBackend(fake);
      addTearDown(backend.close);

      expect(backend.snapshot.health.status, ContinuityBackendHealthStatus.stopped);
      expect(fake.discoverCalls, 0);
    });

    test('reports a GSConnect-only session as explicitly unsupported', () async {
      final fake = FakeKdeConnectDbus()..presence = KdeConnectDaemonPresence.gsConnectOnly;
      final backend = await startBackend(fake);
      addTearDown(backend.close);

      expect(backend.snapshot.health.status, ContinuityBackendHealthStatus.unsupportedEnvironment);
      expect(fake.discoverCalls, 0);
    });

    test('re-enumerates when the daemon appears', () async {
      final fake = FakeKdeConnectDbus()..presence = KdeConnectDaemonPresence.stopped;
      final backend = await startBackend(fake);
      addTearDown(backend.close);

      fake
        ..presence = KdeConnectDaemonPresence.running
        ..discovery = discovery(peer(id: 'phone'))
        ..emitOwner(kdeConnectServiceName, true);
      await waitFor(() => backend.snapshot.health.status == ContinuityBackendHealthStatus.ready);

      expect(backend.snapshot.peers.single.id.opaqueId, 'phone');
    });

    test('daemon restart invalidates stale peers and rebuilds state', () async {
      final fake = FakeKdeConnectDbus()
        ..presence = KdeConnectDaemonPresence.running
        ..discovery = discovery(peer(id: 'old_phone'));
      final backend = await startBackend(fake);
      addTearDown(backend.close);
      expect(backend.snapshot.peers.single.id.opaqueId, 'old_phone');

      fake
        ..presence = KdeConnectDaemonPresence.stopped
        ..emitOwner(kdeConnectServiceName, false);
      await waitFor(() => backend.snapshot.health.status == ContinuityBackendHealthStatus.stopped);
      expect(backend.snapshot.peers, isEmpty);

      fake
        ..presence = KdeConnectDaemonPresence.running
        ..discovery = discovery(peer(id: 'new_phone'))
        ..emitOwner(kdeConnectServiceName, true);
      await waitFor(() => backend.snapshot.peers.any((peer) => peer.id.opaqueId == 'new_phone'));

      expect(backend.snapshot.peers.map((peer) => peer.id.opaqueId), ['new_phone']);
    });

    test('missing daemon interface fails closed as incompatible', () async {
      final fake = FakeKdeConnectDbus()
        ..presence = KdeConnectDaemonPresence.running
        ..discoveryError = const KdeConnectDbusException(KdeConnectDbusFailureKind.incompatibleApi);
      final backend = await startBackend(fake);
      addTearDown(backend.close);

      expect(backend.snapshot.health.status, ContinuityBackendHealthStatus.incompatibleApi);
      expect(backend.snapshot.peers, isEmpty);
    });

    test('missing peer method degrades without exposing clipboard capability', () async {
      final fake = FakeKdeConnectDbus()
        ..presence = KdeConnectDaemonPresence.running
        ..discovery = discovery(peer(id: 'phone', clipboard: false), degraded: true);
      final backend = await startBackend(fake);
      addTearDown(backend.close);

      expect(backend.snapshot.health.status, ContinuityBackendHealthStatus.degraded);
      expect(backend.snapshot.peers.single.capabilities, isEmpty);
    });
  });

  group('clipboard dispatch', () {
    test('requires a paired peer', () async {
      final backend = await backendWithPeer(peer(paired: false));
      addTearDown(backend.close);

      final result = await backend.sendClipboardText(backend.snapshot.peers.single.id, 'harmless');

      expect(result.status, ContinuityResultStatus.peerUnpaired);
    });

    test('requires a reachable peer', () async {
      final backend = await backendWithPeer(peer(reachable: false));
      addTearDown(backend.close);

      final result = await backend.sendClipboardText(backend.snapshot.peers.single.id, 'harmless');

      expect(result.status, ContinuityResultStatus.peerUnreachable);
    });

    test('requires the introspected clipboard text method', () async {
      final backend = await backendWithPeer(peer(clipboard: false));
      addTearDown(backend.close);

      final result = await backend.sendClipboardText(backend.snapshot.peers.single.id, 'harmless');

      expect(result.status, ContinuityResultStatus.unsupported);
    });

    test('bounds text before calling D-Bus', () async {
      final fake = readyFake();
      final backend = KdeConnectDaemonBackend(dbus: fake, maxClipboardBytes: 4);
      await backend.start();
      addTearDown(backend.close);

      final result = await backend.sendClipboardText(backend.snapshot.peers.single.id, '12345');

      expect(result.status, ContinuityResultStatus.contentTooLarge);
      expect(fake.sendCalls, 0);
    });

    test('returns timeout without replaying the clipboard later', () async {
      final never = Completer<void>();
      final fake = readyFake()..send = (_, _) => never.future;
      final backend = KdeConnectDaemonBackend(dbus: fake, operationTimeout: const Duration(milliseconds: 10));
      await backend.start();
      addTearDown(backend.close);

      final result = await backend.sendClipboardText(backend.snapshot.peers.single.id, 'harmless');
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(result.status, ContinuityResultStatus.timedOut);
      expect(fake.sendCalls, 1);
    });

    test('dispatches text successfully once', () async {
      const expectedText = 'Relay KC2 clipboard test';
      var receivedExpectedText = false;
      final fake = readyFake()
        ..send = (_, text) async {
          receivedExpectedText = text == expectedText;
        };
      final backend = await startBackend(fake);
      addTearDown(backend.close);

      final result = await backend.sendClipboardText(backend.snapshot.peers.single.id, expectedText);

      expect(result.status, ContinuityResultStatus.success);
      expect(receivedExpectedText, isTrue);
      expect(fake.sendCalls, 1);
    });

    test('clipboard content never enters backend state or diagnostics', () async {
      const secret = 'KC2-SECRET-MUST-NOT-APPEAR';
      final diagnostics = <ContinuityDiagnostic>[];
      final fake = readyFake()
        ..send = (_, text) async {
          expect(text, secret);
        };
      final backend = KdeConnectDaemonBackend(dbus: fake, diagnostics: diagnostics.add);
      await backend.start();
      addTearDown(backend.close);

      await backend.sendClipboardText(backend.snapshot.peers.single.id, secret);
      final observableText = [backend.snapshot.health, ...backend.snapshot.peers, ...diagnostics].join('\n');

      expect(observableText, isNot(contains(secret)));
    });

    test('provider-scoped KDE ID cannot address another backend', () async {
      final fake = readyFake();
      final backend = await startBackend(fake);
      addTearDown(backend.close);
      const unrelatedId = ContinuityPeerId(backendId: ContinuityBackendId('relay'), opaqueId: 'phone');

      final result = await backend.sendClipboardText(unrelatedId, 'harmless');

      expect(result.status, ContinuityResultStatus.backendUnavailable);
      expect(fake.sendCalls, 0);
    });
  });

  test('continuity remains structurally isolated from transfer, persistence, and Relay trust', () {
    final sources = Directory(
      'lib/continuity',
    ).listSync(recursive: true).whereType<File>().where((file) => file.path.endsWith('.dart')).map((file) => file.readAsStringSync()).join('\n');

    for (final forbidden in [
      'provider/network',
      'localsend_isolates',
      'util/security',
      'PersistenceService',
      'RelayIdentity',
      'NearbyDevicesState',
      'SendProvider',
      'ReceiveProvider',
    ]) {
      expect(sources, isNot(contains(forbidden)), reason: 'Continuity source must not depend on $forbidden.');
    }
  });
}

Future<KdeConnectDaemonBackend> startBackend(FakeKdeConnectDbus fake) async {
  final backend = KdeConnectDaemonBackend(dbus: fake);
  await backend.start();
  return backend;
}

Future<KdeConnectDaemonBackend> backendWithPeer(KdeConnectPeerSnapshot snapshot) {
  return startBackend(
    FakeKdeConnectDbus()
      ..presence = KdeConnectDaemonPresence.running
      ..discovery = discovery(snapshot),
  );
}

FakeKdeConnectDbus readyFake() {
  return FakeKdeConnectDbus()
    ..presence = KdeConnectDaemonPresence.running
    ..discovery = discovery(peer());
}

KdeConnectPeerSnapshot peer({
  String id = 'phone',
  bool paired = true,
  bool reachable = true,
  bool clipboard = true,
}) {
  return KdeConnectPeerSnapshot(
    opaqueId: id,
    displayName: 'Test phone',
    reachable: reachable,
    paired: paired,
    clipboardTextAvailable: clipboard,
  );
}

KdeConnectDiscoverySnapshot discovery(KdeConnectPeerSnapshot snapshot, {bool degraded = false}) {
  return KdeConnectDiscoverySnapshot(peers: [snapshot], degraded: degraded);
}

Future<void> waitFor(bool Function() condition) async {
  for (var i = 0; i < 100; i++) {
    if (condition()) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
  fail('Timed out waiting for asynchronous backend state.');
}

final class FakeKdeConnectDbus implements KdeConnectDbusBoundary {
  final _ownerChanges = StreamController<KdeConnectOwnerChange>.broadcast(sync: true);

  KdeConnectDaemonPresence presence = KdeConnectDaemonPresence.notInstalled;
  KdeConnectDiscoverySnapshot discovery = const KdeConnectDiscoverySnapshot(peers: [], degraded: false);
  Object? discoveryError;
  Future<void> Function(String peerId, String text)? send;
  int discoverCalls = 0;
  int sendCalls = 0;

  @override
  Stream<KdeConnectOwnerChange> get ownerChanges => _ownerChanges.stream;

  void emitOwner(String serviceName, bool hasOwner) {
    _ownerChanges.add(KdeConnectOwnerChange(serviceName: serviceName, hasOwner: hasOwner));
  }

  @override
  Future<KdeConnectDaemonPresence> probePresence() async => presence;

  @override
  Future<KdeConnectDiscoverySnapshot> discoverPeers() async {
    discoverCalls++;
    final error = discoveryError;
    if (error != null) {
      throw error;
    }
    return discovery;
  }

  @override
  Future<void> sendClipboardText(String opaquePeerId, String text) async {
    sendCalls++;
    await send?.call(opaquePeerId, text);
  }

  @override
  Future<void> close() => _ownerChanges.close();
}
