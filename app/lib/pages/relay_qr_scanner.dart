import 'dart:async';

import 'package:flutter/material.dart';
import 'package:localsend_app/config/relay_brand.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';

void relayScannerLog(String message) {
  debugPrint('Relay scanner: $message');
}

String relayScannerErrorCategory(Object error) {
  if (error is MobileScannerException) {
    return switch (error.errorCode) {
      MobileScannerErrorCode.permissionDenied => 'permission',
      MobileScannerErrorCode.unsupported => 'unavailable',
      MobileScannerErrorCode.controllerNotAttached => 'not_attached',
      MobileScannerErrorCode.controllerInitializing => 'initializing',
      MobileScannerErrorCode.controllerAlreadyInitialized => 'already_started',
      MobileScannerErrorCode.controllerDisposed => 'disposed',
      MobileScannerErrorCode.controllerUninitialized => 'uninitialized',
      MobileScannerErrorCode.genericError => 'init',
    };
  }
  return 'init';
}

String relayScannerVisibleError(String category) {
  return switch (category) {
    'permission' => 'Camera permission required',
    'unavailable' => 'Camera unavailable',
    _ => 'Scanner initialization failed',
  };
}

/// Reusable camera scanner. Product callers provide a small payload validator;
/// this page does not connect, pair, or create trust on its own.
class RelayQrScannerPage extends StatefulWidget {
  const RelayQrScannerPage({
    super.key,
    this.requestCamera,
    required this.title,
    required this.instruction,
    this.validate,
  });

  final Future<PermissionStatus> Function()? requestCamera;
  final String title;
  final String instruction;
  final String? Function(String raw)? validate;

  @override
  State<RelayQrScannerPage> createState() => _RelayQrScannerPageState();
}

class _RelayQrScannerPageState extends State<RelayQrScannerPage> with WidgetsBindingObserver {
  late final MobileScannerController _controller;
  StreamSubscription<BarcodeCapture>? _barcodes;
  var _handled = false;
  var _disposed = false;
  var _starting = false;
  var _previewReady = false;
  String? _status = 'Starting camera…';
  String? _errorCategory;
  String? _lastRaw;
  String? _reject;

  Future<PermissionStatus> _requestCamera() {
    return (widget.requestCamera ?? Permission.camera.request)();
  }

