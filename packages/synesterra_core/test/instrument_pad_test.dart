import 'dart:math';

import 'package:synesterra_core/synesterra_core.dart';
import 'package:test/test.dart';

Instrument at(double x, double y) =>
    instrumentForPad(PadPoint(x, y), id: 'pad-test', name: 'Pad test');

Instrument polar(double radius, double angle) => instrumentForPad(
  PadPoint.polar(radius, angle),
  id: 'pad-test',
  name: 'Pad test',
);

List<double> padded(List<double> harmonics, int length) => [
  ...harmonics,
  ...List.filled(length - harmonics.length, 0.0),
];

double centroid(Instrument instrument) {
  var weighted = 0.0;
  var total = 0.0;
  for (final (i, amplitude) in instrument.harmonics.indexed) {
    weighted += (i + 1) * amplitude;
    total += amplitude;
  }
  return weighted / total;
}

/// Largest change of any recipe field, each scaled to a comparable 0..1 span.
/// Attack is linear in ms (a 1 ms rounding step is inaudible); decay is
/// compared in the log domain, where it is blended.
double distance(Instrument a, Instrument b) {
  var worst = 0.0;
  for (var i = 0; i < a.harmonics.length; i++) {
    worst = max(worst, (a.harmonics[i] - b.harmonics[i]).abs());
  }
  worst = max(worst, (a.attackMs - b.attackMs).abs() / 500);
  worst = max(worst, (log(a.decayMs) - log(b.decayMs)).abs() / log(250));
  worst = max(worst, (a.eq.lowDb - b.eq.lowDb).abs() / 24);
  worst = max(worst, (a.eq.midDb - b.eq.midDb).abs() / 24);
  worst = max(worst, (a.eq.highDb - b.eq.highDb).abs() / 24);
  return worst;
}

