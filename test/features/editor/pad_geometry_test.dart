import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:synesterra/features/editor/pad_geometry.dart';
import 'package:synesterra_core/synesterra_core.dart';

void main() {
  const size = Size(300, 300);

  group('padPointAt', () {
    test('maps the centre of the field to the middle of the pad', () {
      final p = padPointAt(const Offset(150, 150), size);
      expect(p.x, closeTo(0.5, 1e-9));
      expect(p.y, closeTo(0.5, 1e-9));
    });

    test('x grows to the right and y grows downward', () {
      final p = padPointAt(const Offset(225, 75), size);
      expect(p.x, greaterThan(0.5));
      expect(p.y, lessThan(0.5));
    });

    test('the inset edges are the corners of the pad', () {
      final topLeft = padPointAt(const Offset(padInset, padInset), size);
      final bottomRight = padPointAt(
        Offset(300 - padInset, 300 - padInset),
        size,
      );
      expect(topLeft, PadPoint(0, 0));
      expect(bottomRight, PadPoint(1, 1));
    });

    test('a touch outside the field clamps to the nearest edge', () {
      expect(padPointAt(const Offset(-50, -10), size), PadPoint(0, 0));
      expect(padPointAt(const Offset(900, 700), size), PadPoint(1, 1));
      expect(padPointAt(const Offset(150, 5000), size).x, closeTo(0.5, 1e-9));
    });

    test('a non-finite offset or an empty field never throws', () {
      expect(
        padPointAt(const Offset(double.nan, double.infinity), size),
        isA<PadPoint>(),
      );
      expect(padPointAt(const Offset(10, 10), Size.zero), PadPoint(0.5, 0.5));
    });
  });

  group('padOffsetOf', () {
    test('is the inverse of padPointAt inside the field', () {
      final p = PadPoint(0.25, 0.8);
      final back = padPointAt(padOffsetOf(p, size), size);
      expect(back.x, closeTo(0.25, 1e-9));
      expect(back.y, closeTo(0.8, 1e-9));
    });

    test('keeps the dot fully inside the field at the corners', () {
      final corner = padOffsetOf(PadPoint(1, 1), size);
      expect(corner.dx, lessThanOrEqualTo(300 - padInset));
      expect(corner.dy, lessThanOrEqualTo(300 - padInset));
      final origin = padOffsetOf(PadPoint(0, 0), size);
      expect(origin.dx, greaterThanOrEqualTo(padInset));
    });
  });

  group('stepPadPoint', () {
    test('starts from the middle when there is no point yet', () {
      final p = stepPadPoint(null, dx: padStep);
      expect(p.x, closeTo(0.5 + padStep, 1e-9));
      expect(p.y, closeTo(0.5, 1e-9));
    });

    test('moves one axis and keeps the other', () {
      final p = stepPadPoint(PadPoint(0.2, 0.7), dy: -padStep);
      expect(p.x, 0.2);
      expect(p.y, closeTo(0.7 - padStep, 1e-9));
    });

    test('clamps at the edges instead of throwing', () {
      expect(
        stepPadPoint(PadPoint(1, 0), dx: padStep, dy: -padStep),
        PadPoint(1, 0),
      );
      expect(
        stepPadPoint(PadPoint(0, 1), dx: -padStep, dy: padStep),
        PadPoint(0, 1),
      );
    });
  });

  test('padPercent rounds a coordinate to a whole percent', () {
    expect(padPercent(0.504), 50);
    expect(padPercent(1), 100);
    expect(padPercent(0), 0);
  });
}
