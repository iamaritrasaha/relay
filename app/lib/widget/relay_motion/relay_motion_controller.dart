import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:relay_app/model/ui/relay_device_vm.dart';

/// Layout coordinates and depth metadata for a device node in the spatial universe.
@immutable
class SpatialNodePosition {
  final Offset offset;
  final double scale;
  final double opacity;
  final double angle;
  final double distance;
  final bool isBehindCenter;
  final bool isTransferring;

  const SpatialNodePosition({
    required this.offset,
    this.scale = 1.0,
    this.opacity = 1.0,
    this.angle = 0.0,
    this.distance = 0.0,
    this.isBehindCenter = false,
    this.isTransferring = false,
  });
}

/// Controller and deterministic math engine for the Relay Spatial Scene.
///
/// Resting positions are deliberately still: spatial layout expresses a device's
/// relationship to this desktop, while motion is reserved for arrivals, focus,
/// departures and real transfer progress.
class RelaySpatialLayoutEngine {
  /// Base radii for spatial orbital rings (scaled to available canvas size)
  static const double baseInnerRadiusRatio = 0.42;
  static const double baseOuterRadiusRatio = 0.70;

  /// Deterministic pseudo-random seed from device string key.
  static int _hashKey(String key) {
    int hash = 0x811c9dc5;
    for (int i = 0; i < key.length; i++) {
      hash ^= key.codeUnitAt(i);
      hash = (hash * 0x01000193) & 0x7FFFFFFF;
    }
    return hash;
  }

  /// Calculates deterministic resting polar coordinates (radius, angle) for a device.
  static ({double radius, double angle}) calculatePolarResting({
    required RelayDeviceVm device,
    required int indexInRing,
    required int totalInRing,
    required double sceneRadius,
  }) {
    final isPrimary = device.isAuthenticatedRelay;
    final baseRadius = isPrimary
        ? (sceneRadius * baseInnerRadiusRatio).clamp(115.0, 240.0)
        : (sceneRadius * baseOuterRadiusRatio).clamp(170.0, 360.0);

    final hash = _hashKey(device.key);
    // Deterministic jitter on radius (+- 8dp)
    final radiusJitter = ((hash % 17) - 8).toDouble();
    final effectiveRadius = baseRadius + radiusJitter;

    // Distribute angles evenly around the ring starting from a deterministic base offset
    final baseAngleOffset = ((hash % 100) / 100.0) * (2 * math.pi / math.max(1, totalInRing));
    final angle = (2 * math.pi * indexInRing / math.max(1, totalInRing)) + baseAngleOffset - (math.pi / 2);

    return (radius: effectiveRadius, angle: angle);
  }

  /// Computes the layout position of the central self node given scene dimensions, focus, and transfer state.
  static SpatialNodePosition computeSelfPosition({
    required Size sceneSize,
    required double focusProgress,
    required bool hasFocusedDevice,
    required double ambientPhase,
    bool isTransferActive = false,
    double? epilogueProgress,
  }) {
    final center = Offset(sceneSize.width / 2, sceneSize.height / 2);

    if (isTransferActive) {
      // During active transfer, self node shifts slightly to provide orbital clearance
      final transferShift = Offset(-math.min(sceneSize.width * 0.12, 45.0), 0);
      final activeOffset = center + transferShift;

      if (epilogueProgress != null) {
        final t = Curves.easeOutCubic.transform(epilogueProgress.clamp(0.0, 1.0));
        return SpatialNodePosition(
          offset: Offset.lerp(activeOffset, center, t)!,
          scale: 1.06 - (0.06 * t),
          opacity: 1.0,
        );
      }

      return SpatialNodePosition(
        offset: activeOffset,
        scale: 1.06,
        opacity: 1.0,
      );
    }

    if (!hasFocusedDevice || focusProgress == 0.0) {
      return SpatialNodePosition(
        offset: center,
        scale: 1.0,
        opacity: 1.0,
      );
    }

    // When a device is focused, self node shifts to the left anchor of the paired focus line
    final pairSpacing = math.min(sceneSize.width * 0.28, 110.0);
    final targetOffset = center + Offset(-pairSpacing, 0);

    final currentOffset = Offset.lerp(center, targetOffset, focusProgress)!;
    final currentScale = 1.0 + (0.06 * focusProgress);

    return SpatialNodePosition(
      offset: currentOffset,
      scale: currentScale,
      opacity: 1.0,
    );
  }

