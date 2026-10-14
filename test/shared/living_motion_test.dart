import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:synesterra/shared/living_blobs/living_motion.dart';

void main() {
  group('spring', () {
    test('settles on its target with an overshoot, then rests', () {
      var state = const SpringState(0);
      var peak = 0.0;
      for (var i = 0; i < 240; i++) {
        state = springStep(state, 1, 1 / 60, LivingSprings.touch);
        peak = math.max(peak, state.value);
      }
      expect(peak, greaterThan(1), reason: 'it should wobble past the target');
      expect(peak, lessThan(1.3), reason: 'but only a little');
      expect(state.value, closeTo(1, 1e-3));
      expect(springSettled(state, 1), isTrue);
    });

    test('a long stall does not explode', () {
      final state = springStep(
        const SpringState(0),
        1,
        5, // a five-second frame (the app was suspended)
        LivingSprings.touch,
      );
      expect(state.value.isFinite, isTrue);
      expect(state.value.abs(), lessThan(2));
    });

    test('a zero step changes nothing, at rest it is settled', () {
      const state = SpringState(.4, .2);
      expect(springStep(state, 1, 0, LivingSprings.touch), state);
      expect(springSettled(const SpringState(0), 0), isTrue);
      expect(springSettled(const SpringState(0, .5), 0), isFalse);
    });
  });

  group('morph noise', () {
    test('is stable per seed and differs between seeds', () {
      expect(morphNoise(7, .3, 12.5), morphNoise(7, .3, 12.5));
      var differs = false;
      for (var i = 0; i < 16; i++) {
        if ((morphNoise(7, i / 16, 3) - morphNoise(8, i / 16, 3)).abs() > .05) {
          differs = true;
        }
      }
      expect(differs, isTrue);
    });

    test('stays within -1..1 and closes the outline (period 1 in u)', () {
      for (var seed = 0; seed < 20; seed++) {
        for (var i = 0; i <= 64; i++) {
          final t = seed * 3.7 + i * .4;
          final value = morphNoise(seed, i / 64, t);
          expect(value.abs(), lessThanOrEqualTo(1));
          expect(morphNoise(seed, 0, t), closeTo(morphNoise(seed, 1, t), 1e-9));
        }
      }
    });

    test('is low-frequency: it changes slowly with time', () {
      // At 60 fps a point moves at most a few hundredths of its range.
      for (var i = 0; i < 100; i++) {
        final t = i * .37;
        final step = (morphNoise(3, .2, t + 1 / 60) - morphNoise(3, .2, t))
            .abs();
        expect(step, lessThan(.03));
      }
    });

    test('stable seeds come from the id, not from String.hashCode', () {
      expect(stableSeed('factory-bell'), stableSeed('factory-bell'));
      expect(stableSeed('factory-bell'), isNot(stableSeed('factory-wood')));
      expect(stableSeed('x'), inInclusiveRange(0, 0x7fffffff));
    });
  });

  group('parallax', () {
    test('rests at zero without time and touch', () {
      for (var layer = 0; layer < LivingDepth.layers; layer++) {
        expect(
          parallaxOffset(layer: layer, time: 0, seed: 3, lean: Offset.zero),
          Offset.zero,
        );
      }
    });

    test('deeper layers drift slower and follow the touch less', () {
      const lean = Offset(1, 0);
      final shifts = [
        for (var layer = 0; layer < LivingDepth.layers; layer++)
          parallaxOffset(layer: layer, time: 0, seed: 3, lean: lean).dx,
      ];
      for (var i = 1; i < shifts.length; i++) {
        expect(shifts[i], lessThan(shifts[i - 1]));
      }
      final speeds = [
        for (var layer = 0; layer < LivingDepth.layers; layer++)
          LivingDepth.driftSpeed(layer),
      ];
      for (var i = 1; i < speeds.length; i++) {
        expect(speeds[i], lessThan(speeds[i - 1]));
      }
    });

    test('never leaves the unit reach', () {
      for (var i = 0; i < 400; i++) {
        final offset = parallaxOffset(
          layer: i % LivingDepth.layers,
          time: i * 1.3,
          seed: i,
          lean: const Offset(1, 1),
        );
        expect(offset.distance, lessThanOrEqualTo(1.0001));
      }
    });
  });

  group('visibility cap', () {
    const viewport = Rect.fromLTWH(0, 0, 400, 800);

    test('animates only visible blobs, at most the cap', () {
      final rects = {
        for (var i = 0; i < 12; i++)
          i: Rect.fromLTWH(0, i * 100.0 - 50, 400, 90),
      };
      final chosen = chooseAnimated(rects, viewport, cap: 6);
      expect(chosen, hasLength(6));
      // Blob 0 is half above the viewport, 9 and later are below it.
      expect(chosen.any((i) => i >= 9), isFalse);
    });

    test('prefers the most visible ones, then the higher ones', () {
      final rects = {
        'half': const Rect.fromLTWH(0, -45, 400, 90),
        'full-low': const Rect.fromLTWH(0, 500, 400, 90),
        'full-high': const Rect.fromLTWH(0, 100, 400, 90),
      };
      expect(chooseAnimated(rects, viewport, cap: 2), {
        'full-high',
        'full-low',
      });
      expect(chooseAnimated(rects, viewport, cap: 1), {'full-high'});
    });

    test('an offscreen or empty blob never animates', () {
      final rects = {
        'below': const Rect.fromLTWH(0, 900, 400, 90),
        'beside': const Rect.fromLTWH(500, 10, 400, 90),
        'empty': const Rect.fromLTWH(10, 10, 0, 0),
      };
      expect(chooseAnimated(rects, viewport, cap: 6), isEmpty);
    });
  });

  group('life, entrance and envelope', () {
    test('life is full while awake, then eases to rest', () {
      expect(lifeAmount(Duration.zero), 1);
      expect(lifeAmount(LivingTiming.awake), 1);
      final mid = lifeAmount(LivingTiming.awake + LivingTiming.settle ~/ 2);
      expect(mid, inExclusiveRange(0, 1));
      expect(lifeAmount(LivingTiming.awake + LivingTiming.settle), 0);
      expect(lifeAmount(const Duration(hours: 1)), 0);
    });

    test('the entrance is staggered by index', () {
      const at = Duration(milliseconds: 200);
      final first = entranceProgress(0, at);
      final third = entranceProgress(2, at);
      expect(first, greaterThan(third));
      expect(entranceProgress(0, Duration.zero), 0);
      expect(entranceProgress(5, const Duration(seconds: 3)), 1);
      // Late cards do not wait forever.
      expect(entranceProgress(40, const Duration(seconds: 2)), 1);
    });

    test('the envelope rises over the attack and falls over the decay', () {
      const attack = Duration(milliseconds: 10);
      const decay = Duration(milliseconds: 90);
      expect(envelopeLevel(Duration.zero, attack, decay), 0);
      expect(envelopeLevel(attack, attack, decay), closeTo(1, 1e-9));
      expect(
        envelopeLevel(const Duration(milliseconds: 55), attack, decay),
        closeTo(.5, 1e-9),
      );
      expect(envelopeLevel(attack + decay, attack, decay), 0);
      expect(envelopeLevel(const Duration(seconds: 2), attack, decay), 0);
    });
  });
}