void main() {
  group('PadPoint', () {
    test('accepts the centre, the rim and points inside the disc', () {
      for (final (x, y) in [
        (0.0, 0.0),
        (1.0, 0.0),
        (-1.0, 0.0),
        (0.0, 1.0),
        (0.0, -1.0),
        (0.6, 0.8),
        (-0.5, 0.5),
      ]) {
        final point = PadPoint(x, y);
        expect(point.x, x);
        expect(point.y, y);
      }
    });

    test('rejects points outside the unit disc and non-finite values', () {
      for (final (x, y) in [
        (1.0, 1.0),
        (0.8, 0.8),
        (1.001, 0.0),
        (0.0, -1.001),
        (-0.75, 0.75),
      ]) {
        expect(() => PadPoint(x, y), throwsArgumentError, reason: '($x, $y)');
      }
      for (final bad in [double.nan, double.infinity, -double.infinity]) {
        expect(() => PadPoint(bad, 0), throwsArgumentError);
        expect(() => PadPoint(0, bad), throwsArgumentError);
      }
    });

    test('the error names the offending field or the disc', () {
      expect(
        () => PadPoint(double.nan, 0),
        throwsA(isA<ArgumentError>().having((e) => e.name, 'name', 'x')),
      );
      expect(
        () => PadPoint(0, double.infinity),
        throwsA(isA<ArgumentError>().having((e) => e.name, 'name', 'y')),
      );
      expect(
        () => PadPoint(1, 1),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('unit disc'),
          ),
        ),
      );
    });

    test('has radius and angle; the angle runs from +x towards +y', () {
      expect(PadPoint(0.3, 0).radius, closeTo(0.3, 1e-12));
      expect(PadPoint(0.3, 0).angle, closeTo(0, 1e-12));
      expect(PadPoint(0, 0.5).angle, closeTo(pi / 2, 1e-12));
      expect(PadPoint(0, -0.5).angle, closeTo(-pi / 2, 1e-12));
      expect(PadPoint(-0.5, 0).angle.abs(), closeTo(pi, 1e-12));
      expect(PadPoint(0.6, 0.8).radius, closeTo(1, 1e-12));
    });

    test('the centre has radius 0 and a defined (0) angle', () {
      expect(PadPoint(0, 0).radius, 0);
      expect(PadPoint(0, 0).angle, 0);
    });

    test('polar builds the point, accepts the rim and rejects bad input', () {
      final p = PadPoint.polar(0.5, pi / 2);
      expect(p.x, closeTo(0, 1e-12));
      expect(p.y, closeTo(0.5, 1e-12));
      for (var k = 0; k < 360; k++) {
        expect(PadPoint.polar(1, k * pi / 180), isA<PadPoint>());
      }
      expect(PadPoint.polar(0, 2).radius, 0);
      expect(() => PadPoint.polar(1.01, 0), throwsArgumentError);
      expect(() => PadPoint.polar(-0.1, 0), throwsArgumentError);
      expect(() => PadPoint.polar(double.nan, 0), throwsArgumentError);
      expect(() => PadPoint.polar(0.5, double.infinity), throwsArgumentError);
    });

    test('has value equality', () {
      expect(PadPoint(0.25, 0.5), PadPoint(0.25, 0.5));
      expect(PadPoint(0.25, 0.5).hashCode, PadPoint(0.25, 0.5).hashCode);
      expect(PadPoint(0.25, 0.5), isNot(PadPoint(0.5, 0.25)));
    });
  });

  group('anchors', () {
    test('the five Founder names sit on the rim where the old feel reads', () {
      final byName = {for (final a in padAnchors) a.name: a};
      expect(byName.keys.toSet(), {
        'warm drone',
        'airy pad',
        'bass',
        'guitar',
        'click',
      });
      // y grows downward: top-left is -135 degrees, bottom is +90.
      const degrees = {
        'warm drone': -135.0,
        'airy pad': -45.0,
        'guitar': 45.0,
        'click': 90.0,
        'bass': 135.0,
      };
      for (final entry in degrees.entries) {
        final anchor = byName[entry.key]!;
        expect(anchor.angle, closeTo(entry.value * pi / 180, 1e-12));
        expect(anchor.point.radius, closeTo(1, 1e-12), reason: entry.key);
      }
      // Soft top, hard bottom, dark left, bright right.
      expect(byName['warm drone']!.point.y, lessThan(0));
      expect(byName['airy pad']!.point.y, lessThan(0));
      expect(byName['click']!.point.y, greaterThan(0.9));
      expect(byName['bass']!.point.x, lessThan(0));
      expect(byName['guitar']!.point.x, greaterThan(0));
    });

    test('every anchor is a valid recipe on its own', () {
      for (final anchor in padAnchors) {
        expect(anchor.harmonics.any((h) => h > 0), isTrue, reason: anchor.name);
        expect(
          instrumentForPad(anchor.point, id: 'a', name: 'a'),
          isA<Instrument>(),
        );
      }
    });

    test('each rim anchor reproduces its anchor recipe', () {
      final length = padAnchors.map((a) => a.harmonics.length).reduce(max);
      for (final anchor in padAnchors) {
        final result = instrumentForPad(anchor.point, id: 'a', name: 'a');
        final want = padded(anchor.harmonics, length);
        for (var h = 0; h < length; h++) {
          expect(
            result.harmonics[h],
            closeTo(want[h], 1e-9),
            reason: '${anchor.name} harmonic $h',
          );
        }
        expect(result.attackMs, anchor.attackMs, reason: anchor.name);
        expect(result.decayMs, anchor.decayMs, reason: anchor.name);
        expect(result.eq.lowDb, closeTo(anchor.eq.lowDb, 1e-9));
        expect(result.eq.midDb, closeTo(anchor.eq.midDb, 1e-9));
        expect(result.eq.highDb, closeTo(anchor.eq.highDb, 1e-9));
      }
    });

    test('the anchors keep the intended character relative to each other', () {
      Instrument named(String name) {
        final a = padAnchors.firstWhere((a) => a.name == name);
        return instrumentForPad(a.point, id: 'a', name: 'a');
      }

      expect(named('click').decayMs, lessThan(named('bass').decayMs));
      expect(named('click').decayMs, lessThan(named('guitar').decayMs));
      expect(named('warm drone').attackMs, greaterThan(100));
      expect(named('airy pad').attackMs, greaterThan(100));
      expect(
        centroid(named('airy pad')),
        greaterThan(centroid(named('warm drone'))),
      );
      expect(centroid(named('guitar')), greaterThan(centroid(named('bass'))));
    });
  });

  group('centre', () {
    test('the centre point reproduces the named centre recipe', () {
      final length = max(
        padCenterRecipe.harmonics.length,
        padAnchors.map((a) => a.harmonics.length).reduce(max),
      );
      final result = at(0, 0);
      final want = padded(padCenterRecipe.harmonics, length);
      for (var h = 0; h < length; h++) {
        expect(result.harmonics[h], closeTo(want[h], 1e-9), reason: 'h $h');
      }
      expect(result.attackMs, padCenterRecipe.attackMs);
      expect(result.decayMs, padCenterRecipe.decayMs);
      expect(result.eq.lowDb, closeTo(padCenterRecipe.eq.lowDb, 1e-9));
      expect(result.eq.midDb, closeTo(padCenterRecipe.eq.midDb, 1e-9));
      expect(result.eq.highDb, closeTo(padCenterRecipe.eq.highDb, 1e-9));
    });

    test('by default the centre is the neutral blend of the five anchors', () {
      final length = padAnchors.map((a) => a.harmonics.length).reduce(max);
      final center = padCenterRecipe;
      for (var h = 0; h < length; h++) {
        final mean =
            padAnchors
                .map((a) => h < a.harmonics.length ? a.harmonics[h] : 0.0)
                .reduce((a, b) => a + b) /
            padAnchors.length;
        expect(
          h < center.harmonics.length ? center.harmonics[h] : 0.0,
          closeTo(mean, 1e-9),
          reason: 'harmonic $h',
        );
      }
      final meanLogDecay =
          padAnchors.map((a) => log(a.decayMs)).reduce((a, b) => a + b) /
          padAnchors.length;
      expect(center.decayMs, closeTo(exp(meanLogDecay), 1));
      final meanLow =
          padAnchors.map((a) => a.eq.lowDb).reduce((a, b) => a + b) /
          padAnchors.length;
      expect(center.eq.lowDb, closeTo(meanLow, 1e-9));
    });

    test('the centre is audible and differs from every anchor', () {
      final centre = at(0, 0);
      for (final anchor in padAnchors) {
        final other = instrumentForPad(anchor.point, id: 'a', name: 'a');
        expect(distance(centre, other), greaterThan(0.05), reason: anchor.name);
      }
    });

    test('the angle is irrelevant at the centre', () {
      final centre = at(0, 0);
      for (var k = 0; k < 24; k++) {
        expect(polar(0, k * pi / 12).harmonics, centre.harmonics);
        expect(polar(0, k * pi / 12).decayMs, centre.decayMs);
      }
    });
  });

  group('instrumentForPad', () {
    test('passes id, name and tags through', () {
      final result = instrumentForPad(
        PadPoint(0.3, 0.6),
        id: 'my-sound',
        name: 'My sound',
        tags: ['dark', 'soft'],
      );
      expect(result.id, 'my-sound');
      expect(result.name, 'My sound');
      expect(result.tags, ['dark', 'soft']);
    });

    test('a bad id or name is rejected by the Instrument rules', () {
      expect(
        () => instrumentForPad(PadPoint(0.5, 0.5), id: 'no spaces', name: 'x'),
        throwsArgumentError,
      );
      expect(
        () => instrumentForPad(PadPoint(0.5, 0.5), id: 'ok', name: ' '),
        throwsArgumentError,
      );
    });

    test('is deterministic', () {
      expect(at(0.37, -0.51), at(0.37, -0.51));
    });

    test('a grid over the disc always gives a valid, audible instrument', () {
      var count = 0;
      for (var i = -20; i <= 20; i++) {
        for (var j = -20; j <= 20; j++) {
          final x = i / 20;
          final y = j / 20;
          if (x * x + y * y > 1) continue;
          count++;
          final instrument = at(x, y);
          expect(Instrument.fromJson(instrument.toJson()), instrument);
          final samples = renderInstrument(
            instrument,
            fundamentalHz: 220,
            sampleRate: 48000,
          );
          final peak = samples.fold<double>(0, (m, s) => max(m, s.abs()));
          expect(peak, greaterThan(0.1), reason: '($x, $y)');
        }
      }
      expect(count, greaterThan(300));
    });

    test('a polar grid including the full rim is valid and audible', () {
      for (var ring = 0; ring <= 10; ring++) {
        for (var k = 0; k < 72; k++) {
          final instrument = polar(ring / 10, k * pi / 36);
          expect(Instrument.fromJson(instrument.toJson()), instrument);
          final samples = renderInstrument(
            instrument,
            fundamentalHz: 220,
            sampleRate: 48000,
          );
          final peak = samples.fold<double>(0, (m, s) => max(m, s.abs()));
          expect(peak, greaterThan(0.1), reason: 'r $ring angle $k');
        }
      }
    });

    test('is continuous: a small step changes the recipe a bounded amount', () {
      const step = 0.01;
      var worst = 0.0;
      for (var i = -100; i <= 100; i++) {
        for (var j = -100; j <= 100; j++) {
          final x = i * step;
          final y = j * step;
          if (x * x + y * y > 1) continue;
          final here = at(x, y);
          final right = x + step;
          if (right * right + y * y <= 1) {
            worst = max(worst, distance(here, at(right, y)));
          }
          final below = y + step;
          if (x * x + below * below <= 1) {
            worst = max(worst, distance(here, at(x, below)));
          }
        }
      }
      // Integer rounding of attack and decay is included in this bound.
      expect(worst, lessThan(0.06));
    });

    test('is continuous across the angular seam', () {
      const eps = 1e-6;
      for (final radius in [0.2, 0.5, 1.0]) {
        // The atan2 seam (+-pi, the left side) and the anchor wrap-around.
        for (final seam in [pi, -3 * pi / 4, 0.0, pi / 2]) {
          final before = polar(radius, seam - eps);
          final after = polar(radius, seam + eps);
          expect(
            distance(before, after),
            lessThan(0.01),
            reason: 'r $radius seam $seam',
          );
        }
        expect(
          distance(polar(radius, pi - eps), polar(radius, -pi + eps)),
          lessThan(0.01),
        );
      }
    });

    test('is continuous at the centre, whatever the approach angle', () {
      final centre = at(0, 0);
      for (var k = 0; k < 36; k++) {
        final near = polar(1e-4, k * pi / 18);
        expect(distance(centre, near), lessThan(0.01), reason: 'angle $k');
      }
    });

    test('farther from the centre moves the recipe toward the rim', () {
      for (var k = 0; k < 72; k++) {
        final angle = k * pi / 36;
        final centre = at(0, 0);
        var previous = 0.0;
        List<double>? lastHarmonics;
        for (var step = 0; step <= 100; step++) {
          final now = polar(step / 100, angle);
          final d = distance(centre, now);
          expect(
            d,
            greaterThanOrEqualTo(previous - 1e-9),
            reason: 'angle $k radius ${step / 100}',
          );
          previous = d;
          lastHarmonics = now.harmonics;
        }
        expect(lastHarmonics, polar(1, angle).harmonics);
        // The rim differs from the centre for every angle.
        expect(previous, greaterThan(0.02), reason: 'angle $k');
      }
    });

    test('every recipe field moves one way from the centre to the rim', () {
      for (var k = 0; k < 72; k++) {
        final angle = k * pi / 36;
        final centre = at(0, 0);
        final rim = polar(1, angle);
        for (var h = 0; h < centre.harmonics.length; h++) {
          final sign = (rim.harmonics[h] - centre.harmonics[h]).sign;
          var previous = centre.harmonics[h];
          for (var step = 1; step <= 50; step++) {
            final value = polar(step / 50, angle).harmonics[h];
            expect(
              (value - previous) * sign,
              greaterThanOrEqualTo(-1e-9),
              reason: 'angle $k harmonic $h',
            );
            previous = value;
          }
        }
      }
    });

    test('brightness never decreases from the left rim to the right rim', () {
      var previous = -1.0;
      for (var i = -100; i <= 100; i++) {
        final value = centroid(at(i / 100, 0));
        expect(
          value,
          greaterThanOrEqualTo(previous - 1e-9),
          reason: 'x ${i / 100}',
        );
        previous = value;
      }
      expect(centroid(at(1, 0)), greaterThan(centroid(at(-1, 0)) + 0.5));
    });

    test('brightness also rises left to right on rows off the diameter', () {
      for (final y in [-0.5, -0.25, 0.25, 0.5]) {
        final span = sqrt(1 - y * y);
        expect(
          centroid(at(span, y)),
          greaterThan(centroid(at(-span, y))),
          reason: 'row $y',
        );
      }
    });

    test('toward the bottom the sound gets harder (shorter, sharper)', () {
      final top = polar(1, -pi / 2);
      final bottom = polar(1, pi / 2);
      expect(bottom.decayMs, lessThan(top.decayMs));
      expect(bottom.attackMs, lessThan(top.attackMs));
      for (final x in [-0.6, -0.3, 0.0, 0.3, 0.6]) {
        final reach = sqrt(1 - x * x);
        double mean(Iterable<double> ys, int Function(Instrument) pick) =>
            ys.map((y) => pick(at(x, y))).reduce((a, b) => a + b) / ys.length;
        final upper = [for (var j = 1; j <= 8; j++) -reach * j / 8];
        final lower = [for (var j = 1; j <= 8; j++) reach * j / 8];
        expect(
          mean(lower, (v) => v.decayMs),
          lessThan(mean(upper, (v) => v.decayMs)),
          reason: 'decay, column $x',
        );
        expect(
          mean(lower, (v) => v.attackMs),
          lessThan(mean(upper, (v) => v.attackMs)),
          reason: 'attack, column $x',
        );
      }
    });
  });
}
