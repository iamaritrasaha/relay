import 'package:relay_app/model/ui/relay_capability_vm.dart';
import 'package:relay_app/pages/relay_home_vm.dart';
import 'package:relay_isolates/rust/api/kdeconnect.dart';
import 'package:test/test.dart';

/// KDE Connect capabilities are directional, and the two directions mean
/// opposite things: a peer's `incomingCapabilities` are the packets it will
/// *accept*, its `outgoingCapabilities` are the packets it will *send*.
///
/// Collapsing the two into one "supports messages" flag is what previously let
/// reading and sending be gated on each other. These tests pin each direction
/// to the packet type that actually governs it.
///
/// The capability lists below are the ones a real KDE Connect Android peer
/// (protocol 8) advertises, trimmed to the types under test.
RsKdeConnectDevice device({
  bool paired = true,
  bool connected = true,
  List<String> incoming = const [],
  List<String> outgoing = const [],
}) => RsKdeConnectDevice(
  deviceId: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  name: 'Phone',
  deviceType: 'phone',
  ip: '192.168.0.100',
  port: 1716,
  paired: paired,
  connected: connected,
  incomingPair: false,
  identityMismatch: false,
  connectivityStale: false,
  incomingCapabilities: incoming,
  outgoingCapabilities: outgoing,
);

/// What a real Android peer accepts.
const _androidAccepts = [
  'kdeconnect.ping',
  'kdeconnect.findmyphone.request',
  'kdeconnect.sms.request',
  'kdeconnect.sms.request_conversations',
  'kdeconnect.sms.request_conversation',
  'kdeconnect.telephony.request_mute',
];

/// What a real Android peer sends.
const _androidSends = [
  'kdeconnect.battery',
  'kdeconnect.sms.messages',
  'kdeconnect.telephony',
];

