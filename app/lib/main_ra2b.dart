import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:localsend_app/config/relay_brand.dart';
import 'package:localsend_app/pages/ra2b_build_info.dart';
import 'package:localsend_app/pages/ra2b_proof_page.dart';
import 'package:localsend_app/widget/relay_symbol.dart';
import 'package:localsend_isolates/rust/api/logging.dart' as rust_logging;
import 'package:localsend_isolates/rust/api/ra2b.dart' as rust_ra2b;
import 'package:localsend_isolates/rust/frb_generated.dart';

/// RA2B development entrypoint. Renders immediately; native init is async.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterError.onError = (details) {
    FlutterError.dumpErrorToConsole(details);
    developer.log(
      details.exceptionAsString(),
      name: 'ra2b',
      stackTrace: details.stack,
      error: details.exception,
    );
  };
  runApp(Ra2bHarnessApp(initialize: initializeRa2bBridge));
}

enum Ra2bBootstrapPhase { loading, ready, failed }

class Ra2bBootstrapResult {
  const Ra2bBootstrapResult._({
    required this.phase,
    this.relayId,
    this.stage,
    this.message,
  });

  const Ra2bBootstrapResult.loading() : this._(phase: Ra2bBootstrapPhase.loading);

  const Ra2bBootstrapResult.ready({required String relayId}) : this._(phase: Ra2bBootstrapPhase.ready, relayId: relayId);

  const Ra2bBootstrapResult.failed({required String stage, required String message})
    : this._(phase: Ra2bBootstrapPhase.failed, stage: stage, message: message);

  final Ra2bBootstrapPhase phase;
  final String? relayId;
  final String? stage;
  final String? message;
}

String _safeInitMessage(Object error) {
  final raw = error.toString();
  final lower = raw.toLowerCase();
  if (lower.contains('private') || lower.contains('signature') || lower.contains('pem') || lower.contains('invite')) {
    return 'Native initialization failed (details omitted).';
  }
  if (raw.length > 400) {
    return '${raw.substring(0, 400)}…';
  }
  return raw;
}

/// Minimum FRB/Rust bridge init. Does not start Iroh, host, or join sessions.
Future<Ra2bBootstrapResult> initializeRa2bBridge() async {
  try {
    await RustLib.init();
  } catch (error, stack) {
    debugPrint('RA2B INITIALIZATION FAILED stage=frb error=$error\n$stack');
    return Ra2bBootstrapResult.failed(stage: 'frb', message: _safeInitMessage(error));
  }
  try {
    await rust_logging.enableDebugLogging();
  } catch (error, stack) {
    debugPrint('RA2B debug logging failed (non-fatal) error=$error\n$stack');
  }
  try {
    final identity = rust_ra2b.ra2BLocalIdentity();
    return Ra2bBootstrapResult.ready(relayId: identity.relayId);
  } catch (error, stack) {
    debugPrint('RA2B INITIALIZATION FAILED stage=identity error=$error\n$stack');
    return Ra2bBootstrapResult.failed(stage: 'identity', message: _safeInitMessage(error));
  }
}

class Ra2bHarnessApp extends StatefulWidget {
  const Ra2bHarnessApp({super.key, required this.initialize, this.bindNative = true});

  final Future<Ra2bBootstrapResult> Function() initialize;
  final bool bindNative;

  @override
  State<Ra2bHarnessApp> createState() => _Ra2bHarnessAppState();
}

class _Ra2bHarnessAppState extends State<Ra2bHarnessApp> {
  Ra2bBootstrapResult _result = const Ra2bBootstrapResult.loading();
  var _generation = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_bootstrap());
  }

  Future<void> _bootstrap() async {
    final generation = ++_generation;
    setState(() => _result = const Ra2bBootstrapResult.loading());
    try {
      final result = await widget.initialize();
      if (!mounted || generation != _generation) {
        return;
      }
      setState(() => _result = result);
      if (result.phase == Ra2bBootstrapPhase.ready) {
        debugPrint('RA2B native bridge ready; Host/Join UI is active');
      }
    } catch (error, stack) {
      debugPrint('RA2B INITIALIZATION FAILED stage=bootstrap error=$error\n$stack');
      if (!mounted || generation != _generation) {
        return;
      }
      setState(() {
        _result = Ra2bBootstrapResult.failed(stage: 'bootstrap', message: _safeInitMessage(error));
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = RelayPalette.dark;
    return MaterialApp(
      title: 'Relay Anywhere RA2B',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: relayColorScheme(Brightness.dark),
        scaffoldBackgroundColor: palette.canvas,
        visualDensity: VisualDensity.standard,
      ),
      home: switch (_result.phase) {
        Ra2bBootstrapPhase.loading => const Ra2bStartupShell(status: Ra2bStartupStatus.loading),
        Ra2bBootstrapPhase.failed => Ra2bStartupShell(
          status: Ra2bStartupStatus.failed,
          stage: _result.stage,
          message: _result.message,
          onRetry: () => unawaited(_bootstrap()),
        ),
        Ra2bBootstrapPhase.ready => Ra2bProofPage(localRelayId: _result.relayId!, bindNative: widget.bindNative),
      },
    );
  }
}

enum Ra2bStartupStatus { loading, failed }

/// Visible first-frame shell used before native init succeeds.
class Ra2bStartupShell extends StatelessWidget {
  const Ra2bStartupShell({
    super.key,
    required this.status,
    this.stage,
    this.message,
    this.onRetry,
  });

  final Ra2bStartupStatus status;
  final String? stage;
  final String? message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final palette = RelayPalette.dark;
    return Scaffold(
      backgroundColor: palette.canvas,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              child: ListView(
                children: [
                  Text(ra2bReleaseBanner, style: RelayTypography.section(palette.accent)),
                  const SizedBox(height: 4),
                  Text(ra2bReleaseSubtitle, style: RelayTypography.legal(palette.textTertiary)),
                  const SizedBox(height: 4),
                  Text('entrypoint: lib/main_ra2b.dart · $ra2bBuildId', style: RelayTypography.legal(palette.textTertiary)),
                  const SizedBox(height: 16),
                  const Row(
                    children: [
                      RelaySymbol(size: 28),
                      SizedBox(width: 10),
                      Text('RELAY ANYWHERE', style: TextStyle(fontSize: 17.5, height: 1.2, fontWeight: FontWeight.w500)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text('Development Proof', style: RelayTypography.section(palette.textSecondary)),
                  const SizedBox(height: 28),
                  if (status == Ra2bStartupStatus.loading) ...[
                    Text('Initializing…', style: RelayTypography.pageTitle(palette.accent)),
                    const SizedBox(height: 12),
                    Text(
                      'Loading the RA2B native bridge. Host/Join stay on this screen until that finishes.',
                      style: RelayTypography.value(palette.textSecondary),
                    ),
                  ] else ...[
                    Text('RA2B INITIALIZATION FAILED', style: RelayTypography.pageTitle(palette.error)),
                    const SizedBox(height: 12),
                    Text('stage: ${stage ?? 'unknown'}', style: RelayTypography.section(palette.textSecondary)),
                    const SizedBox(height: 8),
                    Text(message ?? 'Unknown error', style: RelayTypography.value(palette.textPrimary)),
                    const SizedBox(height: 20),
                    FilledButton(onPressed: onRetry, child: const Text('Retry')),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
