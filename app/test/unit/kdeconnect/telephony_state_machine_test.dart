import 'package:relay_app/provider/kdeconnect_provider.dart';
import 'package:test/test.dart';

/// The call state machine, driven with the event sequences a real KDE Connect
/// Android peer emits. The cases that matter are the ones where a naive
/// "any cancel ends the call" rule goes wrong.
KdeTelephonyState event(String name, {bool isCancel = false, int at = 0}) => KdeTelephonyState(event: name, isCancel: isCancel, timestamp: at);

void main() {
  group('incoming call lifecycle', () {
    test('a ringing event starts the call', () {
      final active = nextActiveCall(null, event('ringing', at: 100));

      expect(active?.event, 'ringing');
      expect(active?.timestamp, 100);
    });

    test('ringing then talking moves the call to in-call', () {
      final ringing = nextActiveCall(null, event('ringing', at: 100));
      final talking = nextActiveCall(ringing, event('talking', at: 200));

      expect(talking?.event, 'talking');
      expect(talking?.timestamp, 200, reason: 'the talking clock starts when talking starts');
    });

    test('a late ringing cancel does not end a call that was answered', () {
      // This is the ordering that previously dropped the UI back to idle the
      // instant a call was picked up.
      final talking = nextActiveCall(nextActiveCall(null, event('ringing')), event('talking', at: 200));
      final afterLateCancel = nextActiveCall(talking, event('ringing', isCancel: true, at: 210));

      expect(afterLateCancel?.event, 'talking');
      expect(afterLateCancel?.timestamp, 200);
    });

    test('a talking cancel ends the call', () {
      final talking = nextActiveCall(null, event('talking', at: 200));

      expect(nextActiveCall(talking, event('talking', isCancel: true, at: 300)), isNull);
    });

    test('repeated talking events keep the original start time', () {
      final talking = nextActiveCall(null, event('talking', at: 200));
      final stillTalking = nextActiveCall(talking, event('talking', at: 260));

      expect(stillTalking?.timestamp, 200, reason: 'a duration measured from the latest repeat would reset to zero');
    });

    test('repeated ringing events keep the original start time', () {
      final ringing = nextActiveCall(null, event('ringing', at: 100));

      expect(nextActiveCall(ringing, event('ringing', at: 150))?.timestamp, 100);
    });
  });

  group('calls that never connect', () {
    test('a declined call ends when ringing is cancelled', () {
      final ringing = nextActiveCall(null, event('ringing', at: 100));

      expect(nextActiveCall(ringing, event('ringing', isCancel: true, at: 180)), isNull);
    });

    test('ringing never stays stuck once its cancel arrives', () {
      var call = nextActiveCall(null, event('ringing'));
      call = nextActiveCall(call, event('ringing'));
      call = nextActiveCall(call, event('ringing', isCancel: true));

      expect(call, isNull);
    });

    test('a missed call clears any live state', () {
      final ringing = nextActiveCall(null, event('ringing', at: 100));

      expect(nextActiveCall(ringing, event('missedCall', at: 190)), isNull);
    });

    test('a missed call from idle stays idle', () {
      expect(nextActiveCall(null, event('missedCall')), isNull);
    });
  });

  group('stray events', () {
    test('a cancel from idle stays idle', () {
      expect(nextActiveCall(null, event('ringing', isCancel: true)), isNull);
      expect(nextActiveCall(null, event('talking', isCancel: true)), isNull);
    });

    test('a talking cancel does not end a ringing call', () {
      final ringing = nextActiveCall(null, event('ringing', at: 100));

      expect(nextActiveCall(ringing, event('talking', isCancel: true, at: 110))?.event, 'ringing');
    });

    test('a full answered call returns to idle at the end', () {
      var call = nextActiveCall(null, event('ringing', at: 10));
      call = nextActiveCall(call, event('talking', at: 20));
      call = nextActiveCall(call, event('ringing', isCancel: true, at: 21));
      call = nextActiveCall(call, event('talking', isCancel: true, at: 90));

      expect(call, isNull);
    });
  });
}
