import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart' show immutable;

// The maths of the living blobs (UX-126): springs for touch, a seeded
// low-frequency noise for the outline, parallax offsets of the depth layers,
// the visibility cap, and the timing of life, entrance and the sound pulse.
// Pure functions of their arguments, so they are unit-tested without
// widgets and every blob of the same id moves the same way.

/// Position and velocity of a one-dimensional spring.
@immutable
class SpringState {
  const SpringState(this.value, [this.velocity = 0]);

  final double value;
  final double velocity;

  @override
  bool operator ==(Object other) =>
      other is SpringState &&
      other.value == value &&
      other.velocity == velocity;

  @override
  int get hashCode => Object.hash(value, velocity);

  @override
  String toString() => 'SpringState($value, $velocity)';
}

/// Stiffness and damping of a unit-mass spring.
@immutable
class SpringParams {
  const SpringParams({required this.stiffness, required this.damping});

  final double stiffness;
  final double damping;
}

/// The springs of the living blobs.
abstract final class LivingSprings {
  /// A touch: about half a second to settle, with one small wobble (damping
  /// ratio about 0.5, so it overshoots by about 15 %).
  static const touch = SpringParams(stiffness: 180, damping: 14);
}

/// The longest step a frame may advance a spring: a stalled or suspended
/// app resumes from where it was instead of jumping.
const _maxSpringStep = 1 / 20;

/// Steps of at most this length keep the integration stable.
const _springSubstep = 1 / 120;

/// Advances [state] toward [target] by [dt] seconds (semi-implicit Euler in
/// small substeps; [dt] is clamped to a twentieth of a second).
SpringState springStep(
  SpringState state,
  double target,
  double dt,
  SpringParams params,
) {
  if (dt <= 0) return state;
  var remaining = math.min(dt, _maxSpringStep);
  var value = state.value;
  var velocity = state.velocity;
  while (remaining > 1e-9) {
    final h = math.min(remaining, _springSubstep);
    final force =
        -params.stiffness * (value - target) - params.damping * velocity;
    velocity += force * h;
    value += velocity * h;
    remaining -= h;
  }
  return SpringState(value, velocity);
}

/// True when [state] is close enough to [target] and slow enough to stop.
bool springSettled(SpringState state, double target, {double epsilon = 1e-3}) =>
    (state.value - target).abs() < epsilon && state.velocity.abs() < epsilon;

/// A stable, non-negative 31-bit seed from an id (32-bit FNV-1a), unlike
/// `String.hashCode`, which Dart does not promise to keep between runs.
int stableSeed(String id) {
  var hash = 0x811c9dc5;
  for (final unit in id.codeUnits) {
    hash = ((hash ^ unit) * 0x01000193) & 0xffffffff;
  }
  return hash & 0x7fffffff;
}

/// One slow wave of the morph: wave number, weight, phase, speed (rad/s),
/// and the speed and phase of its slow swell.
typedef _Wave = (int, double, double, double, double, double);

final _waveCache = <int, List<_Wave>>{};

List<_Wave> _morphWaves(int seed) => _waveCache.putIfAbsent(seed, () {
  if (_waveCache.length > 256) _waveCache.clear();
  final random = math.Random(seed);
  double between(double a, double b) => a + (b - a) * random.nextDouble();
  double sign() => random.nextBool() ? 1 : -1;
  return [
    for (final k in const [2, 3, 4])
      (
        k,
        between(.6, 1) / k,
        between(0, 2 * math.pi),
        sign() * between(.25, .55),
        between(.12, .3),
        between(0, 2 * math.pi),
      ),
  ];
});

/// Seeded low-frequency noise on a closed outline: [u] is the position along
/// it (0..1, period 1) and [time] is in seconds. Three slow waves travel
/// around the outline, each at its own speed and swelling on its own; the
/// result is in -1..1 and moves less than a hundredth of its range per frame.
double morphNoise(int seed, double u, double time) {
  final waves = _morphWaves(seed);
  var sum = 0.0;
  var weights = 0.0;
  for (final (k, weight, phase, speed, swellSpeed, swellPhase) in waves) {
    final swell = .7 + .3 * math.sin(swellSpeed * time + swellPhase);
    sum +=
        weight * swell * math.sin(2 * math.pi * k * u + phase + speed * time);
    weights += weight;
  }
  return weights == 0 ? 0 : (sum / weights).clamp(-1.0, 1.0);
}

/// The translucent depth layers inside a living blob.
abstract final class LivingDepth {
  /// How many gradient layers drift inside a blob.
  static const layers = 3;

