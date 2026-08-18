import 'dart:async';
import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:localsend_app/config/relay_brand.dart';
import 'package:localsend_app/model/cross_file.dart';
import 'package:localsend_app/pages/ra2b_build_info.dart';
import 'package:localsend_app/pages/ra2b_invite_scan.dart';
import 'package:localsend_app/pages/ra2b_qr_scanner_page.dart';
import 'package:localsend_app/util/native/channel/android_channel.dart' as app_android_channel;
import 'package:localsend_app/util/native/cross_file_converters.dart';
import 'package:localsend_app/util/native/directories.dart';
import 'package:localsend_app/widget/relay_symbol.dart';
import 'package:localsend_isolates/src/task/server/file_saver.dart';
import 'package:localsend_isolates/rust/api/cancel.dart' as rust_cancel;
import 'package:localsend_isolates/rust/api/crypto.dart' as rust_crypto;
import 'package:localsend_isolates/rust/api/ra2b.dart' as rust_ra2b;
import 'package:localsend_isolates/util/android_channel.dart' as isolate_android_channel;
import 'package:mime/mime.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';

enum Ra2bScreen { home, host, join }

enum Ra2bUiStage {
  idle,
  startingHost,
  waiting,
  parsingInvite,
  connecting,
  transportConnected,
  authenticating,
  authenticated,
  incomingPrompt,
  transferring,
  complete,
  rejected,
  cancelled,
  failed,
}

class Ra2bSessionSnapshot {
  const Ra2bSessionSnapshot({
    required this.stage,
    this.headline = '',
    this.detail = '',
    this.invite,
    this.localRelayId,
    this.remoteRelayId,
    this.bytes = 0,
    this.total = 1048576,
    this.path,
    this.hashHex,
    this.durationMs,
    this.shaPass,
  });

  final Ra2bUiStage stage;
  final String headline;
  final String detail;
  final String? invite;
  final String? localRelayId;
  final String? remoteRelayId;
  final int bytes;
  final int total;
  final String? path;
  final String? hashHex;
  final int? durationMs;
  final bool? shaPass;

  bool get isBusy =>
      stage != Ra2bUiStage.idle &&
      stage != Ra2bUiStage.complete &&
      stage != Ra2bUiStage.rejected &&
      stage != Ra2bUiStage.cancelled &&
      stage != Ra2bUiStage.failed &&
      stage != Ra2bUiStage.waiting &&
      stage != Ra2bUiStage.parsingInvite &&
      stage != Ra2bUiStage.incomingPrompt;

  bool get canStop =>
      stage == Ra2bUiStage.startingHost ||
      stage == Ra2bUiStage.waiting ||
      stage == Ra2bUiStage.connecting ||
      stage == Ra2bUiStage.transportConnected ||
      stage == Ra2bUiStage.authenticating ||
      stage == Ra2bUiStage.authenticated ||
      stage == Ra2bUiStage.incomingPrompt ||
      stage == Ra2bUiStage.transferring;
}

