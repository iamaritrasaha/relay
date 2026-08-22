import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:relay_app/config/relay_brand.dart';
import 'package:relay_app/config/relay_device_palette.dart';
import 'package:relay_app/config/relay_motion.dart';
import 'package:relay_app/model/ui/relay_device_vm.dart';
import 'package:relay_app/widget/relay_motion/relay_ambient_clock.dart';
import 'package:relay_app/widget/relay_symbol.dart';
import 'package:relay_isolates/model/device.dart';

/// The visual centerpiece of the Relay connected-device Hero:
///
/// [ REMOTE DEVICE SILHOUETTE ]  ═════════  [ RELAY LINK CORE ]  ═════════  [ LOCAL DESKTOP SILHOUETTE ]
///
/// Communicates the live continuity bridge between the selected remote device
/// and this computer with deterministic device-palette styling, optical endpoint anchors,
/// a continuous softly flowing luminous bridge line (no packet dots), and a slow steadily rotating
/// Relay Link Core with subtle luminosity breath.
class RelayConnectionStage extends StatelessWidget {
  final RelayDeviceVm device;
  final RelayDevicePalette palette;
  final String selfAlias;
  final DeviceType selfDeviceType;
  final bool connected;
  final bool connecting;
  final bool animationsEnabled;

  const RelayConnectionStage({
    super.key,
    required this.device,
    required this.palette,
    required this.selfAlias,
    this.selfDeviceType = DeviceType.desktop,
    required this.connected,
    this.connecting = false,
    this.animationsEnabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final disableMotion = (MediaQuery.maybeDisableAnimationsOf(context) ?? false) || !animationsEnabled;
    final sharedClock = RelayAmbientClock.maybeOf(context);

    return TweenAnimationBuilder<RelayDevicePalette>(
      tween: RelayDevicePaletteTween(begin: palette, end: palette),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      builder: (context, animatedPalette, _) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 480;

            if (isWide) {
              return _HorizontalConnectionStage(
                device: device,
                palette: animatedPalette,
                selfAlias: selfAlias,
                selfDeviceType: selfDeviceType,
                connected: connected,
                connecting: connecting,
                isDark: isDark,
                disableMotion: disableMotion,
                sharedClock: sharedClock,
              );
            } else {
              return _VerticalConnectionStage(
                device: device,
                palette: animatedPalette,
                selfAlias: selfAlias,
                selfDeviceType: selfDeviceType,
                connected: connected,
                connecting: connecting,
                isDark: isDark,
                disableMotion: disableMotion,
                sharedClock: sharedClock,
              );
            }
          },
        );
      },
    );
  }
}

/// Tween for smooth 250-350ms device palette crossfades on device switch.
class RelayDevicePaletteTween extends Tween<RelayDevicePalette> {
  RelayDevicePaletteTween({super.begin, super.end});

  @override
  RelayDevicePalette lerp(double t) {
    if (begin == null && end == null) {
      return RelayDevicePalette.fallback();
    }
    if (begin == null) return end!;
    if (end == null) return begin!;
    return RelayDevicePalette.lerp(begin!, end!, t);
  }
}

/// Precise optical geometry metrics for device silhouettes to ensure sub-pixel line contact.
class _SilhouetteOpticalMetrics {
  final double width;
  final double height;
  final double anchorOffsetY; // Y distance from top of silhouette to visual center anchor
  final double displayHeight; // Display body height (excluding stand)

  const _SilhouetteOpticalMetrics({
    required this.width,
    required this.height,
    required this.anchorOffsetY,
    required this.displayHeight,
  });

  static _SilhouetteOpticalMetrics of({
    required DeviceType deviceType,
    required bool isTablet,
    required bool compact,
  }) {
    if (compact) {
      if (isTablet) {
        return const _SilhouetteOpticalMetrics(
          width: 52,
          height: 44,
          anchorOffsetY: 22,
          displayHeight: 44,
        );
      }
      return switch (deviceType) {
        DeviceType.mobile => const _SilhouetteOpticalMetrics(
          width: 38,
          height: 64,
          anchorOffsetY: 32,
          displayHeight: 64,
        ),
        _ => const _SilhouetteOpticalMetrics(
          width: 58,
          height: 44,
          anchorOffsetY: 18, // displayHeight = 36, 36/2 = 18
          displayHeight: 36,
        ),
      };
    }

    if (isTablet) {
      return const _SilhouetteOpticalMetrics(
        width: 66,
        height: 54,
        anchorOffsetY: 27,
        displayHeight: 54,
      );
    }
    return switch (deviceType) {
      DeviceType.mobile => const _SilhouetteOpticalMetrics(
        width: 48,
        height: 80,
        anchorOffsetY: 40,
        displayHeight: 80,
      ),
      _ => const _SilhouetteOpticalMetrics(
        width: 76,
        height: 54,
        anchorOffsetY: 23, // displayHeight = 46, 46/2 = 23
        displayHeight: 46,
      ),
    };
  }
}

