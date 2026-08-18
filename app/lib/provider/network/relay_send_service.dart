import 'package:localsend_app/model/cross_file.dart';
import 'package:localsend_app/provider/network/send_provider.dart';
import 'package:localsend_isolates/model/device.dart';
import 'package:refena_flutter/refena_flutter.dart';

/// Product send entrypoint used by Relay Home.
///
/// The notifier remains the presentation state holder, while its normal LAN
/// execution is driven by the Rust canonical transfer events.  This gateway is
/// deliberately transport-agnostic: Home supplies a logical target and a
/// payload; transport selection never belongs in the widget tree.
final relaySendServiceProvider = Provider<RelaySendService>((ref) => RelaySendService(ref));

class RelaySendService {
  final Ref _ref;

  RelaySendService(this._ref);

  Future<void> send({
    required Device target,
    required List<CrossFile> files,
    required bool background,
  }) => _ref
      .notifier(sendProvider)
      .startSession(
        target: target,
        files: files,
        background: background,
      );

  void cancel(String sessionId) => _ref.notifier(sendProvider).cancelSession(sessionId);
}
