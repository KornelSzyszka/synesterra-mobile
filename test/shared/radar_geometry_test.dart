import 'dart:math';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:synesterra/shared/instrument_radar/radar_geometry.dart';

void main() {
  group('radarAxisAngle', () {
    test('the first axis points straight up and the axes turn clockwise', () {
      expect(radarAxisAngle(0, 6), closeTo(-pi / 2, 1e-12));
      expect(radarAxisAngle(1, 6), closeTo(-pi / 2 + pi / 3, 1e-12));
      expect(radarAxisAngle(3, 6), closeTo(pi / 2, 1e-12));
    });

    test('works for any number of axes from three up', () {
      for (final count in [3, 4, 5, 6, 7, 9, 12]) {
        for (var i = 0; i < count; i++) {
          expect(
            radarAxisAngle(i, count),
            closeTo(-pi / 2 + 2 * pi * i / count, 1e-12),
            reason: '$i of $count',
          );
        }
        final step = radarAxisAngle(1, count) - radarAxisAngle(0, count);
        expect(step, closeTo(2 * pi / count, 1e-12));
      }
    });

    test('rejects fewer than three axes and an index out of range', () {
      expect(() => radarAxisAngle(0, 2), throwsArgumentError);
      expect(() => radarAxisAngle(-1, 6), throwsArgumentError);
      expect(() => radarAxisAngle(6, 6), throwsArgumentError);
    });

    test('directions are unit vectors', () {
      for (var i = 0; i < 5; i++) {
        expect(radarAxisDirection(i, 5).distance, closeTo(1, 1e-12));
      }
      final up = radarAxisDirection(0, 4);
      expect(up.dx, closeTo(0, 1e-12));
      expect(up.dy, closeTo(-1, 1e-12));
    });
  });

  group('radarProject', () {
    const size = Size(300, 300);
    const centre = Offset(150, 150);
    const reach = 100.0;

    test('a touch on the axis gives its distance from the centre', () {
      expect(
        radarProject(centre + const Offset(0, -50), 0, 4, size, reach),
        closeTo(0.5, 1e-12),
      );
      expect(
        radarProject(centre + const Offset(25, 0), 1, 4, size, reach),
        closeTo(0.25, 1e-12),
      );
    });

    test('only the component along the axis counts', () {
      // Axis 0 points up; moving sideways changes nothing.
      for (final dx in [-80.0, -10.0, 0.0, 33.0, 120.0]) {
        expect(
          radarProject(centre + Offset(dx, -70), 0, 6, size, reach),
          closeTo(0.7, 1e-12),
          reason: 'dx $dx',
        );
      }
    });

    test('clamps to 0..1', () {
      expect(radarProject(centre + const Offset(0, 40), 0, 6, size, reach), 0);
      expect(
        radarProject(centre + const Offset(0, -900), 0, 6, size, reach),
        1,
      );
      expect(radarProject(centre, 2, 6, size, reach), 0);
    });

    test('a slanted axis projects along its own direction', () {
      final direction = radarAxisDirection(1, 6);
      final onAxis = centre + direction * 60;
      final normal = Offset(-direction.dy, direction.dx);
      expect(
        radarProject(onAxis + normal * 30, 1, 6, size, reach),
        closeTo(0.6, 1e-9),
      );
    });

    test('is safe with no reach and with non-finite touches', () {
      expect(radarProject(centre, 0, 6, size, 0), 0);
      expect(radarProject(const Offset(double.nan, 3), 0, 6, size, reach), 0);
      expect(
        radarProject(const Offset(150, double.negativeInfinity), 0, 6, size, 1),
        1,
      );
    });

    test('radarPoint and radarProject are inverse on the axis', () {
      for (final count in [3, 6, 8]) {
        for (var i = 0; i < count; i++) {
          for (final value in [0.0, 0.2, 0.5, 0.93, 1.0]) {
            final at = radarPoint(i, count, value, size, reach);
            expect(
              radarProject(at, i, count, size, reach),
              closeTo(value, 1e-9),
            );
          }
        }
      }
    });
  });

  group('radarReach', () {
    test('leaves room for the labels and is positive on a phone', () {
      const size = Size(380, 330);
      final reach = radarReach(size, 6);
      expect(reach, greaterThan(100));
      for (var i = 0; i < 6; i++) {
        final box = radarLabelRect(i, 6, size, reach);
        expect(
          (Offset.zero & size).inflate(1e-9).contains(box.topLeft),
          isTrue,
        );
        expect(
          (Offset.zero & size).inflate(1e-9).contains(box.bottomRight),
          isTrue,
        );
        // A label never covers the end of its own axis.
        expect(box.contains(radarPoint(i, 6, 1, size, reach)), isFalse);
      }
    });

    test('is never negative', () {
      expect(radarReach(const Size(20, 20), 6), 0);
      expect(radarReach(Size.zero, 3), 0);
    });

    test('without labels it is half the shorter side minus the margin', () {
      expect(
        radarReach(const Size(100, 80), 5, label: Size.zero, gap: 0, margin: 4),
        36,
      );
    });
  });

  group('radarHitAxis', () {
    const size = Size(300, 300);
    const centre = Offset(150, 150);
    const reach = 100.0;
    final values = [0.5, 0.5, 0.5, 0.5, 0.5, 0.5];

    test('a touch on a handle picks its axis', () {
      for (var i = 0; i < 6; i++) {
        final at = radarPoint(i, 6, values[i], size, reach);
        expect(radarHitAxis(at, values, size, reach), i);
        expect(radarHitAxis(at + const Offset(10, 10), values, size, reach), i);
      }
    });

    test('the handle target is at least 48 dp across', () {
      expect(radarHandleTarget, greaterThanOrEqualTo(48));
      final at = radarPoint(0, 6, 0.8, size, reach);
      expect(
        radarHitAxis(
          at + const Offset(23, 0),
          [0.8, 0.1, 0.1, 0.1, 0.1, 0.1],
          size,
          reach,
        ),
        0,
      );
    });

    test('a touch along an axis line picks it even away from the handle', () {
      expect(
        radarHitAxis(centre + const Offset(4, -95), values, size, reach),
        0,
      );
    });

    test('the nearest handle wins when two are close', () {
      final crowded = [0.05, 0.05, 0.05, 0.05, 0.05, 0.05];
      final at = radarPoint(2, 6, 0.05, size, reach);
      expect(radarHitAxis(at, crowded, size, reach), 2);
    });

    test('a touch far from every axis picks nothing', () {
      // Between axes 0 and 1, outside the field.
      final between = (radarAxisDirection(0, 6) + radarAxisDirection(1, 6));
      final far = centre + between / between.distance * 145;
      expect(radarHitAxis(far, values, size, reach), isNull);
    });
  });

  group('steps and words', () {
    test('a step moves a tenth and stays in range', () {
      expect(radarStep(0.5, 1), closeTo(0.6, 1e-12));
      expect(radarStep(0.5, -1), closeTo(0.4, 1e-12));
      expect(radarStep(0.95, 1), 1);
      expect(radarStep(0.03, -1), 0);
    });

    test('a step lands on whole tenths so values stay readable', () {
      expect(radarStep(0.53, 1), closeTo(0.6, 1e-12));
      expect(radarStep(0.53, -1), closeTo(0.5, 1e-12));
      expect(radarStep(0.6, 1), closeTo(0.7, 1e-12));
    });

    test('a level is spoken as a whole percent', () {
      expect(radarPercent(0), 0);
      expect(radarPercent(0.5), 50);
      expect(radarPercent(0.126), 13);
      expect(radarPercent(1), 100);
    });
  });
}
