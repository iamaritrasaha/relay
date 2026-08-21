import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:relay_app/config/relay_device_palette.dart';
import 'package:relay_app/model/ui/relay_device_vm.dart';
import 'package:relay_isolates/model/device.dart';

void main() {
  group('RelayDevicePalette', () {
    const device1 = RelayDeviceVm(
      key: 'kdeconnect:device-alpha-123',
      alias: 'Pixel 9 Pro',
      deviceType: DeviceType.mobile,
      phase: RelayDevicePhase.idle,
      progress: null,
      detail: 'Connected',
      relayId: 'device-alpha-123',
    );

    const device2 = RelayDeviceVm(
      key: 'kdeconnect:device-beta-456',
      alias: 'Galaxy S24',
      deviceType: DeviceType.mobile,
      phase: RelayDevicePhase.idle,
      progress: null,
      detail: 'Connected',
      relayId: 'device-beta-456',
    );

    test('is strictly deterministic for identical device ID', () {
      final p1 = RelayDevicePalette.fromDevice(device1, brightness: Brightness.dark);
      final p2 = RelayDevicePalette.fromDevice(device1, brightness: Brightness.dark);

      expect(p1.primary, equals(p2.primary));
      expect(p1.secondary, equals(p2.secondary));
      expect(p1.tertiary, equals(p2.tertiary));
      expect(p1.quaternary, equals(p2.quaternary));
      expect(p1.phaseOffset, equals(p2.phaseOffset));
    });

    test('normalizes device prefixes to produce identical palette', () {
      const devRaw = RelayDeviceVm(
        key: 'device-alpha-123',
        alias: 'Pixel',
        deviceType: DeviceType.mobile,
        phase: RelayDevicePhase.idle,
        progress: null,
        detail: 'Connected',
      );
      const devKde = RelayDeviceVm(
        key: 'kdeconnect:device-alpha-123',
        alias: 'Pixel',
        deviceType: DeviceType.mobile,
        phase: RelayDevicePhase.idle,
        progress: null,
        detail: 'Connected',
      );
      const devRelay = RelayDeviceVm(
        key: 'relay:device-alpha-123',
        alias: 'Pixel',
        deviceType: DeviceType.mobile,
        phase: RelayDevicePhase.idle,
        progress: null,
        detail: 'Connected',
      );

      final pRaw = RelayDevicePalette.fromDevice(devRaw, brightness: Brightness.dark);
      final pKde = RelayDevicePalette.fromDevice(devKde, brightness: Brightness.dark);
      final pRelay = RelayDevicePalette.fromDevice(devRelay, brightness: Brightness.dark);

      expect(pRaw.primary, equals(pKde.primary));
      expect(pKde.primary, equals(pRelay.primary));
    });

    test('produces distinct palettes for different device IDs', () {
      final p1 = RelayDevicePalette.fromDevice(device1, brightness: Brightness.dark);
      final p2 = RelayDevicePalette.fromDevice(device2, brightness: Brightness.dark);

      expect(p1.primary != p2.primary || p1.secondary != p2.secondary, isTrue);
      expect(p1.phaseOffset, isNot(equals(p2.phaseOffset)));
    });

    test('adapts colors for dark and light brightness modes', () {
      final dark = RelayDevicePalette.fromDevice(device1, brightness: Brightness.dark);
      final light = RelayDevicePalette.fromDevice(device1, brightness: Brightness.light);

      expect(dark.isDark, isTrue);
      expect(light.isDark, isFalse);
      expect(dark.primary, isNot(equals(light.primary)));
    });

    test('provides a fallback palette when device is null or empty', () {
      final fallbackDark = RelayDevicePalette.fromDevice(null, brightness: Brightness.dark);
      final fallbackLight = RelayDevicePalette.fromDevice(null, brightness: Brightness.light);

      expect(fallbackDark.primary, isNotNull);
      expect(fallbackLight.primary, isNotNull);
      expect(fallbackDark.gradientColors.length, greaterThanOrEqualTo(3));
    });

    test('gradientColors has 4 distinct steps and loopingGradientColors loops seamlessly', () {
      final p = RelayDevicePalette.fromDevice(device1, brightness: Brightness.dark);
      expect(p.gradientColors.length, equals(4));
      expect(p.loopingGradientColors.length, equals(5));
      expect(p.loopingGradientColors.first, equals(p.loopingGradientColors.last));
    });
  });
}
