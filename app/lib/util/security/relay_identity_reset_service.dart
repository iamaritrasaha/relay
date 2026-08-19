import 'package:relay_app/util/security/relay_identity_coordinator.dart';

/// Retries a signer-protected identity reset once after the server has been
/// completely stopped. UI wiring can use this narrow service without deleting
/// secure identity material outside [RelayIdentityCoordinator].
class RelayIdentityResetService {
  final RelayIdentityCoordinator _coordinator;
  final Future<void> Function() _stopServer;

  RelayIdentityResetService({
    required RelayIdentityCoordinator coordinator,
    required Future<void> Function() stopServer,
  }) : _coordinator = coordinator,
       _stopServer = stopServer;

  Future<RelayIdentityResetResult> reset() async {
    final initial = await _coordinator.resetIdentity();
    if (initial is! RelayIdentityResetSignerActive) {
      return initial;
    }

    await _stopServer();
    return _coordinator.resetIdentity();
  }
}
