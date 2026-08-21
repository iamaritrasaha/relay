import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:relay_app/config/relay_brand.dart';
import 'package:relay_app/config/relay_motion.dart';
import 'package:relay_app/model/ui/relay_device_vm.dart';
import 'package:relay_app/pages/relay_home_vm.dart';
import 'package:relay_app/widget/relay/relay_device_silhouette.dart';
import 'package:relay_isolates/model/device.dart';

/// The relationship between this desktop and the one focused device.
///
/// The route is a quiet dashed path at rest. It animates exactly twice: once
/// when a link is established, and — only while a real transfer is in flight —
/// as a packet travelling along it in the transfer's own direction. Nothing
/// here loops on idle, and nothing here is drawn from invented state.
class RelayLinkHero extends StatefulWidget {
  final RelayDeviceVm device;
  final String selfAlias;
  final DeviceType selfDeviceType;
  final bool connected;
  final RelayTransferVm? activeTransfer;
  final bool animationsEnabled;

  const RelayLinkHero({
    super.key,
    required this.device,
    required this.selfAlias,
    required this.selfDeviceType,
    required this.connected,
    this.activeTransfer,
    this.animationsEnabled = true,
  });

  @override
  State<RelayLinkHero> createState() => _RelayLinkHeroState();
}

class _RelayLinkHeroState extends State<RelayLinkHero> with TickerProviderStateMixin {
  late final AnimationController _establish;
  late final AnimationController _stream;

  /// The quiet sign of life on an idle but live link. Only one pulse travels
  /// per cycle, with a long gap after it, so the route never reads as busy.
  late final AnimationController _idle;

  static const Duration _idlePeriod = Duration(milliseconds: 4200);

  @override
  void initState() {
    super.initState();
    _establish = AnimationController(vsync: this, duration: RelayMotion.focus, value: widget.connected ? 1 : 0);
    _stream = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));
    _idle = AnimationController(vsync: this, duration: _idlePeriod);
    _syncStream();
  }

  @override
  void didUpdateWidget(covariant RelayLinkHero oldWidget) {
    super.didUpdateWidget(oldWidget);

    // A link coming up plays the route in once. Losing it retracts the route
    // rather than snapping, so a drop reads as a change and not as a glitch.
    if (widget.connected != oldWidget.connected || widget.device.key != oldWidget.device.key) {
      if (!_motionEnabled) {
        _establish.value = widget.connected ? 1 : 0;
      } else if (widget.connected) {
        unawaited(_establish.forward(from: widget.device.key != oldWidget.device.key ? 0 : _establish.value));
      } else {
        unawaited(_establish.reverse());
      }
    }
    _syncStream();
  }

  bool get _motionEnabled => widget.animationsEnabled && !MediaQuery.disableAnimationsOf(context);

  void _syncStream() {
    final transferring = widget.activeTransfer != null;
    if (transferring && _motionEnabled) {
      if (!_stream.isAnimating) {
        unawaited(_stream.repeat());
      }
    } else if (_stream.isAnimating) {
      _stream.stop();
      _stream.value = 0;
    }

    // The idle pulse stands down the moment a real transfer takes over the
    // route, so the two are never on the line at the same time.
    final idleWanted = widget.connected && !transferring && _motionEnabled;
    if (idleWanted) {
      if (!_idle.isAnimating) {
        unawaited(_idle.repeat());
      }
    } else if (_idle.isAnimating) {
      _idle.stop();
      _idle.value = 0;
    }
  }

  @override
  void dispose() {
    _establish.dispose();
    _stream.dispose();
    _idle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).relayPalette;
    _syncStream();

    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxWidth;
        final compact = available < 400;
        final glyphSize = compact ? 46.0 : 54.0;
        final routeWidth = (available * 0.34).clamp(compact ? 70.0 : 110.0, 260.0);

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: _DevicePlate(
                    size: glyphSize,
                    deviceType: widget.device.deviceType,
                    label: widget.device.alias,
                    active: widget.connected,
                  ),
                ),
                RepaintBoundary(
                  child: AnimatedBuilder(
                    animation: Listenable.merge([_establish, _stream, _idle]),
                    builder: (context, _) => CustomPaint(
                      size: Size(routeWidth, 26),
                      painter: _RelayRoutePainter(
                        progress: _establish.value,
                        packetPhase: widget.activeTransfer == null ? null : _stream.value,
                        idlePhase: widget.activeTransfer == null && widget.connected && _idle.isAnimating ? _idle.value : null,
                        reversed: widget.activeTransfer?.isReceive ?? false,
                        routeColor: palette.textTertiary,
                        liveColor: widget.connected ? palette.textSecondary : palette.textTertiary,
                        packetColor: palette.accent,
                        nodeColor: palette.accentSecondary,
                        connected: widget.connected,
                      ),
                    ),
                  ),
                ),
                Flexible(
                  child: _DevicePlate(
                    size: glyphSize,
                    deviceType: widget.selfDeviceType,
                    label: widget.selfAlias,
                    active: true,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              widget.connected ? 'Secure connection' : 'Not connected',
              style: RelayTypography.caption(widget.connected ? palette.textSecondary : palette.textTertiary, isGnome: true),
            ),
          ],
        );
      },
    );
  }
}