Ra2bSessionSnapshot snapshotFromEvent(rust_ra2b.RsRa2bEvent event, Ra2bSessionSnapshot previous) {
  return event.map(
    starting: (_) => Ra2bSessionSnapshot(
      stage: previous.invite != null || previous.stage == Ra2bUiStage.waiting ? Ra2bUiStage.startingHost : Ra2bUiStage.connecting,
      headline: previous.stage == Ra2bUiStage.waiting || previous.invite != null ? 'STARTING HOST' : 'CONNECTING',
      invite: previous.invite,
      localRelayId: previous.localRelayId,
    ),
    inviteReady: (value) => Ra2bSessionSnapshot(
      stage: Ra2bUiStage.waiting,
      headline: 'WAITING FOR PEER',
      invite: value.invite,
      localRelayId: value.localRelayId,
      detail: value.autoRelayAvailable ? 'Auto / relay available' : 'Endpoint ready',
    ),
    waitingForPeer: (_) => Ra2bSessionSnapshot(
      stage: Ra2bUiStage.waiting,
      headline: 'WAITING FOR PEER',
      invite: previous.invite,
      localRelayId: previous.localRelayId,
      detail: previous.detail,
    ),
    connecting: (_) => Ra2bSessionSnapshot(
      stage: Ra2bUiStage.connecting,
      headline: 'CONNECTING',
      localRelayId: previous.localRelayId,
      remoteRelayId: previous.remoteRelayId,
    ),
    irohConnected: (_) => Ra2bSessionSnapshot(
      stage: Ra2bUiStage.transportConnected,
      headline: 'IROH CONNECTED',
      invite: previous.invite,
      localRelayId: previous.localRelayId,
      remoteRelayId: previous.remoteRelayId,
    ),
    tlsAuthenticated: (_) => Ra2bSessionSnapshot(
      stage: Ra2bUiStage.authenticating,
      headline: 'TLS AUTHENTICATED',
      invite: previous.invite,
      localRelayId: previous.localRelayId,
      remoteRelayId: previous.remoteRelayId,
    ),
    relayIdentityVerified: (value) => Ra2bSessionSnapshot(
      stage: Ra2bUiStage.authenticated,
      headline: 'RELAY IDENTITY VERIFIED',
      invite: previous.invite,
      localRelayId: previous.localRelayId,
      remoteRelayId: value.remoteRelayId,
    ),
    transferring: (value) => Ra2bSessionSnapshot(
      stage: Ra2bUiStage.transferring,
      headline: 'TRANSFERRING',
      detail: '${(value.bytes.toInt() / 1024).floor()} KiB / 1024 KiB',
      invite: previous.invite,
      localRelayId: previous.localRelayId,
      remoteRelayId: previous.remoteRelayId,
      bytes: value.bytes.toInt(),
      total: value.total.toInt(),
    ),
    complete: (value) => Ra2bSessionSnapshot(
      stage: Ra2bUiStage.complete,
      headline: 'COMPLETE',
      invite: previous.invite,
      localRelayId: value.localRelayId,
      remoteRelayId: value.remoteRelayId,
      bytes: value.bytes,
      path: value.path,
      hashHex: value.hashHex,
      durationMs: value.durationMs.toInt(),
      shaPass: true,
    ),
    rejected: (value) => Ra2bSessionSnapshot(
      stage: Ra2bUiStage.rejected,
      headline: 'IDENTITY REJECTED',
      detail: 'NO PAYLOAD ACCEPTED\n${value.message}',
      invite: previous.invite,
      localRelayId: previous.localRelayId,
      remoteRelayId: previous.remoteRelayId,
    ),
    failed: (value) {
      if (value.category == 'prompt') {
        try {
          final payload = jsonDecode(value.message) as Map<String, dynamic>;
          return Ra2bSessionSnapshot(
            stage: Ra2bUiStage.incomingPrompt,
            headline: 'INCOMING FILE',
            detail: '${payload['name']} · ${payload['size']} bytes',
            invite: previous.invite,
            localRelayId: previous.localRelayId,
            remoteRelayId: payload['remoteRelayId'] as String?,
          );
        } catch (_) {
          // A malformed prompt is terminal rather than an implicit accept.
        }
      }
      return Ra2bSessionSnapshot(
        stage: Ra2bUiStage.failed,
        headline: value.category == 'completion' ? 'REMOTE COMPLETION FAILED' : 'FAILED',
        detail: value.message,
        invite: previous.invite,
        localRelayId: previous.localRelayId,
        remoteRelayId: previous.remoteRelayId,
      );
    },
    cancelled: (_) => Ra2bSessionSnapshot(
      stage: Ra2bUiStage.cancelled,
      headline: 'CANCELLED',
      invite: previous.invite,
      localRelayId: previous.localRelayId,
    ),
  );
}

String ra2bDiagFromEvent(rust_ra2b.RsRa2bEvent event) {
  return event.map(
    starting: (_) => 'SESSION_START',
    inviteReady: (value) => 'ENDPOINT_READY local=${relayIdPrefix(value.localRelayId)}',
    waitingForPeer: (_) => 'WAITING',
    connecting: (_) => 'CONNECTING',
    irohConnected: (_) => 'TRANSPORT CONNECTED',
    tlsAuthenticated: (_) => 'TLS AUTHENTICATED',
    relayIdentityVerified: (value) => 'RELAY IDENTITY VERIFIED remote=${relayIdPrefix(value.remoteRelayId)}',
    transferring: (value) => 'PAYLOAD_BYTES=${value.bytes.toInt()}',
    complete: (value) => 'SESSION_COMPLETE bytes=${value.bytes} path=${value.path} remote=${relayIdPrefix(value.remoteRelayId)}',
    rejected: (value) => 'SESSION_ERROR=identity ${value.message}',
    failed: (value) => 'SESSION_ERROR=${value.category} ${value.message}',
    cancelled: (_) => 'SESSION_CANCELLED',
  );
}

String relayIdPrefix(String? relayId) {
  if (relayId == null || relayId.isEmpty) {
    return '…';
  }
  if (relayId.length <= 12) {
    return relayId;
  }
  return '${relayId.substring(0, 8)}…${relayId.substring(relayId.length - 4)}';
}

class Ra2bProofPage extends StatefulWidget {
  const Ra2bProofPage({
    super.key,
    required this.localRelayId,
    this.bindNative = true,
    this.inviteParser,
    this.requestCamera,
    this.scanInvite,
  });

  final String localRelayId;

  /// When false, Host/Join screens render without calling FRB (widget tests).
  final bool bindNative;

  /// Optional Join parser used by tests (and as a fallback when [bindNative] is false).
  final rust_ra2b.RsRa2bParsedInvite Function(String invite)? inviteParser;

  /// Injected camera permission request. Defaults to [Permission.camera.request].
  final Future<PermissionStatus> Function()? requestCamera;

