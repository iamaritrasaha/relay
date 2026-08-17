import 'dart:typed_data';

import 'package:localsend_isolates/isolate.dart';
import 'package:refena_flutter/refena_flutter.dart';

abstract interface class RelayServerSignerPort {
  Future<RelaySignerInstallOutcome> install(Uint8List privateKey, String expectedRelayId);

  Future<RelaySignerRevokeOutcome> revoke();
}

sealed class RelaySignerInstallOutcome {
  const RelaySignerInstallOutcome();
}

final class RelaySignerInstallInstalled extends RelaySignerInstallOutcome {
  final String relayId;

  const RelaySignerInstallInstalled(this.relayId);
}

final class RelaySignerInstallServerNotRunning extends RelaySignerInstallOutcome {
  const RelaySignerInstallServerNotRunning();
}

final class RelaySignerInstallFailed extends RelaySignerInstallOutcome {
  const RelaySignerInstallFailed();
}

sealed class RelaySignerRevokeOutcome {
  const RelaySignerRevokeOutcome();
}

final class RelaySignerRevokeRevoked extends RelaySignerRevokeOutcome {
  const RelaySignerRevokeRevoked();
}

final class RelaySignerRevokeServerNotRunning extends RelaySignerRevokeOutcome {
  const RelaySignerRevokeServerNotRunning();
}

final class RelaySignerRevokeUnreachable extends RelaySignerRevokeOutcome {
  const RelaySignerRevokeUnreachable();
}

/// Control-plane adapter for the running server isolate.
///
/// It sends only one-shot install/revoke tasks; private bytes never enter
/// synchronized isolate state or app provider state.
class IsolateRelayServerSignerPort implements RelayServerSignerPort {
  final Ref _ref;

  IsolateRelayServerSignerPort(this._ref);

  @override
  Future<RelaySignerInstallOutcome> install(Uint8List privateKey, String expectedRelayId) async {
    try {
      final relayId = await _ref
          .redux(parentIsolateProvider)
          .dispatchAsyncTakeResult(
            IsolateHttpServerInstallRelaySignerAction(
              privateKey: privateKey,
              expectedRelayId: expectedRelayId,
            ),
          );
      return RelaySignerInstallInstalled(relayId);
    } on StateError {
      return const RelaySignerInstallServerNotRunning();
    } catch (error) {
      if (error.toString().contains('Server is not running')) {
        return const RelaySignerInstallServerNotRunning();
      }
      return const RelaySignerInstallFailed();
    }
  }

  @override
  Future<RelaySignerRevokeOutcome> revoke() async {
    try {
      await _ref.redux(parentIsolateProvider).dispatchAsyncTakeResult(IsolateHttpServerRevokeRelaySignerAction());
      return const RelaySignerRevokeRevoked();
    } on StateError {
      return const RelaySignerRevokeServerNotRunning();
    } catch (error) {
      if (error.toString().contains('Server is not running')) {
        return const RelaySignerRevokeServerNotRunning();
      }
      return const RelaySignerRevokeUnreachable();
    }
  }
}

/// Runs non-blocking signer activation once for each running server instance.
/// It deliberately holds no secret material and lets ordinary server startup
/// continue when activation cannot install a signer.
class RelayServerSignerActivationController {
  final Future<void> Function() _activate;
  bool _activatedForCurrentServer = false;

  RelayServerSignerActivationController({
    required Future<void> Function() activate,
  }) : _activate = activate;

  Future<void> onServerStarted() async {
    if (_activatedForCurrentServer) {
      return;
    }
    _activatedForCurrentServer = true;
    try {
      await _activate();
    } catch (_) {
      // The server remains available with an empty Rust signer slot.
    }
  }

  void onServerStopped() {
    _activatedForCurrentServer = false;
  }
}
