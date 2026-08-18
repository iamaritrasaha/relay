import 'package:flutter/foundation.dart';
import 'package:localsend_app/util/security/android_relay_routing_key_secret_store.dart';
import 'package:localsend_app/util/security/linux_relay_routing_key_secret_store.dart';
import 'package:localsend_app/util/security/relay_identity_secret_store.dart';
import 'package:localsend_app/util/security/relay_routing_key_secret_store.dart';

RelayRoutingKeySecretStore createRelayRoutingKeySecretStore() => switch (defaultTargetPlatform) {
  TargetPlatform.android => AndroidRelayRoutingKeySecretStore(),
  TargetPlatform.linux => LinuxRelayRoutingKeySecretStore(),
  _ => const _UnavailableRelayRoutingKeySecretStore(),
};

class _UnavailableRelayRoutingKeySecretStore implements RelayRoutingKeySecretStore {
  const _UnavailableRelayRoutingKeySecretStore();

  @override
  Future<RelaySecretLoadResult> load() async => const RelaySecretNotAvailable();

  @override
  Future<RelaySecretStoreResult> save(Uint8List secret) async => const RelaySecretStoreNotAvailable();

  @override
  Future<RelaySecretStoreResult> delete() async => const RelaySecretStoreNotAvailable();
}