  /// Injected scanner. Defaults to the Android [Ra2bQrScannerPage] route.
  final Future<String?> Function(BuildContext context)? scanInvite;

  @override
  State<Ra2bProofPage> createState() => _Ra2bProofPageState();
}

class _Ra2bProofPageState extends State<Ra2bProofPage> {
  Ra2bScreen _screen = Ra2bScreen.home;
  rust_ra2b.RsRa2bPathPreference _path = rust_ra2b.RsRa2bPathPreference.auto;
  Ra2bSessionSnapshot _session = const Ra2bSessionSnapshot(stage: Ra2bUiStage.idle);
  StreamSubscription<rust_ra2b.RsRa2bEvent>? _events;
  final _inviteController = TextEditingController();
  rust_ra2b.RsRa2bParsedInvite? _parsed;
  String? _parseError;
  String? _error;
  String? _cameraMessage;
  bool _busy = false;
  CrossFile? _ra4File;
  String? _ra4Sha256;
  bool _ra4Receiver = false;
  bool _ra4Hashing = false;
  String? _incomingName;
  int? _incomingSize;

  String get _localRelayId => widget.localRelayId;

  bool _sessionIsActive() {
    if (!widget.bindNative) {
      return false;
    }
    try {
      return rust_ra2b.ra2BSessionIsActive();
    } catch (_) {
      return false;
    }
  }

  void _cancelNativeSession() {
    if (!widget.bindNative) {
      return;
    }
    try {
      rust_ra2b.ra2BCancelSession();
    } catch (error, stack) {
      debugPrint('RA2B cancel failed: $error\n$stack');
    }
  }

  void _clearRa4Native() {
    if (!widget.bindNative) {
      return;
    }
    rust_ra2b.ra4Clear();
  }

  Future<void> _selectRa4File() async {
    if (_busy || _ra4Hashing) {
      return;
    }
    try {
      final CrossFile? file;
      if (defaultTargetPlatform == TargetPlatform.android) {
        final picked = await app_android_channel.pickFilesAndroid();
        file = picked == null || picked.isEmpty ? null : await CrossFileConverters.convertFileInfo(picked.first);
      } else {
        final picked = await openFile();
        file = picked == null ? null : await CrossFileConverters.convertXFile(picked);
      }
      if (file == null) {
        return;
      }
      setState(() {
        _ra4Hashing = true;
        _error = null;
      });
      final hash = await _hashRa4File(file);
      if (!mounted) {
        return;
      }
      setState(() {
        _ra4File = file;
        _ra4Sha256 = hash;
        _ra4Hashing = false;
      });
    } catch (error, stack) {
      debugPrint('RA4A file selection failed: $error\n$stack');
      if (mounted) {
        setState(() {
          _ra4Hashing = false;
          _error = 'Could not select or hash the file.';
        });
      }
    }
  }

  Future<String?> _hashRa4File(CrossFile file) async {
    String? path = file.path;
    int? fileDescriptor;
    if (path != null && path.startsWith('content://')) {
      fileDescriptor = await isolate_android_channel.getFileDescriptorAndroid(uri: path);
      path = null;
    }
    final cancelToken = rust_cancel.createCancellationToken();
    String? hash;
    await for (final event in rust_crypto.hashFile(path: path, fileDescriptor: fileDescriptor, cancelToken: cancelToken)) {
      event.map(
        progress: (_) {},
        done: (value) => hash = value.hash,
      );
    }
    return hash;
  }

  Future<void> _configureRa4Sender() async {
    final file = _ra4File;
    if (file == null) {
      throw StateError('Select one file first');
    }
    String? path = file.path;
    int? fileDescriptor;
    if (path != null && path.startsWith('content://')) {
      fileDescriptor = await isolate_android_channel.getFileDescriptorAndroid(uri: path);
      path = null;
    }
    rust_ra2b.ra4SetSender(
      path: path,
      fileDescriptor: fileDescriptor,
      name: file.name,
      size: BigInt.from(file.size),
      fileType: lookupMimeType(file.name) ?? 'application/octet-stream',
      sha256: _ra4Sha256,
    );
  }

  void _openRa4Host() {
    if (widget.bindNative) {
      rust_ra2b.ra4SetReceiver();
    }
    setState(() {
      _ra4Receiver = true;
      _screen = Ra2bScreen.host;
      _parsed = null;
      _error = null;
      _session = Ra2bSessionSnapshot(stage: Ra2bUiStage.idle, headline: 'RECEIVE FILE', localRelayId: _localRelayId);
    });
  }

  void _openRa4Join() {
    setState(() {
      _ra4Receiver = false;
      _screen = Ra2bScreen.join;
      _parsed = null;
      _parseError = null;
      _cameraMessage = null;
      _session = const Ra2bSessionSnapshot(stage: Ra2bUiStage.idle, headline: 'SEND FILE');
    });
  }

