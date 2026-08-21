import 'dart:async';
import 'package:flutter/material.dart';
import 'package:relay_app/config/relay_motion.dart';

/// Staggered entrance animation for top-level page sections on initial route/page entry.
///
/// Runs once upon mounting, fading in and rising 6px smoothly. Does not replay
/// when inherited providers update.
class RelaySectionReveal extends StatefulWidget {
  final Widget child;
  final int index;
  final Duration staggerDelay;
  final Duration duration;
  final bool animationsEnabled;

  const RelaySectionReveal({
    super.key,
    required this.child,
    this.index = 0,
    this.staggerDelay = RelayMotion.sectionStagger,
    this.duration = RelayMotion.sectionDuration,
    this.animationsEnabled = true,
  });

  @override
  State<RelaySectionReveal> createState() => _RelaySectionRevealState();
}

class _RelaySectionRevealState extends State<RelaySectionReveal> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
    _fade = CurvedAnimation(parent: _controller, curve: RelayMotion.curve);
    _slide = Tween<Offset>(begin: const Offset(0, 6), end: Offset.zero).animate(_fade);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final allowed = widget.animationsEnabled && !(MediaQuery.maybeDisableAnimationsOf(context) ?? false);
    if (!allowed) {
      _controller.value = 1.0;
    } else if (!_controller.isCompleted && !_controller.isAnimating && _timer == null) {
      final delay = widget.staggerDelay * widget.index;
      if (delay == Duration.zero) {
        unawaited(_controller.forward());
      } else {
        _timer = Timer(delay, () {
          if (mounted) {
            unawaited(_controller.forward());
          }
        });
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final allowed = widget.animationsEnabled && !(MediaQuery.maybeDisableAnimationsOf(context) ?? false);
    if (!allowed || _controller.isCompleted) {
      return widget.child;
    }

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Opacity(
          opacity: _fade.value.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: _slide.value,
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}
