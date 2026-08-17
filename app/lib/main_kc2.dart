import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:localsend_app/continuity/continuity_backend.dart';
import 'package:localsend_app/continuity/kde_connect_daemon_backend.dart';
import 'package:localsend_app/continuity/kde_connect_dbus_boundary.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const RelayKc2Harness());
}

class RelayKc2Harness extends StatefulWidget {
  const RelayKc2Harness({super.key});

  @override
  State<RelayKc2Harness> createState() => _RelayKc2HarnessState();
}

class _RelayKc2HarnessState extends State<RelayKc2Harness> {
  KdeConnectDaemonBackend? _backend;
  StreamSubscription<ContinuityBackendSnapshot>? _snapshotSubscription;
  ContinuityBackendSnapshot? _snapshot;
  String _lastResult = 'No clipboard dispatch attempted.';
  String _lastDiagnostic = 'No diagnostics yet.';

  @override
  void initState() {
    super.initState();
    if (!Platform.isLinux) {
      _lastResult = 'KC2 is Linux-only.';
      return;
    }
    final backend = KdeConnectDaemonBackend(
      dbus: KdeConnectDbusClient(),
      diagnostics: (diagnostic) {
        if (mounted) {
          setState(() => _lastDiagnostic = diagnostic.toString());
        }
      },
    );
    _backend = backend;
    _snapshot = backend.snapshot;
    _snapshotSubscription = backend.snapshots.listen((snapshot) {
      if (mounted) {
        setState(() => _snapshot = snapshot);
      }
    });
    unawaited(backend.start());
  }

  @override
  void dispose() {
    unawaited(_snapshotSubscription?.cancel());
    final backend = _backend;
    if (backend != null) {
      unawaited(backend.close());
    }
    super.dispose();
  }

  Future<void> _sendCurrentClipboard(ContinuityPeer peer) async {
    final backend = _backend;
    if (backend == null) {
      return;
    }
    final clipboard = await Clipboard.getData(Clipboard.kTextPlain);
    final text = clipboard?.text;
    if (text == null || text.isEmpty) {
      if (mounted) {
        setState(() => _lastResult = ContinuityResultStatus.invalidContent.name);
      }
      return;
    }

    final result = await backend.sendClipboardText(peer.id, text);
    if (mounted) {
      setState(() => _lastResult = result.status.name);
    }
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: Scaffold(
        appBar: AppBar(title: const Text('Relay KC2 — KDE Connect clipboard proof')),
        body: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Text('Development harness only. It is not connected to Relay discovery, trust, transfer, or production UI.'),
            const SizedBox(height: 16),
            Text('Backend health: ${snapshot?.health.status.name ?? 'unavailable'}'),
            Text('Last result: $_lastResult'),
            Text('Last metadata-only diagnostic: $_lastDiagnostic'),
            const SizedBox(height: 16),
            FilledButton.tonal(
              onPressed: _backend == null ? null : () => unawaited(_backend!.refresh()),
              child: const Text('Refresh daemon state'),
            ),
            const Divider(height: 32),
            if (snapshot == null || snapshot.peers.isEmpty) const Text('No KDE Connect devices exposed by the daemon.'),
            for (final peer in snapshot?.peers ?? const <ContinuityPeer>[])
              Card(
                child: ListTile(
                  title: Text(peer.displayName),
                  subtitle: Text(
                    'Provider ID: ${peer.id.opaqueId}\nPaired: ${peer.paired} · Reachable: ${peer.reachable} · '
                    'Text clipboard: ${peer.supports(ContinuityCapability.sendClipboardText)}',
                  ),
                  trailing: FilledButton(
                    onPressed: peer.supports(ContinuityCapability.sendClipboardText) ? () => unawaited(_sendCurrentClipboard(peer)) : null,
                    child: const Text('Send current text'),
                  ),
                ),
              ),
            const Divider(height: 32),
            const Text(
              'Android → Linux remains manual in the official KDE Connect Android app on Android 10+: use its foreground action, '
              'Quick Settings tile, or connection-notification action.',
            ),
          ],
        ),
      ),
    );
  }
}