  Future<void> _respondIncoming({required bool accept}) async {
    if (!accept) {
      rust_ra2b.ra4Respond(accept: false);
      return;
    }
    final name = _incomingName;
    final size = _incomingSize;
    if (name == null || size == null) {
      rust_ra2b.ra4Respond(accept: false);
      return;
    }
    try {
      final destination = await getDefaultDestinationDirectory();
      final cache = await getCacheDirectory();
      final target = await prepareFileSaveTarget(
        destinationDirectory: destination,
        cacheDirectory: cache,
        fileName: name,
        saveToGallery: false,
        isImage: false,
        createdDirectories: <String>{},
      );
      if (target.path == null) {
        rust_ra2b.ra4Respond(accept: false);
        return;
      }
      rust_ra2b.ra4Respond(accept: true, targetPath: target.path);
    } catch (error, stack) {
      debugPrint('RA4A save target preparation failed: $error\n$stack');
      rust_ra2b.ra4Respond(accept: false);
    }
  }

  Future<void> _stop({bool popToHome = false}) async {
    _cancelNativeSession();
    _clearRa4Native();
    await _events?.cancel();
    _events = null;
    if (!mounted) {
      return;
    }
    if (_ra4Receiver) {
      rust_ra2b.ra4SetReceiver();
    }
    setState(() {
      _busy = false;
      if (popToHome) {
        _screen = Ra2bScreen.home;
        _session = const Ra2bSessionSnapshot(stage: Ra2bUiStage.idle);
        _parsed = null;
        _parseError = null;
        _ra4Receiver = false;
        _incomingName = null;
        _incomingSize = null;
      }
    });
  }

  Future<void> _listen(Stream<rust_ra2b.RsRa2bEvent> stream) async {
    await _events?.cancel();
    _events = stream.listen(
      (event) {
        debugPrint('RA2B ${ra2bDiagFromEvent(event)}');
        if (!mounted) {
          return;
        }
        setState(() {
          _session = snapshotFromEvent(event, _session);
          if (_session.stage == Ra2bUiStage.incomingPrompt) {
            final separator = _session.detail.lastIndexOf(' · ');
            if (separator > 0) {
              _incomingName = _session.detail.substring(0, separator);
              _incomingSize = int.tryParse(_session.detail.substring(separator + 3).replaceFirst(' bytes', ''));
            }
          }
          if (_session.stage == Ra2bUiStage.complete ||
              _session.stage == Ra2bUiStage.rejected ||
              _session.stage == Ra2bUiStage.failed ||
              _session.stage == Ra2bUiStage.cancelled) {
            _busy = false;
          }
        });
      },
      onError: (Object error) {
        if (!mounted) {
          return;
        }
        setState(() {
          _busy = false;
          _error = error.toString();
          _session = Ra2bSessionSnapshot(
            stage: Ra2bUiStage.failed,
            headline: 'FAILED',
            detail: error.toString(),
            invite: _session.invite,
            localRelayId: _session.localRelayId,
            remoteRelayId: _session.remoteRelayId,
          );
        });
      },
      onDone: () {
        if (mounted) {
          setState(() => _busy = false);
        }
      },
    );
  }

  Future<void> _startHost({required bool wrongIdentity}) async {
    if (_busy || _sessionIsActive()) {
      setState(() => _error = 'A proof session is already active');
      return;
    }
    if (!widget.bindNative) {
      setState(() {
        _screen = Ra2bScreen.host;
        _session = Ra2bSessionSnapshot(
          stage: Ra2bUiStage.idle,
          headline: 'HOST READY',
          localRelayId: _localRelayId,
        );
      });
      return;
    }
    if (_ra4Receiver) {
      rust_ra2b.ra4SetReceiver();
    }
    setState(() {
      _screen = Ra2bScreen.host;
      _busy = true;
      _error = null;
      _session = Ra2bSessionSnapshot(
        stage: Ra2bUiStage.startingHost,
        headline: 'STARTING HOST',
        localRelayId: _localRelayId,
      );
    });
    try {
      await _listen(
        rust_ra2b.ra2BStartHost(
          pathPreference: _path,
          wrongIdentity: wrongIdentity,
        ),
      );
    } catch (error, stack) {
      debugPrint('RA2B startHost failed: $error\n$stack');
      setState(() {
        _busy = false;
        _error = error.toString();
        _session = Ra2bSessionSnapshot(
          stage: Ra2bUiStage.failed,
          headline: 'FAILED',
          detail: error.toString(),
          localRelayId: _localRelayId,
        );
      });
    }
  }

  void _openHost() {
    _clearRa4Native();
    setState(() {
      _screen = Ra2bScreen.host;
      _parsed = null;
      _parseError = null;
      _error = null;
      _session = Ra2bSessionSnapshot(
        stage: Ra2bUiStage.idle,
        headline: 'HOST READY',
        localRelayId: _localRelayId,
      );
    });
  }

  void _openJoin() {
    _clearRa4Native();
    setState(() {
      _screen = Ra2bScreen.join;
      _parsed = null;
      _parseError = null;
      _cameraMessage = null;
      _session = const Ra2bSessionSnapshot(stage: Ra2bUiStage.idle, headline: '');
    });
  }

