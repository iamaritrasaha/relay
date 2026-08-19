import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:relay_app/model/ui/relay_device_vm.dart';

/// Layout coordinates for a device node in the spatial universe.
@immutable
class SpatialNodePosition {
  final Offset offset;
  final double scale;
  final double opacity;
  final double angle;
  final double distance;

  const SpatialNodePosition({
    required this.offset,
    this.scale = 1.0,
    this.opacity = 1.0,
    this.angle = 0.0,
    this.distance = 0.0,
  });
}

/// Controller and deterministic math engine for Relay spatial scene positioning,
/// ambient orbits, and focus transitions.
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

  /// Computes the layout position of the central self node given scene dimensions and focus state.
  static SpatialNodePosition computeSelfPosition({
    required Size sceneSize,
    required double focusProgress,
    required bool hasFocusedDevice,
    required double ambientPhase,
  }) {
    final center = Offset(sceneSize.width / 2, sceneSize.height / 2);

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

  /// Computes layout position for a remote device node given scene dimensions,
  /// ambient oscillation, and focus transition state.
  static SpatialNodePosition computeRemotePosition({
    required RelayDeviceVm device,
    required int indexInRing,
    required int totalInRing,
    required Size sceneSize,
    required double ambientPhase,
    required String? focusedDeviceKey,
    required double focusProgress,
  }) {
    final center = Offset(sceneSize.width / 2, sceneSize.height / 2);
    final sceneRadius = math.min(sceneSize.width, sceneSize.height) / 2;

    final polar = calculatePolarResting(
      device: device,
      indexInRing: indexInRing,
      totalInRing: totalInRing,
      sceneRadius: sceneRadius,
    );

    // Ambient orbital harmonic drift (very slow and calm)
    final hash = _hashKey(device.key);
    final phaseOffset = (hash % 100) / 100.0;
    final driftAngle = math.sin((ambientPhase + phaseOffset) * 2 * math.pi) * 0.035;
    final driftRadius = math.cos((ambientPhase + phaseOffset) * 2 * math.pi) * 3.0;

    final currentAngle = polar.angle + driftAngle;
    final currentRadius = polar.radius + driftRadius;

    final orbitalOffset =
        center +
        Offset(
          currentRadius * math.cos(currentAngle),
          currentRadius * math.sin(currentAngle),
        );

    final isThisFocused = focusedDeviceKey != null && focusedDeviceKey == device.key;
    final hasAnyFocus = focusedDeviceKey != null;

    if (!hasAnyFocus || focusProgress == 0.0) {
      return SpatialNodePosition(
        offset: orbitalOffset,
        scale: 1.0,
        opacity: 1.0,
        angle: currentAngle,
        distance: currentRadius,
      );
    }

    if (isThisFocused) {
      // Animate to paired focus position (right anchor of paired focus line)
      final pairSpacing = math.min(sceneSize.width * 0.24, 90.0);
      final targetFocusOffset = center + Offset(pairSpacing, 0);

      final currentOffset = Offset.lerp(orbitalOffset, targetFocusOffset, focusProgress)!;
      final currentScale = 1.0 + (0.12 * focusProgress);

      return SpatialNodePosition(
        offset: currentOffset,
        scale: currentScale,
        opacity: 1.0,
        angle: currentAngle,
        distance: currentRadius,
      );
    }

    // Unrelated device nodes recede/fade slightly
    final recededScale = 1.0 - (0.15 * focusProgress);
    final recededOpacity = 1.0 - (0.75 * focusProgress);
    // Drift slightly outward while receding
    final recededRadius = currentRadius + (20.0 * focusProgress);
    final recededOffset =
        center +
        Offset(
          recededRadius * math.cos(currentAngle),
          recededRadius * math.sin(currentAngle),
        );

    return SpatialNodePosition(
      offset: Offset.lerp(orbitalOffset, recededOffset, focusProgress)!,
      scale: recededScale,
      opacity: recededOpacity.clamp(0.0, 1.0),
      angle: currentAngle,
      distance: currentRadius,
    );
  }
}
