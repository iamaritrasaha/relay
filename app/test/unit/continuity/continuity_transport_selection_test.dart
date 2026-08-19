import 'dart:typed_data';

import 'package:refena_flutter/refena_flutter.dart';
import 'package:relay_app/model/continuity/continuity_runtime.dart';
import 'package:relay_app/model/persistence/relay_continuity_settings.dart';
import 'package:relay_app/model/persistence/relay_paired_address.dart';
import 'package:relay_app/model/persistence/relay_public_identity.dart';
import 'package:relay_app/provider/continuity/continuity_provider.dart';
import 'package:relay_app/util/native/continuity_channel.dart';
import 'package:relay_app/util/security/relay_identity_coordinator.dart';
import 'package:relay_app/util/security/relay_identity_metadata_store.dart';
import 'package:relay_app/util/security/relay_identity_secret_store.dart';
import 'package:relay_app/util/security/relay_server_signer_port.dart';
import 'package:relay_isolates/model/stored_security_context.dart';
import 'package:relay_isolates/rust/api/continuity.dart' as rust;
import 'package:relay_isolates/rust/api/crypto.dart';
import 'package:test/test.dart';

import '../../mocks.mocks.dart';

const _localRelayId = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';
const _phone = 'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB';
const _laptop = 'CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC';

RelayPairedAddress _pairing(String relayId, {String? address}) => RelayPairedAddress(
  relayId: relayId,
  displayLabel: 'Device',
  relayAddress: address,
  pairedAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  origin: address == null ? RelayPairedAddress.originLan : RelayPairedAddress.originAnywhere,
);

rust.RsLanCandidate _candidate(String ip) => rust.RsLanCandidate(ip: ip, port: 53317, https: true, certificateFingerprint: 'FP-$ip');

/// Everything the selection asked for, in order.
class _Attempts {
  final List<String> lan = [];
  final List<String> anywhere = [];
  final List<String> order = [];
}