  rust_ra2b.RsRa2bParsedInvite _parseInviteText(String raw) {
    if (widget.inviteParser != null) {
      return widget.inviteParser!(raw);
    }
    return rust_ra2b.ra2BParseInvite(invite: raw);
  }

  void _parseInviteField({bool fromScan = false}) {
    final raw = _inviteController.text;
    final shapeError = ra2bInviteShapeError(raw);
    if (shapeError != null) {
      setState(() {
        _parsed = null;
        _parseError = shapeError;
        _session = Ra2bSessionSnapshot(
          stage: Ra2bUiStage.failed,
          headline: 'INVITE REJECTED',
          detail: shapeError,
        );
      });
      return;
    }
    if (!widget.bindNative && widget.inviteParser == null) {
      setState(() {
        _parseError = fromScan ? 'Invite parser unavailable' : null;
        _session = const Ra2bSessionSnapshot(stage: Ra2bUiStage.idle, headline: '');
      });
      return;
    }
    try {
      final parsed = _parseInviteText(raw);
      setState(() {
        _parsed = parsed;
        _parseError = null;
        _session = Ra2bSessionSnapshot(
          stage: Ra2bUiStage.idle,
          headline: fromScan ? 'INVITE SCANNED' : '',
          remoteRelayId: parsed.hostRelayId,
        );
      });
    } catch (error, stack) {
      debugPrint('RA2B parseInvite failed: $error\n$stack');
      setState(() {
        _parsed = null;
        _parseError = error.toString();
        _session = Ra2bSessionSnapshot(
          stage: Ra2bUiStage.failed,
          headline: 'INVITE REJECTED',
          detail: error.toString(),
        );
      });
    }
  }

  /// Android-only Join scanner. Not gated on kDebugMode; required in RA2B release.
  bool get _showScanQr => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<void> _scanQr() async {
    ra2bScannerLog('CAMERA_PERMISSION_REQUEST');
    setState(() => _cameraMessage = null);
    try {
      final request = widget.requestCamera ?? Permission.camera.request;
      final status = await request();
      if (!status.isGranted) {
        ra2bScannerLog('CAMERA_PERMISSION_DENIED');
        setState(() => _cameraMessage = 'Camera permission is required to scan an invite.');
        return;
      }
      ra2bScannerLog('CAMERA_PERMISSION_GRANTED');
      if (!mounted) {
        return;
      }
      final scan =
          widget.scanInvite ??
          (context) {
            return Navigator.of(context).push<String>(
              MaterialPageRoute(
                builder: (_) => Ra2bQrScannerPage(requestCamera: widget.requestCamera),
              ),
            );
          };
      final raw = await scan(context);
      if (!mounted || raw == null || raw.trim().isEmpty) {
        return;
      }
      _inviteController.text = raw.trim();
      _parseInviteField(fromScan: true);
    } catch (error, stack) {
      ra2bScannerLog('SCANNER_ERROR=init');
      debugPrint('RA2B scan QR failed: $error\n$stack');
      if (!mounted) {
        return;
      }
      setState(() => _cameraMessage = 'Camera permission is required to scan an invite.');
    }
  }

  Future<void> _startJoin({required bool wrongIdentity}) async {
    if (_parsed == null) {
      _parseInviteField();
    }
    final invite = _inviteController.text;
    if (_parsed == null && widget.bindNative) {
      return;
    }
    if (_busy || _sessionIsActive()) {
      setState(() => _error = 'A proof session is already active');
      return;
    }
    if (!widget.bindNative) {
      setState(() {
        _session = Ra2bSessionSnapshot(
          stage: Ra2bUiStage.idle,
          headline: 'JOIN READY',
          localRelayId: _localRelayId,
        );
      });
      return;
    }
    if (_ra4File != null) {
      try {
        await _configureRa4Sender();
      } catch (error, stack) {
        debugPrint('RA4A sender configuration failed: $error\n$stack');
        if (mounted) {
          setState(() => _error = 'Could not prepare the selected file.');
        }
        return;
      }
    }
    setState(() {
      _busy = true;
      _error = null;
      _session = Ra2bSessionSnapshot(
        stage: Ra2bUiStage.connecting,
        headline: 'CONNECTING',
        remoteRelayId: _parsed?.hostRelayId,
        localRelayId: _localRelayId,
      );
    });
    try {
      await _listen(
        rust_ra2b.ra2BRunJoin(
          invite: invite,
          pathPreference: _path,
          wrongIdentity: wrongIdentity,
        ),
      );
    } catch (error, stack) {
      debugPrint('RA2B runJoin failed: $error\n$stack');
      setState(() {
        _busy = false;
        _error = error.toString();
        _session = Ra2bSessionSnapshot(
          stage: Ra2bUiStage.failed,
          headline: 'FAILED',
          detail: error.toString(),
          remoteRelayId: _parsed?.hostRelayId,
          localRelayId: _localRelayId,
        );
      });
    }
  }

