import 'package:flutter_test/flutter_test.dart';
import 'package:synesterra/shared/formatting/note_name.dart';
import 'package:synesterra/shared/instrument_mist/mist_spec.dart';
import 'package:synesterra_core/synesterra_core.dart';

Instrument instrument({
  List<double> harmonics = const [1, 0.5, 0.25, 0.12],
  String id = 'mist-test',
  InstrumentEq? eq,
  int attackMs = 2,
  int decayMs = 200,
}) => Instrument(
  id: id,
  name: 'Mist test',
  harmonics: harmonics,
  attackMs: attackMs,
  decayMs: decayMs,
  eq: eq,
);

void main() {
  group('lobes', () {
    test('there is one lobe per audible overtone and none for silent ones', () {
      final bell = factoryInstruments.firstWhere((i) => i.id == 'factory-bell');
      expect(buildMistSpec(bell).lobes.map((l) => l.harmonic), [2, 4, 6, 7]);
      expect(buildMistSpec(instrument(harmonics: const [1])).lobes, isEmpty);
    });

    test('harmonics below the audible threshold make no lobe', () {
      final spec = buildMistSpec(
        instrument(harmonics: const [1, audibleHarmonic - 0.001, 0.5]),
      );
      expect(spec.lobes.map((l) => l.harmonic), [2]);
    });

    test('more harmonics give more lobes', () {
      final few = buildMistSpec(instrument(harmonics: const [1, 0.5]));
      final many = buildMistSpec(
        instrument(harmonics: const [1, 0.5, 0.4, 0.3, 0.2, 0.1]),
      );
      expect(many.lobes.length, greaterThan(few.lobes.length));
    });

    test('a stronger harmonic makes a bigger and more opaque lobe', () {
      final weak = buildMistSpec(instrument(harmonics: const [1, 0.2])).lobes;
      final strong = buildMistSpec(instrument(harmonics: const [1, 0.9])).lobes;
      expect(strong.single.radius, greaterThan(weak.single.radius));
      expect(strong.single.opacity, greaterThan(weak.single.opacity));
    });

    test('higher harmonics sit further out and at different angles', () {
      final lobes = buildMistSpec(
        instrument(harmonics: const [1, 0.5, 0.5, 0.5, 0.5]),
      ).lobes;
      for (var i = 1; i < lobes.length; i++) {
        expect(lobes[i].distance, greaterThan(lobes[i - 1].distance));
        expect(lobes[i].angle, isNot(lobes[i - 1].angle));
      }
    });
  });

  group('EQ and envelope', () {
    test('a high shelf boost widens the halo and makes it stronger', () {
      final flat = buildMistSpec(instrument());
      final bright = buildMistSpec(instrument(eq: InstrumentEq(highDb: 12)));
      final dark = buildMistSpec(instrument(eq: InstrumentEq(highDb: -12)));
      expect(bright.haloRadius, greaterThan(flat.haloRadius));
      expect(bright.haloOpacity, greaterThan(flat.haloOpacity));
      expect(dark.haloOpacity, lessThan(flat.haloOpacity));
    });

    test('upper harmonics brighten the halo', () {
      final mellow = buildMistSpec(
        instrument(harmonics: const [1, 0.5, 0.1, 0, 0, 0]),
      );
      final sharp = buildMistSpec(
        instrument(harmonics: const [1, 0.5, 0.5, 0.9, 0.9, 0.9]),
      );
      expect(sharp.haloOpacity, greaterThan(mellow.haloOpacity));
    });

    test('a low shelf boost grows and densifies the core', () {
      final flat = buildMistSpec(instrument());
      final warm = buildMistSpec(instrument(eq: InstrumentEq(lowDb: 12)));
      expect(warm.coreRadius, greaterThan(flat.coreRadius));
      expect(warm.coreOpacity, greaterThan(flat.coreOpacity));
    });

    test('mid EQ scales the opacity of the lobes', () {
      final flat = buildMistSpec(instrument()).lobes.first.opacity;
      final boosted = buildMistSpec(instrument(eq: InstrumentEq(midDb: 12)))
          .lobes
          .first
          .opacity;
      final cut = buildMistSpec(instrument(eq: InstrumentEq(midDb: -12)))
          .lobes
          .first
          .opacity;
      expect(boosted, greaterThan(flat));
      expect(cut, lessThan(flat));
    });

    test('the pulse follows attack and decay, with at least one frame', () {
      final spec = buildMistSpec(instrument(attackMs: 0, decayMs: 900));
      expect(spec.attack, const Duration(milliseconds: 16));
      expect(spec.decay, const Duration(milliseconds: 900));
      expect(
        buildMistSpec(instrument(attackMs: 120)).attack,
        const Duration(milliseconds: 120),
      );
    });

    test('values stay inside their ranges at the extremes', () {
      final spec = buildMistSpec(
        instrument(
          harmonics: List.filled(32, 1.0),
          eq: InstrumentEq(lowDb: 12, midDb: 12, highDb: 12),
        ),
      );
      expect(spec.haloOpacity, inInclusiveRange(0, 1));
      expect(spec.coreOpacity, inInclusiveRange(0, 1));
      expect(spec.haloRadius, inInclusiveRange(0, 1));
      for (final lobe in spec.lobes) {
        expect(lobe.opacity, inInclusiveRange(0, 1));
        expect(lobe.distance, inInclusiveRange(0, 1));
      }
    });
  });

  group('identity', () {
    test('the same recipe gives an equal spec, another recipe does not', () {
      expect(buildMistSpec(instrument()), buildMistSpec(instrument()));
      expect(
        buildMistSpec(instrument()).hashCode,
        buildMistSpec(instrument()).hashCode,
      );
      expect(
        buildMistSpec(instrument(decayMs: 300)),
        isNot(buildMistSpec(instrument())),
      );
    });

    test('the colour comes from the id, never from a pitch', () {
      expect(buildMistSpec(instrument()).colorIndex, 3);
      expect(buildMistSpec(instrument(id: 'factory-wood')).colorIndex, 9);
      expect(buildMistSpec(instrument(id: 'factory-sine')).colorIndex, 5);
      expect(buildMistSpec(instrument(id: 'factory-bell')).colorIndex, 1);
    });

    test('the colour does not change when the recipe changes', () {
      final base = buildMistSpec(instrument(id: 'keep-me')).colorIndex;
      expect(
        buildMistSpec(instrument(id: 'keep-me', decayMs: 900)).colorIndex,
        base,
      );
      expect(
        buildMistSpec(instrument(id: 'keep-me', eq: InstrumentEq(highDb: 12)))
            .colorIndex,
        base,
      );
    });

    test(
      'identityColorIndex is stable, in range and spreads over the palette',
      () {
        expect(identityColorIndex(''), 1);
        final colours = {
          for (var i = 0; i < 100; i++) identityColorIndex('inst-$i'),
        };
        expect(colours.every((c) => c >= 0 && c < 12), isTrue);
        expect(colours.length, 12, reason: '100 ids should use every colour');
        expect(identityColorIndex('x'), identityColorIndex('x'));
      },
    );
  });

  group('note names', () {
    test('names the nearest note', () {
      expect(noteName(440), 'A4');
      expect(noteName(880), 'A5');
      expect(noteName(261.63), 'C4');
      expect(noteName(40), 'D#1');
    });

    test('label rounds the frequency', () {
      expect(pitchLabel(440.4), '440 Hz · A4');
    });
  });
}