  @override
  void initState() {
    super.initState();
    relayScannerLog('SCANNER_PAGE_OPEN');
    _controller = MobileScannerController(
      autoStart: false,
      formats: const [BarcodeFormat.qrCode],
    );
    relayScannerLog('SCANNER_CONTROLLER_CREATED');
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_startScanner());
    });
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_stopScanner(disposeController: true));
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_handled || _disposed) {
      return;
    }
    switch (state) {
      case AppLifecycleState.resumed:
        unawaited(_startScanner());
      case AppLifecycleState.inactive:
        unawaited(_stopScanner());
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        return;
    }
  }

  Future<void> _stopScanner({bool disposeController = false}) async {
    relayScannerLog('SCANNER_STOPPED');
    await _barcodes?.cancel();
    _barcodes = null;
    try {
      await _controller.stop();
    } catch (_) {}
    if (disposeController) {
      await _controller.dispose();
    }
  }

  Future<void> _startScanner() async {
    if (!mounted || _disposed || _handled || _starting) {
      return;
    }
    _starting = true;
    setState(() {
      _status = 'Starting camera…';
      _errorCategory = null;
      _previewReady = false;
    });
    try {
      relayScannerLog('CAMERA_PERMISSION_REQUEST');
      final status = await _requestCamera();
      if (!mounted || _disposed || _handled) {
        return;
      }
      if (!status.isGranted) {
        relayScannerLog('CAMERA_PERMISSION_DENIED');
        setState(() {
          _errorCategory = 'permission';
          _status = relayScannerVisibleError('permission');
        });
        return;
      }
      relayScannerLog('CAMERA_PERMISSION_GRANTED');
      _barcodes ??= _controller.barcodes.listen(
        _onDetect,
        onError: (Object error, StackTrace stack) {
          relayScannerLog('SCANNER_ERROR=${relayScannerErrorCategory(error)}');
          debugPrint('$error\n$stack');
        },
      );
      relayScannerLog('SCANNER_START_REQUEST');
      await _controller.start();
      if (!mounted || _disposed || _handled) {
        return;
      }
      relayScannerLog('SCANNER_STARTED');
      setState(() {
        _previewReady = true;
        _status = null;
        _errorCategory = null;
      });
    } catch (error, stack) {
      final category = relayScannerErrorCategory(error);
      relayScannerLog('SCANNER_ERROR=$category');
      debugPrint('Relay scanner start failed: $error\n$stack');
      if (!mounted || _disposed) {
        return;
      }
      if (error is MobileScannerException && error.errorCode == MobileScannerErrorCode.controllerAlreadyInitialized) {
        setState(() {
          _previewReady = true;
          _status = null;
          _errorCategory = null;
        });
        return;
      }
      setState(() {
        _previewReady = false;
        _errorCategory = category;
        _status = relayScannerVisibleError(category);
      });
    } finally {
      _starting = false;
    }
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled || _disposed) {
      return;
    }
    final raw = capture.barcodes
        .map((barcode) => barcode.rawValue)
        .whereType<String>()
        .map((value) => value.trim())
        .firstWhere((value) => value.isNotEmpty, orElse: () => '');
    if (raw.isEmpty || raw == _lastRaw) {
      return;
    }
    relayScannerLog('BARCODE_DETECTED');
    _lastRaw = raw;
    final error = widget.validate?.call(raw);
    if (error != null) {
      final category = error.contains('unrelated')
          ? 'unrelated'
          : error.contains('unsupported')
          ? 'unsupported'
          : error.contains('exceeds')
          ? 'too_long'
          : 'malformed';
      relayScannerLog('QR_REJECTED=$category');
      setState(() => _reject = error);
      return;
    }
    _handled = true;
    relayScannerLog('QR_ACCEPTED');
    unawaited(_accept(raw));
  }

  Future<void> _accept(String raw) async {
    await _stopScanner();
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop(raw);
  }

  @override
  Widget build(BuildContext context) {
    final palette = RelayPalette.dark;
    return Scaffold(
      backgroundColor: palette.canvas,
      appBar: AppBar(
        backgroundColor: palette.canvas,
        title: Text(widget.title),
        automaticallyImplyLeading: false,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                MobileScanner(
                  controller: _controller,
                  useAppLifecycleState: false,
                  placeholderBuilder: (_) => _statusPane(palette, 'Starting camera…'),
                  errorBuilder: (context, error) {
                    final category = relayScannerErrorCategory(error);
                    return _statusPane(palette, relayScannerVisibleError(category), retry: true);
                  },
                ),
                if (_errorCategory != null) _statusPane(palette, _status ?? relayScannerVisibleError(_errorCategory!), retry: true),
                if (_previewReady && _errorCategory == null)
                  IgnorePointer(
                    child: Center(
                      child: Container(
                        width: 240,
                        height: 240,
                        decoration: BoxDecoration(
                          border: Border.all(color: palette.accent, width: 2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (_reject != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(_reject!, style: RelayTypography.value(palette.error), textAlign: TextAlign.center),
            )
          else
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                widget.instruction,
                style: RelayTypography.legal(palette.textSecondary),
                textAlign: TextAlign.center,
              ),
            ),
        ],
      ),
    );
  }

  Widget _statusPane(RelayPalette palette, String message, {bool retry = false}) {
    return ColoredBox(
      color: palette.canvas,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(message, style: RelayTypography.value(palette.textPrimary), textAlign: TextAlign.center),
              if (retry) ...[
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => unawaited(_startScanner()),
                  child: const Text('Retry'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