class _HorizontalConnectionStage extends StatelessWidget {
  final RelayDeviceVm device;
  final RelayDevicePalette palette;
  final String selfAlias;
  final DeviceType selfDeviceType;
  final bool connected;
  final bool connecting;
  final bool isDark;
  final bool disableMotion;
  final RelayAmbientClockNotifier? sharedClock;

  const _HorizontalConnectionStage({
    required this.device,
    required this.palette,
    required this.selfAlias,
    required this.selfDeviceType,
    required this.connected,
    required this.connecting,
    required this.isDark,
    required this.disableMotion,
    required this.sharedClock,
  });

  bool get _isTabletDevice {
    if (device.deviceType != DeviceType.mobile) return false;
    final lower = '${device.alias} ${device.deviceModel ?? ''}'.toLowerCase();
    return lower.contains('tab') || lower.contains('pad') || lower.contains('tablet');
  }

  @override
  Widget build(BuildContext context) {
    final localDisplayName = selfAlias.isNotEmpty ? selfAlias : 'This computer';
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    const stageHeight = 120.0;
    const connectionAxisY = 46.0;
    const coreDiameter = 44.0;
    const coreRadius = coreDiameter / 2;
    const padX = 16.0;
    const labelTop = 92.0;

    final remoteMetrics = _SilhouetteOpticalMetrics.of(
      deviceType: device.deviceType,
      isTablet: _isTabletDevice,
      compact: false,
    );

    final localMetrics = _SilhouetteOpticalMetrics.of(
      deviceType: selfDeviceType,
      isTablet: false,
      compact: false,
    );

    return SizedBox(
      height: stageHeight,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stageWidth = constraints.maxWidth;
          final centerX = stageWidth / 2;

          // Explicit optical contact anchors (all exactly on connectionAxisY)
          final remoteAnchor = Offset(padX + remoteMetrics.width, connectionAxisY);
          final coreLeft = Offset(centerX - coreRadius, connectionAxisY);
          final coreRight = Offset(centerX + coreRadius, connectionAxisY);
          final localAnchor = Offset(stageWidth - padX - localMetrics.width, connectionAxisY);

          return Stack(
            clipBehavior: Clip.none,
            children: [
              // Continuous glowing bridge line behind silhouettes and core
              Positioned.fill(
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: _BridgePainter(
                      orientation: Axis.horizontal,
                      connected: connected,
                      connecting: connecting,
                      palette: palette,
                      isDark: isDark,
                      sharedClock: sharedClock,
                      disableMotion: disableMotion,
                      startAnchor: remoteAnchor,
                      coreLeft: coreLeft,
                      coreRight: coreRight,
                      endAnchor: localAnchor,
                    ),
                  ),
                ),
              ),

              // Remote device silhouette (aligned to connectionAxisY)
              Positioned(
                left: padX,
                top: connectionAxisY - remoteMetrics.anchorOffsetY,
                width: remoteMetrics.width,
                height: remoteMetrics.height,
                child: AnimatedSwitcher(
                  duration: RelayMotion.focus,
                  switchInCurve: RelayMotion.focusCurve,
                  switchOutCurve: RelayMotion.focusCurve,
                  child: KeyedSubtree(
                    key: ValueKey('${device.key}-${device.deviceType}'),
                    child: RepaintBoundary(
                      child: CustomPaint(
                        size: Size(remoteMetrics.width, remoteMetrics.height),
                        painter: _SilhouettePainter(
                          deviceType: device.deviceType,
                          palette: palette,
                          connected: connected,
                          connecting: connecting,
                          isDark: isDark,
                          isLocal: false,
                          sharedClock: sharedClock,
                          disableMotion: disableMotion,
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // Central Relay Link Core (aligned to connectionAxisY)
              Positioned(
                left: centerX - coreRadius,
                top: connectionAxisY - coreRadius,
                width: coreDiameter,
                height: coreDiameter,
                child: RepaintBoundary(
                  child: _RelayLinkCore(
                    palette: palette,
                    connected: connected,
                    connecting: connecting,
                    isDark: isDark,
                    disableMotion: disableMotion,
                    sharedClock: sharedClock,
                    compact: false,
                  ),
                ),
              ),

              // Local desktop silhouette (aligned to connectionAxisY)
              Positioned(
                right: padX,
                top: connectionAxisY - localMetrics.anchorOffsetY,
                width: localMetrics.width,
                height: localMetrics.height,
                child: RepaintBoundary(
                  child: CustomPaint(
                    size: Size(localMetrics.width, localMetrics.height),
                    painter: _SilhouettePainter(
                      deviceType: selfDeviceType,
                      palette: palette,
                      connected: connected,
                      connecting: connecting,
                      isDark: isDark,
                      isLocal: true,
                      sharedClock: sharedClock,
                      disableMotion: disableMotion,
                    ),
                  ),
                ),
              ),

              // Remote device label (shared baseline at labelTop)
              Positioned(
                left: math.max(0.0, padX + (remoteMetrics.width / 2) - 60.0),
                top: labelTop,
                width: 120.0,
                child: Text(
                  device.alias,
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: connected ? colorScheme.onSurface : colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ),

              // Local device label (shared baseline at labelTop)
              Positioned(
                right: math.max(0.0, padX + (localMetrics.width / 2) - 60.0),
                top: labelTop,
                width: 120.0,
                child: Text(
                  localDisplayName,
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: connected ? colorScheme.onSurface : colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _VerticalConnectionStage extends StatelessWidget {
  final RelayDeviceVm device;
  final RelayDevicePalette palette;
  final String selfAlias;
  final DeviceType selfDeviceType;
  final bool connected;
  final bool connecting;
  final bool isDark;
  final bool disableMotion;
  final RelayAmbientClockNotifier? sharedClock;

  const _VerticalConnectionStage({
    required this.device,
    required this.palette,
    required this.selfAlias,
    required this.selfDeviceType,
    required this.connected,
    required this.connecting,
    required this.isDark,
    required this.disableMotion,
    required this.sharedClock,
  });

  bool get _isTabletDevice {
    if (device.deviceType != DeviceType.mobile) return false;
    final lower = '${device.alias} ${device.deviceModel ?? ''}'.toLowerCase();
    return lower.contains('tab') || lower.contains('pad') || lower.contains('tablet');
  }

  @override
  Widget build(BuildContext context) {
    final localDisplayName = selfAlias.isNotEmpty ? selfAlias : 'This computer';
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    const stageHeight = 220.0;
    const coreDiameter = 38.0;
    const coreRadius = coreDiameter / 2;
    const padY = 8.0;

    final remoteMetrics = _SilhouetteOpticalMetrics.of(
      deviceType: device.deviceType,
      isTablet: _isTabletDevice,
      compact: true,
    );

    final localMetrics = _SilhouetteOpticalMetrics.of(
      deviceType: selfDeviceType,
      isTablet: false,
      compact: true,
    );

    return SizedBox(
      height: stageHeight,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stageWidth = constraints.maxWidth;
          final centerX = stageWidth / 2;
          final centerY = stageHeight / 2;

          final remoteTop = padY;
          final remoteDisplayBottom = remoteTop + (device.deviceType == DeviceType.mobile ? remoteMetrics.height : remoteMetrics.displayHeight);
          final localTop = stageHeight - padY - 20.0 - localMetrics.height;

          // Explicit optical contact anchors along vertical axis X = centerX
          final topAnchor = Offset(centerX, remoteDisplayBottom);
          final coreTop = Offset(centerX, centerY - coreRadius);
          final coreBottom = Offset(centerX, centerY + coreRadius);
          final bottomAnchor = Offset(centerX, localTop);

          return Stack(
            clipBehavior: Clip.none,
            children: [
              // Continuous glowing vertical bridge line
              Positioned.fill(
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: _BridgePainter(
                      orientation: Axis.vertical,
                      connected: connected,
                      connecting: connecting,
                      palette: palette,
                      isDark: isDark,
                      sharedClock: sharedClock,
                      disableMotion: disableMotion,
                      startAnchor: topAnchor,
                      coreLeft: coreTop,
                      coreRight: coreBottom,
                      endAnchor: bottomAnchor,
                    ),
                  ),
                ),
              ),

              // Remote device silhouette (top)
              Positioned(
                left: centerX - (remoteMetrics.width / 2),
                top: remoteTop,
                width: remoteMetrics.width,
                height: remoteMetrics.height,
                child: AnimatedSwitcher(
                  duration: RelayMotion.focus,
                  switchInCurve: RelayMotion.focusCurve,
                  switchOutCurve: RelayMotion.focusCurve,
                  child: KeyedSubtree(
                    key: ValueKey('${device.key}-${device.deviceType}'),
                    child: RepaintBoundary(
                      child: CustomPaint(
                        size: Size(remoteMetrics.width, remoteMetrics.height),
                        painter: _SilhouettePainter(
                          deviceType: device.deviceType,
                          palette: palette,
                          connected: connected,
                          connecting: connecting,
                          isDark: isDark,
                          isLocal: false,
                          sharedClock: sharedClock,
                          disableMotion: disableMotion,
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // Remote device label
              Positioned(
                left: centerX - 50.0,
                top: remoteTop + remoteMetrics.height + 4.0,
                width: 100.0,
                child: Text(
                  device.alias,
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: connected ? colorScheme.onSurface : colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ),

              // Central Relay Link Core (middle)
              Positioned(
                left: centerX - coreRadius,
                top: centerY - coreRadius,
                width: coreDiameter,
                height: coreDiameter,
                child: RepaintBoundary(
                  child: _RelayLinkCore(
                    palette: palette,
                    connected: connected,
                    connecting: connecting,
                    isDark: isDark,
                    disableMotion: disableMotion,
                    sharedClock: sharedClock,
                    compact: true,
                  ),
                ),
              ),

              // Local desktop silhouette (bottom)
              Positioned(
                left: centerX - (localMetrics.width / 2),
                top: localTop,
                width: localMetrics.width,
                height: localMetrics.height,
                child: RepaintBoundary(
                  child: CustomPaint(
                    size: Size(localMetrics.width, localMetrics.height),
                    painter: _SilhouettePainter(
                      deviceType: selfDeviceType,
                      palette: palette,
                      connected: connected,
                      connecting: connecting,
                      isDark: isDark,
                      isLocal: true,
                      sharedClock: sharedClock,
                      disableMotion: disableMotion,
                    ),
                  ),
                ),
              ),

              // Local device label
              Positioned(
                left: centerX - 50.0,
                top: localTop + localMetrics.height + 4.0,
                width: 100.0,
                child: Text(
                  localDisplayName,
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: connected ? colorScheme.onSurface : colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Central circular Relay Link Core with slow steady rotation, subtle luminosity breath,
/// and synchronized bridge-crossing highlight boost.
class _RelayLinkCore extends StatelessWidget {
  final RelayDevicePalette palette;
  final bool connected;
  final bool connecting;
  final bool isDark;
  final bool disableMotion;
  final RelayAmbientClockNotifier? sharedClock;
  final bool compact;

  const _RelayLinkCore({
    required this.palette,
    required this.connected,
    required this.connecting,
    required this.isDark,
    required this.disableMotion,
    required this.sharedClock,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final size = compact ? 38.0 : 44.0;
    final symbolSize = compact ? 20.0 : 24.0;

    final isMotionActive = !disableMotion && (connected || connecting) && sharedClock != null;

    if (!isMotionActive) {
      return _buildStaticCore(size, symbolSize);
    }

    return AnimatedBuilder(
      animation: sharedClock!.cadenceClock,
      builder: (context, _) {
        final elapsed = sharedClock!.elapsedSeconds;

        // Slow steady continuous rotation: 12.0s linear period
        const rotationPeriod = 12.0;
        final rotationPhase = (elapsed / rotationPeriod) % 1.0;
        final rotationAngle = (connected || connecting) ? rotationPhase * 2 * math.pi : 0.0;

        // Subtle luminosity breath (~5.2s cycle)
        final breath = sharedClock!.breathValue; // 0.0 to 1.0

        // Synchronized bridge wave crossing boost (peak at p ≈ 0.5)
        const wavePeriod = 9.2;
        final waveTime = elapsed % wavePeriod;
        double waveProgress;
        if (waveTime < 4.0) {
          waveProgress = Curves.easeInOutSine.transform(waveTime / 4.0);
        } else if (waveTime < 4.4) {
          waveProgress = 1.0;
        } else if (waveTime < 8.4) {
          waveProgress = 1.0 - Curves.easeInOutSine.transform((waveTime - 4.4) / 4.0);
        } else {
          waveProgress = 0.0;
        }

        final distFromCoreCenter = (waveProgress - 0.5).abs();
        double waveCrossingBoost = 0.0;
        if (connected && distFromCoreCenter < 0.22) {
          final normDist = distFromCoreCenter / 0.22;
          final factor = math.cos(normDist * math.pi / 2);
          waveCrossingBoost = 0.15 * factor * factor;
        }

        final baseHaloAlpha = isDark ? 0.14 : 0.08;
        final breathHaloAlpha = baseHaloAlpha + (breath * 0.08) + waveCrossingBoost;
        final haloColor = palette.primary.withValues(alpha: breathHaloAlpha.clamp(0.0, 1.0));

        final baseBorderColor = connected
            ? palette.borderAccent.withValues(alpha: (0.40 + breath * 0.15 + waveCrossingBoost).clamp(0.0, 1.0))
            : (connecting ? palette.primary.withValues(alpha: 0.35) : (isDark ? const Color(0xFF484848) : const Color(0xFFCCCCCC)));

        final nodeBackground = isDark ? const Color(0xFF1F1F1F) : const Color(0xFFF0F0F0);

        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: nodeBackground,
            border: Border.all(color: baseBorderColor, width: 1.5),
            boxShadow: connected
                ? [
                    BoxShadow(
                      color: haloColor,
                      blurRadius: 12 + (waveCrossingBoost * 30),
                      spreadRadius: 1.5 + (waveCrossingBoost * 2),
                    ),
                  ]
                : null,
          ),
          alignment: Alignment.center,
          child: Transform.rotate(
            angle: rotationAngle,
            child: RelaySymbol(
              size: symbolSize,
              palette: palette,
              animated: false,
              color: connected ? null : (isDark ? const Color(0xFF888888) : const Color(0xFF777777)),
            ),
          ),
        );
      },
    );
  }

  Widget _buildStaticCore(double size, double symbolSize) {
    final baseBorderColor = connected
        ? palette.borderAccent
        : (connecting ? palette.primary.withValues(alpha: 0.35) : (isDark ? const Color(0xFF484848) : const Color(0xFFCCCCCC)));

    final nodeBackground = isDark ? const Color(0xFF1F1F1F) : const Color(0xFFF0F0F0);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: nodeBackground,
        border: Border.all(color: baseBorderColor, width: 1.5),
      ),
      alignment: Alignment.center,
      child: RelaySymbol(
        size: symbolSize,
        palette: palette,
        animated: false,
        color: connected ? null : (isDark ? const Color(0xFF888888) : const Color(0xFF777777)),
      ),
    );
  }
}

/// Stylized vector silhouette for a remote device or local desktop.
class _SilhouettePainter extends CustomPainter {
  final DeviceType deviceType;
  final RelayDevicePalette palette;
  final bool connected;
  final bool connecting;
  final bool isDark;
  final bool isLocal;
  final RelayAmbientClockNotifier? sharedClock;
  final bool disableMotion;

  _SilhouettePainter({
    required this.deviceType,
    required this.palette,
    required this.connected,
    required this.connecting,
    required this.isDark,
    required this.isLocal,
    required this.sharedClock,
    required this.disableMotion,
  }) : super(repaint: (!disableMotion && connected) ? sharedClock?.cadenceClock : null);

  double get phase => (!disableMotion && connected && sharedClock != null) ? sharedClock!.phaseSlow : 0.0;

  @override
  void paint(Canvas canvas, Size size) {
    switch (deviceType) {
      case DeviceType.mobile:
        if (size.width > size.height * 0.9) {
          _paintTablet(canvas, size);
        } else {
          _paintPhone(canvas, size);
        }
      case DeviceType.desktop:
      case DeviceType.headless:
      case DeviceType.server:
      case DeviceType.web:
        _paintDesktop(canvas, size);
    }
  }

  void _paintPhone(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final rrect = RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, w, h), const Radius.circular(10));
    final screenRrect = RRect.fromRectAndRadius(Rect.fromLTWH(3, 4, w - 6, h - 8), const Radius.circular(7));

    // Outer frame fill
    final framePaint = Paint()
      ..color = isDark ? const Color(0xFF282828) : const Color(0xFFE2E2E2)
      ..style = PaintingStyle.fill;
    canvas.drawRRect(rrect, framePaint);

    // Screen fill with palette reflection
    final screenPaint = Paint()..style = PaintingStyle.fill;
    if (connected) {
      screenPaint.shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          palette.primary.withValues(alpha: isDark ? 0.32 : 0.22),
          palette.secondary.withValues(alpha: isDark ? 0.16 : 0.10),
        ],
      ).createShader(screenRrect.outerRect);
    } else {
      screenPaint.color = isDark ? const Color(0xFF1E1E1E) : const Color(0xFFEBEBEB);
    }
    canvas.drawRRect(screenRrect, screenPaint);

    // Subtle ambient screen highlight drift
    if (connected && phase > 0) {
      canvas.save();
      canvas.clipRRect(screenRrect);
      final sweepX = (phase * (w * 2.5)) - (w * 0.75);
      final highlightPaint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: 0.0),
            Colors.white.withValues(alpha: isDark ? 0.12 : 0.20),
            Colors.white.withValues(alpha: 0.0),
          ],
        ).createShader(Rect.fromLTWH(sweepX, 0, w * 0.6, h));
      canvas.drawRect(Rect.fromLTWH(0, 0, w, h), highlightPaint);
      canvas.restore();
    }

    // Bezel border
    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = connected ? palette.primary.withValues(alpha: isDark ? 0.40 : 0.30) : (isDark ? const Color(0xFF444444) : const Color(0xFFCCCCCC));
    canvas.drawRRect(rrect, borderPaint);

    // Top speaker slit
    final notchPaint = Paint()
      ..color = isDark ? const Color(0xFF181818) : const Color(0xFFB0B0B0)
      ..style = PaintingStyle.fill;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(w / 2, 2.5), width: 12, height: 2),
        const Radius.circular(1),
      ),
      notchPaint,
    );

    // Bottom home bar
    final barPaint = Paint()
      ..color = connected ? palette.primary.withValues(alpha: isDark ? 0.5 : 0.35) : (isDark ? const Color(0xFF383838) : const Color(0xFFC0C0C0))
      ..style = PaintingStyle.fill;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(w / 2, h - 3), width: 16, height: 2),
        const Radius.circular(1),
      ),
      barPaint,
    );
  }

  void _paintTablet(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final rrect = RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, w, h), const Radius.circular(8));
    final screenRrect = RRect.fromRectAndRadius(Rect.fromLTWH(3.5, 3.5, w - 7, h - 7), const Radius.circular(5));

    final framePaint = Paint()
      ..color = isDark ? const Color(0xFF282828) : const Color(0xFFE2E2E2)
      ..style = PaintingStyle.fill;
    canvas.drawRRect(rrect, framePaint);

    final screenPaint = Paint()..style = PaintingStyle.fill;
    if (connected) {
      screenPaint.shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          palette.primary.withValues(alpha: isDark ? 0.28 : 0.18),
          palette.secondary.withValues(alpha: isDark ? 0.14 : 0.08),
        ],
      ).createShader(screenRrect.outerRect);
    } else {
      screenPaint.color = isDark ? const Color(0xFF1E1E1E) : const Color(0xFFEBEBEB);
    }
    canvas.drawRRect(screenRrect, screenPaint);

    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = connected ? palette.primary.withValues(alpha: isDark ? 0.40 : 0.30) : (isDark ? const Color(0xFF444444) : const Color(0xFFCCCCCC));
    canvas.drawRRect(rrect, borderPaint);

    // Camera dot
    final dotPaint = Paint()
      ..color = isDark ? const Color(0xFF181818) : const Color(0xFFB0B0B0)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(w / 2, 2), 1.2, dotPaint);
  }

  void _paintDesktop(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final displayHeight = h - 8;
    final rrect = RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, w, displayHeight), const Radius.circular(6));
    final screenRrect = RRect.fromRectAndRadius(Rect.fromLTWH(3, 3, w - 6, displayHeight - 6), const Radius.circular(4));

    // Stand neck & foot
    final standPaint = Paint()
      ..color = isDark ? const Color(0xFF383838) : const Color(0xFFCCCCCC)
      ..style = PaintingStyle.fill;

    // Neck
    canvas.drawRect(Rect.fromCenter(center: Offset(w / 2, displayHeight + 2), width: 7, height: 5), standPaint);
    // Foot
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(w / 2, h - 1.5), width: 28, height: 3),
        const Radius.circular(1.5),
      ),
      standPaint,
    );

    // Frame
    final framePaint = Paint()
      ..color = isDark ? const Color(0xFF282828) : const Color(0xFFE2E2E2)
      ..style = PaintingStyle.fill;
    canvas.drawRRect(rrect, framePaint);

    // Screen fill
    final screenPaint = Paint()..style = PaintingStyle.fill;
    if (connected) {
      if (isLocal) {
        screenPaint.shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            palette.primary.withValues(alpha: isDark ? 0.20 : 0.12),
            isDark ? const Color(0xFF1C1C1C) : const Color(0xFFE8E8E8),
          ],
        ).createShader(screenRrect.outerRect);
      } else {
        screenPaint.shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            palette.primary.withValues(alpha: isDark ? 0.28 : 0.18),
            palette.secondary.withValues(alpha: isDark ? 0.14 : 0.08),
          ],
        ).createShader(screenRrect.outerRect);
      }
    } else {
      screenPaint.color = isDark ? const Color(0xFF1E1E1E) : const Color(0xFFEBEBEB);
    }
    canvas.drawRRect(screenRrect, screenPaint);

    // Bezel border
    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = connected
          ? (isLocal ? palette.primary.withValues(alpha: isDark ? 0.30 : 0.20) : palette.primary.withValues(alpha: isDark ? 0.40 : 0.30))
          : (isDark ? const Color(0xFF444444) : const Color(0xFFCCCCCC));
    canvas.drawRRect(rrect, borderPaint);
  }

  @override
  bool shouldRepaint(_SilhouettePainter oldDelegate) =>
      deviceType != oldDelegate.deviceType ||
      palette != oldDelegate.palette ||
      connected != oldDelegate.connected ||
      connecting != oldDelegate.connecting ||
      isDark != oldDelegate.isDark ||
      isLocal != oldDelegate.isLocal ||
      disableMotion != oldDelegate.disableMotion;
}

