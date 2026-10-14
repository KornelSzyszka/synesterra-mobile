import 'dart:convert';

import 'package:synesterra_core/synesterra_core.dart';
import 'package:test/test.dart';

/// Seeds spread over the whole uint32 range, edges included.
final List<int> seeds = [
  0,
  1,
  2,
  0xffffffff,
  0x7fffffff,
  0x80000000,
  for (var i = 0; i < 1000; i++) (i * 2654435761) & 0xffffffff,
];

const factoryIds = {'factory-wood', 'factory-sine', 'factory-bell'};

/// Pitch classes of the major pentatonic on [root]; the minor pentatonic
/// on a root is the major pentatonic three semitones up, so one test covers
/// both.
Set<int> pentatonic(int root) => {
  for (final degree in const [0, 2, 4, 7, 9]) (root + degree) % 12,
};

void main() {
  group('SeededRandom', () {
    test('is mulberry32: pinned against the reference implementation', () {
      // Values from the public-domain JavaScript reference (Tommy Ettinger).
      for (final (seed, expected) in [
        (0, [1144304738, 1416247, 958946056]),
        (1, [2693262067, 11749833, 2265367787]),
        (0xffffffff, [3850105811, 813802916, 3073704848]),
      ]) {
        final random = SeededRandom(seed);
        expect([
          random.nextUint32(),
          random.nextUint32(),
          random.nextUint32(),
        ], expected);
      }
    });

    test('rejects a seed outside uint32', () {
      expect(() => SeededRandom(-1), throwsArgumentError);
      expect(() => SeededRandom(0x100000000), throwsArgumentError);
    });

    test('nextInt, nextDouble and nextBool stay in range', () {
      final random = SeededRandom(42);
      for (var i = 0; i < 10000; i++) {
        expect(random.nextInt(7), inInclusiveRange(0, 6));
        final d = random.nextDouble();
        expect(d >= 0 && d < 1, isTrue);
        random.nextBool();
      }
      expect(random.nextInt(1), 0);
      expect(() => random.nextInt(0), throwsRangeError);
    });
  });

  group('randomLoopDocument', () {
    test('every seed gives a document the real parser accepts unchanged', () {
      for (final seed in seeds) {
        final document = randomLoopDocument(seed: seed);
        final parsed = parseSessionDocument(document.serialize());
        expect(parsed.isSuccess, isTrue, reason: 'seed $seed ${parsed.errors}');
        expect(parsed.value, document, reason: 'seed $seed');
      }
    });

    test('is deterministic: the same seed gives the same document', () {
      for (final seed in seeds.take(50)) {
        expect(
          randomLoopDocument(seed: seed).serialize(),
          randomLoopDocument(seed: seed).serialize(),
        );
      }
    });

    test('different seeds give different loops', () {
      final loops = {
        for (var seed = 0; seed < 100; seed++)
          randomLoopDocument(seed: seed).serialize(),
      };
      expect(loops.length, 100);
    });

    test('stays inside the musical ranges', () {
      for (final seed in seeds) {
        final document = randomLoopDocument(seed: seed);
        final reason = 'seed $seed';
        final cycle = document.transport.practiceCycleBeats;
        expect(cycle.denominator, 1, reason: reason);
        expect(randomLoopCycleBeats, contains(cycle.numerator), reason: reason);
        expect(
          document.transport.bpm,
          inInclusiveRange(randomLoopMinTempo, randomLoopMaxTempo),
          reason: reason,
        );
        expect(document.transport.bpm, isA<int>(), reason: reason);
        expect(document.randomSeed, seed, reason: reason);
        final layers = document.scenes.first.layers;
        expect(layers.length, inInclusiveRange(2, 4), reason: reason);
        expect(
          [for (final layer in layers) layer.id],
          [for (var i = 1; i <= layers.length; i++) 'layer-$i'],
          reason: reason,
        );
        for (final layer in layers) {
          final steps = layer.pattern.steps;
          expect(layer.pattern.durationBeats, cycle, reason: reason);
          expect(steps.length, inInclusiveRange(2, 16), reason: reason);
          // Step spacing at least 1/16 beat.
          expect(
            cycle.numerator / steps.length,
            greaterThanOrEqualTo(1 / 16),
            reason: reason,
          );
          expect(factoryIds, contains(layer.instrumentId), reason: reason);
          expect(layer.pitch, inInclusiveRange(24, 107), reason: reason);
          expect(layer.phaseSteps, 0, reason: reason);
          expect(layer.swing.grid, 'off', reason: reason);
          expect(layer.mix.muted || layer.mix.solo, isFalse, reason: reason);
          expect(layer.mix.pan, 0, reason: reason);
          expect(layer.mix.gain, inInclusiveRange(0.5, 0.9), reason: reason);
          expect(steps.first.enabled, isTrue, reason: reason);
          for (final step in steps) {
            expect(step.probability, 1, reason: reason);
            if (step.accent) expect(step.enabled, isTrue, reason: reason);
          }
          for (final step in steps.skip(1)) {
            expect(step.accent, isFalse, reason: reason);
          }
        }
      }
    });

    test('density, step counts and pitches have musical shape', () {
      var accents = 0;
      var layersSeen = 0;
      final counts = <int>{};
      for (final seed in seeds) {
        final layers = randomLoopDocument(seed: seed).scenes.first.layers;
        final reason = 'seed $seed';
        final stepCounts = [for (final l in layers) l.pattern.steps.length];
        // Every layer has its own count, so there are always at least two.
        expect(stepCounts.toSet().length, layers.length, reason: reason);
        counts.addAll(stepCounts);
        for (final layer in layers) {
          final on = layer.pattern.steps.where((s) => s.enabled).length;
          expect(on, greaterThanOrEqualTo(1), reason: 'no empty layer $seed');
          // 30-70 % of the steps on (a two-step layer: one of two).
          expect(
            on / layer.pattern.steps.length,
            inInclusiveRange(0.3, 0.7),
            reason: reason,
          );
          layersSeen++;
          if (layer.pattern.steps.first.accent) accents++;
        }
        // All pitches in one pentatonic set, within two octaves.
        final pitches = [for (final l in layers) l.pitch];
        expect(
          List.generate(
            12,
            pentatonic,
          ).any((scale) => pitches.every((p) => scale.contains(p % 12))),
          isTrue,
          reason: '$reason $pitches',
        );
        final low = pitches.reduce((a, b) => a < b ? a : b);
        final high = pitches.reduce((a, b) => a > b ? a : b);
        expect(high - low, lessThan(24), reason: reason);
        expect(low, inInclusiveRange(24, 72), reason: reason);
        // The slowest layer sits lowest.
        final slowest = layers.reduce(
          (a, b) => a.pattern.steps.length <= b.pattern.steps.length ? a : b,
        );
        expect(slowest.pitch, low, reason: reason);
      }
      expect(counts.length, greaterThan(6), reason: 'step counts vary');
      // Accents on the first step with some probability, not always.
      expect(accents / layersSeen, inInclusiveRange(0.4, 0.85));
    });

    test('scene B is scene A, as the Loop panel writes it', () {
      for (final seed in seeds) {
        final scenes = randomLoopDocument(seed: seed).scenes;
        expect(scenes.map((s) => s.id), ['A', 'B']);
        expect(
          jsonEncode(scenes[1].toJson()..remove('id')),
          jsonEncode(scenes[0].toJson()..remove('id')),
          reason: 'seed $seed',
        );
      }
    });

    test('draws instruments from the ids passed in and keeps the title', () {
      const mine = ['mine-1', 'mine-2'];
      final used = <String>{};
      for (final seed in seeds.take(200)) {
        final document = randomLoopDocument(
          seed: seed,
          instrumentIds: mine,
          title: 'My loop',
        );
        expect(document.title, 'My loop');
        for (final layer in document.scenes.first.layers) {
          expect(mine, contains(layer.instrumentId));
          used.add(layer.instrumentId);
        }
      }
      expect(used, mine.toSet());
    });

    test('uses different instruments while there are enough of them', () {
      for (final seed in seeds.take(200)) {
        final layers = randomLoopDocument(seed: seed).scenes.first.layers;
        final ids = {for (final l in layers) l.instrumentId};
        expect(ids.length, layers.length < 3 ? layers.length : 3);
      }
    });

    test('rejects a seed outside uint32 and invalid instrument ids', () {
      expect(() => randomLoopDocument(seed: -1), throwsArgumentError);
      expect(() => randomLoopDocument(seed: 1 << 32), throwsArgumentError);
      expect(
        () => randomLoopDocument(seed: 1, instrumentIds: ['bad id']),
        throwsArgumentError,
      );
    });

    test('covers the layer counts and cycles it promises', () {
      final layerCounts = <int>{};
      final cycles = <int>{};
      for (final seed in seeds) {
        final document = randomLoopDocument(seed: seed);
        layerCounts.add(document.scenes.first.layers.length);
        cycles.add(document.transport.practiceCycleBeats.numerator);
      }
      expect(layerCounts, {2, 3, 4});
      expect(cycles, randomLoopCycleBeats.toSet());
    });
  });

  group('randomArrangement', () {
    const loops = ['loop-a', 'loop-b', 'loop-c'];

    Arrangement? roll(int seed, [List<String> ids = loops]) =>
        randomArrangement(seed: seed, loopIds: ids, id: 'arr-1', name: 'Roll');

    test('no loops: no arrangement, explicitly', () {
      expect(roll(7, const []), isNull);
    });

    test('every seed passes the real parser and stays in range', () {
      for (final seed in seeds) {
        final arrangement = roll(seed)!;
        final reason = 'seed $seed';
        expect(
          Arrangement.fromJson(jsonDecode(jsonEncode(arrangement.toJson()))),
          arrangement,
          reason: reason,
        );
        expect(arrangement.id, 'arr-1');
        expect(arrangement.name, 'Roll');
        expect(arrangement.sections.length, inInclusiveRange(2, 6));
        for (final section in arrangement.sections) {
          expect(loops, contains(section.loopId), reason: reason);
          expect(section.repeats, inInclusiveRange(1, 4), reason: reason);
        }
        for (var i = 1; i < arrangement.sections.length; i++) {
          expect(
            arrangement.sections[i].loopId,
            isNot(arrangement.sections[i - 1].loopId),
            reason: '$reason: no immediate repeat',
          );
        }
      }
    });

    test('is deterministic and varied', () {
      expect(roll(5), roll(5));
      final all = {for (var seed = 0; seed < 100; seed++) roll(seed)};
      expect(all.length, greaterThan(80));
    });

    test('a single loop is repeated, since nothing else is possible', () {
      for (final seed in seeds.take(100)) {
        final arrangement = roll(seed, const ['only'])!;
        expect(arrangement.sections.length, inInclusiveRange(2, 6));
        expect(arrangement.sections.map((s) => s.loopId).toSet(), {'only'});
      }
    });

    test('duplicate ids count once; invalid input is rejected', () {
      for (final seed in seeds.take(100)) {
        final arrangement = roll(seed, const ['a', 'a', 'b'])!;
        for (var i = 1; i < arrangement.sections.length; i++) {
          expect(
            arrangement.sections[i].loopId,
            isNot(arrangement.sections[i - 1].loopId),
          );
        }
      }
      expect(() => roll(-1), throwsArgumentError);
      expect(() => roll(1, const ['bad id']), throwsArgumentError);
      expect(
        () => randomArrangement(seed: 1, loopIds: loops, id: 'x', name: ' '),
        throwsArgumentError,
      );
    });
  });
}
