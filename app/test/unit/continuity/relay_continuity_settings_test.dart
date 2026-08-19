import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_app/model/persistence/relay_continuity_settings.dart';

const _relayId = 'A1B2C3D4E5F6071829304152637485960718293041526374859607182930415C';

void main() {
  group('continuity consent', () {
    test('a device with no record shares nothing', () {
      const settings = RelayContinuitySettings(relayId: _relayId);
      expect(settings.trusted, isFalse);
      expect(settings.hasAnyCapability, isFalse);
      for (final capability in ContinuityCapabilityKind.values) {
        expect(settings.isEnabled(capability), isFalse, reason: '$capability must default to off');
      }
    });

    test('granting a capability without trust does not enable it', () {
      // Pairing can create a route; only a user decision creates trust. A grant
      // recorded against an untrusted device must stay inert.
      final settings = const RelayContinuitySettings(relayId: _relayId).withCapability(ContinuityCapabilityKind.notifications, true);
      expect(settings.granted, contains(ContinuityCapabilityKind.notifications));
      expect(settings.isEnabled(ContinuityCapabilityKind.notifications), isFalse);
    });

    test('clipboard is off while its mode is off, even when granted', () {
      final settings = const RelayContinuitySettings(
        relayId: _relayId,
        trusted: true,
      ).withCapability(ContinuityCapabilityKind.clipboard, true).copyWith(clipboardMode: ClipboardSharingMode.off);
      expect(settings.isEnabled(ContinuityCapabilityKind.clipboard), isFalse);

      final asking = settings.copyWith(clipboardMode: ClipboardSharingMode.ask);
      expect(asking.isEnabled(ContinuityCapabilityKind.clipboard), isTrue);
    });

    test('a granted capability is enabled once the device is trusted', () {
      final settings = const RelayContinuitySettings(relayId: _relayId, trusted: true).withCapability(ContinuityCapabilityKind.messages, true);
      expect(settings.isEnabled(ContinuityCapabilityKind.messages), isTrue);
      expect(settings.hasAnyCapability, isTrue);
    });
  });

  group('persistence', () {
    test('round trips', () {
      final original = const RelayContinuitySettings(relayId: _relayId, trusted: true)
          .withCapability(ContinuityCapabilityKind.battery, true)
          .withCapability(ContinuityCapabilityKind.phone, true)
          .copyWith(clipboardMode: ClipboardSharingMode.automatic);

      final restored = RelayContinuitySettings.tryParse(original.toJson());
      expect(restored, isNotNull);
      expect(restored!.trusted, isTrue);
      expect(restored.granted, original.granted);
      expect(restored.clipboardMode, ClipboardSharingMode.automatic);
    });

    test('a damaged record fails closed rather than granting anything', () {
      // Every unreadable field must degrade to "denied", never to "allowed".
      final parsed = RelayContinuitySettings.tryParse({
        'version': RelayContinuitySettings.currentVersion,
        'relayId': _relayId,
        'trusted': 'yes-please',
        'granted': ['messages', 'teleport', 42],
        'clipboardMode': 'always',
      });
      expect(parsed, isNotNull);
      expect(parsed!.trusted, isFalse, reason: 'only a real boolean true means trusted');
      expect(parsed.granted, {ContinuityCapabilityKind.messages});
      expect(parsed.clipboardMode, ClipboardSharingMode.off);
      expect(parsed.hasAnyCapability, isFalse);
    });

    test('an unrecognised or malformed record is dropped', () {
      expect(RelayContinuitySettings.tryParse(null), isNull);
      expect(RelayContinuitySettings.tryParse('nope'), isNull);
      expect(
        RelayContinuitySettings.tryParse({'version': 99, 'relayId': _relayId}),
        isNull,
        reason: 'a future record version is not guessed at',
      );
      expect(
        RelayContinuitySettings.tryParse({
          'version': RelayContinuitySettings.currentVersion,
          'relayId': 'not-a-relay-id',
        }),
        isNull,
      );
    });
  });

  group('withdrawing trust', () {
    test('clears the capabilities with it', () {
      final trusted = const RelayContinuitySettings(
        relayId: _relayId,
        trusted: true,
      ).withCapability(ContinuityCapabilityKind.notifications, true).copyWith(clipboardMode: ClipboardSharingMode.automatic);
      expect(trusted.hasAnyCapability, isTrue);

      // Mirrors what ContinuitySetTrustedAction persists: consent does not
      // survive untrusting, so re-trusting later cannot silently restore it.
      final untrusted = trusted.copyWith(
        trusted: false,
        granted: const {},
        clipboardMode: ClipboardSharingMode.off,
      );
      expect(untrusted.hasAnyCapability, isFalse);
      expect(untrusted.granted, isEmpty);
    });
  });
}