/// Single lightweight CustomPainter for the restrained base bridge line and the
/// softly flowing continuous luminous wave (no particle dots).
class _BridgePainter extends CustomPainter {
  final Axis orientation;
  final bool connected;
  final bool connecting;
  final RelayDevicePalette palette;
  final bool isDark;
  final RelayAmbientClockNotifier? sharedClock;
  final bool disableMotion;
  final Offset startAnchor;
  final Offset coreLeft;
  final Offset coreRight;
  final Offset endAnchor;

  _BridgePainter({
    required this.orientation,
    required this.connected,
    required this.connecting,
    required this.palette,
    required this.isDark,
    required this.sharedClock,
    required this.disableMotion,
    required this.startAnchor,
    required this.coreLeft,
    required this.coreRight,
    required this.endAnchor,
  }) : super(repaint: (!disableMotion && (connected || connecting)) ? sharedClock?.cadenceClock : null);

  double get elapsed => (!disableMotion && sharedClock != null) ? sharedClock!.elapsedSeconds : 0.0;

  @override
  void paint(Canvas canvas, Size size) {
    if (orientation == Axis.horizontal) {
      if (endAnchor.dx <= startAnchor.dx) return;
    } else {
      if (endAnchor.dy <= startAnchor.dy) return;
    }

    final linePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    if (connected) {
      // Base bridge line: restrained neutral hairline mixed with device palette
      final baseColor = isDark ? palette.primary.withValues(alpha: 0.32) : palette.primary.withValues(alpha: 0.22);
      linePaint.color = baseColor;

      // Segment 1: Remote endpoint to Core outer radius
      canvas.drawLine(startAnchor, coreLeft, linePaint);
      // Segment 2: Core outer radius to Local endpoint
      canvas.drawLine(coreRight, endAnchor, linePaint);

      // Continuous luminous glow wave (no packet dots)
      if (!disableMotion && elapsed > 0) {
        _paintLuminousGlow(canvas);
      }
    } else if (connecting) {
      // Connecting: dashed forming line
      linePaint.color = palette.primary.withValues(alpha: isDark ? 0.45 : 0.30);
      final phaseOffset = elapsed * 12.0;
      _drawDashedLine(canvas, startAnchor, coreLeft, linePaint, 4, 4, phaseOffset);
      _drawDashedLine(canvas, coreRight, endAnchor, linePaint, 4, 4, phaseOffset);
    } else {
      // Offline / Paired: muted static broken line
      linePaint.color = isDark ? const Color(0xFF383838) : const Color(0xFFD8D8D8);
      _drawDashedLine(canvas, startAnchor, coreLeft, linePaint, 3, 6, 0);
      _drawDashedLine(canvas, coreRight, endAnchor, linePaint, 3, 6, 0);
    }
  }