  /// Computes layout position, depth, and scale for a remote device node given scene dimensions,
  /// continuous orbital revolution, ambient oscillation, focus transition state, active transfer state,
  /// and terminal epilogue settlement.
  static SpatialNodePosition computeRemotePosition({
    required RelayDeviceVm device,
    required int indexInRing,
    required int totalInRing,
    required Size sceneSize,
    required double ambientPhase,
    required String? focusedDeviceKey,
    required double focusProgress,
    String? transferDeviceKey,
    double? transferProgress,
    RelayDevicePhase? transferPhase,
    double? epilogueProgress,
  }) {
    final center = Offset(sceneSize.width / 2, sceneSize.height / 2);
    final sceneRadius = math.min(sceneSize.width, sceneSize.height) / 2;

    final polar = calculatePolarResting(
      device: device,
      indexInRing: indexInRing,
      totalInRing: totalInRing,
      sceneRadius: sceneRadius,
    );

    // Resting layout must be stable. There is no idle orbit or breathing.
    final continuousAngle = polar.angle;
    final effectiveRestingRadius = polar.radius;
    const isIdleBehind = false;
    const idleDepthScale = 1.0;
    const idleDepthOpacity = 1.0;

    // Slight elliptical perspective compression on the Y axis
    final restingOffset =
        center +
        Offset(
          effectiveRestingRadius * math.cos(continuousAngle),
          (effectiveRestingRadius * 0.76) * math.sin(continuousAngle),
        );

    // --- Active Transfer Orbit Handling ---
    final isThisTransferring =
        (transferDeviceKey != null && transferDeviceKey == device.key) ||
        device.phase == RelayDevicePhase.sending ||
        device.phase == RelayDevicePhase.verifying ||
        (transferDeviceKey == device.key &&
            (transferPhase == RelayDevicePhase.success || transferPhase == RelayDevicePhase.failed || transferPhase == RelayDevicePhase.cancelled));
    final hasAnyTransfer = transferDeviceKey != null || device.phase == RelayDevicePhase.sending;

    if (isThisTransferring) {
      final isTerminal =
          transferPhase == RelayDevicePhase.success || transferPhase == RelayDevicePhase.failed || transferPhase == RelayDevicePhase.cancelled;
      // A stream only moves when a real transfer has supplied progress.
      final progressVal = isTerminal ? 1.0 : (transferProgress ?? 0.0).clamp(0.0, 1.0);

      // Signature 3D Perspective Orbit: Generous elliptical path tilted on Y-axis
      final rx = math.min(sceneSize.width * 0.38, 160.0);
      final ry = rx * 0.58;

      // Real progress drives the orbital angle progression
      final startAngle = continuousAngle;
      final currentOrbitalAngle = startAngle + (progressVal * 1.7 * math.pi);

      // Perspective Depth: z-depth is sin(currentOrbitalAngle)
      final zDepth = math.sin(currentOrbitalAngle);
      final isBehind = zDepth < -0.15;

      // Transfer orbit position
      final transferCenter = center + Offset(-math.min(sceneSize.width * 0.12, 45.0), 0);
      final orbitOffset = transferCenter + Offset(rx * math.cos(currentOrbitalAngle), ry * math.sin(currentOrbitalAngle));

      // Perspective Scale & Opacity Modulation
      double depthScale = 1.04 + (0.18 * zDepth); // 0.86x in back, 1.22x in front
      double depthOpacity = isBehind ? 0.80 : 1.0;

      // Smooth approach / exit transition based on progress
      Offset effectiveOffset;
      if (progressVal < 0.10) {
        final t = progressVal / 0.10;
        effectiveOffset = Offset.lerp(restingOffset, orbitOffset, Curves.easeOutCubic.transform(t))!;
      } else if (progressVal > 0.88) {
        final t = (progressVal - 0.88) / 0.12;
        final pairedOffset = transferCenter + Offset(rx * 0.95, 0);
        effectiveOffset = Offset.lerp(orbitOffset, pairedOffset, Curves.easeInOutCubic.transform(t))!;
      } else {
        effectiveOffset = orbitOffset;
      }

      // Epilogue settlement back to resting orbit
      if (epilogueProgress != null) {
        final settleT = Curves.easeOutCubic.transform(epilogueProgress.clamp(0.0, 1.0));
        effectiveOffset = Offset.lerp(effectiveOffset, restingOffset, settleT)!;
        depthScale = Offset.lerp(Offset(depthScale, 0), Offset(idleDepthScale, 0), settleT)!.dx;
        depthOpacity = Offset.lerp(Offset(depthOpacity, 0), Offset(idleDepthOpacity, 0), settleT)!.dx;
      }

      return SpatialNodePosition(
        offset: effectiveOffset,
        scale: depthScale,
        opacity: depthOpacity,
        angle: currentOrbitalAngle,
        distance: rx,
        isBehindCenter: isBehind,
        isTransferring: true,
      );
    }

    if (hasAnyTransfer) {
      // Unrelated devices recede smoothly while a transfer is active
      double recededScale = 0.76;
      double recededOpacity = 0.18;
      final recededRadius = effectiveRestingRadius + 36.0;
      Offset recededOffset =
          center +
          Offset(
            recededRadius * math.cos(continuousAngle),
            (recededRadius * 0.76) * math.sin(continuousAngle),
          );

      if (epilogueProgress != null) {
        final settleT = Curves.easeOutCubic.transform(epilogueProgress.clamp(0.0, 1.0));
        recededScale = 0.76 + ((idleDepthScale - 0.76) * settleT);
        recededOpacity = 0.18 + ((idleDepthOpacity - 0.18) * settleT);
        recededOffset = Offset.lerp(recededOffset, restingOffset, settleT)!;
      }

      return SpatialNodePosition(
        offset: recededOffset,
        scale: recededScale,
        opacity: recededOpacity,
        angle: continuousAngle,
        distance: recededRadius,
        isBehindCenter: isIdleBehind,
        isTransferring: false,
      );
    }

    // --- Device Focus Handling ---
    final isThisFocused = focusedDeviceKey != null && focusedDeviceKey == device.key;
    final hasAnyFocus = focusedDeviceKey != null;

    if (!hasAnyFocus || focusProgress == 0.0) {
      return SpatialNodePosition(
        offset: restingOffset,
        scale: idleDepthScale,
        opacity: idleDepthOpacity,
        angle: continuousAngle,
        distance: effectiveRestingRadius,
        isBehindCenter: isIdleBehind,
      );
    }

    if (isThisFocused) {
      // Animate to paired focus position (right anchor of paired focus line)
      final pairSpacing = math.min(sceneSize.width * 0.28, 110.0);
      final targetFocusOffset = center + Offset(pairSpacing, 0);

      final currentOffset = Offset.lerp(restingOffset, targetFocusOffset, focusProgress)!;
      final currentScale = 1.0 + (0.14 * focusProgress);

      return SpatialNodePosition(
        offset: currentOffset,
        scale: currentScale,
        opacity: 1.0,
        angle: continuousAngle,
        distance: effectiveRestingRadius,
        isBehindCenter: false,
      );
    }

    // Unrelated device nodes recede/fade slightly during focus
    final recededScale = idleDepthScale - (0.18 * focusProgress);
    final recededOpacity = idleDepthOpacity - (0.78 * focusProgress);
    final recededRadius = effectiveRestingRadius + (24.0 * focusProgress);
    final recededOffset =
        center +
        Offset(
          recededRadius * math.cos(continuousAngle),
          (recededRadius * 0.76) * math.sin(continuousAngle),
        );

    return SpatialNodePosition(
      offset: Offset.lerp(restingOffset, recededOffset, focusProgress)!,
      scale: recededScale,
      opacity: recededOpacity.clamp(0.0, 1.0),
      angle: continuousAngle,
      distance: effectiveRestingRadius,
      isBehindCenter: isIdleBehind,
    );
  }
}
