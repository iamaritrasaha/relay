import 'package:localsend_app/model/persistence/relay_paired_address.dart';
import 'package:localsend_app/provider/persistence_provider.dart';
import 'package:refena_flutter/refena_flutter.dart';

/// Reactive view of authenticated routing metadata.
///
/// Entries are keyed by proven RelayId but remain deliberately separate from
/// the trust directory. Refreshing this provider cannot create trust.
final relayPairedRoutesProvider = NotifierProvider<RelayPairedRoutesNotifier, List<RelayPairedAddress>>((ref) {
  return RelayPairedRoutesNotifier(ref.read(persistenceProvider));
});

class RelayPairedRoutesNotifier extends PureNotifier<List<RelayPairedAddress>> {
  final PersistenceService _persistence;

  RelayPairedRoutesNotifier(this._persistence);

  @override
  List<RelayPairedAddress> init() => _load();

  Future<void> refresh() async {
    state = _load();
  }

  List<RelayPairedAddress> _load() {
    final byRelayId = <String, RelayPairedAddress>{};
    for (final entry in _persistence.getRelayPairedAddresses()) {
      byRelayId[entry.relayId] = entry;
    }
    return byRelayId.values.toList()..sort((a, b) => a.relayId.compareTo(b.relayId));
  }
}
