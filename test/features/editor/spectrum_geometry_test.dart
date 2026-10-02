import 'package:flutter_test/flutter_test.dart';
import 'package:synesterra/features/editor/spectrum_geometry.dart';

void main() {
  group('barIndexAt', () {
    test('maps a touch to the bar under it', () {
      // 8 bars in 160 px: 20 px each.
      expect(barIndexAt(0, 160, 8), 0);
      expect(barIndexAt(19.9, 160, 8), 0);
      expect(barIndexAt(20, 160, 8), 1);
      expect(barIndexAt(79, 160, 8), 3);
      expect(barIndexAt(159.9, 160, 8), 7);
    });

    test('touches outside the chart go to the nearest bar', () {
      expect(barIndexAt(-30, 160, 8), 0);
      expect(barIndexAt(160, 160, 8), 7);
      expect(barIndexAt(400, 160, 8), 7);
    });

    test('degenerate charts do not crash', () {
      expect(barIndexAt(50, 160, 1), 0);
      expect(barIndexAt(50, 0, 8), 0);
      expect(barIndexAt(50, 160, 0), 0);
    });

    test('covers every bar exactly once across the width', () {
      final hit = {for (var x = 0.0; x < 320; x += 0.5) barIndexAt(x, 320, 32)};
      expect(hit, {for (var i = 0; i < 32; i++) i});
    });
  });

  group('amplitudeAt', () {
    test('the top is 1, the middle is half, the bottom is 0', () {
      expect(amplitudeAt(0, 150), 1);
      expect(amplitudeAt(75, 150), closeTo(0.5, 1e-9));
      expect(amplitudeAt(150, 150), 0);
    });

    test('the bottom 3 percent snaps to silence', () {
      expect(amplitudeAt(150 * 0.97 + 0.01, 150), 0);
      expect(amplitudeAt(150 * 0.9, 150), closeTo(0.1, 1e-9));
    });

    test('touches above or below the chart are clamped', () {
      expect(amplitudeAt(-40, 150), 1);
      expect(amplitudeAt(300, 150), 0);
    });

    test('a chart with no height gives 0', () {
      expect(amplitudeAt(10, 0), 0);
    });
  });

  group('strokeBetween', () {
    test('a stroke inside one bar changes only that bar', () {
      expect(strokeBetween(3, 0.2, 3, 0.7), {3: 0.7});
    });

    test('a fast stroke interpolates the bars it skipped', () {
      final stroke = strokeBetween(0, 0, 4, 1);
      expect(stroke.keys, [0, 1, 2, 3, 4]);
      expect(stroke[0], 0);
      expect(stroke[1], closeTo(0.25, 1e-9));
      expect(stroke[2], closeTo(0.5, 1e-9));
      expect(stroke[4], 1);
    });

    test('a stroke to the left runs from the first touch to the last', () {
      final stroke = strokeBetween(5, 1, 2, 0.4);
      expect(stroke.keys, [5, 4, 3, 2]);
      expect(stroke[5], 1);
      expect(stroke[2], closeTo(0.4, 1e-9));
      expect(stroke[4], closeTo(0.8, 1e-9));
    });

    test('both ends are always included', () {
      final stroke = strokeBetween(1, 0.3, 30, 0.9);
      expect(stroke.length, 30);
      expect(stroke[1], 0.3);
      expect(stroke[30], closeTo(0.9, 1e-9));
    });
  });
}
