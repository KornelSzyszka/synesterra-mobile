import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:synesterra/shared/loop_view/loop_geometry.dart';

Matcher near(Offset o) =>
    predicate<Offset>((p) => (p - o).distance < 1e-9, 'is within 1e-9 of $o');

void main() {
  group('stepFraction', () {
    test('spreads steps evenly over the cycle', () {
      expect(
        [for (var i = 0; i < 3; i++) stepFraction(i, 3)],
        [0, 1 / 3, 2 / 3],
      );
      expect([for (var i = 0; i < 2; i++) stepFraction(i, 2)], [0, 0.5]);
    });

    test('phase moves every step forward and wraps', () {
      expect(stepFraction(0, 4, phaseSteps: 1), 0.25);
      expect(stepFraction(3, 4, phaseSteps: 1), 0);
    });
  });

  group('playhead', () {
    test('starts at 12 o clock and runs clockwise', () {
      expect(playheadAngle(0), closeTo(-math.pi / 2, 1e-12));
      expect(playheadAngle(0.25), closeTo(0, 1e-12));
      expect(playheadAngle(0.5), closeTo(math.pi / 2, 1e-12));
    });

    test('a full turn lands where the cycle started', () {
      const c = Offset(10, 10);
      expect(
        pointOnCircle(c, 5, playheadAngle(1)),
        near(pointOnCircle(c, 5, playheadAngle(0))),
      );
    });

    test('pointOnCircle places angles on the radius', () {
      const c = Offset(100, 100);
      expect(
        pointOnCircle(c, 50, playheadAngle(0)),
        near(const Offset(100, 50)),
      );
      expect(
        pointOnCircle(c, 50, playheadAngle(0.25)),
        near(const Offset(150, 100)),
      );
    });
  });

  test('ring radii go from the outer ring inwards and stay positive', () {
    final radii = [for (var i = 0; i < 4; i++) ringRadius(i, 4, 100)];
    expect(radii.first, 100);
    for (var i = 1; i < radii.length; i++) {
      expect(radii[i], lessThan(radii[i - 1]));
    }
    expect(radii.last, greaterThan(0));
    expect(ringRadius(0, 1, 100), 100);
  });

  group('polygonVertices', () {
    const c = Offset(0, 0);

    test('3 vertices make a triangle with the first vertex at the top', () {
      final v = polygonVertices(c, 10, 3);
      expect(v, hasLength(3));
      expect(v[0], near(const Offset(0, -10)));
      expect(v[1].dx, closeTo(10 * math.sin(2 * math.pi / 3), 1e-9));
      expect(v[1].dy, closeTo(5, 1e-9));
      expect(v[2].dx, closeTo(-v[1].dx, 1e-9));
    });

    test('2 vertices make a line through the centre', () {
      final v = polygonVertices(c, 10, 2);
      expect(v[0], near(const Offset(0, -10)));
      expect(v[1], near(const Offset(0, 10)));
    });

    test('4 and 5 vertices are on the circle, evenly spaced', () {
      for (final n in [4, 5]) {
        final v = polygonVertices(c, 10, n);
        expect(v, hasLength(n));
        for (var i = 0; i < n; i++) {
          expect(v[i].distance, closeTo(10, 1e-9));
          final next = v[(i + 1) % n];
          expect(
            (next - v[i]).distance,
            closeTo(2 * 10 * math.sin(math.pi / n), 1e-9),
          );
        }
      }
      expect(polygonVertices(c, 10, 4)[1], near(const Offset(10, 0)));
    });

    test('1 vertex is a single point at the top', () {
      expect(polygonVertices(c, 10, 1), [near(const Offset(0, -10))]);
    });
  });

  group('polygonDotPoint', () {
    test('is on a vertex exactly when its step hits (triangle)', () {
      final v = polygonVertices(Offset.zero, 10, 3);
      expect(polygonDotPoint(v, 0), near(v[0]));
      expect(polygonDotPoint(v, 1 / 3), near(v[1]));
      expect(polygonDotPoint(v, 2 / 3), near(v[2]));
    });

    test('moves along an edge in between', () {
      final v = polygonVertices(Offset.zero, 10, 3);
      expect(polygonDotPoint(v, 1 / 6), near((v[0] + v[1]) / 2));
      expect(polygonDotPoint(v, 5 / 6), near((v[2] + v[0]) / 2));
    });

    test('a line goes there and back', () {
      final v = polygonVertices(Offset.zero, 10, 2);
      expect(polygonDotPoint(v, 0.25), near(Offset.zero));
      expect(polygonDotPoint(v, 0.5), near(v[1]));
      expect(polygonDotPoint(v, 0.75), near(Offset.zero));
    });

    test('square and pentagon hit their vertices on step fractions', () {
      for (final n in [4, 5]) {
        final v = polygonVertices(Offset.zero, 10, n);
        for (var i = 0; i < n; i++) {
          expect(polygonDotPoint(v, i / n), near(v[i]));
        }
      }
    });

    test('phase shifts which vertex the dot is on at the cycle start', () {
      final v = polygonVertices(Offset.zero, 10, 4);
      // With phase 1, step 0 hits at fraction 1/4, so the dot is on v[0] then.
      expect(polygonDotPoint(v, 0.25, phaseSteps: 1), near(v[0]));
      expect(polygonDotPoint(v, 0, phaseSteps: 1), near(v[3]));
    });

    test('a single vertex stays put', () {
      final v = polygonVertices(Offset.zero, 10, 1);
      expect(polygonDotPoint(v, 0.7), near(v[0]));
    });
  });

  test('timelineX maps the cycle onto the width', () {
    expect(timelineX(0, 20, 200), 20);
    expect(timelineX(0.5, 20, 200), 120);
    expect(timelineX(0.999, 20, 200), closeTo(219.8, 1e-9));
  });

  group('stepPulse', () {
    test('is 1 at the hit, fades to 0 after the window and is 0 before', () {
      expect(stepPulse(0.5, 0.5), 1);
      expect(stepPulse(0.55, 0.5, window: 0.1), closeTo(0.5, 1e-9));
      expect(stepPulse(0.6, 0.5, window: 0.1), 0);
      expect(stepPulse(0.4, 0.5, window: 0.1), 0);
    });

    test('wraps around the end of the cycle', () {
      expect(stepPulse(0.02, 0.95, window: 0.1), closeTo(0.3, 1e-9));
      expect(stepPulse(0.0, 0.0), 1);
    });
  });
}
