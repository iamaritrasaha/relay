import 'package:relay_app/model/persistence/relay_paired_address.dart';

import '../mocks.mocks.dart';

/// Persistence for the desktop review renders.
class ReviewPersistenceService extends MockPersistenceService {
  @override
  bool getRemoteRelayEnabled() => false;

  @override
  List<RelayPairedAddress> getRelayPairedAddresses() => const [];
}
