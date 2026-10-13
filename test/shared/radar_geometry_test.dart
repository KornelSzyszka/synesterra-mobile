import 'dart:math';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:synesterra/shared/instrument_radar/radar_geometry.dart';

/// Normalizes an angle to -pi..pi.
double wrap(double a) => atan2(sin(a), cos(a));

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

  group('WheelLayout', () {
    test('rings sit inside each other: ticks, names, then the chart', () {
      const size = Size(380, 380);
      final layout = WheelLayout.of(size);
      expect(layout.centre, const Offset(190, 190));
      expect(layout.outer, lessThanOrEqualTo(190));
      expect(layout.ringInner, lessThan(layout.outer));
      expect(
        layout.nameRadius + wheelNameHeight / 2,
        lessThan(layout.ringInner),
      );
      // A handle at the edge (value 1) and its glow stay clear of the names.
      expect(
        layout.reach + radarHandleTarget / 4,
        lessThan(layout.nameRadius - wheelNameHeight / 2),
      );
      expect(layout.reach, greaterThan(120), reason: 'big on a phone');
    });

    test('a non-square field uses its shorter side, centred', () {
      final layout = WheelLayout.of(const Size(400, 300));
      expect(layout.centre, const Offset(200, 150));
      expect(layout.outer, lessThanOrEqualTo(150));
    });

    test('is never negative', () {
      final layout = WheelLayout.of(const Size(20, 20));
      expect(layout.reach, 0);
      expect(WheelLayout.of(Size.zero).reach, 0);
    });

    test(
      'a bare wheel (a thumbnail) has no ring and nearly fills the field',
      () {
        final layout = WheelLayout.bare(const Size(56, 56));
        expect(layout.reach, closeTo(28 - wheelBareMargin, 1e-9));
        expect(layout.hasRing, isFalse);
        expect(WheelLayout.of(const Size(380, 380)).hasRing, isTrue);
      },
    );
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

    test('only the component along the spoke counts', () {
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
    });

    test('a slanted spoke projects along its own direction', () {
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

    test('radarPoint and radarProject are inverse on the spoke', () {
      for (final count in [3, 6, 8, 10]) {
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

  group('radarHitAxis', () {
    const size = Size(300, 300);
    const centre = Offset(150, 150);
    const reach = 100.0;
    final values = [0.5, 0.5, 0.5, 0.5, 0.5, 0.5];

    test('a touch on a handle picks its spoke', () {
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

    test('a touch along a spoke picks it even away from the handle', () {
      expect(
        radarHitAxis(centre + const Offset(4, -95), values, size, reach),
        0,
      );
    });

    test('a touch far from every spoke picks nothing', () {
      final between = (radarAxisDirection(0, 6) + radarAxisDirection(1, 6));
      final far = centre + between / between.distance * 145;
      expect(radarHitAxis(far, values, size, reach), isNull);
    });

    test('handles stacked at the centre are all candidates', () {
      final zero = [0.0, 0.0, 0.0, 0.5, 0.5, 0.5];
      expect(radarHandlesAt(centre, zero, size, reach), [0, 1, 2]);
      expect(
        radarHandlesAt(radarPoint(4, 6, 0.5, size, reach), zero, size, reach),
        [4],
      );
    });

    test('the first move picks the stacked spoke it points along', () {
      for (var i = 0; i < 6; i++) {
        final move = radarAxisDirection(i, 6) * 12 + const Offset(1, -1);
        expect(radarPickByDirection([0, 1, 2, 3, 4, 5], move, 6), i);
      }
      // Only candidates count.
      expect(radarPickByDirection([1, 2], radarAxisDirection(5, 6) * 10, 6), 1);
    });
  });

  group('ranks: ten steps, E to A', () {
    test('values snap to the nearest of ten steps from the centre', () {
      expect(rankSteps, 10);
      expect(rankStep(0), 0);
      expect(rankStep(1), 10);
      expect(rankStep(0.5), 5);
      expect(rankStep(0.53), 5);
      expect(rankStep(0.57), 6);
      expect(rankStep(-3), 0);
      expect(rankStep(7), 10);
      expect(rankStep(double.nan), 0);
      for (var step = 0; step <= 10; step++) {
        expect(snapToRank(step / 10 + 0.04), closeTo(step / 10, 1e-12));
        expect(snapToRank(step / 10 - 0.04), closeTo(step / 10, 1e-12));
        expect(rankValue(step), closeTo(step / 10, 1e-12));
      }
    });

    test('five ranks, each in two half-steps; E near the centre, A at the '
        'edge', () {
      expect(rankLetters, ['E', 'D', 'C', 'B', 'A']);
      expect(
        [for (var s = 0; s <= 10; s++) rankName(s)],
        ['none', 'E', 'E+', 'D', 'D+', 'C', 'C+', 'B', 'B+', 'A', 'A+'],
      );
      expect(rankSpoken(6), 'C plus');
      expect(rankSpoken(9), 'A');
      expect(rankSpoken(0), 'none');
      expect(rankName(5), 'C', reason: 'the middle of the chart is rank C');
    });

    test('the letters sit on the full steps, the half-steps between', () {
      expect(
        [
          for (var s = 1; s <= 10; s++)
            if (isLetterStep(s)) s,
        ],
        [1, 3, 5, 7, 9],
      );
      expect(rankLetterStep(0), 1, reason: 'E');
      expect(rankLetterStep(4), 9, reason: 'A');
    });

    test('a step moves to the neighbouring step and stays in range', () {
      expect(rankStepFrom(0.5, 1), closeTo(0.6, 1e-12));
      expect(rankStepFrom(0.5, -1), closeTo(0.4, 1e-12));
      expect(rankStepFrom(0.53, 1), closeTo(0.6, 1e-12));
      expect(rankStepFrom(1, 1), 1);
      expect(rankStepFrom(0, -1), 0);
    });

    test(
      'the graduated spoke ticks: one per step, the letter steps marked',
      () {
        final ticks = spokeTicks();
        expect(ticks, hasLength(10));
        for (final (i, tick) in ticks.indexed) {
          expect(tick.step, i + 1);
          expect(tick.value, closeTo((i + 1) / 10, 1e-12));
          expect(tick.letter, isLetterStep(i + 1));
        }
      },
    );

    test('rank letters sit beside the first spoke, E nearest the centre', () {
      const size = Size(300, 300);
      const reach = 100.0;
      final points = [
        for (var r = 0; r < 5; r++)
          rankLetterPoint(rankLetterStep(r), 6, size, reach),
      ];
      for (var r = 0; r < 5; r++) {
        // Beside the upward spoke (to its right), at the letter's height.
        expect(points[r].dx, greaterThan(150 + 6));
        expect(
          points[r].dy,
          closeTo(150 - rankValue(rankLetterStep(r)) * reach, 1e-9),
        );
        if (r > 0) expect(points[r].dy, lessThan(points[r - 1].dy));
      }
    });
  });

  group('the outer ring: tick blocks', () {
    test('evenly spaced, the dividers midway between the names', () {
      for (var count = 3; count <= 10; count++) {
        final ticks = ringTicks(count);
        expect(ticks, hasLength(count * ringTicksPerSector));
        final step = 2 * pi / ticks.length;
        for (var i = 1; i < ticks.length; i++) {
          expect(
            ticks[i].angle - ticks[i - 1].angle,
            closeTo(step, 1e-9),
            reason: '$count',
          );
        }
        final dividers = [
          for (final t in ticks)
            if (t.kind == RingTickKind.divider) t.angle,
        ];
        expect(dividers, hasLength(count));
        final marks = [
          for (final t in ticks)
            if (t.kind == RingTickKind.axis) t.angle,
        ];
        expect(marks, hasLength(count));
        for (var i = 0; i < count; i++) {
          expect(
            wrap(dividers[i] - radarAxisAngle(i, count)),
            closeTo(-pi / count, 1e-9),
          );
          expect(wrap(marks[i] - radarAxisAngle(i, count)), closeTo(0, 1e-9));
        }
      }
    });
  });

  group('names written along the ring', () {
    const centre = Offset(200, 200);
    const radius = 160.0;
    // Rough uppercase advances (11.5 px tracked), 8 to 11 px per letter.
    List<double> advances(String text) => [
      for (final c in text.split('')) 'MW'.contains(c) ? 11.0 : 8.5,
    ];
    const names = [
      'BRIGHTNESS',
      'FULLNESS',
      'WARMTH',
      'AIR',
      'SOFTNESS',
      'LENGTH',
      'SPARKLE',
      'GRIT',
      'SHIMMER',
      'DEPTH',
    ];

    test('the bottom half reads left to right, upright', () {
      for (final angle in [pi / 2, pi / 3, 2 * pi / 3]) {
        expect(ringReadsReversed(angle), isTrue, reason: '$angle');
        final glyphs = ringGlyphs(
          centre: centre,
          radius: radius,
          angle: angle,
          advances: advances('WARMTH'),
        );
        expect(glyphs.first.position.dx, lessThan(glyphs.last.position.dx));
        // Upright at the very bottom: the glyph's top faces the centre.
        if (angle == pi / 2) {
          for (final g in glyphs) {
            expect(wrap(g.rotation), closeTo(0, 0.2));
          }
        }
      }
    });

    test('the top half reads left to right, upright', () {
      for (final angle in [-pi / 2, -pi / 3, -2 * pi / 3]) {
        expect(ringReadsReversed(angle), isFalse);
        final glyphs = ringGlyphs(
          centre: centre,
          radius: radius,
          angle: angle,
          advances: advances('BRIGHTNESS'),
        );
        expect(glyphs.first.position.dx, lessThan(glyphs.last.position.dx));
        if (angle == -pi / 2) {
          for (final g in glyphs) {
            expect(wrap(g.rotation), closeTo(0, 0.3));
          }
        }
      }
    });

    test('glyphs sit on the ring, centred on the name angle, in reading '
        'order with their own widths', () {
      final widths = advances('LENGTH');
      for (final angle in [-pi / 2, pi / 2, 0.4, 2.6]) {
        final glyphs = ringGlyphs(
          centre: centre,
          radius: radius,
          angle: angle,
          advances: widths,
        );
        expect(glyphs, hasLength(widths.length));
        for (final g in glyphs) {
          expect((g.position - centre).distance, closeTo(radius, 1e-9));
        }
        // The middle of the name is at the name's angle.
        final first = glyphs.first.angle;
        final last = glyphs.last.angle;
        final mid = wrap(
          (first + last) / 2 + (widths.last - widths.first) / 4 / radius,
        );
        expect(wrap(mid - angle), closeTo(0, 1e-9));
        // Neighbouring glyphs are half their widths apart along the arc.
        for (var i = 1; i < glyphs.length; i++) {
          expect(
            wrap(glyphs[i].angle - glyphs[i - 1].angle).abs() * radius,
            closeTo((widths[i] + widths[i - 1]) / 2, 1e-9),
          );
        }
      }
    });

    test('for N = 3..10 the names never overlap once scaled to fit', () {
      for (var count = 3; count <= 10; count++) {
        final labels = [for (var i = 0; i < count; i++) advances(names[i])];
        final scale = ringLabelScale(labels, radius: radius, count: count);
        expect(scale, inInclusiveRange(ringMinLabelScale, 1));
        final spans = [
          for (final l in labels) ringLabelSpan(l, radius) * scale,
        ];
        for (var i = 0; i < count; i++) {
          final j = (i + 1) % count;
          final gap = 2 * pi / count - spans[i] / 2 - spans[j] / 2;
          expect(
            gap,
            greaterThanOrEqualTo(ringLabelGap / radius - 1e-9),
            reason: '$count names, between ${names[i]} and ${names[j]}',
          );
        }
      }
    });

    test('short names on few spokes keep full size', () {
      expect(
        ringLabelScale(
          [advances('AIR'), advances('GRIT'), advances('DEPTH')],
          radius: radius,
          count: 3,
        ),
        1,
      );
    });
  });
}
