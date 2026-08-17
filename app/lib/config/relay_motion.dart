import 'package:flutter/animation.dart';

abstract final class RelayMotion {
  static const deviceTransition = Duration(milliseconds: 180);
  static const presenceTransition = Duration(milliseconds: 240);
  static const progressTransition = Duration(milliseconds: 260);
  static const curve = Curves.easeOutCubic;

  static Duration gated(Duration duration, bool enabled) => enabled ? duration : Duration.zero;
}
