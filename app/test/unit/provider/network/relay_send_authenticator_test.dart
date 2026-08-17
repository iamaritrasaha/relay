import 'package:localsend_app/provider/network/relay_send_authenticator.dart';
import 'package:localsend_isolates/rust/api/http.dart' as rust_http;
import 'package:localsend_isolates/rust/api/model.dart' as rust_model;
import 'package:test/test.dart';

void main() {
  Future<rust_http.RsRelayPeerAuth> authenticate(
    RelaySendAttemptAuthenticator authenticator,
    rust_http.RsRelayPeerAuth result,
  ) {
    return authenticator.authenticate(
      protocol: rust_model.ProtocolType.https,
      attempt: () async => result,
    );
  }

  test('authenticated HTTPS peer logs its RelayId', () async {
    final logs = <String>[];
    final result = await authenticate(
      RelaySendAttemptAuthenticator(log: logs.add),
      const rust_http.RsRelayPeerAuth.authenticated(relayId: 'relay-id'),
    );

    expect(result, isA<rust_http.RsRelayPeerAuth_Authenticated>());
    expect(logs, ['Relay auth authenticated: relay-id']);
  });

  test('unsupported peer continues with a diagnostic', () async {
    final logs = <String>[];
    final result = await authenticate(
      RelaySendAttemptAuthenticator(log: logs.add),
      const rust_http.RsRelayPeerAuth.unsupported(),
    );

    expect(result, isA<rust_http.RsRelayPeerAuth_Unsupported>());
    expect(logs, ['Relay auth unsupported']);
  });

  test('signer-unavailable peer continues with a diagnostic', () async {
    final logs = <String>[];
    final result = await authenticate(
      RelaySendAttemptAuthenticator(log: logs.add),
      const rust_http.RsRelayPeerAuth.signerUnavailable(),
    );

    expect(result, isA<rust_http.RsRelayPeerAuth_SignerUnavailable>());
    expect(logs, ['Relay auth signer unavailable']);
  });

  test('crypto-invalid peer is never marked authenticated', () async {
    final logs = <String>[];
    final result = await authenticate(
      RelaySendAttemptAuthenticator(log: logs.add),
      const rust_http.RsRelayPeerAuth.cryptoInvalid(),
    );

    expect(result, isA<rust_http.RsRelayPeerAuth_CryptoInvalid>());
    expect(result, isNot(isA<rust_http.RsRelayPeerAuth_Authenticated>()));
    expect(logs, ['Relay auth CryptoInvalid']);
  });

  test('HTTP peer skips Relay authentication', () async {
    final logs = <String>[];
    var attempts = 0;
    final result = await RelaySendAttemptAuthenticator(log: logs.add).authenticate(
      protocol: rust_model.ProtocolType.http,
      attempt: () async {
        attempts++;
        return const rust_http.RsRelayPeerAuth.authenticated(relayId: 'unexpected');
      },
    );

    expect(result, isA<rust_http.RsRelayPeerAuth_NotAttempted>());
    expect(attempts, 0);
    expect(logs, ['Relay auth not attempted']);
  });

  test('one send initiation authenticates once for multiple files', () async {
    var attempts = 0;
    final authenticator = RelaySendAttemptAuthenticator(log: (_) {});
    Future<rust_http.RsRelayPeerAuth> authentication() async {
      attempts++;
      return const rust_http.RsRelayPeerAuth.authenticated(relayId: 'relay-id');
    }

    await authenticator.authenticate(protocol: rust_model.ProtocolType.https, attempt: authentication);
    await authenticator.authenticate(protocol: rust_model.ProtocolType.https, attempt: authentication);

    expect(attempts, 1);
  });
}
