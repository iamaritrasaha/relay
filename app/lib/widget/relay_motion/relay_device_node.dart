import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:relay_app/config/relay_brand.dart';
import 'package:relay_app/model/ui/relay_capability_vm.dart';
import 'package:relay_app/model/ui/relay_device_vm.dart';
import 'package:relay_isolates/model/device.dart';

/// Stylized vector silhouette painter for devices in the Relay spatial scene.
class RelayDeviceSilhouettePainter extends CustomPainter {
  final DeviceType deviceType;
  final Color strokeColor;
  final Color fillColor;
  final double strokeWidth;

  const RelayDeviceSilhouettePainter({
    required this.deviceType,
    required this.strokeColor,
    required this.fillColor,
    this.strokeWidth = 1.5,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final strokePaint = Paint()
      ..color = strokeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final fillPaint = Paint()
      ..color = fillColor
      ..style = PaintingStyle.fill;

    final w = size.width;
    final h = size.height;

    switch (deviceType) {
      case DeviceType.mobile:
        // Stylized smartphone silhouette
        final rect = RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(w / 2, h / 2), width: w * 0.52, height: h * 0.86),
          const Radius.circular(7),
        );
        canvas.drawRRect(rect, fillPaint);
        canvas.drawRRect(rect, strokePaint);

        // Screen inner display line
        final screenRect = RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(w / 2, h * 0.48), width: w * 0.40, height: h * 0.62),
          const Radius.circular(3),
        );
        canvas.drawRRect(screenRect, strokePaint..strokeWidth = 1.0);

        // Speaker / dynamic notch
        canvas.drawLine(
          Offset(w / 2 - 4, h * 0.12),
          Offset(w / 2 + 4, h * 0.12),
          strokePaint..strokeWidth = 1.5,
        );

        // Home indicator bar
        canvas.drawLine(
          Offset(w / 2 - 5, h * 0.86),
          Offset(w / 2 + 5, h * 0.86),
          strokePaint..strokeWidth = 1.2,
        );
        break;

      case DeviceType.desktop:
        // Stylized desktop workstation monitor + stand
        final screenRect = RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(w / 2, h * 0.40), width: w * 0.84, height: h * 0.54),
          const Radius.circular(5),
        );
        canvas.drawRRect(screenRect, fillPaint);
        canvas.drawRRect(screenRect, strokePaint);

        // Inner display frame
        final innerScreen = RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(w / 2, h * 0.39), width: w * 0.72, height: h * 0.42),
          const Radius.circular(2),
        );
        canvas.drawRRect(innerScreen, strokePaint..strokeWidth = 1.0);

        // Stand stem
        canvas.drawLine(
          Offset(w / 2, h * 0.67),
          Offset(w / 2, h * 0.84),
          strokePaint..strokeWidth = 2.0,
        );

        // Base foot
        final baseRRect = RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(w / 2, h * 0.86), width: w * 0.42, height: h * 0.06),
          const Radius.circular(2),
        );
        canvas.drawRRect(baseRRect, fillPaint);
        canvas.drawRRect(baseRRect, strokePaint..strokeWidth = 1.5);
        break;

      case DeviceType.web:
        // Stylized cloud / web terminal node
        final center = Offset(w / 2, h / 2);
        canvas.drawCircle(center, w * 0.38, fillPaint);
        canvas.drawCircle(center, w * 0.38, strokePaint);

        // Latitude / Longitude arcs
        final ovalH = Rect.fromCenter(center: center, width: w * 0.76, height: h * 0.36);
        canvas.drawOval(ovalH, strokePaint..strokeWidth = 1.0);
        final ovalV = Rect.fromCenter(center: center, width: w * 0.36, height: h * 0.76);
        canvas.drawOval(ovalV, strokePaint..strokeWidth = 1.0);
        canvas.drawLine(Offset(w / 2 - w * 0.38, h / 2), Offset(w / 2 + w * 0.38, h / 2), strokePaint..strokeWidth = 1.0);
        break;

      case DeviceType.headless:
      case DeviceType.server:
        // Stylized rack unit / terminal server
        final rack1 = RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(w / 2, h * 0.32), width: w * 0.82, height: h * 0.24),
          const Radius.circular(4),
        );
        final rack2 = RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(w / 2, h * 0.68), width: w * 0.82, height: h * 0.24),
          const Radius.circular(4),
        );
        canvas.drawRRect(rack1, fillPaint);
        canvas.drawRRect(rack1, strokePaint);
        canvas.drawRRect(rack2, fillPaint);
        canvas.drawRRect(rack2, strokePaint);

        // Status LEDs
        canvas.drawCircle(Offset(w * 0.22, h * 0.32), 2, strokePaint..style = PaintingStyle.fill);
        canvas.drawCircle(Offset(w * 0.32, h * 0.32), 2, strokePaint..style = PaintingStyle.fill);
        canvas.drawCircle(Offset(w * 0.22, h * 0.68), 2, strokePaint..style = PaintingStyle.fill);
        canvas.drawCircle(Offset(w * 0.32, h * 0.68), 2, strokePaint..style = PaintingStyle.fill);
        break;
    }
  }

  @override
  bool shouldRepaint(covariant RelayDeviceSilhouettePainter oldDelegate) {
    return oldDelegate.deviceType != deviceType ||
        oldDelegate.strokeColor != strokeColor ||
        oldDelegate.fillColor != fillColor ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}

