import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:relay_app/config/relay_brand.dart';
import 'package:relay_app/model/ui/relay_capability_vm.dart';
import 'package:relay_app/model/ui/relay_device_vm.dart';
import 'package:relay_app/pages/relay_home_vm.dart';
import 'package:relay_app/widget/relay_motion/relay_device_node.dart';
import 'package:relay_app/widget/relay_motion/relay_motion_controller.dart';
import 'package:relay_app/widget/relay_motion/relay_transfer_stream.dart';
import 'package:relay_isolates/model/device.dart';

/// Background guide painter for the Relay Spatial Scene.
class RelaySpatialUniversePainter extends CustomPainter {
  final Color primaryGuideColor;
  final Color secondaryGuideColor;
  final Color centerGlowColor;
  final double ambientPhase;

  const RelaySpatialUniversePainter({
    required this.primaryGuideColor,
    required this.secondaryGuideColor,
    required this.centerGlowColor,
    required this.ambientPhase,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = math.min(size.width, size.height) / 2;

    // Quiet focal wash: the background stays still while events animate.
    final glowRadius = (maxRadius * 0.75).clamp(80.0, 260.0);
    final glowPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          centerGlowColor.withValues(alpha: 0.07),
          centerGlowColor.withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: glowRadius));
    canvas.drawOval(
      Rect.fromCenter(center: center, width: glowRadius * 2, height: glowRadius * 2 * 0.76),
      glowPaint,
    );

    final guidePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    // Inner orbit ring (Primary / Authenticated devices)
    guidePaint.color = primaryGuideColor.withValues(alpha: 0.12);
    final innerRadius = (maxRadius * RelaySpatialLayoutEngine.baseInnerRadiusRatio).clamp(115.0, 240.0);
    _drawDashedEllipse(canvas, center, innerRadius, innerRadius * 0.76, guidePaint, dashLength: 4, spaceLength: 4);

