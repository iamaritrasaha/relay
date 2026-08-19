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

/// Background universe orbital guides and radial grid painter.
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

    // Faint center gravitational ambient glow
    final glowPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          centerGlowColor.withValues(alpha: 0.08 + 0.03 * math.sin(ambientPhase * 2 * math.pi)),
          centerGlowColor.withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: maxRadius * 0.7));
    canvas.drawCircle(center, maxRadius * 0.7, glowPaint);

    final guidePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    // Inner orbit ring (Primary / Authenticated devices)
    guidePaint.color = primaryGuideColor.withValues(alpha: 0.12);
    final innerRadius = (maxRadius * RelaySpatialLayoutEngine.baseInnerRadiusRatio).clamp(95.0, 140.0);
    _drawDashedCircle(canvas, center, innerRadius, guidePaint, dashLength: 4, spaceLength: 4);

    // Outer orbit ring (Secondary / LocalSend compatibility devices)
    guidePaint.color = secondaryGuideColor.withValues(alpha: 0.07);
    final outerRadius = (maxRadius * RelaySpatialLayoutEngine.baseOuterRadiusRatio).clamp(150.0, 210.0);
    _drawDashedCircle(canvas, center, outerRadius, guidePaint, dashLength: 3, spaceLength: 6);
  }

  void _drawDashedCircle(Canvas canvas, Offset center, double radius, Paint paint, {required double dashLength, required double spaceLength}) {
    final circumference = 2 * math.pi * radius;
    final count = (circumference / (dashLength + spaceLength)).floor();
    final angleStep = (2 * math.pi) / count;
    final dashAngle = (dashLength / circumference) * 2 * math.pi;

    for (int i = 0; i < count; i++) {
      final startAngle = i * angleStep;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
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
/// Places THIS DEVICE at the visual center of a motion universe with remote devices
/// orbiting deterministically around it. Tapping a device smoothly focuses the relationship.
class RelaySpatialScene extends StatefulWidget {
  final String selfAlias;
  final DeviceType selfDeviceType;
  final RelayPresence presence;
  final List<RelayDeviceVm> devices;
  final String? selectedDeviceKey;
  final ValueChanged<RelayDeviceVm?>? onDeviceSelected;
  final ValueChanged<RelayDeviceVm>? onSendFiles;
  final ValueChanged<RelayDeviceVm>? onOpenDetails;
  final bool animationsEnabled;
  final double height;

  const RelaySpatialScene({
    super.key,
    required this.selfAlias,
    required this.selfDeviceType,
    required this.presence,
    required this.devices,
    this.selectedDeviceKey,
    this.onDeviceSelected,
    this.onSendFiles,
    this.onOpenDetails,
    this.animationsEnabled = true,
    this.height = 360,
  });

  @override
  State<RelaySpatialScene> createState() => _RelaySpatialSceneState();
}

class _RelaySpatialSceneState extends State<RelaySpatialScene> with TickerProviderStateMixin {
  late final AnimationController _ambientController;
  late final AnimationController _focusController;
  late Animation<double> _focusCurve;

  String? _internalFocusedKey;

  @override
  void initState() {
    super.initState();
    _internalFocusedKey = widget.selectedDeviceKey;

    _ambientController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 14),
    );

    _focusController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );

    _focusCurve = CurvedAnimation(
      parent: _focusController,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );

    if (widget.animationsEnabled) {
      unawaited(_ambientController.repeat());
    }

    if (_internalFocusedKey != null) {
      _focusController.value = 1.0;
    }
  }

  @override
  void didUpdateWidget(covariant RelaySpatialScene oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.animationsEnabled != oldWidget.animationsEnabled) {
      if (widget.animationsEnabled) {
        unawaited(_ambientController.repeat());
      } else {
        _ambientController.stop();
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
  }

  @override
  void dispose() {
    _ambientController.dispose();
    _focusController.dispose();
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

    final focusedDevice = widget.devices.where((d) => d.key == _internalFocusedKey).firstOrNull;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Primary Motion Canvas
        SizedBox(
          height: widget.height,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final sceneSize = Size(constraints.maxWidth, widget.height);

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
                                ambientPhase: reducedMotion ? 0.0 : _ambientController.value,
                              ),
                            );
                          },
                        ),
                      ),

                      // Animated Relationship Energy Bridge / Stream
                      AnimatedBuilder(
                        animation: Listenable.merge([_ambientController, _focusController]),
                        builder: (context, child) {
                          final focusVal = reducedMotion ? (_internalFocusedKey != null ? 1.0 : 0.0) : _focusCurve.value;
                          final ambientVal = reducedMotion ? 0.0 : _ambientController.value;

                          if (focusedDevice != null && focusVal > 0.01) {
                            final selfPos = RelaySpatialLayoutEngine.computeSelfPosition(
                              sceneSize: sceneSize,
                              focusProgress: focusVal,
                              hasFocusedDevice: true,
                              ambientPhase: ambientVal,
                            );

                            final isPrimary = focusedDevice.isAuthenticatedRelay;
                            final ringList = isPrimary ? primaryDevices : compatibilityDevices;
                            final idx = math.max(0, ringList.indexWhere((d) => d.key == focusedDevice.key));

                            final targetPos = RelaySpatialLayoutEngine.computeRemotePosition(
                              device: focusedDevice,
                              indexInRing: idx,
                              totalInRing: math.max(1, ringList.length),
                              sceneSize: sceneSize,
                              ambientPhase: ambientVal,
                              focusedDeviceKey: _internalFocusedKey,
                              focusProgress: focusVal,
                            );

                            return RelayTransferStream(
                              sourceOffset: selfPos.offset,
                              targetOffset: targetPos.offset,
                              phase: focusedDevice.phase,
                              progress: focusedDevice.progress,
                              pulsePhase: (ambientVal * 4) % 1.0,
                              isFocusedPair: true,
                            );
                          }
                          return const SizedBox.shrink();
                        },
                      ),

                      // Surrounding Remote Device Nodes
                      AnimatedBuilder(
                        animation: Listenable.merge([_ambientController, _focusController]),
                        builder: (context, child) {
                          final focusVal = reducedMotion ? (_internalFocusedKey != null ? 1.0 : 0.0) : _focusCurve.value;
                          final ambientVal = reducedMotion ? 0.0 : _ambientController.value;

                          final widgets = <Widget>[];

                          // Render Center / Self Device Node (Base layer)
                          final selfPos = RelaySpatialLayoutEngine.computeSelfPosition(
                            sceneSize: sceneSize,
                            focusProgress: focusVal,
                            hasFocusedDevice: _internalFocusedKey != null,
                            ambientPhase: ambientVal,
                          );

                          widgets.add(
                            Positioned(
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
                            ),
                          );

                          // Render Compatibility Devices (Outer Ring)
                          for (int i = 0; i < compatibilityDevices.length; i++) {
                            final device = compatibilityDevices[i];
                            final pos = RelaySpatialLayoutEngine.computeRemotePosition(
                              device: device,
                              indexInRing: i,
                              totalInRing: compatibilityDevices.length,
                              sceneSize: sceneSize,
                              ambientPhase: ambientVal,
                              focusedDeviceKey: _internalFocusedKey,
                              focusProgress: focusVal,
                            );

                            final isThisFocused = _internalFocusedKey == device.key;
                            final isDimmed = _internalFocusedKey != null && !isThisFocused;

                            widgets.add(
                              Positioned(
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
                              ),
                            );
                          }

                          // Render Authenticated / Paired Devices (Inner Ring)
                          for (int i = 0; i < primaryDevices.length; i++) {
                            final device = primaryDevices[i];
                            final pos = RelaySpatialLayoutEngine.computeRemotePosition(
                              device: device,
                              indexInRing: i,
                              totalInRing: primaryDevices.length,
                              sceneSize: sceneSize,
                              ambientPhase: ambientVal,
                              focusedDeviceKey: _internalFocusedKey,
                              focusProgress: focusVal,
                            );

                            final isThisFocused = _internalFocusedKey == device.key;
                            final isDimmed = _internalFocusedKey != null && !isThisFocused;

                            widgets.add(
                              Positioned(
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
                              ),
                            );
                          }

                          return Stack(clipBehavior: Clip.none, children: widgets);
                        },
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),

        // Emergent Relationship Capabilities Panel (Active when a device is focused)
        AnimatedSize(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
          child: focusedDevice != null ? _buildRelationshipPanel(context, palette, focusedDevice) : const SizedBox.shrink(),
        ),
      ],
    );
  }

  Widget _buildRelationshipPanel(BuildContext context, RelayPalette palette, RelayDeviceVm device) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.softSurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: palette.accent.withValues(alpha: 0.25)),
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
                      device.statusSummary,
                      style: RelayTypography.caption(palette.textSecondary),
                    ),
                  ],
                ),
              ),
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
