import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Centralized, high-efficiency ambient scheduler providing synchronized, out-of-phase
/// phase signals to all ambient visual components via discrete subscription-driven cadence channels.
///
/// Long-lived ambient effects only schedule frames at their required cadence:
/// - Fast ambient (Hero perimeter): ~30 FPS (~33ms)
/// - Medium ambient (Hero atmosphere, breath, icon): ~12 FPS (~83ms)
/// - Status ambient (Connection dot, dock indicator): ~10 FPS (~100ms)
/// - Slow ambient (Global ambient background): ~6 FPS (~166ms)
///
/// Channels with 0 active subscribers do not run timers.
/// When animations are disabled, in reduced-motion mode, or when the app is paused,
/// all timers are canceled immediately (zero active wakeups).
class RelayAmbientClock extends StatefulWidget {
  final Widget child;
  final bool animationsEnabled;

  const RelayAmbientClock({
    super.key,
    required this.child,
    this.animationsEnabled = true,
  });

  /// Finds the ambient clock notifier in the widget tree, if present, without creating a widget dependency.
  static RelayAmbientClockNotifier? maybeOf(BuildContext context) {
    final inherited = context.getInheritedWidgetOfExactType<_InheritedAmbientClock>();
    return inherited?.notifier;
  }

  @override
  State<RelayAmbientClock> createState() => _RelayAmbientClockState();
}

class _AmbientChannel extends ChangeNotifier {
  final Duration interval;
  Timer? _timer;
  int _listenerCount = 0;
  bool _enabled = true;

  _AmbientChannel(this.interval);

  void setEnabled(bool enabled) {
    if (_enabled == enabled) return;
    _enabled = enabled;
    _syncTimer();
  }

  @override
  void addListener(VoidCallback listener) {
    super.addListener(listener);
    _listenerCount++;
    _syncTimer();
  }

  @override
  void removeListener(VoidCallback listener) {
    super.removeListener(listener);
    _listenerCount = math.max(0, _listenerCount - 1);
    _syncTimer();
  }

  void _syncTimer() {
    if (_enabled && _listenerCount > 0) {
      if (_timer == null || !_timer!.isActive) {
        _timer = Timer.periodic(interval, _onTick);
      }
    } else {
      _timer?.cancel();
      _timer = null;
    }
  }

  void _onTick(Timer timer) {
    if (!_enabled || _listenerCount == 0) {
      _timer?.cancel();
      _timer = null;
      return;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timer = null;
    super.dispose();
  }
}

class RelayAmbientClockNotifier extends ChangeNotifier {
  final Stopwatch _stopwatch = Stopwatch()..start();
  bool _enabled = true;

  // Channels with independent cadences
  late final _AmbientChannel _fastClock = _AmbientChannel(const Duration(milliseconds: 33)); // 30 FPS
  late final _AmbientChannel _mediumClock = _AmbientChannel(const Duration(milliseconds: 83)); // 12 FPS
  late final _AmbientChannel _statusClock = _AmbientChannel(const Duration(milliseconds: 100)); // 10 FPS
  late final _AmbientChannel _backgroundClock = _AmbientChannel(const Duration(milliseconds: 166)); // 6 FPS

  Listenable get fastClock => _fastClock;
  Listenable get cadenceClock => _mediumClock;
  Listenable get mediumClock => _mediumClock;
  Listenable get statusClock => _statusClock;
  Listenable get backgroundClock => _backgroundClock;

  /// Monotonic wall-clock seconds since clock start.
  double get elapsedSeconds => _stopwatch.elapsedMicroseconds / 1000000.0;

  /// Fast phase (~5.2s cycle for Hero breath, halo, connection dot).
  double get phaseFast => (elapsedSeconds / 5.2) % 1.0;

  /// Medium phase (~7.5s cycle for Hero perimeter sweep).
  double get phaseMedium => (elapsedSeconds / 7.5) % 1.0;

  /// Slow phase (~14.0s cycle for Hero atmospheric drift).
  double get phaseSlow => (elapsedSeconds / 14.0) % 1.0;

  /// Background phase (~24.0s cycle for ambient background field drift).
  double get phaseBackground => (elapsedSeconds / 24.0) % 1.0;

  /// Sine oscillation for breath/halo (0.0 to 1.0).
  double get breathValue => 0.5 + 0.5 * math.sin(phaseFast * 2 * math.pi);

  void setEnabled(bool enabled) {
    if (_enabled == enabled) return;
    _enabled = enabled;
    _fastClock.setEnabled(enabled);
    _mediumClock.setEnabled(enabled);
    _statusClock.setEnabled(enabled);
    _backgroundClock.setEnabled(enabled);
    if (enabled && !_stopwatch.isRunning) {
      _stopwatch.start();
    } else if (!enabled && _stopwatch.isRunning) {
      _stopwatch.stop();
    }
  }

  @override
  void dispose() {
    _fastClock.dispose();
    _mediumClock.dispose();
    _statusClock.dispose();
    _backgroundClock.dispose();
    _stopwatch.stop();
    super.dispose();
  }
}

class _InheritedAmbientClock extends InheritedWidget {
  final RelayAmbientClockNotifier notifier;

  const _InheritedAmbientClock({
    required this.notifier,
    required super.child,
  });

  @override
  bool updateShouldNotify(covariant _InheritedAmbientClock oldWidget) => false;
}

class _RelayAmbientClockState extends State<RelayAmbientClock> with WidgetsBindingObserver {
  late final RelayAmbientClockNotifier _notifier;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _notifier = RelayAmbientClockNotifier();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(covariant RelayAmbientClock oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _sync();
  }

  bool get _motionAllowed =>
      widget.animationsEnabled && !(MediaQuery.maybeDisableAnimationsOf(context) ?? false) && TickerMode.valuesOf(context).enabled;

  void _sync() {
    _notifier.setEnabled(_motionAllowed);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _notifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _InheritedAmbientClock(
      notifier: _notifier,
      child: widget.child,
    );
  }
}
