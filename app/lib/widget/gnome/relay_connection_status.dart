import 'dart:async';
import 'package:flutter/material.dart';
import 'package:relay_app/config/relay_brand.dart';
import 'package:relay_app/config/relay_motion.dart';
import 'package:relay_app/widget/relay_motion/relay_ambient_clock.dart';

/// Presentation-only connection state for explicit GNOME status displays.
///
/// State derivation stays with the caller. Connected state uses the device's
/// unique palette on the indicator while all labels remain neutral system text.
class RelayConnectionStatus extends StatefulWidget {
  static const ambientPeriod = RelayMotion.ambientGlowCycle;
  static const eventDuration = RelayMotion.connectionEvent;

  final bool connected;
  final String label;
  final RelayDevicePalette? palette;
  final bool animationsEnabled;
  final bool ambient;
  final bool compact;

  const RelayConnectionStatus({
    super.key,
    required this.connected,
    required this.label,
    this.palette,
    required this.animationsEnabled,
    this.ambient = false,
    this.compact = false,
  });

  @override
  State<RelayConnectionStatus> createState() => _RelayConnectionStatusState();
}

class _RelayConnectionStatusState extends State<RelayConnectionStatus> with TickerProviderStateMixin {
  AnimationController? _ambientLocal;
  late final AnimationController _event;
  bool _motionAllowed = false;

  @override
  void initState() {
    super.initState();
    _event = AnimationController(vsync: this, duration: RelayConnectionStatus.eventDuration);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final clock = RelayAmbientClock.maybeOf(context);
    _syncMotion(clock);
  }

  @override
  void didUpdateWidget(covariant RelayConnectionStatus oldWidget) {
    super.didUpdateWidget(oldWidget);
    final clock = RelayAmbientClock.maybeOf(context);
    _syncMotion(clock);
    if (!oldWidget.connected && widget.connected && _motionAllowed) {
      unawaited(_event.forward(from: 0));
    }
  }

  void _syncMotion(RelayAmbientClockNotifier? sharedClock) {
    final allowed = widget.animationsEnabled && !MediaQuery.disableAnimationsOf(context);
    _motionAllowed = allowed;

    if (sharedClock == null) {
      if (allowed && widget.connected && widget.ambient) {
        _ambientLocal ??= AnimationController(vsync: this, duration: RelayConnectionStatus.ambientPeriod);
        if (!_ambientLocal!.isAnimating) {
          unawaited(_ambientLocal!.repeat());
        }
      } else if (_ambientLocal != null) {
        _ambientLocal!.stop();
        _ambientLocal!.value = 0;
      }
    } else if (_ambientLocal != null) {
      _ambientLocal!.stop();
      _ambientLocal!.dispose();
      _ambientLocal = null;
    }

    if (!allowed) {
      _event.stop();
      _event.value = 0;
    }
  }

  @override
  void dispose() {
    _ambientLocal?.dispose();
    _event.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sharedClock = RelayAmbientClock.maybeOf(context);
    final theme = Theme.of(context);
    final fallbackPalette = theme.relayPalette;
    final labelColor = widget.connected ? theme.colorScheme.onSurface : theme.colorScheme.onSurfaceVariant;
    final activeColor = widget.palette?.primary ?? fallbackPalette.accent;
    final secondaryColor = widget.palette?.secondary ?? fallbackPalette.accentSecondary;
    final phaseOffset = widget.palette?.phaseOffset ?? 0.0;
    final Listenable repaint = sharedClock != null
        ? Listenable.merge([sharedClock.statusClock, _event])
        : Listenable.merge([_ambientLocal ?? _event, _event]);

    return Semantics(
      label: widget.label,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          RepaintBoundary(
            child: SizedBox.square(
              dimension: 16,
              child: AnimatedBuilder(
                animation: repaint,
                builder: (context, _) {
                  final rawPhase = sharedClock != null ? sharedClock.phaseFast : (_ambientLocal?.value ?? 0.0);
                  final ambientPhase = (rawPhase + phaseOffset) % 1.0;
                  final ambientOpacity = widget.connected
                      ? (_motionAllowed && widget.ambient
                            ? TweenSequence<double>([
                                TweenSequenceItem(tween: Tween(begin: 0.55, end: 0.95), weight: 1),
                                TweenSequenceItem(tween: Tween(begin: 0.95, end: 0.55), weight: 1),
                              ]).transform(ambientPhase)
                            : 0.75)
                      : 0.45;
                  final eventProgress = Curves.easeOutCubic.transform(_event.value);

                  return Stack(
                    alignment: Alignment.center,
                    children: [
                      // Secondary outer ripple during connection burst
                      Opacity(
                        opacity: _event.isAnimating ? (1 - eventProgress) * 0.7 : 0,
                        child: Transform.scale(
                          scale: 0.5 + eventProgress * 0.9,
                          child: Container(
                            width: 16,
                            height: 16,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: secondaryColor.withValues(alpha: 0.55), width: 1.2),
                            ),
                          ),
                        ),
                      ),
                      // Primary ring
                      Opacity(
                        key: const ValueKey('relay-connection-event-ring'),
                        opacity: _event.isAnimating ? 1 - eventProgress : 0,
                        child: Transform.scale(
                          scale: 0.45 + eventProgress * 0.65,
                          child: Container(
                            width: 14,
                            height: 14,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: activeColor.withValues(alpha: 0.75), width: 1.6),
                            ),
                          ),
                        ),
                      ),
                      // Glowing dot
                      Opacity(
                        opacity: ambientOpacity,
                        child: Container(
                          key: const ValueKey('relay-connection-dot'),
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: widget.connected ? activeColor : theme.colorScheme.onSurfaceVariant,
                            boxShadow: widget.connected && _motionAllowed && widget.ambient
                                ? [
                                    BoxShadow(
                                      color: activeColor.withValues(alpha: 0.4 * ambientOpacity),
                                      blurRadius: 4,
                                      spreadRadius: 0.5,
                                    ),
                                  ]
                                : null,
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
          SizedBox(width: widget.compact ? 5 : 7),
          Flexible(
            child: AnimatedSwitcher(
              duration: _motionAllowed ? RelayMotion.state : Duration.zero,
              switchInCurve: RelayMotion.curve,
              switchOutCurve: RelayMotion.curve,
              child: Text(
                widget.label,
                key: ValueKey('${widget.connected}-${widget.label}'),
                overflow: TextOverflow.ellipsis,
                style: (widget.compact ? theme.textTheme.labelSmall : theme.textTheme.bodyMedium)?.copyWith(
                  color: labelColor,
                  fontWeight: widget.connected ? FontWeight.w500 : FontWeight.normal,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
