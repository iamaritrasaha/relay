import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_app/config/relay_brand.dart';
import 'package:localsend_app/main_ra2b.dart';
import 'package:localsend_app/pages/ra2b_build_info.dart';
import 'package:localsend_app/pages/ra2b_invite_scan.dart';
import 'package:localsend_app/pages/ra2b_proof_page.dart';
import 'package:localsend_app/pages/ra2b_qr_scanner_page.dart';
import 'package:localsend_isolates/rust/api/ra2b.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';

const _testRelayId = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';

Widget _proofApp({
  RsRa2bParsedInvite Function(String invite)? inviteParser,
  Future<PermissionStatus> Function()? requestCamera,
  Future<String?> Function(BuildContext context)? scanInvite,
}) {
  return MaterialApp(
    theme: ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: relayColorScheme(Brightness.dark),
    ),
    home: Ra2bProofPage(
      localRelayId: _testRelayId,
      bindNative: false,
      inviteParser: inviteParser,
      requestCamera: requestCamera,
      scanInvite: scanInvite,
    ),
  );
}

void main() {
  test('relayIdPrefix keeps short ids and abbreviates long ones', () {
    expect(relayIdPrefix(null), '…');
    expect(relayIdPrefix('ABC'), 'ABC');
    expect(relayIdPrefix('ABCDEFGH1234WXYZ'), 'ABCDEFGH…WXYZ');
  });

  test('iroh connected is transport, not proof complete', () {
    const previous = Ra2bSessionSnapshot(stage: Ra2bUiStage.connecting, localRelayId: _testRelayId);
    final next = snapshotFromEvent(const RsRa2bEvent.irohConnected(), previous);
    expect(next.headline, 'IROH CONNECTED');
    expect(next.stage, Ra2bUiStage.transportConnected);
    expect(ra2bDiagFromEvent(const RsRa2bEvent.irohConnected()), 'TRANSPORT CONNECTED');
  });

  test('completion failure uses remote completion headline', () {
    const previous = Ra2bSessionSnapshot(stage: Ra2bUiStage.transferring, localRelayId: _testRelayId);
    final next = snapshotFromEvent(
      const RsRa2bEvent.failed(message: 'host did not confirm session result', category: 'completion'),
      previous,
    );
    expect(next.headline, 'REMOTE COMPLETION FAILED');
    expect(next.stage, Ra2bUiStage.failed);
  });

  test('scanner error categories map to visible copy', () {
    expect(ra2bScannerVisibleError('permission'), 'Camera permission required');
    expect(ra2bScannerVisibleError('unavailable'), 'Camera unavailable');
    expect(ra2bScannerVisibleError('init'), 'Scanner initialization failed');
    expect(
      ra2bScannerErrorCategory(const MobileScannerException(errorCode: MobileScannerErrorCode.permissionDenied)),
      'permission',
    );
  });

  test('invite shape accepts RA2B1 prefix and rejects junk', () {
    expect(ra2bInviteShapeError('RA2B1.${'A' * 20}'), isNull);
    expect(ra2bInviteShapeError('hello-world'), contains('unrelated'));
    expect(ra2bInviteShapeError('RA2B9.abc'), contains('unsupported'));
    expect(ra2bInviteShapeError('RA2B1.${'A' * ra2bMaxInviteLength}'), contains('exceeds'));
  });

  testWidgets('RA2B loading shell renders', (tester) async {
    final pending = Completer<Ra2bBootstrapResult>();
    await tester.pumpWidget(Ra2bHarnessApp(initialize: () => pending.future));
    expect(find.text(ra2bReleaseBanner), findsOneWidget);
    expect(find.text(ra2bReleaseSubtitle), findsOneWidget);
    expect(find.text('Development Proof'), findsOneWidget);
    expect(find.text('Initializing…'), findsOneWidget);
    pending.complete(const Ra2bBootstrapResult.ready(relayId: _testRelayId));
  });

  testWidgets('RA2B initialization failure renders an error instead of blank UI', (tester) async {
    await tester.pumpWidget(
      Ra2bHarnessApp(
        initialize: () async => const Ra2bBootstrapResult.failed(stage: 'frb', message: 'bridge unavailable'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('RA2B INITIALIZATION FAILED'), findsOneWidget);
    expect(find.textContaining('stage: frb'), findsOneWidget);
    expect(find.text('bridge unavailable'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Initializing…'), findsNothing);
  });

  testWidgets('RA2B ready shell shows Host and Join', (tester) async {
    await tester.pumpWidget(
      Ra2bHarnessApp(
        bindNative: false,
        initialize: () async => const Ra2bBootstrapResult.ready(relayId: _testRelayId),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('RELAY ANYWHERE'), findsOneWidget);
    expect(find.text('Development Proof'), findsOneWidget);
    expect(find.text('Host'), findsOneWidget);
    expect(find.text('Join'), findsOneWidget);
    expect(find.text(ra2bReleaseBanner), findsOneWidget);
  });

  testWidgets('Host screen renders Start Host', (tester) async {
    await tester.pumpWidget(_proofApp());
    await tester.tap(find.text('Host'));
    await tester.pumpAndSettle();
    expect(find.text('Start Host'), findsOneWidget);
    expect(find.text('HOST READY'), findsOneWidget);
  });

  testWidgets('Join screen renders Paste Invite and Connect', (tester) async {
    await tester.pumpWidget(_proofApp());
    await tester.tap(find.text('Join'));
    await tester.pumpAndSettle();
    expect(find.text('Paste Invite'), findsOneWidget);
    expect(find.text('Connect & Run Proof'), findsOneWidget);
    expect(find.text('Scan QR'), findsOneWidget);
  });

  testWidgets('scanned valid invite populates Join and does not auto-connect', (tester) async {
    await tester.pumpWidget(
      _proofApp(
        requestCamera: () async => PermissionStatus.granted,
        scanInvite: (_) async => 'RA2B1.${'A' * 24}',
        inviteParser: (invite) {
          expect(invite.startsWith(ra2bInvitePrefix), isTrue);
          return const RsRa2bParsedInvite(
            version: 1,
            hostRelayId: _testRelayId,
            routingAvailable: true,
          );
        },
      ),
    );
    await tester.tap(find.text('Join'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scan QR'));
    await tester.pumpAndSettle();
    expect(find.text(_testRelayId), findsOneWidget);
    expect(find.text('Available'), findsOneWidget);
    expect(find.text('INVITE SCANNED'), findsOneWidget);
    expect(find.text('CONNECTING'), findsNothing);
    expect(find.text('Connect & Run Proof'), findsOneWidget);
  });

  testWidgets('malformed scan is rejected without connecting', (tester) async {
    await tester.pumpWidget(
      _proofApp(
        requestCamera: () async => PermissionStatus.granted,
        scanInvite: (_) async => 'https://example.com',
      ),
    );
    await tester.tap(find.text('Join'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scan QR'));
    await tester.pumpAndSettle();
    expect(find.textContaining('unrelated QR'), findsAtLeast(1));
    expect(find.text('CONNECTING'), findsNothing);
    expect(find.text('Paste Invite'), findsOneWidget);
  });

  testWidgets('unsupported invite version is rejected', (tester) async {
    await tester.pumpWidget(
      _proofApp(
        requestCamera: () async => PermissionStatus.granted,
        scanInvite: (_) async => 'RA2B9.not-v1',
      ),
    );
    await tester.tap(find.text('Join'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scan QR'));
    await tester.pumpAndSettle();
    expect(find.textContaining('unsupported invite version'), findsAtLeast(1));
    expect(find.text('CONNECTING'), findsNothing);
  });

  testWidgets('permission denied leaves Paste Invite usable', (tester) async {
    await tester.pumpWidget(
      _proofApp(
        requestCamera: () async => PermissionStatus.denied,
        scanInvite: (_) async => throw StateError('scanner must not open'),
      ),
    );
    await tester.tap(find.text('Join'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scan QR'));
    await tester.pumpAndSettle();
    expect(find.text('Camera permission is required to scan an invite.'), findsOneWidget);
    expect(find.text('Paste Invite'), findsOneWidget);
    expect(find.text('Connect & Run Proof'), findsOneWidget);
  });
}