void main() {
  group('SMS capabilities are derived independently per direction', () {
    test('a peer that accepts both read and send requests enables both', () {
      final vm = RelayHomeVm.kdeDeviceVm(device(incoming: _androidAccepts, outgoing: _androidSends));

      expect(vm.canSendSms, isTrue);
      expect(vm.capabilities[RelayCapability.messages], CapabilityStatus.available);
    });

    test('reading stays available when the peer refuses send requests', () {
      final incoming = _androidAccepts.where((type) => type != 'kdeconnect.sms.request').toList();
      final vm = RelayHomeVm.kdeDeviceVm(device(incoming: incoming, outgoing: _androidSends));

      expect(vm.canSendSms, isFalse, reason: 'send must follow kdeconnect.sms.request alone');
      expect(
        vm.capabilities[RelayCapability.messages],
        CapabilityStatus.available,
        reason: 'a peer that cannot be sent to can still be read from',
      );
    });

    test('sending stays available when the peer refuses conversation requests', () {
      final incoming = _androidAccepts.where((type) => type != 'kdeconnect.sms.request_conversations').toList();
      final vm = RelayHomeVm.kdeDeviceVm(device(incoming: incoming, outgoing: _androidSends));

      expect(vm.canSendSms, isTrue, reason: 'send must not be disabled by an unrelated read capability');
    });

    test('send is never offered to a peer that does not accept the request packet', () {
      final vm = RelayHomeVm.kdeDeviceVm(device(incoming: const ['kdeconnect.ping'], outgoing: _androidSends));

      expect(vm.canSendSms, isFalse);
    });

    test('a peer advertising sms.request only as outgoing does not enable send', () {
      // The wrong-direction case: the type is present, but on the list of things
      // the peer sends rather than the list of things it accepts.
      final vm = RelayHomeVm.kdeDeviceVm(device(incoming: const [], outgoing: const ['kdeconnect.sms.request']));

      expect(vm.canSendSms, isFalse);
    });

    test('an unpaired or disconnected peer offers neither', () {
      final unpaired = RelayHomeVm.kdeDeviceVm(device(paired: false, incoming: _androidAccepts, outgoing: _androidSends));
      final offline = RelayHomeVm.kdeDeviceVm(device(connected: false, incoming: _androidAccepts, outgoing: _androidSends));

      expect(unpaired.canSendSms, isFalse);
      expect(offline.canSendSms, isFalse);
      expect(unpaired.capabilities[RelayCapability.messages], CapabilityStatus.unavailable);
      expect(offline.capabilities[RelayCapability.messages], CapabilityStatus.unavailable);
    });

    /// Regression guard for the capability-refresh bug: once the Rust core
    /// authoritatively updates a peer's cached capabilities (after granting
    /// SEND_SMS on the phone and completing a secure re-handshake), the VM
    /// derivation must reflect the new snapshot rather than sticking to
    /// whatever it computed the first time.
    ///
    /// This is a VM-reactivity check only: it re-derives the VM from two
    /// static snapshots the way a Rust-side capability refresh would produce
    /// them, not a reproduction of the Rust bug itself -- a pure-Dart test
    /// cannot drive the two-peer TCP/TLS handshake that bug lives in. See
    /// `capability_refresh_completes_end_to_end_and_survives_stale_reader_cleanup`
    /// in `packages/core/src/kdeconnect/lan.rs` for that coverage.
    test('canSendSms flips true when a fresh snapshot adds the capability', () {
      final before = RelayHomeVm.kdeDeviceVm(
        device(incoming: const ['kdeconnect.ping'], outgoing: _androidSends),
      );
      expect(before.canSendSms, isFalse, reason: 'SEND_SMS not yet granted on the phone');

      final after = RelayHomeVm.kdeDeviceVm(device(incoming: _androidAccepts, outgoing: _androidSends));
      expect(after.canSendSms, isTrue, reason: 'capability refresh should surface the newly-granted permission');
    });
  });

  group('telephony capabilities follow their own direction', () {
    test('a peer that sends telephony events enables the phone surface', () {
      final vm = RelayHomeVm.kdeDeviceVm(device(incoming: const [], outgoing: const ['kdeconnect.telephony']));

      expect(vm.capabilities[RelayCapability.phone], CapabilityStatus.available);
    });

    test('muting follows the peer accepting the mute request, not sending events', () {
      final eventsOnly = RelayHomeVm.kdeDeviceVm(device(incoming: const [], outgoing: const ['kdeconnect.telephony']));
      final muteOnly = RelayHomeVm.kdeDeviceVm(device(incoming: const ['kdeconnect.telephony.request_mute'], outgoing: const []));

      expect(eventsOnly.canMuteRinger, isFalse, reason: 'sending events says nothing about accepting a mute request');
      expect(muteOnly.canMuteRinger, isTrue);
    });

    test('a real Android peer gets both event awareness and ringer mute', () {
      final vm = RelayHomeVm.kdeDeviceVm(device(incoming: _androidAccepts, outgoing: _androidSends));

      expect(vm.capabilities[RelayCapability.phone], CapabilityStatus.available);
      expect(vm.canMuteRinger, isTrue);
    });

    test('mute is not offered while disconnected', () {
      final vm = RelayHomeVm.kdeDeviceVm(device(connected: false, incoming: _androidAccepts, outgoing: _androidSends));

      expect(vm.canMuteRinger, isFalse);
    });
  });

  /// The display-facing map is a separate step from the derivation above, and
  /// it used to overwrite the SMS result with a hardcoded "unavailable". That
  /// hid the Messages action on the device page and told the GNOME pill the
  /// phone had no messages, on peers whose conversations Relay was reading at
  /// that very moment.
  group('the display capability map keeps the derived SMS result', () {
    test('a peer that accepts conversation requests reports messages available', () {
      final vm = RelayHomeVm.kdeDeviceVm(device(incoming: _androidAccepts, outgoing: _androidSends));

      expect(vm.capabilityStatuses[RelayCapability.messages], CapabilityStatus.available);
    });

    test('the display map agrees with the derived map', () {
      final vm = RelayHomeVm.kdeDeviceVm(device(incoming: _androidAccepts, outgoing: _androidSends));

      expect(vm.capabilityStatuses[RelayCapability.messages], vm.capabilities[RelayCapability.messages]);
    });

    test('a peer that refuses conversation requests still reports unavailable', () {
      final incoming = _androidAccepts.where((type) => type != 'kdeconnect.sms.request_conversations').toList();
      final vm = RelayHomeVm.kdeDeviceVm(device(incoming: incoming, outgoing: _androidSends));

      expect(vm.capabilityStatuses[RelayCapability.messages], CapabilityStatus.unavailable);
    });
  });
}
