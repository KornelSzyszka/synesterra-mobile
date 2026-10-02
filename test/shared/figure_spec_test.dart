import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:synesterra/shared/instrument_figure/figure_spec.dart';
import 'package:synesterra_core/synesterra_core.dart';

Instrument recipe({
  double hz = 440,
  List<double> harmonics = const [1],
  InstrumentEq? eq,
}) => Instrument(
  id: 'figure-test',
  name: 'Figure test',
  fundamentalHz: hz,
  harmonics: harmonics,
  attackMs: 2,
  decayMs: 200,
  eq: eq,
);

/// Counts strict local maxima of the distance from the centre around the
/// closed curve, which is the number of lobes.
int lobes(List<Offset> curve) {
  final r = [for (final p in curve.take(curve.length - 1)) p.distance];
  var count = 0;
  for (var i = 0; i < r.length; i++) {
    final before = r[(i - 1 + r.length) % r.length];
    final after = r[(i + 1) % r.length];
    if (r[i] > before && r[i] >= after) count++;
  }
  return count;
}

void main() {
  group('figure', () {
    test('a pure tone is a circle', () {
      final curve = buildFigure(recipe());
      for (final point in curve) {
        expect(point.distance, closeTo(1, 1e-9));
      }
    });

    test('the curve is closed and has points + 1 entries', () {
      final curve = buildFigure(recipe(harmonics: [1, 0.5]), points: 360);
      expect(curve, hasLength(361));
      expect((curve.first - curve.last).distance, lessThan(1e-9));
    });

    test('it is scaled so the farthest point is at distance 1', () {
      final curve = buildFigure(recipe(harmonics: [1, 0.7, 0.3, 0.2]));
      final farthest = curve.map((p) => p.distance).reduce(math.max);
      expect(farthest, closeTo(1, 1e-9));
    });

    test('harmonic n adds n-1 lobes around the circle', () {
      for (final n in [2, 3, 4, 6]) {
        final harmonics = [1.0, ...List.filled(n - 2, 0.0), 0.3];
        expect(
          lobes(buildFigure(recipe(harmonics: harmonics))),
          n - 1,
          reason: 'harmonic $n',
        );
      }
    });

    test('a pure tone has no lobes to count, only a circle', () {
      final r = buildFigure(recipe()).map((p) => p.distance).toList();
      expect(r.reduce(math.max) - r.reduce(math.min), lessThan(1e-9));
    });

    test('each harmonic changes the figure', () {
      final base = buildFigure(recipe(harmonics: [1, 0.4, 0.2]));
      expect(buildFigure(recipe(harmonics: [1, 0.5, 0.2])), isNot(base));
      expect(buildFigure(recipe(harmonics: [1, 0.4, 0.3])), isNot(base));
    });

    test('the EQ changes the figure', () {
      final flat = buildFigure(recipe(hz: 1500, harmonics: [1, 0.6, 0.6]));
      final bright = buildFigure(
        recipe(
          hz: 1500,
          harmonics: [1, 0.6, 0.6],
          eq: InstrumentEq(highDb: 12),
        ),
      );
      expect(bright, isNot(flat));
    });

    test('the same recipe always gives the same curve', () {
      final a = buildFigure(recipe(harmonics: [1, 0.5, 0.25]));
      final b = buildFigure(recipe(harmonics: [1, 0.5, 0.25]));
      expect(a, b);
    });

    test('a recipe whose harmonics are all above Nyquist gives no NaN', () {
      final silent = recipe(hz: 2000, harmonics: [...List.filled(11, 0.0), 1]);
      final curve = buildFigure(silent);
      expect(curve.every((p) => p.dx.isFinite && p.dy.isFinite), isTrue);
    });
  });

  group('period wave', () {
    test('a pure tone is a sine over one period', () {
      final wave = buildPeriodWave(recipe(), points: 128);
      for (var i = 0; i < wave.length; i++) {
        expect(wave[i], closeTo(math.sin(2 * math.pi * i / 128), 1e-9));
      }
    });

    test('it is closed and stays within -1..1 with a peak of 1', () {
      final wave = buildPeriodWave(recipe(harmonics: [1, 0.5, 0.33, 0.25]));
      expect(wave.first, closeTo(wave.last, 1e-9));
      expect(wave.every((y) => y.abs() <= 1 + 1e-9), isTrue);
      expect(wave.map((y) => y.abs()).reduce(math.max), closeTo(1, 1e-9));
    });

    test('more harmonics make the waveform less like a sine', () {
      double distanceFromSine(List<double> harmonics) {
        final wave = buildPeriodWave(recipe(harmonics: harmonics), points: 128);
        var sum = 0.0;
        for (var i = 0; i < wave.length; i++) {
          sum += (wave[i] - math.sin(2 * math.pi * i / 128)).abs();
        }
        return sum;
      }

      expect(
        distanceFromSine([1, 0.6, 0.5, 0.4]),
        greaterThan(distanceFromSine([1, 0.1])),
      );
    });

    test('the same recipe always gives the same wave', () {
      expect(
        buildPeriodWave(recipe(harmonics: [1, 0.5])),
        buildPeriodWave(recipe(harmonics: [1, 0.5])),
      );
    });

    test('a recipe whose harmonics are all above Nyquist gives no NaN', () {
      final silent = recipe(hz: 2000, harmonics: [...List.filled(11, 0.0), 1]);
      expect(buildPeriodWave(silent).every((y) => y.isFinite), isTrue);
    });
  });
}
