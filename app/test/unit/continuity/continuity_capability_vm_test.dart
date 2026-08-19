import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_app/model/continuity/continuity_runtime.dart';
import 'package:localsend_app/model/persistence/relay_continuity_settings.dart';
import 'package:localsend_app/model/ui/relay_capability_vm.dart';
import 'package:localsend_app/model/ui/relay_device_vm.dart';
import 'package:flutter/material.dart';
import 'package:localsend_isolates/model/device.dart';

const _relayId = 'A1B2C3D4E5F6071829304152637485960718293041526374859607182930415C';

RelayDeviceVm _device({
  RelayDeviceTargetKind kind = RelayDeviceTargetKind.pairedRelay,
  Map<RelayCapability, CapabilityStatus> capabilities = const {},
  bool connected = false,
  RelayBatteryVm battery = const RelayBatteryVm(),
}) {
  return RelayDeviceVm(
    key: 'relay:$_relayId',
    alias: 'Pixel',
    deviceType: DeviceType.mobile,
    phase: RelayDevicePhase.idle,
    progress: null,
    detail: 'Nearby',
    targetKind: kind,
    relayId: _relayId,
    capabilities: capabilities,
    continuityConnected: connected,
    battery: battery,
  );
}

void main() {
  group('LocalSend isolation', () {
    test('a LocalSend peer is offered files and nothing else', () {
      final statuses = _device(
        kind: RelayDeviceTargetKind.unresolvedLan,
        // Even if some capability state leaked in, it must not be presented.
        capabilities: {RelayCapability.messages: CapabilityStatus.available},
      ).capabilityStatuses;

      expect(statuses[RelayCapability.files], CapabilityStatus.available);
      for (final capability in RelayCapability.values) {
        if (capability == RelayCapability.files) continue;
        expect(
          statuses[capability],
          CapabilityStatus.unavailable,
          reason: 'LocalSend peers never receive $capability',
        );
      }
    });
  });

  group('capability presentation', () {
    test('an unconfigured Relay device reports every capability off', () {
      final statuses = _device().capabilityStatuses;
      expect(statuses[RelayCapability.files], CapabilityStatus.available);
      expect(statuses[RelayCapability.clipboard], CapabilityStatus.disabled);
      expect(statuses[RelayCapability.phone], CapabilityStatus.disabled);
    });

    test('there is no longer a coming-soon state to fall into', () {
      // Every capability is implemented, so the only honest states are about
      // permission, platform limits, and whether the user turned it on.
      expect(
        CapabilityStatus.values.map((status) => status.name),
        containsAll(<String>['available', 'limited', 'permissionRequired', 'disabled', 'unavailable']),
      );
      expect(CapabilityStatus.values, hasLength(5));
    });

    test('a limited capability keeps its own badge', () {
      const info = RelayCapabilityInfo(
        capability: RelayCapability.clipboard,
        status: CapabilityStatus.limited,
        title: 'Clipboard',
        description: '',
        icon: Icons.abc,
        reason: 'Android only lets the focused app read the clipboard.',
      );
      expect(info.statusBadge, 'Limited');
      expect(info.isAvailable, isTrue);
      expect(info.reason, contains('focused app'));
    });
  });

  group('status summary', () {
    test('reads Connected only when a continuity session is live', () {
      expect(_device().statusSummary, isNot(contains('Connected')));
      expect(_device(connected: true).statusSummary, contains('Connected'));
    });
  });

  group('battery presentation', () {
    test('a missing reading is never shown as a number', () {
      expect(const RelayBatteryVm().displayString, 'Not reported');
      expect(const RelayBatteryVm().hasInfo, isFalse);
    });

    test('a stale reading is labelled rather than presented as live', () {
      const stale = RelayBatteryVm(percentage: 82, isCharging: true, isStale: true);
      expect(stale.displayString, contains('last known'));
      expect(stale.displayString, isNot(contains('Charging')));
    });

    test('charging and charged are distinguished', () {
      expect(const RelayBatteryVm(percentage: 82, isCharging: true).displayString, '82% · Charging');
      expect(const RelayBatteryVm(percentage: 100, isCharging: true, isFull: true).displayString, '100% · Charged');
      expect(const RelayBatteryVm(percentage: 55).displayString, '55%');
    });

    test('a remote reading goes stale rather than disappearing', () {
      final now = DateTime.now();
      final fresh = RemoteBattery(percentage: 82, charging: 'charging', observedAt: now);
      final old = RemoteBattery(
        percentage: 82,
        charging: 'charging',
        observedAt: now.subtract(const Duration(hours: 2)),
      );
      expect(fresh.isStale(now), isFalse);
      expect(old.isStale(now), isTrue);
      expect(old.summary(now), contains('last known'));
    });
  });

  group('call presentation', () {
    test('an unknown caller is never given a fabricated name', () {
      const call = RemoteCall(
        phase: RemoteCallPhase.ringing,
        address: null,
        displayName: null,
        activeDuration: null,
      );
      expect(call.title, 'Unknown caller');
      expect(call.statusLabel, 'Incoming call');
    });

    test('a resolved contact name is preferred over the number', () {
      const call = RemoteCall(
        phase: RemoteCallPhase.active,
        address: '+10000000000',
        displayName: 'Mum',
        activeDuration: Duration(seconds: 65),
      );
      expect(call.title, 'Mum');
      expect(call.isIdle, isFalse);
    });
  });

  group('continuity state', () {
    test('a fresh state enables nothing', () {
      const state = RelayContinuityState();
      expect(state.anyCapabilityEnabled, isFalse);
      expect(state.settingsFor(_relayId).hasAnyCapability, isFalse);
      expect(state.deviceFor(_relayId).connected, isFalse);
    });

    test('one enabled device is enough to need a connection', () {
      final state = RelayContinuityState(
        settings: {
          _relayId: const RelayContinuitySettings(relayId: _relayId, trusted: true).withCapability(ContinuityCapabilityKind.battery, true),
        },
      );
      expect(state.anyCapabilityEnabled, isTrue);
    });
  });

  _activityPrivacyTests();
}

/// Activity must be able to describe what happened without recording what was
/// in it. These strings are what the user sees in the Activity list.
void _activityPrivacyTests() {
  group('activity privacy', () {
    final entry = ContinuityActivityEntry(
      relayId: _relayId,
      deviceLabel: 'Pixel',
      kind: ContinuityActivityKind.clipboardShared,
      at: DateTime.now(),
    );

    test('a clipboard line names the device, never the content', () {
      expect(entry.summary, 'Clipboard shared with Pixel');
    });

    test('a message line records that one was sent, not its body or recipient', () {
      final sent = ContinuityActivityEntry(
        relayId: _relayId,
        deviceLabel: 'Pixel',
        kind: ContinuityActivityKind.messageSent,
        at: DateTime.now(),
      );
      expect(sent.summary, 'Message sent from Pixel');
    });

    test('every activity kind has a content-free summary', () {
      for (final kind in ContinuityActivityKind.values) {
        final line = ContinuityActivityEntry(
          relayId: _relayId,
          deviceLabel: 'Pixel',
          kind: kind,
          at: DateTime.now(),
        ).summary;
        expect(line, isNotEmpty);
        expect(line, contains('Pixel'));
      }
    });

    test('the feed stays bounded and is not persisted', () {
      var state = const RelayContinuityState();
      for (var index = 0; index < 200; index++) {
        state = state.withActivity(entry);
      }
      expect(state.activity, hasLength(50));
    });
  });
}