  void _paintLuminousGlow(Canvas canvas) {
    // Complete cycle:
    // 0.0 .. 4.0s: Remote → Local (4.0s)
    // 4.0 .. 4.4s: Soft hold at Local (0.4s)
    // 4.4 .. 8.4s: Local → Remote (4.0s)
    // 8.4 .. 9.2s: Rest at Remote (0.8s)
    const totalCycle = 9.2;
    final cycleTime = elapsed % totalCycle;

    double progress;
    if (cycleTime < 4.0) {
      final u = cycleTime / 4.0;
      progress = Curves.easeInOutSine.transform(u);
    } else if (cycleTime < 4.4) {
      progress = 1.0;
    } else if (cycleTime < 8.4) {
      final u = (cycleTime - 4.4) / 4.0;
      progress = 1.0 - Curves.easeInOutSine.transform(u);
    } else {
      progress = 0.0;
    }

    final isResting = cycleTime >= 8.4;
    if (isResting) return;

    // Luminous region occupies roughly 28% of the full bridge length
    const waveWidth = 0.28;
    final p = progress;
    final w = waveWidth;

    final s0 = (p - w).clamp(0.0, 1.0);
    final s1 = (p - w * 0.5).clamp(0.0, 1.0);
    final s2 = p.clamp(0.0, 1.0);
    final s3 = (p + w * 0.5).clamp(0.0, 1.0);
    final s4 = (p + w).clamp(0.0, 1.0);

    final peakColor = isDark ? Color.lerp(palette.secondary, Colors.white, 0.40)! : Color.lerp(palette.secondary, Colors.white, 0.20)!;

    final stops = <double>[];
    final colors = <Color>[];

    void addStop(double stop, Color color) {
      if (stops.isEmpty || stop > stops.last + 0.0001) {
        stops.add(stop);
        colors.add(color);
      }
    }

    addStop(0.0, palette.primary.withValues(alpha: 0.0));
    if (s0 > 0.0) addStop(s0, palette.primary.withValues(alpha: 0.0));
    if (s1 > s0) addStop(s1, palette.primary.withValues(alpha: isDark ? 0.40 : 0.28));
    if (s2 > s1) addStop(s2, peakColor.withValues(alpha: isDark ? 0.95 : 0.82));
    if (s3 > s2) addStop(s3, palette.secondary.withValues(alpha: isDark ? 0.40 : 0.28));
    if (s4 > s3 && s4 < 1.0) addStop(s4, palette.primary.withValues(alpha: 0.0));
    addStop(1.0, palette.primary.withValues(alpha: 0.0));

    if (stops.length < 2) return;

    final gradient = LinearGradient(
      begin: orientation == Axis.horizontal ? Alignment.centerLeft : Alignment.topCenter,
      end: orientation == Axis.horizontal ? Alignment.centerRight : Alignment.bottomCenter,
      stops: stops,
      colors: colors,
    );

    final lineRect = Rect.fromPoints(
      Offset(startAnchor.dx - 2, startAnchor.dy - 2),
      Offset(endAnchor.dx + 2, endAnchor.dy + 2),
    );
    final glowShader = gradient.createShader(lineRect);

    // Pass 1: Soft luminous bloom stroke (3.0px)
    final bloomPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..shader = glowShader
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(startAnchor, coreLeft, bloomPaint);
    canvas.drawLine(coreRight, endAnchor, bloomPaint);

    // Pass 2: Sharp core luminous wave (1.5px)
    final corePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..shader = glowShader
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(startAnchor, coreLeft, corePaint);
    canvas.drawLine(coreRight, endAnchor, corePaint);
  }

