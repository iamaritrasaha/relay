import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:relay_app/config/relay_brand.dart';
import 'package:relay_app/config/relay_motion.dart';
import 'package:relay_app/model/ui/relay_device_vm.dart';
import 'package:relay_app/widget/relay_motion/relay_ambient_clock.dart';
import 'package:relay_app/widget/relay_symbol.dart';
import 'package:relay_isolates/model/device.dart';

/// The visual centerpiece of the Relay connected-device Hero:
///
/// [ REMOTE DEVICE SILHOUETTE ]  ─────────  [ RELAY LINK CORE ]  ─────────  [ LOCAL DESKTOP SILHOUETTE ]
///
/// Communicates the live continuity bridge between the selected remote device
/// and this computer with deterministic device-palette styling, responsive horizontal
/// and vertical layouts, and ambient low-overhead data particle flow.
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

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 480;

        if (isWide) {
          return _HorizontalConnectionStage(
            device: device,
            palette: palette,
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
            palette: palette,
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

  @override
  Widget build(BuildContext context) {
    final localDisplayName = selfAlias.isNotEmpty ? selfAlias : 'This computer';

    return SizedBox(
      height: 120,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Background bridge connecting remote to local through core
          Positioned.fill(
            child: RepaintBoundary(
              child: _BridgeLine(
                orientation: Axis.horizontal,
                connected: connected,
                connecting: connecting,
                palette: palette,
                isDark: isDark,
                disableMotion: disableMotion,
                sharedClock: sharedClock,
              ),
            ),
          ),
          // Content Row: Remote on left, Core in center, Local on right
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Remote device silhouette
              AnimatedSwitcher(
                duration: RelayMotion.focus,
                switchInCurve: RelayMotion.focusCurve,
                switchOutCurve: RelayMotion.focusCurve,
                child: KeyedSubtree(
                  key: ValueKey('${device.key}-${device.deviceType}'),
                  child: _DeviceSilhouette(
                    deviceType: device.deviceType,
                    palette: palette,
                    connected: connected,
                    connecting: connecting,
                    isDark: isDark,
                    isLocal: false,
                    label: device.alias,
                    deviceModel: device.deviceModel,
                    disableMotion: disableMotion,
                    sharedClock: sharedClock,
                  ),
                ),
              ),
              // Central Relay Link Core
              _RelayLinkCore(
                palette: palette,
                connected: connected,
                connecting: connecting,
                isDark: isDark,
                disableMotion: disableMotion,
                sharedClock: sharedClock,
              ),
              // Local desktop silhouette
              _DeviceSilhouette(
                deviceType: selfDeviceType,
                palette: palette,
                connected: connected,
                connecting: connecting,
                isDark: isDark,
                isLocal: true,
                label: localDisplayName,
                disableMotion: disableMotion,
                sharedClock: sharedClock,
              ),
            ],
          ),
        ],
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

  @override
  Widget build(BuildContext context) {
    final localDisplayName = selfAlias.isNotEmpty ? selfAlias : 'This computer';

    return SizedBox(
      height: 220,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Background vertical bridge connecting remote to local through core
          Positioned.fill(
            child: RepaintBoundary(
              child: _BridgeLine(
                orientation: Axis.vertical,
                connected: connected,
                connecting: connecting,
                palette: palette,
                isDark: isDark,
                disableMotion: disableMotion,
                sharedClock: sharedClock,
              ),
            ),
          ),
          // Content Column: Remote on top, Core in middle, Local on bottom
          Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Remote device silhouette
              AnimatedSwitcher(
                duration: RelayMotion.focus,
                switchInCurve: RelayMotion.focusCurve,
                switchOutCurve: RelayMotion.focusCurve,
                child: KeyedSubtree(
                  key: ValueKey('${device.key}-${device.deviceType}'),
                  child: _DeviceSilhouette(
                    deviceType: device.deviceType,
                    palette: palette,
                    connected: connected,
                    connecting: connecting,
                    isDark: isDark,
                    isLocal: false,
                    label: device.alias,
                    deviceModel: device.deviceModel,
                    disableMotion: disableMotion,
                    sharedClock: sharedClock,
                    compact: true,
                  ),
                ),
              ),
              // Central Relay Link Core
              _RelayLinkCore(
                palette: palette,
                connected: connected,
                connecting: connecting,
                isDark: isDark,
                disableMotion: disableMotion,
                sharedClock: sharedClock,
                compact: true,
              ),
              // Local desktop silhouette
              _DeviceSilhouette(
                deviceType: selfDeviceType,
                palette: palette,
                connected: connected,
                connecting: connecting,
                isDark: isDark,
                isLocal: true,
                label: localDisplayName,
                disableMotion: disableMotion,
                sharedClock: sharedClock,
                compact: true,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Central circular Relay Link Core.
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
        boxShadow: connected && !disableMotion
            ? [
                BoxShadow(
                  color: palette.haloColor,
                  blurRadius: 12,
                  spreadRadius: 2,
                ),
              ]
            : null,
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
class _DeviceSilhouette extends StatelessWidget {
  final DeviceType deviceType;
  final RelayDevicePalette palette;
  final bool connected;
  final bool connecting;
  final bool isDark;
  final bool isLocal;
  final String label;
  final String? deviceModel;
  final bool disableMotion;
  final RelayAmbientClockNotifier? sharedClock;
  final bool compact;

  const _DeviceSilhouette({
    required this.deviceType,
    required this.palette,
    required this.connected,
    required this.connecting,
    required this.isDark,
    required this.isLocal,
    required this.label,
    this.deviceModel,
    required this.disableMotion,
    required this.sharedClock,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: _silhouetteWidth,
          height: _silhouetteHeight,
          child: CustomPaint(
            painter: _SilhouettePainter(
              deviceType: deviceType,
              palette: palette,
              connected: connected,
              connecting: connecting,
              isDark: isDark,
              isLocal: isLocal,
              sharedClock: sharedClock,
              disableMotion: disableMotion,
            ),
          ),
        ),
        const SizedBox(height: 6),
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: compact ? 90 : 120),
          child: Text(
            label,
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
  }

  bool get _isTabletDevice {
    final lower = '$label ${deviceModel ?? ''}'.toLowerCase();
    return lower.contains('tab') || lower.contains('pad') || lower.contains('tablet');
  }

  double get _silhouetteWidth {
    if (compact) {
      if (_isTabletDevice) return 52;
      return switch (deviceType) {
        DeviceType.mobile => 38,
        _ => 58,
      };
    }
    if (_isTabletDevice) return 66;
    return switch (deviceType) {
      DeviceType.mobile => 48,
      _ => 76,
    };
  }

  double get _silhouetteHeight {
    if (compact) {
      if (_isTabletDevice) return 44;
      return switch (deviceType) {
        DeviceType.mobile => 64,
        _ => 44,
      };
    }
    if (_isTabletDevice) return 54;
    return switch (deviceType) {
      DeviceType.mobile => 80,
      _ => 54,
    };
  }
}

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

    // Top speaker / pill slit
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
        // Local machine gets subtle Yaru warmth and subtle palette reflection
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

/// Restrained connection bridge line with travelling live data particles.
class _BridgeLine extends StatelessWidget {
  final Axis orientation;
  final bool connected;
  final bool connecting;
  final RelayDevicePalette palette;
  final bool isDark;
  final bool disableMotion;
  final RelayAmbientClockNotifier? sharedClock;

  const _BridgeLine({
    required this.orientation,
    required this.connected,
    required this.connecting,
    required this.palette,
    required this.isDark,
    required this.disableMotion,
    required this.sharedClock,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _BridgePainter(
        orientation: orientation,
        connected: connected,
        connecting: connecting,
        palette: palette,
        isDark: isDark,
        sharedClock: sharedClock,
        disableMotion: disableMotion,
      ),
    );
  }
}

class _BridgePainter extends CustomPainter {
  final Axis orientation;
  final bool connected;
  final bool connecting;
  final RelayDevicePalette palette;
  final bool isDark;
  final RelayAmbientClockNotifier? sharedClock;
  final bool disableMotion;

  _BridgePainter({
    required this.orientation,
    required this.connected,
    required this.connecting,
    required this.palette,
    required this.isDark,
    required this.sharedClock,
    required this.disableMotion,
  }) : super(repaint: (!disableMotion && (connected || connecting)) ? sharedClock?.cadenceClock : null);

  double get phase => (!disableMotion && sharedClock != null) ? sharedClock!.elapsedSeconds : 0.0;

  @override
  void paint(Canvas canvas, Size size) {
    if (orientation == Axis.horizontal) {
      _paintHorizontal(canvas, size);
    } else {
      _paintVertical(canvas, size);
    }
  }

  void _paintHorizontal(Canvas canvas, Size size) {
    final midY = size.height / 2; // align with silhouette center
    final leftX = 54.0;
    final rightX = size.width - 54.0;
    final centerX = size.width / 2;
    final coreRadius = 24.0;

    if (rightX <= leftX + coreRadius * 2) return;

    final linePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    if (connected) {
      linePaint.color = palette.primary.withValues(alpha: isDark ? 0.32 : 0.22);
      // Segment 1: Left device to Core
      canvas.drawLine(Offset(leftX, midY), Offset(centerX - coreRadius, midY), linePaint);
      // Segment 2: Core to Right device
      canvas.drawLine(Offset(centerX + coreRadius, midY), Offset(rightX, midY), linePaint);

      // Draw travelling data packet train when motion is active
      if (!disableMotion && phase > 0) {
        final trainDotCount = 6;
        final dotSpacing = 8.0;
        final coreRadius = 24.0;
        final flashDuration = 0.15; // seconds

        // Forward train (remote → local)
        final cycleA = 3.2; // total travel time
        final progressA = (phase % cycleA) / cycleA;
        final startXA = leftX + dotSpacing;
        final endXA = rightX - dotSpacing;
        final travelDistA = endXA - startXA;
        double? currentXA;
        for (int i = 0; i < trainDotCount; i++) {
          final offset = i * (dotSpacing + 2.0);
          final pos = startXA + (travelDistA * progressA) - offset;
          if (i == 0) currentXA = pos;
          if (pos < startXA || pos > endXA) continue;
          final radius = 5.0 - i * 0.5;
          final opacity = 1.0 - (i * 0.12);
          final paint = Paint()
            ..style = PaintingStyle.fill
            ..color = Colors.white.withValues(alpha: opacity);
          final glow = Paint()
            ..style = PaintingStyle.fill
            ..color = palette.primary.withValues(alpha: (isDark ? 0.7 : 0.5) * opacity);
          canvas.drawCircle(Offset(pos, midY), radius + 2, glow);
          canvas.drawCircle(Offset(pos, midY), radius, paint);
        }

        // Reverse train (local → remote)
        final cycleB = 4.8;
        final progressB = 1.0 - ((phase % cycleB) / cycleB);
        final startXB = rightX - dotSpacing;
        final endXB = leftX + dotSpacing;
        final travelDistB = startXB - endXB;
        double? currentXB;
        for (int i = 0; i < trainDotCount; i++) {
          final offset = i * (dotSpacing + 2.0);
          final pos = startXB - (travelDistB * progressB) + offset;
          if (i == 0) currentXB = pos;
          if (pos < endXB || pos > startXB) continue;
          final radius = 4.0 - i * 0.4;
          final opacity = 0.85 - (i * 0.1);
          final paint = Paint()
            ..style = PaintingStyle.fill
            ..color = Colors.white.withValues(alpha: opacity);
          final glow = Paint()
            ..style = PaintingStyle.fill
            ..color = palette.secondary.withValues(alpha: (isDark ? 0.5 : 0.35) * opacity);
          canvas.drawCircle(Offset(pos, midY), radius + 2, glow);
          canvas.drawCircle(Offset(pos, midY), radius, paint);
        }

        // Core flash when either train passes through core region
        final coreCenter = Offset(centerX, midY);
        final coreFlashPaint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4.0
          ..color = palette.haloColor.withValues(alpha: 0.6);
        // Simple flash based on phase proximity to core crossing
        final coreCrossA = (currentXA ?? leftX) - coreCenter.dx;
        final coreCrossB = (currentXB ?? rightX) - coreCenter.dx;
        if ((coreCrossA.abs() < coreRadius && (phase % cycleA) < flashDuration) ||
            (coreCrossB.abs() < coreRadius && (phase % cycleB) < flashDuration)) {
          canvas.drawCircle(coreCenter, coreRadius + 6, coreFlashPaint);
        }

        // Endpoint highlight when train reaches endpoints
        final endpointPaint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.0
          ..color = palette.primary.withValues(alpha: 0.5);
        // Forward reaching right endpoint
        if ((currentXA ?? leftX) > rightX - coreRadius && (phase % cycleA) < flashDuration) {
          canvas.drawCircle(Offset(rightX, midY), 8, endpointPaint);
        }
        // Reverse reaching left endpoint
        if ((currentXB ?? rightX) < leftX + coreRadius && (phase % cycleB) < flashDuration) {
          canvas.drawCircle(Offset(leftX, midY), 8, endpointPaint);
        }
      }
    } else if (connecting) {
      // Dashed moving line for connecting
      linePaint.color = palette.primary.withValues(alpha: isDark ? 0.45 : 0.30);
      _drawDashedLine(canvas, Offset(leftX, midY), Offset(centerX - coreRadius, midY), linePaint, 4, 4, phase * 10);
      _drawDashedLine(canvas, Offset(centerX + coreRadius, midY), Offset(rightX, midY), linePaint, 4, 4, phase * 10);
    } else {
      // Offline: faded broken line
      linePaint.color = isDark ? const Color(0xFF383838) : const Color(0xFFD8D8D8);
      _drawDashedLine(canvas, Offset(leftX, midY), Offset(centerX - coreRadius, midY), linePaint, 3, 6, 0);
      _drawDashedLine(canvas, Offset(centerX + coreRadius, midY), Offset(rightX, midY), linePaint, 3, 6, 0);
    }
  }

  void _paintVertical(Canvas canvas, Size size) {
    final midX = size.width / 2;
    final topY = 48.0;
    final bottomY = size.height - 48.0;
    final centerY = size.height / 2;
    final coreRadius = 22.0;

    if (bottomY <= topY + coreRadius * 2) return;

    final linePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    if (connected) {
      linePaint.color = palette.primary.withValues(alpha: isDark ? 0.32 : 0.22);
      canvas.drawLine(Offset(midX, topY), Offset(midX, centerY - coreRadius), linePaint);
      canvas.drawLine(Offset(midX, centerY + coreRadius), Offset(midX, bottomY), linePaint);

      // Draw travelling data packet train when motion is active
      if (!disableMotion && phase > 0) {
        final trainDotCount = 6;
        final dotSpacing = 8.0;
        final flashDuration = 0.15; // seconds

        // Forward train (top → bottom)
        final cycleA = 3.2;
        final progressA = (phase % cycleA) / cycleA;
        final startYA = topY + dotSpacing;
        final endYA = bottomY - dotSpacing;
        final travelDistA = endYA - startYA;
        double? currentYA;
        for (int i = 0; i < trainDotCount; i++) {
          final offset = i * (dotSpacing + 2.0);
          final pos = startYA + (travelDistA * progressA) - offset;
          if (i == 0) currentYA = pos;
          if (pos < startYA || pos > endYA) continue;
          final radius = 5.0 - i * 0.5;
          final opacity = 1.0 - (i * 0.12);
          final paint = Paint()
            ..style = PaintingStyle.fill
            ..color = Colors.white.withValues(alpha: opacity);
          final glow = Paint()
            ..style = PaintingStyle.fill
            ..color = palette.primary.withValues(alpha: (isDark ? 0.7 : 0.5) * opacity);
          canvas.drawCircle(Offset(midX, pos), radius + 2, glow);
          canvas.drawCircle(Offset(midX, pos), radius, paint);
        }

        // Reverse train (bottom → top)
        final cycleB = 4.8;
        final progressB = 1.0 - ((phase % cycleB) / cycleB);
        final startYB = bottomY - dotSpacing;
        final endYB = topY + dotSpacing;
        final travelDistB = startYB - endYB;
        double? currentYB;
        for (int i = 0; i < trainDotCount; i++) {
          final offset = i * (dotSpacing + 2.0);
          final pos = startYB - (travelDistB * progressB) + offset;
          if (i == 0) currentYB = pos;
          if (pos < endYB || pos > startYB) continue;
          final radius = 4.0 - i * 0.4;
          final opacity = 0.85 - (i * 0.1);
          final paint = Paint()
            ..style = PaintingStyle.fill
            ..color = Colors.white.withValues(alpha: opacity);
          final glow = Paint()
            ..style = PaintingStyle.fill
            ..color = palette.secondary.withValues(alpha: (isDark ? 0.5 : 0.35) * opacity);
          canvas.drawCircle(Offset(midX, pos), radius + 2, glow);
          canvas.drawCircle(Offset(midX, pos), radius, paint);
        }

        // Core flash when either train passes through core region
        final coreCenter = Offset(midX, centerY);
        final coreFlashPaint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4.0
          ..color = palette.haloColor.withValues(alpha: 0.6);
        final coreCrossA = (currentYA ?? topY) - coreCenter.dy;
        final coreCrossB = (currentYB ?? bottomY) - coreCenter.dy;
        if ((coreCrossA.abs() < coreRadius && (phase % cycleA) < flashDuration) ||
            (coreCrossB.abs() < coreRadius && (phase % cycleB) < flashDuration)) {
          canvas.drawCircle(coreCenter, coreRadius + 6, coreFlashPaint);
        }

        // Endpoint highlight when train reaches endpoints
        final endpointPaint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.0
          ..color = palette.primary.withValues(alpha: 0.5);
        // Forward reaching bottom endpoint
        if ((currentYA ?? topY) > bottomY - coreRadius && (phase % cycleA) < flashDuration) {
          canvas.drawCircle(Offset(midX, bottomY), 8, endpointPaint);
        }
        // Reverse reaching top endpoint
        if ((currentYB ?? bottomY) < topY + coreRadius && (phase % cycleB) < flashDuration) {
          canvas.drawCircle(Offset(midX, topY), 8, endpointPaint);
        }
      }
    } else if (connecting) {
      linePaint.color = palette.primary.withValues(alpha: isDark ? 0.45 : 0.30);
      _drawDashedLine(canvas, Offset(midX, topY), Offset(midX, centerY - coreRadius), linePaint, 4, 4, phase * 10);
      _drawDashedLine(canvas, Offset(midX, centerY + coreRadius), Offset(midX, bottomY), linePaint, 4, 4, phase * 10);
    } else {
      linePaint.color = isDark ? const Color(0xFF383838) : const Color(0xFFD8D8D8);
      _drawDashedLine(canvas, Offset(midX, topY), Offset(midX, centerY - coreRadius), linePaint, 3, 6, 0);
      _drawDashedLine(canvas, Offset(midX, centerY + coreRadius), Offset(midX, bottomY), linePaint, 3, 6, 0);
    }
  }

  void _drawDashedLine(Canvas canvas, Offset p1, Offset p2, Paint paint, double dashWidth, double dashSpace, double offset) {
    final dx = p2.dx - p1.dx;
    final dy = p2.dy - p1.dy;
    final count = math.sqrt(dx * dx + dy * dy);
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
      disableMotion != oldDelegate.disableMotion;
}
