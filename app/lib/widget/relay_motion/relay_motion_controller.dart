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

/// Controller and deterministic math engine for Relay spatial scene positioning,
/// ambient orbits, focus transitions, and signature transfer depth mechanics.
class RelaySpatialLayoutEngine {
  /// Base radii for spatial orbital rings (scaled to available canvas size)
  static const double baseInnerRadiusRatio = 0.32;
  static const double baseOuterRadiusRatio = 0.44;

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
        ? (sceneRadius * baseInnerRadiusRatio).clamp(110.0, 145.0)
        : (sceneRadius * baseOuterRadiusRatio).clamp(160.0, 215.0);

    final hash = _hashKey(device.key);
    // Deterministic jitter on radius (+- 6dp)
    final radiusJitter = ((hash % 13) - 6).toDouble();
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
      final transferShift = Offset(-math.min(sceneSize.width * 0.08, 30.0), 0);
      final activeOffset = center + transferShift;

      if (epilogueProgress != null) {
        final t = Curves.easeOutCubic.transform(epilogueProgress.clamp(0.0, 1.0));
        return SpatialNodePosition(
          offset: Offset.lerp(activeOffset, center, t)!,
          scale: 1.05 - (0.05 * t),
          opacity: 1.0,
        );
      }

      return SpatialNodePosition(
        offset: activeOffset,
        scale: 1.05,
        opacity: 1.0,
      );
    }

    if (!hasFocusedDevice || focusProgress == 0.0) {
      // Resting center with tiny ambient harmonic drift
      final driftX = math.sin(ambientPhase * 2 * math.pi) * 1.5;
      final driftY = math.cos(ambientPhase * 2 * math.pi) * 1.5;
      return SpatialNodePosition(
        offset: center + Offset(driftX, driftY),
        scale: 1.0,
        opacity: 1.0,
      );
    }

    // When a device is focused, self node shifts to the left anchor of the paired focus line
    final pairSpacing = math.min(sceneSize.width * 0.24, 90.0);
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
  /// ambient oscillation, focus transition state, active transfer state, and terminal epilogue settlement.
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

    // Ambient orbital harmonic drift (calm resting motion)
    final hash = _hashKey(device.key);
    final phaseOffset = (hash % 100) / 100.0;
    final driftAngle = math.sin((ambientPhase + phaseOffset) * 2 * math.pi) * 0.035;
    final driftRadius = math.cos((ambientPhase + phaseOffset) * 2 * math.pi) * 3.0;

    final restingAngle = polar.angle + driftAngle;
    final restingRadius = polar.radius + driftRadius;

    final restingOffset =
        center +
        Offset(
          restingRadius * math.cos(restingAngle),
          restingRadius * math.sin(restingAngle),
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
      final progressVal = isTerminal ? 1.0 : (transferProgress ?? (ambientPhase % 1.0)).clamp(0.0, 1.0);

      // Signature 3D Perspective Orbit: Elliptical path tilted on Y-axis
      final rx = math.min(sceneSize.width * 0.26, 100.0);
      final ry = rx * 0.62;

      // Real progress drives the orbital angle progression
      final startAngle = polar.angle;
      final currentOrbitalAngle = startAngle + (progressVal * 1.7 * math.pi);

      // Perspective Depth: z-depth is sin(currentOrbitalAngle)
      final zDepth = math.sin(currentOrbitalAngle);
      final isBehind = zDepth < -0.15;

      // Transfer orbit position
      final transferCenter = center + Offset(-math.min(sceneSize.width * 0.08, 30.0), 0);
      final orbitOffset = transferCenter + Offset(rx * math.cos(currentOrbitalAngle), ry * math.sin(currentOrbitalAngle));

      // Perspective Scale & Opacity Modulation
      double depthScale = 1.0 + (0.16 * zDepth); // 0.84x in back, 1.16x in front
      double depthOpacity = isBehind ? 0.80 : 1.0;

      // Smooth approach / exit transition based on progress
      Offset effectiveOffset;
      if (progressVal < 0.10) {
        final t = progressVal / 0.10;
        effectiveOffset = Offset.lerp(restingOffset, orbitOffset, Curves.easeOutCubic.transform(t))!;
      } else if (progressVal > 0.88) {
        final t = (progressVal - 0.88) / 0.12;
        final pairedOffset = transferCenter + Offset(rx * 0.9, 0);
        effectiveOffset = Offset.lerp(orbitOffset, pairedOffset, Curves.easeInOutCubic.transform(t))!;
      } else {
        effectiveOffset = orbitOffset;
      }

      // Epilogue settlement back to resting orbit
      if (epilogueProgress != null) {
        final settleT = Curves.easeOutCubic.transform(epilogueProgress.clamp(0.0, 1.0));
        effectiveOffset = Offset.lerp(effectiveOffset, restingOffset, settleT)!;
        depthScale = Offset.lerp(Offset(depthScale, 0), const Offset(1.0, 0), settleT)!.dx;
        depthOpacity = Offset.lerp(Offset(depthOpacity, 0), const Offset(1.0, 0), settleT)!.dx;
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
      double recededScale = 0.82;
      double recededOpacity = 0.22;
      final recededRadius = restingRadius + 24.0;
      Offset recededOffset =
          center +
          Offset(
            recededRadius * math.cos(restingAngle),
            recededRadius * math.sin(restingAngle),
          );

      if (epilogueProgress != null) {
        final settleT = Curves.easeOutCubic.transform(epilogueProgress.clamp(0.0, 1.0));
        recededScale = 0.82 + (0.18 * settleT);
        recededOpacity = 0.22 + (0.78 * settleT);
        recededOffset = Offset.lerp(recededOffset, restingOffset, settleT)!;
      }

      return SpatialNodePosition(
        offset: recededOffset,
        scale: recededScale,
        opacity: recededOpacity,
        angle: restingAngle,
        distance: recededRadius,
        isBehindCenter: false,
        isTransferring: false,
      );
    }

    // --- Device Focus Handling ---
    final isThisFocused = focusedDeviceKey != null && focusedDeviceKey == device.key;
    final hasAnyFocus = focusedDeviceKey != null;

    if (!hasAnyFocus || focusProgress == 0.0) {
      return SpatialNodePosition(
        offset: restingOffset,
        scale: 1.0,
        opacity: 1.0,
        angle: restingAngle,
        distance: restingRadius,
      );
    }

    if (isThisFocused) {
      // Animate to paired focus position (right anchor of paired focus line)
      final pairSpacing = math.min(sceneSize.width * 0.24, 90.0);
      final targetFocusOffset = center + Offset(pairSpacing, 0);

      final currentOffset = Offset.lerp(restingOffset, targetFocusOffset, focusProgress)!;
      final currentScale = 1.0 + (0.12 * focusProgress);

      return SpatialNodePosition(
        offset: currentOffset,
        scale: currentScale,
        opacity: 1.0,
        angle: restingAngle,
        distance: restingRadius,
      );
    }

    // Unrelated device nodes recede/fade slightly during focus
    final recededScale = 1.0 - (0.15 * focusProgress);
    final recededOpacity = 1.0 - (0.75 * focusProgress);
    final recededRadius = restingRadius + (20.0 * focusProgress);
    final recededOffset =
        center +
        Offset(
          recededRadius * math.cos(restingAngle),
          recededRadius * math.sin(restingAngle),
        );

    return SpatialNodePosition(
      offset: Offset.lerp(restingOffset, recededOffset, focusProgress)!,
      scale: recededScale,
      opacity: recededOpacity.clamp(0.0, 1.0),
      angle: restingAngle,
      distance: restingRadius,
    );
  }
}