void main() {
  late _Attempts attempts;
  late List<void Function()> scheduledReselections;

  ReduxNotifierTester<RelayContinuityState> service({
    required Map<String, RelayContinuitySettings> settings,
    required List<RelayPairedAddress> routes,
    Map<String, List<rust.RsLanCandidate>> candidates = const {},
    Set<String> lanSucceeds = const {},
    String? listenerAddress = 'RELAY1.listener',
  }) {
    return ReduxNotifier.test(
      redux: ContinuityService(
        persistence: MockPersistenceService(),
        channel: const ContinuityChannel(),
        identityCoordinator: _coordinator(),
        listenerAddress: () => listenerAddress,
        pairedRoutes: () => routes,
        lanCandidates: (relayId) => candidates[relayId] ?? const [],
        securityContext: () => const StoredSecurityContext(
          privateKey: 'client-key',
          publicKey: 'client-public',
          certificate: 'client-cert',
          certificateHash: 'FP-SELF',
        ),
        serveLocalContinuity: (privateKey, relayId) async => privateKey != null,
        connectOverLan:
            ({
              required privateKeyPem,
              required relayId,
              required remoteRelayId,
              required clientPrivateKey,
              required clientCertificate,
              required candidates,
            }) async {
              attempts.lan.add(remoteRelayId);
              attempts.order.add('lan:$remoteRelayId');
              return lanSucceeds.contains(remoteRelayId);
            },
        connectOverAnywhere: ({required privateKeyPem, required relayId, required remoteAddress}) async {
          attempts.anywhere.add(remoteAddress);
          attempts.order.add('anywhere:$remoteAddress');
        },
        scheduleReselection: (_, callback) => scheduledReselections.add(callback),
      ),
      initialState: RelayContinuityState(settings: settings),
    );
  }

  RelayContinuitySettings enabled(String relayId) => RelayContinuitySettings(
    relayId: relayId,
    trusted: true,
  ).withCapability(ContinuityCapabilityKind.battery, true);

  setUp(() {
    attempts = _Attempts();
    scheduledReselections = [];
  });

  void establish(ReduxNotifierTester<RelayContinuityState> it, String relayId, {bool local = true}) {
    it.dispatch(
      ContinuityRemoteEventAction(
        rust.RsContinuityEvent.sessionEstablished(remoteRelayId: relayId, directPath: local, localPath: local),
      ),
    );
  }

  void end(ReduxNotifierTester<RelayContinuityState> it, String relayId, {String reason = 'transport_failed'}) {
    it.dispatch(ContinuityRemoteEventAction(rust.RsContinuityEvent.sessionEnded(remoteRelayId: relayId, reason: reason)));
  }

  Future<void> runScheduledReselection() async {
    final callbacks = List<void Function()>.from(scheduledReselections);
    scheduledReselections.clear();
    for (final callback in callbacks) {
      callback();
    }
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
  }

  group('transport selection', () {
    test('an authenticated local session is preferred and stops there', () async {
      final it = service(
        settings: {_phone: enabled(_phone)},
        routes: [_pairing(_phone, address: 'RELAY1.phone')],
        candidates: {
          _phone: [_candidate('192.168.1.24')],
        },
        lanSucceeds: {_phone},
      );

      await it.dispatchAsync(ContinuityConnectEnabledDevicesAction());

      // The local network answered, so the Anywhere route is not dialled as
      // well: one peer gets one link.
      expect(attempts.order, ['lan:$_phone']);
      expect(attempts.anywhere, isEmpty);
    });

    test('the Anywhere route is the fallback when the peer is not reachable locally', () async {
      final it = service(
        settings: {_phone: enabled(_phone)},
        routes: [_pairing(_phone, address: 'RELAY1.phone')],
        candidates: {
          _phone: [_candidate('192.168.1.24')],
        },
      );

      await it.dispatchAsync(ContinuityConnectEnabledDevicesAction());

      // Local was tried first and failed; the authenticated remote route ran
      // only afterwards.
      expect(attempts.order, ['lan:$_phone', 'anywhere:RELAY1.phone']);
    });

    test('a device with no local candidates and no route connects over nothing', () async {
      final it = service(
        settings: {_phone: enabled(_phone)},
        routes: [_pairing(_phone)],
      );

      await it.dispatchAsync(ContinuityConnectEnabledDevicesAction());

      // There is deliberately no third, unauthenticated option.
      expect(attempts.order, isEmpty);
    });

    test('a LAN-only pairing stays local and never invents a remote route', () async {
      final it = service(
        settings: {_phone: enabled(_phone)},
        routes: [_pairing(_phone)],
        candidates: {
          _phone: [_candidate('192.168.1.24')],
        },
        lanSucceeds: {_phone},
      );

      await it.dispatchAsync(ContinuityConnectEnabledDevicesAction());

      expect(attempts.order, ['lan:$_phone']);
    });

    test('a device is skipped when neither transport can be authenticated', () async {
      final it = service(
        settings: {_phone: enabled(_phone)},
        routes: [_pairing(_phone, address: 'RELAY1.phone')],
        candidates: {
          _phone: [_candidate('192.168.1.24')],
        },
        // The Anywhere transport has no endpoint to dial from either.
        listenerAddress: null,
      );

      await it.dispatchAsync(ContinuityConnectEnabledDevicesAction());

      expect(attempts.lan, [_phone]);
      expect(attempts.anywhere, isEmpty);
    });
  });

  group('what never starts a session', () {
    test('a device that is discovered but not paired is not a target', () async {
      final it = service(
        settings: {_phone: enabled(_phone)},
        routes: const [],
        candidates: {
          _phone: [_candidate('192.168.1.24')],
        },
        lanSucceeds: {_phone},
      );

      await it.dispatchAsync(ContinuityConnectEnabledDevicesAction());

      // Being visible on the network, and even having consent recorded, is not
      // a relationship. Without a pairing nothing is dialled.
      expect(attempts.order, isEmpty);
    });

    test('a paired but untrusted device is not a target', () async {
      final it = service(
        settings: {
          _phone: const RelayContinuitySettings(relayId: _phone).withCapability(ContinuityCapabilityKind.battery, true),
        },
        routes: [_pairing(_phone)],
        candidates: {
          _phone: [_candidate('192.168.1.24')],
        },
        lanSucceeds: {_phone},
      );

      await it.dispatchAsync(ContinuityConnectEnabledDevicesAction());

      expect(attempts.order, isEmpty);
    });

    test('a paired and trusted device with nothing granted is not a target', () async {
      final it = service(
        settings: {_phone: const RelayContinuitySettings(relayId: _phone, trusted: true)},
        routes: [_pairing(_phone)],
        candidates: {
          _phone: [_candidate('192.168.1.24')],
        },
        lanSucceeds: {_phone},
      );

      await it.dispatchAsync(ContinuityConnectEnabledDevicesAction());

      expect(attempts.order, isEmpty);
    });
  });

  group('session-loss reselection', () {
    test('an established LAN loss becomes disconnected and falls back to Anywhere without user action', () async {
      final it = service(
        settings: {_phone: enabled(_phone)},
        routes: [_pairing(_phone, address: 'RELAY1.phone')],
        candidates: {
          _phone: [_candidate('192.168.1.24')],
        },
      );

      establish(it, _phone);
      end(it, _phone);

      expect(it.state.deviceFor(_phone).connected, isFalse);
      expect(it.state.deviceFor(_phone).localPath, isFalse);
      expect(scheduledReselections, hasLength(1));

      await runScheduledReselection();

      expect(attempts.order, ['lan:$_phone', 'anywhere:RELAY1.phone']);
    });

    test('a disconnected peer can recover over LAN when it becomes locally available later', () async {
      final candidates = <String, List<rust.RsLanCandidate>>{};
      final it = service(
        settings: {_phone: enabled(_phone)},
        routes: [_pairing(_phone)],
        candidates: candidates,
      );

      establish(it, _phone);
      end(it, _phone);
      await runScheduledReselection();
      expect(attempts.order, isEmpty);

      candidates[_phone] = [_candidate('192.168.1.24')];
      it.dispatch(ContinuityLocalAvailabilityChangedAction());
      await runScheduledReselection();

      expect(attempts.order, ['lan:$_phone']);
    });

    test('no route after a LAN loss stays disconnected', () async {
      final it = service(
        settings: {_phone: enabled(_phone)},
        routes: [_pairing(_phone)],
        candidates: {
          _phone: [_candidate('192.168.1.24')],
        },
      );

      establish(it, _phone);
      end(it, _phone);
      await runScheduledReselection();

      expect(attempts.order, ['lan:$_phone']);
      expect(it.state.deviceFor(_phone).connected, isFalse);
    });

    test('duplicate link-loss events schedule only one retry and a healthy peer is not churned', () async {
      final it = service(
        settings: {_phone: enabled(_phone)},
        routes: [_pairing(_phone, address: 'RELAY1.phone')],
        candidates: {
          _phone: [_candidate('192.168.1.24')],
        },
      );

      establish(it, _phone);
      end(it, _phone);
      end(it, _phone);
      expect(scheduledReselections, hasLength(1));

      await runScheduledReselection();
      expect(attempts.order, ['lan:$_phone', 'anywhere:RELAY1.phone']);

      establish(it, _phone, local: false);
      await it.dispatchAsync(ContinuityConnectEnabledDevicesAction(relayIds: {_phone}));
      expect(attempts.order, ['lan:$_phone', 'anywhere:RELAY1.phone']);
    });

    test('a forgotten device is not reconnected after its retry was queued', () async {
      final settings = <String, RelayContinuitySettings>{_phone: enabled(_phone)};
      final routes = <RelayPairedAddress>[_pairing(_phone, address: 'RELAY1.phone')];
      final it = service(
        settings: settings,
        routes: routes,
        candidates: {
          _phone: [_candidate('192.168.1.24')],
        },
      );

      establish(it, _phone);
      end(it, _phone);
      settings.remove(_phone);
      routes.clear();
      await runScheduledReselection();

      expect(attempts.order, isEmpty);
    });

    test('a trust-revoked device is not reconnected after its retry was queued', () async {
      final settings = <String, RelayContinuitySettings>{_phone: enabled(_phone)};
      final it = service(
        settings: settings,
        routes: [_pairing(_phone, address: 'RELAY1.phone')],
        candidates: {
          _phone: [_candidate('192.168.1.24')],
        },
      );

      establish(it, _phone);
      end(it, _phone);
      settings[_phone] = const RelayContinuitySettings(relayId: _phone);
      await runScheduledReselection();

      expect(attempts.order, isEmpty);
    });

    test('a zero-grant device is not reconnected after its retry was queued', () async {
      final settings = <String, RelayContinuitySettings>{_phone: enabled(_phone)};
      final it = service(
        settings: settings,
        routes: [_pairing(_phone, address: 'RELAY1.phone')],
        candidates: {
          _phone: [_candidate('192.168.1.24')],
        },
      );

      establish(it, _phone);
      end(it, _phone);
      settings[_phone] = const RelayContinuitySettings(relayId: _phone, trusted: true);
      await runScheduledReselection();

      expect(attempts.order, isEmpty);
    });

    test('a compatibility peer without a paired continuity relationship never retries', () {
      final it = service(settings: const {}, routes: const []);

      establish(it, _phone);
      end(it, _phone);

      expect(scheduledReselections, isEmpty);
      expect(attempts.order, isEmpty);
    });

    test('a loss for one paired device does not reselect another healthy device', () async {
      final it = service(
        settings: {_phone: enabled(_phone), _laptop: enabled(_laptop)},
        routes: [
          _pairing(_phone, address: 'RELAY1.phone'),
          _pairing(_laptop, address: 'RELAY1.laptop'),
        ],
        candidates: {
          _phone: [_candidate('192.168.1.24')],
          _laptop: [_candidate('192.168.1.31')],
        },
      );

      establish(it, _phone);
      establish(it, _laptop);
      end(it, _phone);
      await runScheduledReselection();

      expect(attempts.order, ['lan:$_phone', 'anywhere:RELAY1.phone']);
    });
  });

  group('multiple paired devices', () {
    test('each device resolves its own transport independently', () async {
      final it = service(
        settings: {_phone: enabled(_phone), _laptop: enabled(_laptop)},
        routes: [
          _pairing(_phone),
          _pairing(_laptop, address: 'RELAY1.laptop'),
        ],
        candidates: {
          _phone: [_candidate('192.168.1.24')],
          _laptop: [_candidate('192.168.1.31')],
        },
        lanSucceeds: {_phone},
      );

      await it.dispatchAsync(ContinuityConnectEnabledDevicesAction());

      // The phone is local; the laptop was not reachable locally and fell back.
      expect(attempts.lan, containsAll([_phone, _laptop]));
      expect(attempts.anywhere, ['RELAY1.laptop']);
    });
  });
}

