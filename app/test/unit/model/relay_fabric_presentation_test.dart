import 'package:relay_app/model/ui/relay_feature.dart';
import 'package:relay_app/model/ui/relay_last_seen.dart';
import 'package:relay_isolates/rust/api/kdeconnect.dart';
import 'package:test/test.dart';

void main() {
  group('last seen', () {
    final now = DateTime(2026, 8, 23, 12);

    int unix(DateTime value) => value.toUtc().millisecondsSinceEpoch ~/ 1000;

    test('uses deterministic human boundaries', () {
      expect(relayLastSeenLabel(unix(now.subtract(const Duration(seconds: 59))), now: now), 'Just now');
      expect(relayLastSeenLabel(unix(now.subtract(const Duration(minutes: 5))), now: now), '5 min ago');
      expect(relayLastSeenLabel(unix(now.subtract(const Duration(hours: 2))), now: now), '2 h ago');
      expect(relayLastSeenLabel(unix(DateTime(2026, 8, 22, 23, 59)), now: now), 'Yesterday');
      expect(relayLastSeenLabel(null, now: now), 'Never');
    });

    test('a future timestamp is clamped to Just now', () {
      expect(relayLastSeenLabel(unix(now.add(const Duration(minutes: 3))), now: now), 'Just now');
    });
  });

  test('every core feature availability keeps its distinct product meaning', () {
    final mapped = relayFeatureAvailability(const [
      RsRelayFeatureState(feature: RsRelayFeature.messages, availability: RsFeatureAvailability.available),
      RsRelayFeatureState(feature: RsRelayFeature.files, availability: RsFeatureAvailability.notConnected),
      RsRelayFeatureState(feature: RsRelayFeature.clipboard, availability: RsFeatureAvailability.disabled),
      RsRelayFeatureState(feature: RsRelayFeature.remoteInput, availability: RsFeatureAvailability.needsPermission),
      RsRelayFeatureState(feature: RsRelayFeature.commands, availability: RsFeatureAvailability.notConfigured),
    ]);

    expect(mapped[RelayFeature.messages], RelayFeatureAvailability.available);
    expect(mapped[RelayFeature.files], RelayFeatureAvailability.notConnected);
    expect(mapped[RelayFeature.clipboard], RelayFeatureAvailability.disabled);
    expect(mapped[RelayFeature.remoteInput], RelayFeatureAvailability.needsPermission);
    expect(mapped[RelayFeature.commands], RelayFeatureAvailability.notConfigured);
    expect(mapped[RelayFeature.battery], isNull, reason: 'an omitted feature is never invented as available');
  });
}
