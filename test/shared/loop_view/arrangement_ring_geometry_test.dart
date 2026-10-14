import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:synesterra/shared/loop_view/arrangement_ring_geometry.dart';
import 'package:synesterra/shared/loop_view/arrangement_strip.dart';
import 'package:synesterra/shared/loop_view/position_source.dart';

const _turn = 2 * math.pi;
const _eps = 1e-9;

void main() {
  group('ringArcs', () {
    test('one section is the whole ring less one gap, from 12 o clock', () {
      final arcs = ringArcs([3]);
      expect(arcs, hasLength(1));
      expect(arcs.single.start, closeTo(-math.pi / 2 + ringGap / 2, _eps));
      expect(arcs.single.sweep, closeTo(_turn - ringGap, _eps));
    });

    test('spans are proportional to repeats when none is clamped', () {
      final arcs = ringArcs([1, 2, 3]);
      final room = _turn - 3 * ringGap;
      expect(arcs[0].sweep, closeTo(room / 6, _eps));
      expect(arcs[1].sweep, closeTo(room * 2 / 6, _eps));
      expect(arcs[2].sweep, closeTo(room * 3 / 6, _eps));
    });

    test('arcs follow each other clockwise with one gap between them', () {
      final arcs = ringArcs([4, 1, 7, 2]);
      for (var i = 1; i < arcs.length; i++) {
        expect(arcs[i].start, closeTo(arcs[i - 1].end + ringGap, _eps));
      }
      // The last gap closes the ring back at the first arc.
      expect(arcs.last.end + ringGap, closeTo(arcs.first.start + _turn, _eps));
    });

    test('for 1..16 sections of 1..32 repeats: whole ring, minimum sweep, '
        'order kept', () {
      final random = math.Random(123);
      for (var n = 1; n <= 16; n++) {
        for (final repeats in [
          List.filled(n, 1),
          List.filled(n, 32),
          [for (var i = 0; i < n; i++) i == 0 ? 32 : 1],
          [for (var i = 0; i < n; i++) (i * 7) % 32 + 1],
          [for (var i = 0; i < n; i++) random.nextInt(32) + 1],
        ]) {
          final arcs = ringArcs(repeats);
          expect(arcs, hasLength(n));
          final sum = arcs.fold<double>(0, (s, a) => s + a.sweep);
          expect(sum + n * ringGap, closeTo(_turn, 1e-9), reason: '$repeats');
          for (var i = 0; i < n; i++) {
            expect(
              arcs[i].sweep,
              greaterThanOrEqualTo(ringMinSweep - _eps),
              reason: '$repeats',
            );
            for (var j = 0; j < n; j++) {
              if (repeats[i] > repeats[j]) {
                expect(
                  arcs[i].sweep,
                  greaterThanOrEqualTo(arcs[j].sweep - _eps),
                  reason: 'more repeats never get a shorter arc: $repeats',
                );
              }
              if (repeats[i] == repeats[j]) {
                expect(arcs[i].sweep, closeTo(arcs[j].sweep, _eps));
              }
            }
          }
        }
      }
    });

    test('a short section among long ones keeps the minimum sweep', () {
      final arcs = ringArcs([32, 32, 32, 1]);
      expect(arcs[3].sweep, closeTo(ringMinSweep, _eps));
      expect(arcs[0].sweep, closeTo(arcs[1].sweep, _eps));
    });

    test('rejects what an arrangement cannot hold', () {
      expect(() => ringArcs([]), throwsArgumentError);
      expect(() => ringArcs(List.filled(17, 1)), throwsArgumentError);
      expect(() => ringArcs([0]), throwsArgumentError);
      expect(() => ringArcs([33]), throwsArgumentError);
    });

    test('mid and end', () {
      final arc = RingArc(start: 1, sweep: 2);
      expect(arc.mid, 2);
      expect(arc.end, 3);
    });
  });

  group('ringProgress and the playhead', () {
    LoopPosition at(double cyclePosition, int cycleIndex) => LoopPosition(
      playing: true,
      cyclePosition: cyclePosition,
      cycleIndex: cycleIndex,
      sectionIndex: 0,
    );

    test('continuous: the same fill as the strip', () {
      expect(ringProgress(at(.5, 1), 4), closeTo(1.5 / 4, _eps));
      expect(
        ringProgress(at(.25, 2), 3),
        closeTo(sectionProgress(at(.25, 2), 3), _eps),
      );
    });

    test('reduce motion: whole cycles only, so it moves once a cycle', () {
      expect(ringProgress(at(.9, 1), 4, continuous: false), closeTo(.25, _eps));
      expect(ringProgress(at(0, 1), 4, continuous: false), closeTo(.25, _eps));
      expect(ringProgress(at(.1, 3), 4, continuous: false), closeTo(.75, _eps));
    });

    test('stopped is 0', () {
      expect(ringProgress(LoopPosition.stopped, 4), 0);
    });

    test('the playhead walks its own arc', () {
      final arcs = ringArcs([2, 6]);
      expect(ringPlayheadAngle(arcs[1], 0), closeTo(arcs[1].start, _eps));
      expect(ringPlayheadAngle(arcs[1], .5), closeTo(arcs[1].mid, _eps));
      expect(
        ringPlayheadAngle(arcs[1], .999),
        lessThan(arcs[1].end),
        reason: 'half-open: the end of a section is the next one',
      );
      expect(() => ringPlayheadAngle(arcs[0], 1), throwsArgumentError);
      expect(() => ringPlayheadAngle(arcs[0], -.1), throwsArgumentError);
    });
  });

  group('arcFits', () {
    test('compares the arc length at a radius with a length', () {
      final arc = RingArc(start: 0, sweep: .2);
      expect(arcFits(arc, 100, 20), isTrue);
      expect(arcFits(arc, 100, 20.01), isFalse);
    });
  });

  group('loopColorIndexes', () {
    test('one colour per distinct loop, in order of first appearance', () {
      expect(loopColorIndexes(['a', 'b', 'a', 'c', 'b']), [0, 1, 0, 2, 1]);
    });

    test('wraps after the colour count', () {
      final ids = [for (var i = 0; i < 14; i++) 'loop-$i'];
      final colors = loopColorIndexes(ids, colorCount: 12);
      expect(colors[11], 11);
      expect(colors[12], 0);
      expect(colors[13], 1);
    });
  });
}
