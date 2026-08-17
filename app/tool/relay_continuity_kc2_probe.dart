import 'dart:io';

import 'package:localsend_app/continuity/kde_connect_daemon_backend.dart';
import 'package:localsend_app/continuity/kde_connect_dbus_boundary.dart';

Future<void> main() async {
  final backend = KdeConnectDaemonBackend(dbus: KdeConnectDbusClient());
  try {
    await backend.start();
    final snapshot = backend.snapshot;
    stdout.writeln('backend=kdeconnectd health=${snapshot.health.status.name} peers=${snapshot.peers.length}');
    for (final peer in snapshot.peers) {
      stdout.writeln(
        'peer=${peer.id.opaqueId} paired=${peer.paired} reachable=${peer.reachable} '
        'clipboardText=${peer.capabilities.isNotEmpty} name=${peer.displayName}',
      );
    }
  } finally {
    await backend.close();
  }
}
