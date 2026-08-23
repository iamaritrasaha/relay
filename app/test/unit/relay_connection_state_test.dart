import 'package:flutter_test/flutter_test.dart';
import 'package:relay_app/model/ui/relay_connection_state.dart';
import 'package:relay_app/pages/relay_home_vm.dart';
import 'package:relay_isolates/rust/api/kdeconnect.dart';

/// Reachability has exactly one derivation. These pin the two defects that came
/// from having several: an offline device presented as "Local", and Local vs
/// Remote being collapsed into a single "Connected" string.
void main() {
  RsKdeConnectDevice device({
    bool paired = true,
    bool connected = true,
    String transportState = 'local',
  }) => RsKdeConnectDevice(
    deviceId: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    name: 'Galaxy M14',
    deviceType: 'phone',
    paired: paired,
    connected: connected,
    incomingPair: false,
    identityMismatch: false,
    connectivityStale: false,
    incomingCapabilities: const [],
    outgoingCapabilities: const [],
    transportState: transportState,
  );

  group('core mapping', () {
    test('each transport state maps to its own connection state', () {
      expect(RelayConnectionState.fromCore('local'), RelayConnectionState.local);
      expect(RelayConnectionState.fromCore('remoteDirect'), RelayConnectionState.remoteDirect);
      expect(RelayConnectionState.fromCore('remoteRelay'), RelayConnectionState.remoteRelay);
      expect(RelayConnectionState.fromCore('reconnecting'), RelayConnectionState.reconnecting);
      expect(RelayConnectionState.fromCore('offline'), RelayConnectionState.offline);
    });

    test('an unknown or missing state is offline, never a connected one', () {
      // Claiming reachability Relay cannot back up is the more damaging error:
      // every feature gate keys off this.
      for (final raw in [null, '', 'something-new', 'LOCAL']) {
        expect(RelayConnectionState.fromCore(raw), RelayConnectionState.offline, reason: '$raw');
      }
    });

    test('offline never reads as local', () {
      // The exact regression: a catch-all used to map offline onto local.
      final state = RelayConnectionState.fromCore('offline');
      expect(state, isNot(RelayConnectionState.local));
      expect(state.isConnected, isFalse);
      expect(state.userLabel, 'Offline');
    });
  });

  group('labels', () {
    test('both remote states read simply as Remote to a normal user', () {
      expect(RelayConnectionState.remoteDirect.userLabel, 'Remote');
      expect(RelayConnectionState.remoteRelay.userLabel, 'Remote');
    });

    test('the precise route is available only as a diagnostic', () {
      expect(RelayConnectionState.remoteRelay.diagnosticLabel, 'Relay WAN · Relay');
      expect(RelayConnectionState.remoteDirect.diagnosticLabel, 'Relay WAN · Direct');
      expect(RelayConnectionState.local.diagnosticLabel, 'KDE LAN');
    });

    test('no transport vocabulary leaks into a user-facing label', () {
      for (final state in RelayConnectionState.values) {
        final label = state.userLabel.toLowerCase();
        for (final banned in ['kde', 'iroh', 'wan', 'lan', 'quic', 'relay wan']) {
          expect(label, isNot(contains(banned)), reason: '$state exposed "$banned"');
        }
      }
    });
  });

  group('reachability predicates', () {
    test('only live routes count as connected', () {
      expect(RelayConnectionState.local.isConnected, isTrue);
      expect(RelayConnectionState.remoteDirect.isConnected, isTrue);
      expect(RelayConnectionState.remoteRelay.isConnected, isTrue);
      expect(RelayConnectionState.offline.isConnected, isFalse);
      expect(RelayConnectionState.reconnecting.isConnected, isFalse);
    });

    test('only remote routes are remote, which is what the file policy uses', () {
      expect(RelayConnectionState.remoteDirect.isRemote, isTrue);
      expect(RelayConnectionState.remoteRelay.isRemote, isTrue);
      expect(RelayConnectionState.local.isRemote, isFalse);
      expect(RelayConnectionState.offline.isRemote, isFalse);
    });
  });

  group('device view model', () {
    test('a connected LAN device is Local', () {
      final vm = RelayHomeVm.kdeDeviceVm(device(transportState: 'local'));
      expect(vm.connectionState, RelayConnectionState.local);
      expect(vm.connectionState.userLabel, 'Local');
    });

    test('a connected WAN device is Remote, not merely "Connected"', () {
      final vm = RelayHomeVm.kdeDeviceVm(device(transportState: 'remoteDirect'));
      expect(vm.connectionState, RelayConnectionState.remoteDirect);
      expect(vm.connectionState.userLabel, 'Remote');
    });

    test('a paired but disconnected device is Offline, not Local', () {
      final vm = RelayHomeVm.kdeDeviceVm(device(connected: false, transportState: 'offline'));
      expect(vm.connectionState, RelayConnectionState.offline);
      expect(vm.connectionState.isConnected, isFalse);
    });

    test('trust and reachability are independent facts', () {
      // Unpaired but somehow "connected" must not be treated as usable.
      final vm = RelayHomeVm.kdeDeviceVm(device(paired: false, transportState: 'local'));
      expect(vm.connectionState, RelayConnectionState.offline);
    });

    test('a stale transport string cannot outrank a disconnected device', () {
      // connected=false wins even if the transport state still says 'local'.
      final vm = RelayHomeVm.kdeDeviceVm(device(connected: false, transportState: 'local'));
      expect(vm.connectionState, RelayConnectionState.offline);
    });
  });
}