  void _drawDashedLine(Canvas canvas, Offset p1, Offset p2, Paint paint, double dashWidth, double dashSpace, double offset) {
    final dx = p2.dx - p1.dx;
    final dy = p2.dy - p1.dy;
    final count = math.sqrt(dx * dx + dy * dy);
    if (count <= 0) return;

    final unitX = dx / count;
    final unitY = dy / count;

    final dashStep = dashWidth + dashSpace;
    final startOffset = (offset % dashStep);
    double current = -dashStep + startOffset;

    while (current < count) {
      final start = math.max(0.0, current);
      final end = math.min(count, current + dashWidth);
      if (end > start) {
        canvas.drawLine(
          Offset(p1.dx + unitX * start, p1.dy + unitY * start),
          Offset(p1.dx + unitX * end, p1.dy + unitY * end),
          paint,
        );
      }
      current += dashStep;
    }
  }

  @override
  bool shouldRepaint(_BridgePainter oldDelegate) =>
      orientation != oldDelegate.orientation ||
      connected != oldDelegate.connected ||
      connecting != oldDelegate.connecting ||
      palette != oldDelegate.palette ||
      isDark != oldDelegate.isDark ||
      disableMotion != oldDelegate.disableMotion ||
      startAnchor != oldDelegate.startAnchor ||
      coreLeft != oldDelegate.coreLeft ||
      coreRight != oldDelegate.coreRight ||
      endAnchor != oldDelegate.endAnchor;
}
