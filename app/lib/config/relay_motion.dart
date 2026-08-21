import 'package:flutter/animation.dart';

abstract final class RelayMotion {
  /// Pointer feedback: a surface reacting to being hovered.
  static const hover = Duration(milliseconds: 120);

  /// The moment a control is pressed, before it settles back.
  static const press = Duration(milliseconds: 90);

  /// A value or a surface changing state in place.
  static const state = Duration(milliseconds: 180);

  /// Moving between destinations inside the shell.
  static const navigation = Duration(milliseconds: 220);

  /// Relay Arrival / Departure: a device entering or leaving the scene.
  static const arrival = Duration(milliseconds: 300);
  static const departure = Duration(milliseconds: 220);

  /// Relay Focus: selecting a device or changing the primary context.
  static const focus = Duration(milliseconds: 280);

  /// Relay Pulse: a small event acknowledgement, never an idle loop.
  static const pulse = Duration(milliseconds: 160);

  /// Relay Stream: progress that is backed by a real transfer.
  static const stream = Duration(milliseconds: 240);

  static const deviceTransition = arrival;
  static const presenceTransition = focus;
  static const progressTransition = stream;
  static const curve = Curves.easeOutCubic;
  static const focusCurve = Curves.easeInOutCubic;

  static Duration gated(Duration duration, bool enabled) => enabled ? duration : Duration.zero;
}
