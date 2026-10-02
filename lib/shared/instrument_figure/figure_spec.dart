import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'package:synesterra_core/synesterra_core.dart';

/// The figure of a sound: a closed curve `z(t) = sum s_n * e^(i * n * t)` for
/// `t` in 0..2π, where `s_n` is the amplitude of harmonic n after EQ.
///
/// A pure tone is a circle. Harmonic n adds n-1 lobes around the fundamental's
/// circle (the fourth gives three), so a bright spectrum is spiky and a dark
/// one smooth. The curve is scaled so its farthest point is
/// at distance 1 from the centre, and its last point equals its first.
List<Offset> buildFigure(Instrument instrument, {int points = 720}) {
  final shaped = shapedHarmonics(instrument);
  final curve = <Offset>[];
  var farthest = 0.0;
  for (var i = 0; i <= points; i++) {
    final t = 2 * math.pi * (i % points) / points;
    var x = 0.0;
    var y = 0.0;
    for (var n = 0; n < shaped.length; n++) {
      x += shaped[n] * math.cos((n + 1) * t);
      y += shaped[n] * math.sin((n + 1) * t);
    }
    final point = Offset(x, y);
    curve.add(point);
    farthest = math.max(farthest, point.distance);
  }
  if (farthest <= 0) return curve;
  return [for (final point in curve) point / farthest];
}

/// One period of the waveform `sum s_n * sin(n * t)`, scaled to -1..1. Its
/// last value equals its first.
List<double> buildPeriodWave(Instrument instrument, {int points = 256}) {
  final shaped = shapedHarmonics(instrument);
  final wave = <double>[];
  var largest = 0.0;
  for (var i = 0; i <= points; i++) {
    final t = 2 * math.pi * (i % points) / points;
    var y = 0.0;
    for (var n = 0; n < shaped.length; n++) {
      y += shaped[n] * math.sin((n + 1) * t);
    }
    wave.add(y);
    largest = math.max(largest, y.abs());
  }
  if (largest <= 0) return wave;
  return [for (final y in wave) y / largest];
}
