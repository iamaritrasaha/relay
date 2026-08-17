import 'package:flutter/foundation.dart';
import 'package:localsend_app/util/security/android_relay_identity_secret_store.dart';
import 'package:localsend_app/util/security/linux_relay_identity_secret_store.dart';
import 'package:localsend_app/util/security/relay_identity_secret_store.dart';

RelayIdentitySecretStore createRelayIdentitySecretStore() => switch (defaultTargetPlatform) {
  TargetPlatform.android => AndroidRelayIdentitySecretStore(),
  TargetPlatform.linux => LinuxRelayIdentitySecretStore(),
  _ => const _UnavailableRelayIdentitySecretStore(),
};

class _UnavailableRelayIdentitySecretStore implements RelayIdentitySecretStore {
  const _UnavailableRelayIdentitySecretStore();

  @override
  Future<RelaySecretLoadResult> load() async => const RelaySecretNotAvailable();

  @override
  Future<RelaySecretStoreResult> save(Uint8List secret) async => const RelaySecretStoreNotAvailable();

  @override
  Future<RelaySecretStoreResult> delete() async => const RelaySecretStoreNotAvailable();
}
