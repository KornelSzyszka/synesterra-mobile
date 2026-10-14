import 'dart:ui';

import 'package:flutter/foundation.dart';

import 'living_motion.dart';

/// The motion of an instrument's mist behind the stat wheel (UX-126): its
/// lobes drift at their own depths and morph slowly for a while after it
/// appears or is touched, it leans toward the finger dragging a vertex and
/// swells while held (on springs, settling back after the release), and it
/// pulses with the instrument's envelope on every audition.
///
/// It owns no ticker: the wheel calls [tick] from its own while [resting]
/// is false, and paints from [time], [life], [lean], [hold] and [pulse].
class LivingMist extends ChangeNotifier {
  LivingMist();

  double _time = 0;
  Duration _sinceWake = LivingTiming.awake + LivingTiming.settle;
  SpringState _x = const SpringState(0);
  SpringState _y = const SpringState(0);
  SpringState _hold = const SpringState(0);
  Offset _leanTarget = Offset.zero;
  double _holdTarget = 0;
  Duration? _pulseElapsed;
  Duration _attack = Duration.zero;
  Duration _decay = Duration.zero;

  /// Seconds of motion so far.
  double get time => _time;

  /// 0..1: how much the mist drifts and morphs ([lifeAmount]).
  double get life => lifeAmount(_sinceWake);

  /// The lean toward the finger, in wheel reaches (at most unit length).
  Offset get lean => Offset(_x.value, _y.value);

  /// The swell while a vertex is held, about 0..1.
  double get hold => _hold.value;

  /// 0..1: the instrument's envelope since the last audition.
  double get pulse {
    final elapsed = _pulseElapsed;
    return elapsed == null ? 0 : envelopeLevel(elapsed, _attack, _decay);
  }

  bool get _settled =>
      springSettled(_x, _leanTarget.dx) &&
      springSettled(_y, _leanTarget.dy) &&
      springSettled(_hold, _holdTarget);

  /// True when nothing moves: the ticker may stop.
  bool get resting => life == 0 && _settled && _pulseElapsed == null;

  /// Full motion again for [LivingTiming.awake].
  void wake() => _sinceWake = Duration.zero;

  /// A finger holds the wheel at [lean] (in reaches from the centre).
  void touch(Offset lean) {
    final reach = lean.distance;
    _leanTarget = reach > 1 ? lean / reach : lean;
    _holdTarget = 1;
    wake();
  }

  /// The finger lifted (or the drag was cancelled): spring back.
  void release() {
    _leanTarget = Offset.zero;
    _holdTarget = 0;
    wake();
  }

  /// One audition: pulse over [attack] and [decay].
  void pulseWith(Duration attack, Duration decay) {
    _attack = attack;
    _decay = decay;
    _pulseElapsed = Duration.zero;
    wake();
  }

  /// Advances by [step] (one frame) and repaints.
  void tick(Duration step) {
    final dt = step.inMicroseconds / Duration.microsecondsPerSecond;
    _time += dt;
    _sinceWake += step;
    const spring = LivingSprings.touch;
    _x = springStep(_x, _leanTarget.dx, dt, spring);
    _y = springStep(_y, _leanTarget.dy, dt, spring);
    _hold = springStep(_hold, _holdTarget, dt, spring);
    if (_settled) {
      _x = SpringState(_leanTarget.dx);
      _y = SpringState(_leanTarget.dy);
      _hold = SpringState(_holdTarget);
    }
    final elapsed = _pulseElapsed;
    if (elapsed != null) {
      final next = elapsed + step;
      _pulseElapsed = next >= _attack + _decay ? null : next;
    }
    notifyListeners();
  }
}
