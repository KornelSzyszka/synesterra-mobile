import 'dart:math';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:synesterra/features/editor/pad_geometry.dart';
import 'package:synesterra_core/synesterra_core.dart';

void main() {
  const size = Size(300, 300);
  // The disc is centred at (150, 150) with radius 150 - padInset.
  const centre = Offset(150, 150);
  const reach = 150 - padInset;

  group('padPointAt', () {
    test('maps the centre of the field to the centre of the pad', () {
      final p = padPointAt(centre, size);
      expect(p.x, closeTo(0, 1e-9));
      expect(p.y, closeTo(0, 1e-9));
      expect(p.radius, closeTo(0, 1e-9));
    });

    test('x grows to the right and y grows downward', () {
      final p = padPointAt(centre + const Offset(reach / 2, -reach / 2), size);
      expect(p.x, closeTo(0.5, 1e-9));
      expect(p.y, closeTo(-0.5, 1e-9));
    });

    test('the inset circle is the rim of the pad', () {
      expect(
        padPointAt(centre + const Offset(reach, 0), size).radius,
        closeTo(1, 1e-9),
      );
      final left = padPointAt(centre - const Offset(reach, 0), size);
      expect(left.x, closeTo(-1, 1e-9));
      expect(left.y, closeTo(0, 1e-9));
      final bottom = padPointAt(centre + const Offset(0, reach), size);
      expect(bottom.y, closeTo(1, 1e-9));
    });

    test('halfway to the rim is half the strength', () {
      expect(
        padPointAt(centre + const Offset(0, reach / 2), size).radius,
        closeTo(0.5, 1e-9),
      );
    });

    test('a touch outside the disc clamps onto the rim in its direction', () {
      // The corner of the square is outside the disc.
      final corner = padPointAt(const Offset(299, 299), size);
      expect(corner.radius, closeTo(1, 1e-9));
      expect(corner.angle, closeTo(pi / 4, 1e-9));
      final far = padPointAt(const Offset(-5000, 150), size);
      expect(far.x, closeTo(-1, 1e-9));
      expect(far.y, closeTo(0, 1e-9));
      final above = padPointAt(const Offset(150, -5000), size);
      expect(above.angle, closeTo(-pi / 2, 1e-9));
    });

    test('a non-finite offset or an empty field never throws', () {
      expect(
        padPointAt(const Offset(double.nan, double.infinity), size),
        isA<PadPoint>(),
      );
      expect(
        padPointAt(const Offset(double.infinity, double.infinity), size),
        isA<PadPoint>(),
      );
      expect(padPointAt(const Offset(10, 10), Size.zero), PadPoint(0, 0));
    });

    test('a non-square field uses its shorter side', () {
      const wide = Size(400, 200);
      final p = padPointAt(const Offset(400, 100), wide);
      expect(p.x, closeTo(1, 1e-9));
      expect(p.radius, closeTo(1, 1e-9));
    });
  });

  group('padOffsetOf', () {
    test('is the inverse of padPointAt inside the disc', () {
      final p = PadPoint(-0.3, 0.6);
      final back = padPointAt(padOffsetOf(p, size), size);
      expect(back.x, closeTo(-0.3, 1e-9));
      expect(back.y, closeTo(0.6, 1e-9));
    });

    test('draws the centre in the middle of the field', () {
      expect(padOffsetOf(PadPoint(0, 0), size), centre);
    });

    test('keeps the dot fully inside the field all around the rim', () {
      for (var k = 0; k < 36; k++) {
        final dot = padOffsetOf(PadPoint.polar(1, k * pi / 18), size);
        expect(
          dot.dx,
          inInclusiveRange(padInset - 1e-9, 300 - padInset + 1e-9),
        );
        expect(
          dot.dy,
          inInclusiveRange(padInset - 1e-9, 300 - padInset + 1e-9),
        );
        expect((dot - centre).distance, closeTo(reach, 1e-9));
      }
    });
  });

  test('padDiscRadius is half the shorter side minus the inset', () {
    expect(padDiscRadius(size), reach);
    expect(padDiscRadius(const Size(400, 200)), 100 - padInset);
    expect(padDiscRadius(Size.zero), 0);
  });

  group('stepPadPoint', () {
    test('with no point yet, strength starts from the centre at the top', () {
      final p = stepPadPoint(null, dRadius: padStepRadius);
      expect(p.radius, closeTo(padStepRadius, 1e-9));
      expect(p.angle, closeTo(-pi / 2, 1e-9));
    });

    test('with no point yet, turning starts at half strength from the top', () {
      final p = stepPadPoint(null, dAngle: padStepAngle);
      expect(p.radius, closeTo(0.5, 1e-9));
      expect(p.angle, closeTo(-pi / 2 + padStepAngle, 1e-9));
    });

    test('turning keeps the strength and moves the angle', () {
      final from = PadPoint.polar(0.7, 0.3);
      final p = stepPadPoint(from, dAngle: -padStepAngle);
      expect(p.radius, closeTo(0.7, 1e-9));
      expect(p.angle, closeTo(0.3 - padStepAngle, 1e-9));
    });

    test('turning wraps around the circle without throwing', () {
      var p = PadPoint.polar(0.6, pi - 0.01);
      for (var i = 0; i < 30; i++) {
        p = stepPadPoint(p, dAngle: padStepAngle);
        expect(p.radius, closeTo(0.6, 1e-9));
      }
    });

    test('strength keeps the angle and moves the radius', () {
      final from = PadPoint.polar(0.4, 1.0);
      final p = stepPadPoint(from, dRadius: padStepRadius);
      expect(p.radius, closeTo(0.4 + padStepRadius, 1e-9));
      expect(p.angle, closeTo(1.0, 1e-9));
    });

    test('strength clamps at the centre and at the rim', () {
      expect(
        stepPadPoint(PadPoint.polar(1, 2), dRadius: padStepRadius).radius,
        closeTo(1, 1e-9),
      );
      expect(
        stepPadPoint(PadPoint.polar(0.05, 2), dRadius: -padStepRadius).radius,
        0,
      );
    });

    test('turning from the exact centre lifts it to half strength', () {
      final p = stepPadPoint(PadPoint(0, 0), dAngle: padStepAngle);
      expect(p.radius, closeTo(0.5, 1e-9));
    });
  });

  group('padPercent', () {
    test('rounds a radius to a whole percent', () {
      expect(padPercent(0.504), 50);
      expect(padPercent(1), 100);
      expect(padPercent(0), 0);
    });
  });

  group('padCharacterName', () {
    test('names the anchor closest in angle', () {
      for (final anchor in padAnchors) {
        expect(padCharacterName(anchor.point), anchor.name);
        expect(
          padCharacterName(PadPoint.polar(0.4, anchor.angle + 0.1)),
          anchor.name,
        );
      }
    });

    test('works across the angular seam', () {
      expect(padCharacterName(PadPoint.polar(1, pi - 0.1)), 'bass');
      expect(padCharacterName(PadPoint.polar(1, -pi + 0.1)), 'warm drone');
    });
  });
}