  /// Drift speed of [layer] in rad/s: the front layer is the fastest.
  static double driftSpeed(int layer) => const [.21, .13, .08][layer];

  /// How far [layer] follows a touch, as a share of its reach.
  static double leanShare(int layer) => const [.5, .3, .15][layer];

  /// How far [layer] drifts on its own, as a share of its reach.
  static const driftShare = .45;
}

/// Where depth [layer] sits, as an offset within a unit reach: a slow orbit
/// at its own speed (zero at time zero) plus a share of [lean] (a touch
/// direction, clamped to unit length). Deeper layers drift slower and follow
/// the touch less, which reads as parallax.
Offset parallaxOffset({
  required int layer,
  required double time,
  required int seed,
  required Offset lean,
}) {
  final speed = LivingDepth.driftSpeed(layer);
  final phase = (seed % 360) * math.pi / 180 + layer * 2.1;
  final angle = speed * time + phase;
  // The radius opens from zero, so a blob at rest has its layers centred.
  final radius = LivingDepth.driftShare * (1 - math.cos(speed * .7 * time)) / 2;
  final drift = Offset(math.cos(angle), math.sin(angle)) * radius;
  final reach = lean.distance;
  final unitLean = reach > 1 ? lean / reach : lean;
  return drift + unitLean * LivingDepth.leanShare(layer);
}

/// The blobs that may animate: those that overlap [viewport], the most
/// visible first (then the higher ones), at most [cap]. The others stay
/// still, so a long gallery costs no more than a short one.
Set<T> chooseAnimated<T>(
  Map<T, Rect> rects,
  Rect viewport, {
  required int cap,
}) {
  final visible = <(T, double, double)>[];
  for (final MapEntry(:key, :value) in rects.entries) {
    final overlap = value.intersect(viewport);
    if (overlap.width <= 0 || overlap.height <= 0) continue;
    visible.add((key, overlap.width * overlap.height, value.top));
  }
  visible.sort((a, b) {
    final byArea = b.$2.compareTo(a.$2);
    return byArea != 0 ? byArea : a.$3.compareTo(b.$3);
  });
  return {for (final (key, _, _) in visible.take(cap)) key};
}

/// How long the blobs live after they appear or are touched, and how long
/// they take to come to rest.
abstract final class LivingTiming {
  /// Full motion after the gallery opens, a touch or a scroll.
  static const awake = Duration(seconds: 10);

  /// The slow fade of the motion back to the still shape.
  static const settle = Duration(milliseconds: 1600);

  /// Delay between the entrances of neighbouring cards.
  static const stagger = Duration(milliseconds: 60);

  /// Length of one card's entrance.
  static const entrance = Duration(milliseconds: 420);

  /// Cards after this many enter together (a long list does not wait).
  static const maxStaggered = 8;
}

double _smooth(double t) => t * t * (3 - 2 * t);

/// The amount of motion [sinceWake] after the last wake: 1 while awake,
/// then a smooth fall to 0 over [LivingTiming.settle]. At 0 the blob is
/// exactly its still shape, so stopping never jumps.
double lifeAmount(Duration sinceWake) {
  final over = sinceWake - LivingTiming.awake;
  if (over <= Duration.zero) return 1;
  final t = over.inMicroseconds / LivingTiming.settle.inMicroseconds;
  if (t >= 1) return 0;
  return 1 - _smooth(t);
}

/// 0..1 progress of card [index]'s entrance [sinceOpen] after the gallery
/// opened, eased out; each card starts [LivingTiming.stagger] after the one
/// before it.
double entranceProgress(int index, Duration sinceOpen) {
  final start =
      LivingTiming.stagger * math.min(index, LivingTiming.maxStaggered);
  final t =
      (sinceOpen - start).inMicroseconds / LivingTiming.entrance.inMicroseconds;
  if (t <= 0) return 0;
  if (t >= 1) return 1;
  final inverse = 1 - t;
  return 1 - inverse * inverse * inverse;
}

/// The instrument's envelope as a 0..1 level [elapsed] after a hit: it rises
/// over [attack] and falls linearly over [decay] (the mist pulse).
double envelopeLevel(Duration elapsed, Duration attack, Duration decay) {
  final a = math.max(attack.inMicroseconds, 1);
  final d = math.max(decay.inMicroseconds, 1);
  final e = elapsed.inMicroseconds;
  if (e <= 0 || e >= a + d) return 0;
  if (e < a) return e / a;
  return 1 - (e - a) / d;
}