    // Outer orbit ring (Secondary / LocalSend compatibility devices)
    guidePaint.color = secondaryGuideColor.withValues(alpha: 0.07);
    final outerRadius = (maxRadius * RelaySpatialLayoutEngine.baseOuterRadiusRatio).clamp(170.0, 360.0);
    _drawDashedEllipse(canvas, center, outerRadius, outerRadius * 0.76, guidePaint, dashLength: 3, spaceLength: 6);
  }

  void _drawDashedEllipse(
    Canvas canvas,
    Offset center,
    double rx,
    double ry,
    Paint paint, {
    required double dashLength,
    required double spaceLength,
  }) {
    // Ramanujan approximation for ellipse perimeter
    final h = math.pow(rx - ry, 2) / math.pow(rx + ry, 2);
    final perimeter = math.pi * (rx + ry) * (1 + (3 * h) / (10 + math.sqrt(4 - 3 * h)));
    final count = math.max(12, (perimeter / (dashLength + spaceLength)).floor());
    final angleStep = (2 * math.pi) / count;
    final dashAngle = (dashLength / perimeter) * 2 * math.pi;

    for (int i = 0; i < count; i++) {
      final startAngle = i * angleStep;
      canvas.drawArc(
        Rect.fromCenter(center: center, width: rx * 2, height: ry * 2),
        startAngle,
        dashAngle,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant RelaySpatialUniversePainter oldDelegate) {
    return oldDelegate.primaryGuideColor != primaryGuideColor ||
        oldDelegate.secondaryGuideColor != secondaryGuideColor ||
        oldDelegate.centerGlowColor != centerGlowColor ||
        oldDelegate.ambientPhase != ambientPhase;
  }
}

/// The core spatial device experience scene.
///
/// Places this desktop at the centre of a calm, relationship-oriented device scene.
/// Resting devices stay still; motion is reserved for focus and real events.
class RelaySpatialScene extends StatefulWidget {
  final String selfAlias;
  final DeviceType selfDeviceType;
  final RelayPresence presence;
  final List<RelayDeviceVm> devices;
  final RelayTransferVm? activeTransfer;
  final String? selectedDeviceKey;
  final ValueChanged<RelayDeviceVm?>? onDeviceSelected;
  final ValueChanged<RelayDeviceVm>? onSendFiles;
  final ValueChanged<RelayDeviceVm>? onOpenDetails;
  final VoidCallback? onCancelTransfer;
  final bool animationsEnabled;
  final double? height;

  const RelaySpatialScene({
    super.key,
    required this.selfAlias,
    required this.selfDeviceType,
    required this.presence,
    required this.devices,
    this.activeTransfer,
    this.selectedDeviceKey,
    this.onDeviceSelected,
    this.onSendFiles,
    this.onOpenDetails,
    this.onCancelTransfer,
    this.animationsEnabled = true,
    this.height,
  });

  @override
  State<RelaySpatialScene> createState() => _RelaySpatialSceneState();
}

class _RelaySpatialSceneState extends State<RelaySpatialScene> with TickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _ambientController;
  late final AnimationController _focusController;
  late final AnimationController _epilogueController;
  late Animation<double> _focusCurve;

  String? _internalFocusedKey;
  RelayTransferVm? _epilogueTransfer;
  RelayDevicePhase? _epiloguePhase;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _internalFocusedKey = widget.selectedDeviceKey;

    _ambientController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 120),
    );

    _focusController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    _epilogueController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 750),
    );

    _epilogueController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        setState(() {
          _epilogueTransfer = null;
          _epiloguePhase = null;
        });
      }
    });

    _focusCurve = CurvedAnimation(
      parent: _focusController,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );

    if (_internalFocusedKey != null) {
      _focusController.value = 1.0;
    }

    // Check if initial active transfer is already in terminal state
    if (widget.activeTransfer != null &&
        (widget.activeTransfer!.phase == RelayDevicePhase.success ||
            widget.activeTransfer!.phase == RelayDevicePhase.failed ||
            widget.activeTransfer!.phase == RelayDevicePhase.cancelled)) {
      _startEpilogue(widget.activeTransfer!, widget.activeTransfer!.phase);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // No ambient animation survives lifecycle changes: Relay does not animate
    // unless a real event or a user action requires it.
  }

  @override
  void didUpdateWidget(covariant RelaySpatialScene oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.animationsEnabled != oldWidget.animationsEnabled) {
      if (!widget.animationsEnabled) {
        _ambientController.stop();
        _epilogueController.stop();
        _epilogueTransfer = null;
        _epiloguePhase = null;
      }
    }

    if (widget.selectedDeviceKey != oldWidget.selectedDeviceKey) {
      _internalFocusedKey = widget.selectedDeviceKey;
      if (_internalFocusedKey != null) {
        if (widget.animationsEnabled) {
          unawaited(_focusController.forward());
        } else {
          _focusController.value = 1.0;
        }
      } else {
        if (widget.animationsEnabled) {
          unawaited(_focusController.reverse());
        } else {
          _focusController.value = 0.0;
        }
      }
    }

    // Handle Transfer Terminal Transitions & Visual Epilogue Memory
    final oldTransfer = oldWidget.activeTransfer;
    final newTransfer = widget.activeTransfer;

    if (newTransfer != null &&
        (newTransfer.phase == RelayDevicePhase.success ||
            newTransfer.phase == RelayDevicePhase.failed ||
            newTransfer.phase == RelayDevicePhase.cancelled)) {
      if (_epilogueTransfer?.sessionId != newTransfer.sessionId || _epiloguePhase != newTransfer.phase) {
        _startEpilogue(newTransfer, newTransfer.phase);
      }
    } else if (oldTransfer != null && newTransfer == null) {
      // Backend removed completed/terminal transfer: retain visual epilogue
      if (_epilogueTransfer == null) {
        if (oldTransfer.phase == RelayDevicePhase.sending && (oldTransfer.progress ?? 0.0) >= 0.90) {
          _startEpilogue(oldTransfer, RelayDevicePhase.success);
        } else if (oldTransfer.phase == RelayDevicePhase.failed ||
            oldTransfer.phase == RelayDevicePhase.cancelled ||
            oldTransfer.phase == RelayDevicePhase.success) {
          _startEpilogue(oldTransfer, oldTransfer.phase);
        } else {
          _startEpilogue(oldTransfer, RelayDevicePhase.cancelled);
        }
      }
    } else if (newTransfer != null && _epilogueTransfer != null && _epilogueTransfer!.sessionId != newTransfer.sessionId) {
      _epilogueController.stop();
      _epilogueTransfer = null;
      _epiloguePhase = null;
    }
  }

  void _startEpilogue(RelayTransferVm transfer, RelayDevicePhase phase) {
    if (!widget.animationsEnabled) {
      _epilogueTransfer = null;
      _epiloguePhase = null;
      return;
    }
    _epilogueTransfer = transfer;
    _epiloguePhase = phase;
    final duration = switch (phase) {
      RelayDevicePhase.success => const Duration(milliseconds: 800),
      RelayDevicePhase.failed => const Duration(milliseconds: 600),
      RelayDevicePhase.cancelled => const Duration(milliseconds: 500),
      _ => const Duration(milliseconds: 600),
    };
    _epilogueController.duration = duration;
    unawaited(_epilogueController.forward(from: 0.0));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ambientController.dispose();
    _focusController.dispose();
    _epilogueController.dispose();
    super.dispose();
  }

  void _handleDeviceTap(RelayDeviceVm device) {
    if (_internalFocusedKey == device.key) {
      // Toggle off / unfocus
      setState(() => _internalFocusedKey = null);
      if (widget.animationsEnabled) {
        unawaited(_focusController.reverse());
      } else {
        _focusController.value = 0.0;
      }
      widget.onDeviceSelected?.call(null);
    } else {
      // Focus this device
      setState(() => _internalFocusedKey = device.key);
      if (widget.animationsEnabled) {
        unawaited(_focusController.forward(from: 0.0));
      } else {
        _focusController.value = 1.0;
      }
      widget.onDeviceSelected?.call(device);
    }
  }

  void _handleCanvasTap() {
    if (_internalFocusedKey != null) {
      setState(() => _internalFocusedKey = null);
      if (widget.animationsEnabled) {
        unawaited(_focusController.reverse());
      } else {
        _focusController.value = 0.0;
      }
      widget.onDeviceSelected?.call(null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).relayPalette;
    final bool reducedMotion = !widget.animationsEnabled || MediaQuery.disableAnimationsOf(context);

    final primaryDevices = widget.devices.where((d) => d.isAuthenticatedRelay).toList();
    final compatibilityDevices = widget.devices.where((d) => d.isCompatibilityPeer).toList();

    // Identify active transfer device (either canonical active transfer or transient epilogue)
    final effectiveTransfer = widget.activeTransfer ?? _epilogueTransfer;
    final isEpilogue = widget.activeTransfer == null && _epilogueTransfer != null;
    final epilogueProgress = (isEpilogue || _epilogueController.isAnimating) ? _epilogueController.value : null;

    RelayDeviceVm? transferringDevice;
    if (effectiveTransfer != null) {
      transferringDevice = widget.devices.where((d) {
        return (effectiveTransfer.deviceKey != null && d.key == effectiveTransfer.deviceKey) ||
            d.alias.toLowerCase() == effectiveTransfer.targetAlias.toLowerCase() ||
            d.phase == RelayDevicePhase.sending ||
            d.phase == RelayDevicePhase.verifying ||
            d.phase == RelayDevicePhase.success ||
            d.phase == RelayDevicePhase.failed ||
            d.phase == RelayDevicePhase.cancelled;
      }).firstOrNull;
    }

    final focusedDevice = transferringDevice ?? widget.devices.where((d) => d.key == _internalFocusedKey).firstOrNull;

    Widget buildCanvas(Size sceneSize) {
      return GestureDetector(
        onTap: _handleCanvasTap,
        behavior: HitTestBehavior.opaque,
        child: ClipRect(
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // Universe Guides & Orbital Tracks
              RepaintBoundary(
                child: AnimatedBuilder(
                  animation: _ambientController,
                  builder: (context, child) {
                    return CustomPaint(
                      size: sceneSize,
                      painter: RelaySpatialUniversePainter(
                        primaryGuideColor: palette.accent,
                        secondaryGuideColor: palette.textTertiary,
                        centerGlowColor: palette.accent,
                        ambientPhase: 0.0,
                      ),
                    );
                  },
                ),
              ),

              // Layered Device Universe with Depth Z-Ordering and Transfer Stream
              AnimatedBuilder(
                animation: Listenable.merge([_ambientController, _focusController, _epilogueController]),
                builder: (context, child) {
                  final focusVal = reducedMotion ? (_internalFocusedKey != null ? 1.0 : 0.0) : _focusCurve.value;
                  const ambientVal = 0.0;

                  final isTransferActive = transferringDevice != null;
                  final transferProgress = effectiveTransfer?.progress ?? transferringDevice?.progress;
                  final transferPhase = _epiloguePhase ?? effectiveTransfer?.phase ?? transferringDevice?.phase ?? RelayDevicePhase.idle;
                  final transferDir = effectiveTransfer?.direction ?? RelayTransferDirection.send;

                  // Compute Self Node Position
                  final selfPos = RelaySpatialLayoutEngine.computeSelfPosition(
                    sceneSize: sceneSize,
                    focusProgress: focusVal,
                    hasFocusedDevice: focusedDevice != null,
                    ambientPhase: ambientVal,
                    isTransferActive: isTransferActive && !reducedMotion,
                    epilogueProgress: epilogueProgress,
                  );

                  final rearNodes = <Widget>[];
                  final frontNodes = <Widget>[];
                  SpatialNodePosition? activeTransferRemotePos;

                  // Process and position compatibility devices (Outer Ring)
                  for (int i = 0; i < compatibilityDevices.length; i++) {
                    final device = compatibilityDevices[i];
                    final pos = RelaySpatialLayoutEngine.computeRemotePosition(
                      device: device,
                      indexInRing: i,
                      totalInRing: compatibilityDevices.length,
                      sceneSize: sceneSize,
                      ambientPhase: ambientVal,
                      focusedDeviceKey: focusedDevice?.key,
                      focusProgress: focusVal,
                      transferDeviceKey: transferringDevice?.key,
                      transferProgress: transferProgress,
                      transferPhase: transferPhase,
                      epilogueProgress: epilogueProgress,
                    );

                    if (transferringDevice?.key == device.key) {
                      activeTransferRemotePos = pos;
                    }

                    final isThisFocused = focusedDevice?.key == device.key;
                    final isDimmed = (focusedDevice != null && !isThisFocused) || pos.opacity < 0.99;

                    final nodeWidget = Positioned(
                      left: pos.offset.dx - 50,
                      top: pos.offset.dy - 40,
                      child: Transform.scale(
                        scale: pos.scale,
                        child: RelayDeviceNode(
                          alias: device.alias,
                          deviceType: device.deviceType,
                          isSelected: isThisFocused,
                          isDimmed: isDimmed,
                          isVerifiedRelay: false,
                          isCompatibilityPeer: true,
                          continuityConnected: device.continuityConnected,
                          battery: device.battery,
                          detail: device.detail,
                          phase: device.phase,
                          progress: device.progress,
                          ambientPulse: ambientVal,
                          onTap: () => _handleDeviceTap(device),
                        ),
                      ),
                    );

                    if (pos.isBehindCenter) {
                      rearNodes.add(nodeWidget);
                    } else {
                      frontNodes.add(nodeWidget);
                    }
                  }

                  // Process and position primary/authenticated devices (Inner Ring)
                  for (int i = 0; i < primaryDevices.length; i++) {
                    final device = primaryDevices[i];
                    final pos = RelaySpatialLayoutEngine.computeRemotePosition(
                      device: device,
                      indexInRing: i,
                      totalInRing: primaryDevices.length,
                      sceneSize: sceneSize,
                      ambientPhase: ambientVal,
                      focusedDeviceKey: focusedDevice?.key,
                      focusProgress: focusVal,
                      transferDeviceKey: transferringDevice?.key,
                      transferProgress: transferProgress,
                      transferPhase: transferPhase,
                      epilogueProgress: epilogueProgress,
                    );

                    if (transferringDevice?.key == device.key) {
                      activeTransferRemotePos = pos;
                    }

                    final isThisFocused = focusedDevice?.key == device.key;
                    final isDimmed = (focusedDevice != null && !isThisFocused) || pos.opacity < 0.99;

                    final nodeWidget = Positioned(
                      left: pos.offset.dx - 50,
                      top: pos.offset.dy - 40,
                      child: Transform.scale(
                        scale: pos.scale,
                        child: RelayDeviceNode(
                          alias: device.alias,
                          deviceType: device.deviceType,
                          isSelected: isThisFocused,
                          isDimmed: isDimmed,
                          isVerifiedRelay: device.isVerifiedRelay,
                          isCompatibilityPeer: false,
                          continuityConnected: device.continuityConnected,
                          battery: device.battery,
                          detail: device.detail,
                          phase: device.phase,
                          progress: device.progress,
                          ambientPulse: ambientVal,
                          onTap: () => _handleDeviceTap(device),
                        ),
                      ),
                    );

                    if (pos.isBehindCenter) {
                      rearNodes.add(nodeWidget);
                    } else {
                      frontNodes.add(nodeWidget);
                    }
                  }

                  // Center Self Device Node Widget
                  final selfNodeWidget = Positioned(
                    left: selfPos.offset.dx - 50,
                    top: selfPos.offset.dy - 46,
                    child: Transform.scale(
                      scale: selfPos.scale,
                      child: RelayDeviceNode(
                        alias: widget.selfAlias,
                        deviceType: widget.selfDeviceType,
                        isSelf: true,
                        isSelected: false,
                        isDimmed: false,
                        ambientPulse: ambientVal,
                      ),
                    ),
                  );

                  // State-Driven Transfer Stream / Relationship Bridge
                  Widget? streamWidget;
                  if (transferringDevice != null && activeTransferRemotePos != null) {
                    streamWidget = RelayTransferStream(
                      sourceOffset: selfPos.offset,
                      targetOffset: activeTransferRemotePos.offset,
                      direction: transferDir,
                      phase: transferPhase,
                      progress: transferProgress,
                      pulsePhase: epilogueProgress ?? ((ambientVal * 4) % 1.0),
                      isFocusedPair: true,
                      fileCount: effectiveTransfer?.fileCount ?? 1,
                      origin: effectiveTransfer?.origin,
                    );
                  } else if (focusedDevice != null && focusVal > 0.01) {
                    final isPrimary = focusedDevice.isAuthenticatedRelay;
                    final ringList = isPrimary ? primaryDevices : compatibilityDevices;
                    final idx = math.max(0, ringList.indexWhere((d) => d.key == focusedDevice.key));

                    final targetPos = RelaySpatialLayoutEngine.computeRemotePosition(
                      device: focusedDevice,
                      indexInRing: idx,
                      totalInRing: math.max(1, ringList.length),
                      sceneSize: sceneSize,
                      ambientPhase: ambientVal,
                      focusedDeviceKey: focusedDevice.key,
                      focusProgress: focusVal,
                    );

                    streamWidget = RelayTransferStream(
                      sourceOffset: selfPos.offset,
                      targetOffset: targetPos.offset,
                      direction: RelayTransferDirection.send,
                      phase: focusedDevice.phase,
                      progress: focusedDevice.progress,
                      pulsePhase: (ambientVal * 4) % 1.0,
                      isFocusedPair: true,
                      origin: focusedDevice.connectionType.label,
                    );
                  }

                  // Compose Z-Order: Rear Nodes -> Self Node -> Stream -> Front Nodes
                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      ...rearNodes,
                      selfNodeWidget,
                      ?streamWidget,
                      ...frontNodes,
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      );
    }

    if (widget.height != null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: widget.height,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final sceneSize = Size(constraints.maxWidth, widget.height!);
                return buildCanvas(sceneSize);
              },
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            child: focusedDevice != null ? _buildRelationshipPanel(context, palette, focusedDevice, effectiveTransfer) : const SizedBox.shrink(),
          ),
        ],
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableHeight = constraints.maxHeight.isFinite ? constraints.maxHeight : 500.0;
        final sceneSize = Size(constraints.maxWidth, availableHeight);

        return Stack(
          children: [
            Positioned.fill(
              child: buildCanvas(sceneSize),
            ),
            if (focusedDevice != null)
              Positioned(
                left: 0,
                right: 0,
                bottom: 12,
                child: SafeArea(
                  top: false,
                  child: AnimatedSize(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOutCubic,
                    child: _buildRelationshipPanel(context, palette, focusedDevice, effectiveTransfer),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildRelationshipPanel(
    BuildContext context,
    RelayPalette palette,
    RelayDeviceVm device,
    RelayTransferVm? activeTransfer,
  ) {
    final bool isTransferActive =
        activeTransfer != null &&
        (device.phase == RelayDevicePhase.sending ||
            device.phase == RelayDevicePhase.verifying ||
            device.phase == RelayDevicePhase.success ||
            device.phase == RelayDevicePhase.failed ||
            device.phase == RelayDevicePhase.cancelled ||
            activeTransfer.targetAlias.toLowerCase() == device.alias.toLowerCase());

    final statusText = isTransferActive
        ? (activeTransfer.phase == RelayDevicePhase.success
              ? 'Transfer complete'
              : activeTransfer.phase == RelayDevicePhase.failed
              ? 'Transfer failed'
              : activeTransfer.phase == RelayDevicePhase.cancelled
              ? 'Transfer cancelled'
              : activeTransfer.isReceive
              ? 'Receiving from device…'
              : 'Sending to device…')
        : device.statusSummary;

    final showCancel =
        isTransferActive &&
        (activeTransfer.phase == RelayDevicePhase.sending ||
            activeTransfer.phase == RelayDevicePhase.verifying ||
            activeTransfer.phase == RelayDevicePhase.waiting);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.softSurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isTransferActive ? palette.accent.withValues(alpha: 0.45) : palette.accent.withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      device.alias,
                      style: RelayTypography.heading(palette.textPrimary),
                    ),
                    Text(
                      statusText,
                      style: RelayTypography.caption(isTransferActive ? palette.accentSoft : palette.textSecondary),
                    ),
                  ],
                ),
              ),
              if (showCancel)
                FilledButton.tonalIcon(
                  onPressed: widget.onCancelTransfer,
                  icon: const Icon(Icons.close_rounded, size: 16),
                  label: const Text('Cancel'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                )
              else
                FilledButton.icon(
                  onPressed: () => widget.onSendFiles?.call(device),
                  icon: const Icon(Icons.send_rounded, size: 16),
                  label: const Text('Send Files'),
                  style: FilledButton.styleFrom(
                    backgroundColor: palette.accent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              const SizedBox(width: 6),
              IconButton(
                icon: const Icon(Icons.chevron_right_rounded),
                tooltip: 'Device Details',
                onPressed: () => widget.onOpenDetails?.call(device),
              ),
            ],
          ),
          if (isTransferActive && activeTransfer.progress != null) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: activeTransfer.progress,
                minHeight: 4,
                backgroundColor: palette.canvas,
                valueColor: AlwaysStoppedAnimation(activeTransfer.phase == RelayDevicePhase.success ? palette.success : palette.accent),
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  activeTransfer.origin ?? 'Local',
                  style: RelayTypography.caption(palette.textTertiary).copyWith(fontSize: 11),
                ),
                Text(
                  '${(activeTransfer.progress! * 100).toInt()}%',
                  style: RelayTypography.caption(
                    activeTransfer.phase == RelayDevicePhase.success ? palette.success : palette.accentSoft,
                  ).copyWith(fontSize: 11, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ],
          const SizedBox(height: 14),
          // Relationship capability pills
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _capabilityPill(palette, icon: Icons.folder_outlined, label: 'Files', available: true),
                const SizedBox(width: 8),
                _capabilityPill(
                  palette,
                  icon: Icons.content_paste_rounded,
                  label: 'Clipboard',
                  available: device.capabilities[RelayCapability.clipboard] == CapabilityStatus.available,
                ),
                const SizedBox(width: 8),
                _capabilityPill(
                  palette,
                  icon: Icons.sms_outlined,
                  label: 'Messages',
                  available: device.capabilities[RelayCapability.messages] == CapabilityStatus.available,
                ),
                const SizedBox(width: 8),
                _capabilityPill(
                  palette,
                  icon: Icons.notifications_none_rounded,
                  label: 'Notifications',
                  available: device.capabilities[RelayCapability.notifications] == CapabilityStatus.available,
                ),
                const SizedBox(width: 8),
                _capabilityPill(
                  palette,
                  icon: Icons.call_outlined,
                  label: 'Phone',
                  available: device.capabilities[RelayCapability.phone] == CapabilityStatus.available,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _capabilityPill(RelayPalette palette, {required IconData icon, required String label, required bool available}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: available ? palette.elevated : palette.canvas,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: available ? palette.accent.withValues(alpha: 0.3) : palette.hairline,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 14,
            color: available ? palette.accentSoft : palette.textTertiary,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: available ? palette.textPrimary : palette.textTertiary,
              fontSize: 12,
              fontWeight: available ? FontWeight.w500 : FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
}
