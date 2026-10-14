import 'package:synesterra_core/synesterra_core.dart';
import 'package:test/test.dart';

void main() {
  group('randomInstrumentTraits', () {
    test('is deterministic per seed and differs between seeds', () {
      expect(randomInstrumentTraits(seed: 7), randomInstrumentTraits(seed: 7));
      expect(
        randomInstrumentTraits(seed: 7),
        isNot(randomInstrumentTraits(seed: 8)),
      );
    });

    test('values stay in range, in hundredths, for every default trait', () {
      for (var seed = 0; seed < 500; seed++) {
        final traits = randomInstrumentTraits(
          seed: seed * 2654435761 & 0xffffffff,
        );
        expect(traits.values.keys, [
          for (final d in defaultTraitDefinitions) d.id,
        ]);
        for (final v in traits.values.values) {
          expect(v, inInclusiveRange(randomTraitMin, randomTraitMax));
          expect((v * 100).round() / 100, v);
        }
      }
    });

    test('the traits map to a valid instrument', () {
      final traits = randomInstrumentTraits(seed: 3);
      expect(
        () => instrumentForTraits(traits, id: 'x', name: 'Random'),
        returnsNormally,
      );
    });

    test('rejects a seed outside uint32', () {
      expect(() => randomInstrumentTraits(seed: -1), throwsArgumentError);
      expect(
        () => randomInstrumentTraits(seed: 0x100000000),
        throwsArgumentError,
      );
    });
  });

  group('TapTempo', () {
    Duration ms(int v) => Duration(milliseconds: v);

    test('gives nothing before the third tap, then the average interval', () {
      final t = TapTempo();
      expect(t.tap(ms(0)), isNull);
      expect(t.tap(ms(500)), isNull);
      expect(t.tap(ms(1000)), 120);
      expect(t.tap(ms(1500)), 120);
    });

    test('averages uneven intervals', () {
      final t = TapTempo()..tap(ms(0));
      t.tap(ms(400));
      expect(t.tap(ms(1000)), 120); // 1000 ms over 2 intervals
    });

    test('keeps only the last taps', () {
      final t = TapTempo(maxTaps: 3);
      for (var i = 0; i < 4; i++) {
        t.tap(ms(i * 1000)); // 60 BPM
      }
      expect(t.tap(ms(3500)), 80); // last three: 2000, 3000, 3500
    });

    test('resets after a long silence and on time going backwards', () {
      final t = TapTempo();
      t.tap(ms(0));
      t.tap(ms(500));
      expect(t.tap(ms(1000)), 120);
      expect(t.tap(ms(3500)), isNull); // gap 2500 ms starts over
      expect(t.count, 1);
      t.tap(ms(4000));
      expect(t.tap(ms(4500)), 120);
      expect(t.tap(ms(4400)), isNull); // went backwards
      expect(t.count, 1);
    });

    test('exactly resetAfter still counts', () {
      final t = TapTempo()..tap(ms(0));
      t.tap(ms(2000));
      expect(t.tap(ms(4000)), 30);
    });

    test('clamps to the range', () {
      final fast = TapTempo()..tap(ms(0));
      fast.tap(ms(50));
      expect(fast.tap(ms(100)), 300);
      final slow = TapTempo()..tap(ms(0));
      slow.tap(ms(2000));
      slow.tap(ms(4000));
      expect(slow.tap(ms(6000)), 30);
      final slowest = TapTempo(minBpm: 40)..tap(ms(0));
      slowest.tap(ms(2000));
      expect(slowest.tap(ms(4000)), 40);
    });

    test('reset forgets taps; bad arguments throw', () {
      final t = TapTempo()..tap(ms(0));
      t.reset();
      expect(t.count, 0);
      expect(() => TapTempo(minTaps: 1), throwsArgumentError);
      expect(() => TapTempo(minTaps: 4, maxTaps: 3), throwsArgumentError);
      expect(() => TapTempo(minBpm: 0), throwsArgumentError);
    });
  });
}
