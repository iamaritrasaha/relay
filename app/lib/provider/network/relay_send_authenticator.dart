import 'package:relay_isolates/rust/api/http.dart' as rust_http;
import 'package:relay_isolates/rust/api/model.dart' as rust_model;

/// Performs at most one Relay proof check for a logical send initiation.
///
/// The outcome is diagnostic-only for Alpha: the existing manual transfer
/// flow always continues without introducing trust policy.
class RelaySendAttemptAuthenticator {
  final void Function(String) _log;
  Future<rust_http.RsRelayPeerAuth>? _result;

  RelaySendAttemptAuthenticator({required void Function(String) log}) : _log = log;

  Future<rust_http.RsRelayPeerAuth> authenticate({
    required rust_model.ProtocolType protocol,
    required Future<rust_http.RsRelayPeerAuth> Function() attempt,
  }) {
    return _result ??= _authenticate(protocol: protocol, attempt: attempt);
  }

  Future<rust_http.RsRelayPeerAuth> _authenticate({
    required rust_model.ProtocolType protocol,
    required Future<rust_http.RsRelayPeerAuth> Function() attempt,
  }) async {
    if (protocol != rust_model.ProtocolType.https) {
      const result = rust_http.RsRelayPeerAuth.notAttempted();
      _logResult(result);
      return result;
    }

    final rust_http.RsRelayPeerAuth result;
    try {
      result = await attempt();
    } catch (_) {
      const fallback = rust_http.RsRelayPeerAuth.transportUnauthenticated();
      _logResult(fallback);
      return fallback;
    }
    _logResult(result);
    return result;
  }

  void _logResult(rust_http.RsRelayPeerAuth result) {
    switch (result) {
      case rust_http.RsRelayPeerAuth_Authenticated(:final relayId):
        _log('Relay auth authenticated: $relayId');
      case rust_http.RsRelayPeerAuth_Unsupported():
        _log('Relay auth unsupported');
      case rust_http.RsRelayPeerAuth_SignerUnavailable():
        _log('Relay auth signer unavailable');
      case rust_http.RsRelayPeerAuth_NotAttempted():
        _log('Relay auth not attempted');
      case rust_http.RsRelayPeerAuth_TransportUnauthenticated():
        _log('Relay auth TransportUnauthenticated');
      case rust_http.RsRelayPeerAuth_Malformed():
        _log('Relay auth Malformed');
      case rust_http.RsRelayPeerAuth_RoleMismatch():
        _log('Relay auth RoleMismatch');
      case rust_http.RsRelayPeerAuth_ChallengeMismatch():
        _log('Relay auth ChallengeMismatch');
      case rust_http.RsRelayPeerAuth_CryptoInvalid():
        _log('Relay auth CryptoInvalid');
    }
  }
}
