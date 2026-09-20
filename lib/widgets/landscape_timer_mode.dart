import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../controllers/app_controller.dart';
import '../ui/ui_helpers.dart';

class LandscapeTimerMode extends StatefulWidget {
  const LandscapeTimerMode({
    super.key,
    required this.controller,
    required this.child,
    this.displayDuration = const Duration(minutes: 2),
    this.blackoutDuration = const Duration(seconds: 5),
  });

  final AppController controller;
  final Widget child;
  final Duration displayDuration;
  final Duration blackoutDuration;

  @override
  State<LandscapeTimerMode> createState() => _LandscapeTimerModeState();
}

class _LandscapeTimerModeState extends State<LandscapeTimerMode> {
  Timer? _burnInTimer;
  bool _active = false;
  bool _blackout = false;
  bool _syncScheduled = false;

  @override
  Widget build(BuildContext context) {
    final shouldBeActive =
        MediaQuery.orientationOf(context) == Orientation.landscape &&
        widget.controller.phase != TimerPhase.idle;
    if (shouldBeActive) _disableDebugBaselineOverlay();
    _scheduleModeSync(shouldBeActive);
    if (!shouldBeActive) return widget.child;
    return ColoredBox(
      key: const Key('landscape-timer-mode'),
      color: Colors.black,
      child: _blackout
          ? const Center(
              child: SizedBox.shrink(key: Key('landscape-timer-blackout')),
            )
          : Padding(
              padding: const EdgeInsets.all(12),
              child: SizedBox.expand(
                child: FittedBox(
                  fit: BoxFit.contain,
                  alignment: Alignment.center,
                  child: Text(
                    formatClock(widget.controller.remainingSeconds),
                    key: const Key('landscape-timer-clock'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 320,
                      fontWeight: FontWeight.w600,
                      height: 1,
                      letterSpacing: 2,
                      decoration: TextDecoration.none,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ),
            ),
    );
  }

  void _disableDebugBaselineOverlay() {
    assert(() {
      debugPaintBaselinesEnabled = false;
      return true;
    }());
  }

  void _scheduleModeSync(bool active) {
    if (_active == active || _syncScheduled) return;
    _syncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncScheduled = false;
      if (!mounted) return;
      _setActive(
        MediaQuery.orientationOf(context) == Orientation.landscape &&
            widget.controller.phase != TimerPhase.idle,
      );
    });
  }

  void _setActive(bool active) {
    if (_active == active) return;
    _active = active;
    _burnInTimer?.cancel();
    _blackout = false;
    unawaited(widget.controller.setKeepScreenOn(active));
    unawaited(
      SystemChrome.setEnabledSystemUIMode(
        active ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
      ),
    );
    if (active) _scheduleBlackout();
  }

  void _scheduleBlackout() {
    _burnInTimer = Timer(widget.displayDuration, () {
      if (!mounted || !_active) return;
      setState(() => _blackout = true);
      _burnInTimer = Timer(widget.blackoutDuration, () {
        if (!mounted || !_active) return;
        setState(() => _blackout = false);
        _scheduleBlackout();
      });
    });
  }

  @override
  void dispose() {
    _burnInTimer?.cancel();
    if (_active) {
      unawaited(widget.controller.setKeepScreenOn(false));
      unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    }
    super.dispose();
  }
}