/// Stylized interactive device node widget representing a device in the spatial universe.
class RelayDeviceNode extends StatelessWidget {
  final String alias;
  final DeviceType deviceType;
  final bool isSelf;
  final bool isSelected;
  final bool isDimmed;
  final bool isVerifiedRelay;
  final bool isCompatibilityPeer;
  final bool continuityConnected;
  final RelayBatteryVm? battery;
  final String? detail;
  final RelayDevicePhase phase;
  final double? progress;
  final double ambientPulse;
  final VoidCallback? onTap;

  const RelayDeviceNode({
    super.key,
    required this.alias,
    required this.deviceType,
    this.isSelf = false,
    this.isSelected = false,
    this.isDimmed = false,
    this.isVerifiedRelay = true,
    this.isCompatibilityPeer = false,
    this.continuityConnected = false,
    this.battery,
    this.detail,
    this.phase = RelayDevicePhase.idle,
    this.progress,
    this.ambientPulse = 0.0,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).relayPalette;

    // Node sizing: Self node is slightly larger anchor, remote nodes are standard pucks
    final double nodeSize = isSelf ? 76.0 : (isSelected ? 72.0 : 64.0);
    final double iconBoxSize = isSelf ? 44.0 : 40.0;

    // Visual classification styling
    final Color accentColor = isSelf
        ? palette.accent
        : isCompatibilityPeer
        ? palette.textTertiary
        : isVerifiedRelay
        ? palette.accent
        : palette.accentSecondary;

    final Color ringBorderColor = isSelected
        ? palette.accent
        : isSelf
        ? palette.accent.withValues(alpha: 0.6 + 0.3 * math.sin(ambientPulse * math.pi))
        : isCompatibilityPeer
        ? palette.hairline.withValues(alpha: 0.4)
        : isVerifiedRelay
        ? palette.accent.withValues(alpha: 0.35)
        : palette.hairline;

    final Color backgroundSurface = isSelected
        ? palette.elevated
        : isSelf
        ? palette.canvasTonalHigh
        : palette.softSurface;

    final double nodeOpacity = isDimmed ? 0.30 : 1.0;

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
      opacity: nodeOpacity,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Spatial Node Disc with Aura
            Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                // Outer subtle ambient aura / selection halo
                if (isSelected || (isSelf && ambientPulse > 0.05))
                  Container(
                    width: nodeSize + 18,
                    height: nodeSize + 18,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: accentColor.withValues(alpha: isSelected ? 0.28 : 0.12 * math.sin(ambientPulse * math.pi)),
                          blurRadius: isSelected ? 22 : 16,
                          spreadRadius: isSelected ? 4 : 2,
                        ),
                      ],
                    ),
                  ),

                // Main Node Puck
                Container(
                  width: nodeSize,
                  height: nodeSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: backgroundSurface,
                    border: Border.all(
                      color: ringBorderColor,
                      width: isSelected ? 2.2 : (isSelf ? 1.8 : (isCompatibilityPeer ? 1.0 : 1.4)),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.35),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Center(
                    child: SizedBox(
                      width: iconBoxSize,
                      height: iconBoxSize,
                      child: CustomPaint(
                        painter: RelayDeviceSilhouettePainter(
                          deviceType: deviceType,
                          strokeColor: isSelected
                              ? palette.accentSoft
                              : isSelf
                              ? palette.accent
                              : isCompatibilityPeer
                              ? palette.textTertiary
                              : palette.textPrimary,
                          fillColor: (isSelected ? palette.accent : accentColor).withValues(alpha: 0.10),
                          strokeWidth: isSelected ? 1.8 : 1.4,
                        ),
                      ),
                    ),
                  ),
                ),

                // Top Badge (This Device / Verified / Compatibility)
                Positioned(
                  top: -2,
                  right: -2,
                  child: _buildBadge(palette),
                ),

                // Battery Pill Indicator (if available)
                if (battery != null && battery!.hasInfo)
                  Positioned(
                    bottom: -4,
                    child: _buildBatteryIndicator(palette, battery!),
                  ),
              ],
            ),

            const SizedBox(height: 8),

            // Device Name Label
            SizedBox(
              width: 100,
              child: Text(
                alias,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: isSelf
                    ? RelayTypography.body(palette.textPrimary).copyWith(fontWeight: FontWeight.w600)
                    : isSelected
                    ? RelayTypography.body(palette.textPrimary).copyWith(fontWeight: FontWeight.w600)
                    : RelayTypography.caption(palette.textSecondary),
              ),
            ),

            // Subtitle Status / Detail
            if (isSelf)
              Text(
                'This Device',
                style: RelayTypography.caption(palette.accent).copyWith(fontSize: 11, fontWeight: FontWeight.w500),
              )
            else if (detail != null && detail!.isNotEmpty)
              Text(
                isCompatibilityPeer ? 'LocalSend' : detail!,
                style: RelayTypography.caption(
                  isCompatibilityPeer ? palette.textTertiary : (isSelected ? palette.accentSoft : palette.textTertiary),
                ).copyWith(fontSize: 11),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBadge(RelayPalette palette) {
    if (isSelf) {
      return Container(
        width: 14,
        height: 14,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: palette.accent,
          border: Border.all(color: palette.canvas, width: 2),
        ),
        child: Center(
          child: Container(
            width: 4,
            height: 4,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
            ),
          ),
        ),
      );
    }

    if (continuityConnected) {
      return Container(
        width: 14,
        height: 14,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: palette.success,
          border: Border.all(color: palette.canvas, width: 2),
        ),
        child: const Center(
          child: Icon(Icons.link, size: 8, color: Colors.black),
        ),
      );
    }

    if (isCompatibilityPeer) {
      return Container(
        width: 14,
        height: 14,
        decoration: BoxDecoration(
          color: palette.elevated,
          shape: BoxShape.circle,
          border: Border.all(color: palette.hairline),
        ),
        child: Icon(
          Icons.near_me_outlined,
          size: 8,
          color: palette.textTertiary,
        ),
      );
    }

    if (isVerifiedRelay) {
      return Container(
        width: 14,
        height: 14,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: palette.accent.withValues(alpha: 0.85),
          border: Border.all(color: palette.canvas, width: 2),
        ),
        child: const Center(
          child: Icon(Icons.check, size: 8, color: Colors.white),
        ),
      );
    }

    return const SizedBox.shrink();
  }

  Widget _buildBatteryIndicator(RelayPalette palette, RelayBatteryVm battery) {
    final pct = battery.percentage ?? 0;
    final Color batteryColor = pct < 20
        ? palette.error
        : pct < 50
        ? palette.warning
        : palette.success;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
      decoration: BoxDecoration(
        color: palette.elevated,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: palette.hairline, width: 0.8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 4,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            battery.isCharging ? Icons.bolt_rounded : Icons.battery_std_rounded,
            size: 10,
            color: batteryColor,
          ),
          const SizedBox(width: 2),
          Text(
            '$pct%',
            style: TextStyle(
              color: palette.textSecondary,
              fontSize: 9,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
