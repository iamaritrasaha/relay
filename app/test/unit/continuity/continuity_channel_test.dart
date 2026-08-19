import 'package:flutter_test/flutter_test.dart';
import 'package:relay_app/util/native/continuity_channel.dart';

/// The channel decodes untrusted-shaped platform maps. Missing or wrong-typed
/// entries must produce a usable value rather than throwing into a stream.
void main() {
  test('a capability state without a reason still decodes', () {
    final state = PlatformCapabilityState.parse({'state': 'limited'});
    expect(state.state, 'limited');
    expect(state.isAvailable, isTrue);
    expect(state.reason, isNull);
  });

  test('an unknown capability state is not treated as available', () {
    final state = PlatformCapabilityState.parse({});
    expect(state.isAvailable, isFalse);
    expect(state.needsPermission, isFalse);
  });

  test('a battery reading with no level stays null rather than becoming zero', () {
    final battery = PlatformBattery.parse({'charging': 'charging'});
    expect(battery.percentage, isNull);
    expect(battery.charging, 'charging');
  });

  test('a foreground-restricted clipboard read carries its reason', () {
    final read = PlatformClipboardRead.parse({
      'state': 'requiresForeground',
      'reason': 'Android only lets the focused app read the clipboard',
    });
    expect(read.text, isNull);
    expect(read.unavailableReason, contains('focused app'));
  });

  test('conversation and message pages tolerate missing fields', () {
    final page = PlatformConversationsPage.parse({
      'conversations': [
        {'conversationId': '42', 'lastMessageAtMs': 17},
        'not a conversation',
      ],
      'hasMore': true,
    });
    expect(page.conversations, hasLength(1));
    expect(page.conversations.single.conversationId, '42');
    expect(page.conversations.single.addresses, isEmpty);
    expect(page.hasMore, isTrue);

    final messages = PlatformMessagesPage.parse({
      'conversationId': '42',
      'messages': [
        {'messageId': '900', 'body': 'hello', 'outgoing': true},
      ],
    });
    expect(messages.messages.single.outgoing, isTrue);
    expect(messages.messages.single.sentAtMs, 0);
    expect(messages.hasMore, isFalse);
  });

  test('a missing platform result is an honest failure, not a success', () {
    final outcome = PlatformOutcome.parse(null);
    expect(outcome.succeeded, isFalse);
    expect(outcome.state, 'unsupported');
  });

  test('an event without a kind is discarded', () {
    expect(PlatformContinuityEvent.parse({'nothing': true}).isUnknown, isTrue);
    expect(PlatformContinuityEvent.parse({'event': 'battery'}).isUnknown, isFalse);
  });
}