RelayIdentityCoordinator _coordinator() {
  final material = RelayIdentityMaterial(
    privateKey: Uint8List.fromList([1, 2, 3]),
    relayId: _localRelayId,
    publicKey: 'test-public-key',
  );
  return RelayIdentityCoordinator(
    secureStore: _FakeSecretStore(),
    identityApi: _FakeIdentityApi(material),
    metadataStore: _FakeMetadataStore(),
    signerPort: _FakeSignerPort(),
  );
}

class _FakeSecretStore implements RelayIdentitySecretStore {
  @override
  Future<RelaySecretLoadResult> load() async => RelaySecretFound(Uint8List.fromList([1, 2, 3]));

  @override
  Future<RelaySecretStoreResult> save(Uint8List secret) async => const RelaySecretStoreSuccess();

  @override
  Future<RelaySecretStoreResult> delete() async => const RelaySecretStoreSuccess();
}

class _FakeIdentityApi implements RelayIdentityApi {
  final RelayIdentityMaterial _material;

  _FakeIdentityApi(this._material);

  @override
  Future<RelayIdentityMaterial> generate() async => _material;

  @override
  Future<RelayIdentityMaterial> restore(Uint8List privateKey) async => _material;
}

class _FakeMetadataStore implements RelayIdentityMetadataStore {
  @override
  Future<void> clear() async {}

  @override
  Future<RelayPublicIdentity?> load() async => null;

  @override
  Future<void> save(RelayPublicIdentity identity) async {}
}

class _FakeSignerPort implements RelayServerSignerPort {
  @override
  Future<RelaySignerInstallOutcome> install(Uint8List privateKey, String expectedRelayId) async => RelaySignerInstallInstalled(expectedRelayId);

  @override
  Future<RelaySignerRevokeOutcome> revoke() async => const RelaySignerRevokeServerNotRunning();
}