class _DevicePlate extends StatelessWidget {
  final double size;
  final DeviceType deviceType;
  final String label;
  final bool active;

  const _DevicePlate({required this.size, required this.deviceType, required this.label, required this.active});

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).relayPalette;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: palette.softSurface,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: RelayDeviceSilhouette(
            deviceType: deviceType,
            color: active ? palette.textSecondary : palette.textTertiary,
            size: size * 0.54,
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: size + 44,
          child: Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: RelayTypography.caption(active ? palette.textSecondary : palette.textTertiary, isGnome: true),
          ),
        ),
      ],
    );
  }
}

/// Draws the dashed route, the established segment over it, and the packet.
class _RelayRoutePainter extends CustomPainter {
  final double progress;
  final double? packetPhase;
  final double? idlePhase;
  final bool reversed;
  final bool connected;
  final Color routeColor;
  final Color liveColor;
  final Color packetColor;
  final Color nodeColor;

  const _RelayRoutePainter({
    required this.progress,
    required this.packetPhase,
    required this.idlePhase,
    required this.reversed,
    required this.connected,
    required this.routeColor,
    required this.liveColor,
    required this.packetColor,
    required this.nodeColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;

    if (connected) {
      // A live link is one continuous hairline; the establish animation draws
      // it in from the device end rather than flashing it on.
      final line = Paint()
        ..color = liveColor.withValues(alpha: 0.45)
        ..strokeWidth = 1.0
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(Offset(0, y), Offset(size.width * progress, y), line);
    } else {
      // Remote or absent: the route is there but dashed and subdued.
      final dashed = Paint()
        ..color = routeColor.withValues(alpha: 0.4)
        ..strokeWidth = 1.0
        ..strokeCap = StrokeCap.round;
      const dash = 3.0;
      const gap = 5.0;
      for (double x = 0; x < size.width; x += dash + gap) {
        canvas.drawLine(Offset(x, y), Offset((x + dash).clamp(0, size.width), y), dashed);
      }
    }

    // The node sits at the midpoint and only lights up once the link is up.
    final node = Offset(size.width / 2, y);
    if (connected) {
      canvas.drawCircle(node, 3.0 * progress, Paint()..color = nodeColor);
    } else {
      canvas.drawCircle(
        node,
        2.5,
        Paint()
          ..color = routeColor.withValues(alpha: 0.5)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0,
      );
    }

    // Idle sign of life: one small warm pulse per cycle, then a long rest.
    final idle = idlePhase;
    if (idle != null && idle < 0.42) {
      final t = idle / 0.42;
      final envelope = math.sin(math.pi * t);
      canvas.drawCircle(
        Offset(size.width * t, y),
        2.0,
        Paint()..color = packetColor.withValues(alpha: 0.55 * envelope),
      );
    }

    if (packetPhase != null) {
      final t = reversed ? 1 - packetPhase! : packetPhase!;
      final edge = (1 - (2 * packetPhase! - 1).abs()).clamp(0.0, 1.0);
      canvas.drawCircle(
        Offset(size.width * t, y),
        2.5,
        Paint()..color = packetColor.withValues(alpha: 0.3 + 0.7 * edge),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RelayRoutePainter old) =>
      old.progress != progress ||
      old.packetPhase != packetPhase ||
      old.idlePhase != idlePhase ||
      old.reversed != reversed ||
      old.connected != connected ||
      old.routeColor != routeColor ||
      old.liveColor != liveColor ||
      old.packetColor != packetColor ||
      old.nodeColor != nodeColor;
}