  Future<void> _pasteInvite() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.trim().isEmpty) {
      setState(() => _parseError = 'Clipboard is empty');
      return;
    }
    _inviteController.text = text.trim();
    _parseInviteField();
  }

  Future<void> _copyInvite(String invite) async {
    await Clipboard.setData(ClipboardData(text: invite));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invite copied')));
  }

  @override
  void dispose() {
    _cancelNativeSession();
    _clearRa4Native();
    unawaited(_events?.cancel());
    _inviteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = RelayPalette.dark;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              child: switch (_screen) {
                Ra2bScreen.home => _home(palette),
                Ra2bScreen.host => _host(palette),
                Ra2bScreen.join => _join(palette),
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _home(RelayPalette palette) {
    return ListView(
      children: [
        _header(palette, showBack: false),
        const SizedBox(height: 28),
        _ra4Panel(palette),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: _busy ? null : _openHost,
          child: const Padding(
            padding: EdgeInsets.symmetric(vertical: 14),
            child: Text('Host'),
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: _busy ? null : _openJoin,
          child: const Padding(
            padding: EdgeInsets.symmetric(vertical: 14),
            child: Text('Join'),
          ),
        ),
        const SizedBox(height: 28),
        _pathPicker(palette),
        const SizedBox(height: 20),
        _diagnostics(palette),
      ],
    );
  }

  Widget _ra4Panel(RelayPalette palette) {
    final file = _ra4File;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.elevated,
        borderRadius: BorderRadius.circular(RelayComponentTokens.groupedRadius),
        border: Border.all(color: palette.accent.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('RA4A · ONE FILE', style: RelayTypography.section(palette.accent)),
          const SizedBox(height: 6),
          Text('Production HTTP transfer over the authenticated Anywhere stream.', style: RelayTypography.legal(palette.textTertiary)),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _busy || _ra4Hashing ? null : () => unawaited(_selectRa4File()),
            icon: _ra4Hashing
                ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.attach_file),
            label: Text(_ra4Hashing ? 'Hashing…' : 'Select File'),
          ),
          if (file != null) ...[
            const SizedBox(height: 10),
            _kv(palette, 'Filename', file.name),
            _kv(palette, 'Size', '${file.size} bytes'),
            _kv(palette, 'SHA-256', _ra4Sha256 == null ? '…' : '${_ra4Sha256!.substring(0, 12)}…'),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: _busy ? null : _openRa4Join,
                    child: const Text('Send File'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _busy ? null : _openRa4Host,
                    child: const Text('Receive File'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _host(RelayPalette palette) {
    final invite = _session.invite;
    return ListView(
      children: [
        _header(palette, showBack: true),
        const SizedBox(height: 16),
        _statusCard(palette),
        if (_session.stage == Ra2bUiStage.incomingPrompt) ...[
          const SizedBox(height: 12),
          _incomingPromptCard(palette),
        ],
        if (invite != null) ...[
          const SizedBox(height: 16),
          _invitePanel(palette, invite),
        ],
        const SizedBox(height: 16),
        if (!_busy && !_session.canStop)
          FilledButton(
            onPressed: () => unawaited(_startHost(wrongIdentity: false)),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(_ra4Receiver ? 'Start Receive' : 'Start Host'),
            ),
          ),
        if (_session.canStop || _busy)
          OutlinedButton(
            onPressed: () => unawaited(_stop()),
            child: const Text('Stop host'),
          ),
        const SizedBox(height: 12),
        _pathPicker(palette),
        const SizedBox(height: 12),
        _securityTest(
          palette,
          enabled: !_busy,
          onPressed: () {
            unawaited(() async {
              await _stop();
              await _startHost(wrongIdentity: true);
            }());
          },
          label: 'Host will reject the next authenticated client RelayId',
        ),
        if (_session.stage == Ra2bUiStage.complete) ...[
          const SizedBox(height: 16),
          _hostResult(palette),
        ],
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: RelayTypography.value(palette.error)),
        ],
      ],
    );
  }

  Widget _join(RelayPalette palette) {
    final parsed = _parsed;
    return ListView(
      children: [
        _header(palette, showBack: true),
        const SizedBox(height: 16),
        Text('Paste Relay Anywhere development invite', style: RelayTypography.row(palette.textPrimary)),
        const SizedBox(height: 8),
        TextField(
          controller: _inviteController,
          minLines: 3,
          maxLines: 8,
          style: RelayTypography.value(palette.textPrimary),
          decoration: InputDecoration(
            hintText: 'RA2B1.…',
            border: const OutlineInputBorder(),
            filled: true,
            fillColor: palette.elevated,
          ),
          onChanged: (_) {
            if (_parsed != null || _parseError != null) {
              setState(() {
                _parsed = null;
                _parseError = null;
              });
            }
          },
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (_showScanQr) FilledButton(onPressed: _busy ? null : () => unawaited(_scanQr()), child: const Text('Scan QR')),
            OutlinedButton(onPressed: _busy ? null : _pasteInvite, child: const Text('Paste Invite')),
            FilledButton.tonal(onPressed: _busy ? null : _parseInviteField, child: const Text('Parse')),
          ],
        ),
        if (_cameraMessage != null) ...[
          const SizedBox(height: 8),
          Text(_cameraMessage!, style: RelayTypography.value(palette.warning)),
        ],
        if (_parseError != null) ...[
          const SizedBox(height: 8),
          Text(_parseError!, style: RelayTypography.value(palette.error)),
        ],
        if (parsed != null) ...[
          const SizedBox(height: 16),
          _kv(palette, 'Remote RelayId', parsed.hostRelayId),
          _kv(palette, 'Routing endpoint', parsed.routingAvailable ? 'Available' : 'Unavailable'),
        ],
        const SizedBox(height: 12),
        Text('Mode', style: RelayTypography.section(palette.textSecondary)),
        const SizedBox(height: 8),
        _pathPicker(palette),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _busy ? null : () => unawaited(_startJoin(wrongIdentity: false)),
          child: const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('Connect & Run Proof'),
          ),
        ),
        const SizedBox(height: 16),
        _statusCard(palette),
        if (_session.stage == Ra2bUiStage.complete) ...[
          const SizedBox(height: 16),
          _joinResult(palette),
        ],
        const SizedBox(height: 12),
        _securityTest(
          palette,
          enabled: parsed != null && !_busy,
          onPressed: () => unawaited(_startJoin(wrongIdentity: true)),
          label: 'Connect using a deliberately wrong expected host RelayId',
        ),
        if (_session.canStop)
          OutlinedButton(
            onPressed: () => unawaited(_stop()),
            child: const Text('Cancel'),
          ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: RelayTypography.value(palette.error)),
        ],
      ],
    );
  }

  Widget _header(RelayPalette palette, {required bool showBack}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (showBack)
              IconButton(
                onPressed: () => unawaited(_stop(popToHome: true)),
                icon: const Icon(Icons.arrow_back),
              ),
            const RelaySymbol(size: 28),
            const SizedBox(width: 10),
            Text('RELAY ANYWHERE', style: RelayTypography.wordmark(palette.textPrimary)),
          ],
        ),
        const SizedBox(height: 6),
        Text(ra2bReleaseBanner, style: RelayTypography.legal(palette.accent)),
        const SizedBox(height: 4),
        Text('$ra2bReleaseSubtitle · $ra2bBuildId', style: RelayTypography.legal(palette.textTertiary)),
        const SizedBox(height: 6),
        Text('Development Proof', style: RelayTypography.section(palette.textSecondary)),
      ],
    );
  }

  Widget _diagnostics(RelayPalette palette) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.elevated,
        borderRadius: BorderRadius.circular(RelayComponentTokens.groupedRadius),
        border: Border.all(color: palette.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('LOCAL IDENTITY', style: RelayTypography.section(palette.textSecondary)),
          const SizedBox(height: 8),
          _kv(palette, 'Build', '$ra2bReleaseBanner · $ra2bBuildId'),
          _kv(palette, 'RelayId', _localRelayId),
          _kv(palette, 'Prefix', relayIdPrefix(_localRelayId)),
          _kv(palette, 'Session', _sessionIsActive() || _busy ? 'active' : 'idle'),
          const SizedBox(height: 10),
          Text(
            'RA2B invite is a test addressing package, not production trust. '
            'Relay-path proofs do not yet verify deployment-time relay-server TLS.',
            style: RelayTypography.legal(palette.textTertiary),
          ),
        ],
      ),
    );
  }

  Widget _pathPicker(RelayPalette palette) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('PATH', style: RelayTypography.section(palette.textSecondary)),
        SegmentedButton<rust_ra2b.RsRa2bPathPreference>(
          segments: const [
            ButtonSegment(value: rust_ra2b.RsRa2bPathPreference.auto, label: Text('Auto')),
            ButtonSegment(value: rust_ra2b.RsRa2bPathPreference.forceRelay, label: Text('Force Relay')),
          ],
          selected: {_path},
          onSelectionChanged: _busy
              ? null
              : (value) {
                  if (value.isNotEmpty) {
                    setState(() => _path = value.first);
                  }
                },
        ),
      ],
    );
  }

  Widget _statusCard(RelayPalette palette) {
    Color color = palette.accent;
    if (_session.stage == Ra2bUiStage.complete) {
      color = palette.success;
    } else if (_session.stage == Ra2bUiStage.rejected || _session.stage == Ra2bUiStage.failed) {
      color = palette.error;
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.elevated,
        borderRadius: BorderRadius.circular(RelayComponentTokens.groupedRadius),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_session.headline.isEmpty ? 'IDLE' : _session.headline, style: RelayTypography.pageTitle(color)),
          if (_session.detail.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(_session.detail, style: RelayTypography.value(palette.textSecondary)),
          ],
          const SizedBox(height: 8),
          _kv(palette, 'Local RelayId', relayIdPrefix(_session.localRelayId ?? _localRelayId)),
          if (_session.remoteRelayId != null) _kv(palette, 'Remote RelayId', relayIdPrefix(_session.remoteRelayId)),
        ],
      ),
    );
  }

  Widget _inviteQr(RelayPalette palette, String invite) {
    try {
      return ColoredBox(
        color: Colors.white,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: PrettyQrView.data(
            data: invite,
            errorCorrectLevel: QrErrorCorrectLevel.M,
            decoration: const PrettyQrDecoration(
              background: Colors.white,
              quietZone: PrettyQrQuietZone.standard,
              shape: PrettyQrSmoothSymbol(roundFactor: 0, color: Colors.black),
            ),
          ),
        ),
      );
    } catch (_) {
      return Center(
        child: Text(
          'Invite too long for QR. Use Copy Invite.',
          style: RelayTypography.value(palette.textSecondary),
          textAlign: TextAlign.center,
        ),
      );
    }
  }

  Widget _invitePanel(RelayPalette palette, String invite) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.elevated,
        borderRadius: BorderRadius.circular(RelayComponentTokens.groupedRadius),
      ),
      child: Column(
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final maxSide = MediaQuery.sizeOf(context).shortestSide;
              final width = constraints.maxWidth.isFinite ? constraints.maxWidth : maxSide;
              final size = width.clamp(320.0, 480.0);
              return SizedBox(
                width: size,
                height: size,
                child: _inviteQr(palette, invite),
              );
            },
          ),
          const SizedBox(height: 8),
          Text(
            'QR encodes the full RA2B1 invite string.',
            style: RelayTypography.legal(palette.textTertiary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          SelectableText(invite, style: RelayTypography.legal(palette.textSecondary)),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () => unawaited(_copyInvite(invite)),
            icon: const Icon(Icons.copy),
            label: const Text('Copy Invite'),
          ),
        ],
      ),
    );
  }

  Widget _hostResult(RelayPalette palette) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('PROOF COMPLETE', style: RelayTypography.section(palette.success)),
        _kv(palette, 'REMOTE RELAY ID', relayIdPrefix(_session.remoteRelayId)),
        _kv(palette, 'RELAY AUTHENTICATION', 'PASS'),
        _kv(palette, 'PATH', _session.path ?? '…'),
        _kv(palette, 'RECEIVED', '1048576'),
        _kv(palette, 'SHA-256', _session.shaPass == true ? 'PASS' : '…'),
        if (_session.durationMs != null) _kv(palette, 'DURATION', '${_session.durationMs} ms'),
      ],
    );
  }

  Widget _incomingPromptCard(RelayPalette palette) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.elevated,
        borderRadius: BorderRadius.circular(RelayComponentTokens.groupedRadius),
        border: Border.all(color: palette.warning.withValues(alpha: 0.55)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Incoming file', style: RelayTypography.section(palette.warning)),
          const SizedBox(height: 8),
          _kv(palette, 'Filename', _incomingName ?? '…'),
          _kv(palette, 'Size', '${_incomingSize ?? 0} bytes'),
          _kv(palette, 'RelayId', relayIdPrefix(_session.remoteRelayId)),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: () => unawaited(_respondIncoming(accept: true)),
                  child: const Text('Accept'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => unawaited(_respondIncoming(accept: false)),
                  child: const Text('Decline'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _joinResult(RelayPalette palette) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _kv(palette, 'PATH', _session.path ?? '…'),
        _kv(palette, 'SENT', '1048576'),
        _kv(palette, 'SHA-256', _session.shaPass == true ? 'PASS' : '…'),
        _kv(palette, 'REMOTE RESULT', _session.shaPass == true ? 'PASS' : '…'),
        _kv(palette, 'REMOTE RELAY ID', relayIdPrefix(_session.remoteRelayId)),
        if (_session.durationMs != null) _kv(palette, 'DURATION', '${_session.durationMs} ms'),
      ],
    );
  }

  Widget _securityTest(
    RelayPalette palette, {
    required bool enabled,
    required VoidCallback onPressed,
    required String label,
  }) {
    return ExpansionTile(
      title: Text('Security test', style: RelayTypography.row(palette.textPrimary)),
      subtitle: Text('Development-only identity mismatch', style: RelayTypography.legal(palette.textTertiary)),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Text(label, style: RelayTypography.value(palette.textSecondary)),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: enabled ? onPressed : null,
          child: const Text('Run wrong-identity check'),
        ),
      ],
    );
  }

  Widget _kv(RelayPalette palette, String key, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(key, style: RelayTypography.section(palette.textTertiary)),
          ),
          Expanded(
            child: SelectableText(value, style: RelayTypography.value(palette.textPrimary)),
          ),
        ],
      ),
    );
  }
}
