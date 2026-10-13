import 'dart:math';

import 'package:synesterra_core/synesterra_core.dart';
import 'package:test/test.dart';

const _ids = [
  TraitIds.brightness,
  TraitIds.fullness,
  TraitIds.warmth,
  TraitIds.air,
  TraitIds.softness,
  TraitIds.length,
];

InstrumentTraits traits(Map<String, double> overrides) =>
    InstrumentTraits.neutral().withValues(overrides);

Instrument build(InstrumentTraits t) =>
    instrumentForTraits(t, id: 'traits-test', name: 'Traits test');

double centroid(Instrument instrument) {
  var weighted = 0.0;
  var total = 0.0;
  for (final (i, amplitude) in instrument.harmonics.indexed) {
    weighted += (i + 1) * amplitude;
    total += amplitude;
  }
  return weighted / total;
}

int audibleCount(Instrument instrument) =>
    instrument.harmonics.where((a) => a > 1e-4).length;

List<double> padded(Instrument instrument) => [
  ...instrument.harmonics,
  ...List.filled(Instrument.maxHarmonics - instrument.harmonics.length, 0.0),
];

InstrumentTraits randomTraits(Random random) =>
    InstrumentTraits({for (final id in _ids) id: random.nextDouble()});

/// Every corner of the unit cube plus seeded random vectors.
List<InstrumentTraits> sampleVectors() {
  final random = Random(111);
  return [
    for (var corner = 0; corner < 64; corner++)
      InstrumentTraits({
        for (final (i, id) in _ids.indexed)
          id: (corner >> i) & 1 == 1 ? 1.0 : 0.0,
      }),
    for (var i = 0; i < 400; i++) randomTraits(random),
  ];
}

void main() {
  group('trait definitions and validation', () {
    test('the default list holds six traits with unique ids', () {
      expect(defaultTraitDefinitions.map((d) => d.id), _ids);
      expect(
        defaultTraitDefinitions.map((d) => d.id).toSet().length,
        defaultTraitDefinitions.length,
      );
      for (final definition in defaultTraitDefinitions) {
        expect(definition.label, isNotEmpty);
        expect(definition.defaultValue, inInclusiveRange(0, 1));
      }
    });

    test('neutral holds every default value', () {
      final neutral = InstrumentTraits.neutral();
      for (final definition in defaultTraitDefinitions) {
        expect(neutral[definition.id], definition.defaultValue);
      }
    });

    test('rejects values outside 0..1 and non-finite values', () {
      for (final bad in [-0.01, 1.01, double.nan, double.infinity]) {
        expect(
          () => InstrumentTraits({TraitIds.brightness: bad}),
          throwsArgumentError,
          reason: '$bad',
        );
      }
    });

    test('rejects unknown trait ids', () {
      expect(() => InstrumentTraits({'loudness': 0.5}), throwsArgumentError);
      expect(() => InstrumentTraits.neutral()['loudness'], throwsArgumentError);
      expect(
        () => InstrumentTraits.neutral().withValues({'loudness': 0.5}),
        throwsArgumentError,
      );
    });

    test('missing ids take their default and the values are immutable', () {
      final t = InstrumentTraits({TraitIds.air: 0.9});
      expect(t[TraitIds.air], 0.9);
      expect(t[TraitIds.length], 0.5);
      expect(() => t.values[TraitIds.air] = 0.1, throwsUnsupportedError);
    });

    test('has value equality', () {
      expect(InstrumentTraits.neutral(), InstrumentTraits.neutral());
      expect(
        InstrumentTraits.neutral().hashCode,
        InstrumentTraits.neutral().hashCode,
      );
      expect(traits({TraitIds.air: 0.7}), isNot(InstrumentTraits.neutral()));
    });

    test('an added trait drives the recipe through its declared effect', () {
      const custom = [
        TraitDefinition(
          id: 'sparkle',
          label: 'Sparkle',
          defaultValue: 0.5,
          effect: TraitEffect.highShelf,
        ),
        TraitDefinition(
          id: 'depth',
          label: 'Depth',
          defaultValue: 0.5,
          effect: TraitEffect.lowShelf,
        ),
      ];
      final low = InstrumentTraits({'sparkle': 0.0}, definitions: custom);
      final high = InstrumentTraits({'sparkle': 1.0}, definitions: custom);
      expect(build(low).eq.highDb, -InstrumentEq.maxGainDb);
      expect(build(high).eq.highDb, InstrumentEq.maxGainDb);
      expect(build(high).eq.lowDb, 0);
      expect(() => high[TraitIds.air], throwsArgumentError);
      expect(
        () => InstrumentTraits({TraitIds.air: 0.5}, definitions: custom),
        throwsArgumentError,
      );
      // And the inverse reads it back from the same axis.
      final back = traitsForInstrument(build(high), definitions: custom);
      expect(back['sparkle'], 1);
      expect(back['depth'], 0.5);
    });

    test('a removed trait leaves its recipe field neutral', () {
      final withoutAir = [
        for (final d in defaultTraitDefinitions)
          if (d.id != TraitIds.air) d,
      ];
      final t = InstrumentTraits({
        TraitIds.warmth: 1.0,
      }, definitions: withoutAir);
      expect(build(t).eq.highDb, 0);
      expect(build(t).eq.lowDb, InstrumentEq.maxGainDb);
    });

    test('two definitions with the same effect are rejected', () {
      const twice = [
        TraitDefinition(
          id: 'a',
          label: 'A',
          defaultValue: 0.5,
          effect: TraitEffect.attack,
        ),
        TraitDefinition(
          id: 'b',
          label: 'B',
          defaultValue: 0.5,
          effect: TraitEffect.attack,
        ),
      ];
      expect(
        () => InstrumentTraits(const {}, definitions: twice),
        throwsArgumentError,
      );
    });

    test('equality and hash include the definitions', () {
      final reordered = InstrumentTraits(
        const {},
        definitions: defaultTraitDefinitions.reversed.toList(),
      );
      expect(reordered, isNot(InstrumentTraits.neutral()));
      final relabeled = InstrumentTraits(
        const {},
        definitions: [
          const TraitDefinition(
            id: TraitIds.brightness,
            label: 'Light',
            defaultValue: 0.5,
            effect: TraitEffect.harmonicTilt,
          ),
          ...defaultTraitDefinitions.skip(1),
        ],
      );
      expect(relabeled, isNot(InstrumentTraits.neutral()));
      final same = InstrumentTraits(
        const {},
        definitions: List.of(defaultTraitDefinitions),
      );
      expect(same, InstrumentTraits.neutral());
      expect(same.hashCode, InstrumentTraits.neutral().hashCode);
    });
  });

  group('forward mapping', () {
    test('is deterministic', () {
      final t = traits({TraitIds.brightness: 0.3, TraitIds.length: 0.8});
      expect(build(t), build(t));
    });

    test('passes id, name and tags on', () {
      final instrument = instrumentForTraits(
        InstrumentTraits.neutral(),
        id: 'my-id',
        name: 'My sound',
        tags: ['soft'],
      );
      expect(instrument.id, 'my-id');
      expect(instrument.name, 'My sound');
      expect(instrument.tags, ['soft']);
    });

    test('corners and seeded vectors give valid, non-silent instruments', () {
      for (final t in sampleVectors()) {
        final instrument = build(t);
        expect(instrument.harmonics.any((a) => a > 0), isTrue, reason: '$t');
        expect(instrument.harmonics.first, 1);
        // Re-validation through JSON proves every field is in range.
        expect(Instrument.fromJson(instrument.toJson()), instrument);
      }
    });

    test('trait extremes reach the model limits', () {
      final low = build(InstrumentTraits({for (final id in _ids) id: 0.0}));
      final high = build(InstrumentTraits({for (final id in _ids) id: 1.0}));
      expect(low.harmonics, hasLength(1));
      expect(high.harmonics, hasLength(Instrument.maxHarmonics));
      expect(low.eq.lowDb, -InstrumentEq.maxGainDb);
      expect(high.eq.lowDb, InstrumentEq.maxGainDb);
      expect(low.eq.highDb, -InstrumentEq.maxGainDb);
      expect(high.eq.highDb, InstrumentEq.maxGainDb);
      expect(low.attackMs, 0);
      expect(high.attackMs, Instrument.maxAttackMs);
      expect(low.decayMs, Instrument.minDecayMs);
      expect(high.decayMs, Instrument.maxDecayMs);
    });
  });

  group('monotonicity (other traits held fixed)', () {
    final random = Random(7);
    final contexts = [
      InstrumentTraits.neutral(),
      for (var i = 0; i < 20; i++) randomTraits(random),
    ];
    const steps = 20;

    void check(String id, num Function(Instrument) measure) {
      for (final context in contexts) {
        var previous = double.negativeInfinity;
        var rose = false;
        for (var i = 0; i <= steps; i++) {
          final value = i / steps;
          final measured = measure(build(context.withValues({id: value})))
              .toDouble();
          expect(
            measured,
            greaterThanOrEqualTo(previous),
            reason: '$id $value',
          );
          if (measured > previous && previous.isFinite) rose = true;
          previous = measured;
        }
        expect(rose, isTrue, reason: '$id never rises');
      }
    }

    test('brightness raises the harmonic centroid', () {
      // With one harmonic the centroid cannot move, so hold fullness up.
      for (final context in contexts) {
        final base = context.withValues({TraitIds.fullness: 0.6});
        var previous = 0.0;
        for (var i = 0; i <= steps; i++) {
          final value = centroid(
            build(base.withValues({TraitIds.brightness: i / steps})),
          );
          expect(value, greaterThan(previous));
          previous = value;
        }
      }
    });

    test(
      'fullness raises the harmonic count',
      () => check(TraitIds.fullness, audibleCount),
    );
    test(
      'warmth raises the low EQ',
      () => check(TraitIds.warmth, (i) => i.eq.lowDb),
    );
    test(
      'air raises the high EQ',
      () => check(TraitIds.air, (i) => i.eq.highDb),
    );
    test(
      'softness raises the attack',
      () => check(TraitIds.softness, (i) => i.attackMs),
    );
    test(
      'length raises the decay',
      () => check(TraitIds.length, (i) => i.decayMs),
    );

    test('a trait leaves the recipe fields it does not own unchanged', () {
      final a = build(InstrumentTraits.neutral());
      final b = build(traits({TraitIds.softness: 0.9}));
      expect(b.harmonics, a.harmonics);
      expect(b.decayMs, a.decayMs);
      expect(b.eq, a.eq);
      final c = build(traits({TraitIds.warmth: 0.9}));
      expect(c.eq.highDb, a.eq.highDb);
      expect(c.attackMs, a.attackMs);
    });
  });

  group('continuity', () {
    const delta = 1e-4;

    test('a tiny trait step changes the recipe by a bounded amount', () {
      final random = Random(42);
      for (var n = 0; n < 200; n++) {
        final base = randomTraits(random);
        for (final id in _ids) {
          final up = min(1.0, base[id] + delta);
          final a = build(base);
          final b = build(base.withValues({id: up}));
          final step = up - base[id];
          final reason = '$id from ${base[id]}';
          final ha = padded(a);
          final hb = padded(b);
          for (var k = 0; k < ha.length; k++) {
            // d amplitude / d trait: at most about 7 (brightness), 31 (fullness).
            expect(
              (ha[k] - hb[k]).abs(),
              lessThanOrEqualTo(40 * step + 1e-12),
              reason: reason,
            );
          }
          // Whole milliseconds: a step may flip one rounding.
          expect(
            (a.attackMs - b.attackMs).abs(),
            lessThanOrEqualTo(1 + 3500 * step),
            reason: reason,
          );
          expect(
            (a.decayMs - b.decayMs).abs(),
            lessThanOrEqualTo(1 + 28000 * step),
            reason: reason,
          );
          expect(
            (a.eq.lowDb - b.eq.lowDb).abs(),
            lessThanOrEqualTo(24 * step + 1e-12),
            reason: reason,
          );
          expect(
            (a.eq.highDb - b.eq.highDb).abs(),
            lessThanOrEqualTo(24 * step + 1e-12),
            reason: reason,
          );
        }
      }
    });
  });

  group('presets', () {
    test('five characters and a neutral shape, with unique names', () {
      expect(traitPresets.map((p) => p.name), [
        'neutral',
        'warm drone',
        'airy pad',
        'bass',
        'guitar',
        'click',
      ]);
      expect(traitPresets.first.traits, InstrumentTraits.neutral());
    });

    test('every preset yields a valid, non-silent instrument', () {
      for (final preset in traitPresets) {
        final instrument = build(preset.traits);
        expect(instrument.harmonics.any((a) => a > 0), isTrue);
        expect(Instrument.fromJson(instrument.toJson()), instrument);
      }
    });

    test('the character shapes keep the intended feel', () {
      Instrument of(String name) =>
          build(traitPresets.firstWhere((p) => p.name == name).traits);
      final drone = of('warm drone');
      final pad = of('airy pad');
      final bass = of('bass');
      final guitar = of('guitar');
      final click = of('click');
      // dark soft long / bright soft / dark hard / bright hard / hardest short
      expect(centroid(drone), lessThan(centroid(pad)));
      expect(centroid(bass), lessThan(centroid(guitar)));
      expect(drone.attackMs, greaterThan(100));
      expect(pad.attackMs, greaterThan(100));
      expect(bass.attackMs, lessThan(20));
      expect(guitar.attackMs, lessThan(20));
      expect(drone.decayMs, greaterThan(bass.decayMs));
      expect(click.attackMs, 0);
      for (final other in [drone, pad, bass, guitar]) {
        expect(click.decayMs, lessThan(other.decayMs));
      }
    });
  });

  group('approximate inverse', () {
    // The stated bound: every trait within this distance after a round trip.
    // Brightness is only observable from two or more harmonics, so its check
    // starts at fullness 0.1.
    const tolerance = 0.02;

    test('round trip stays within the tolerance for in-range vectors', () {
      var worst = 0.0;
      for (final t in sampleVectors()) {
        final back = traitsForInstrument(build(t));
        for (final id in _ids) {
          if (id == TraitIds.brightness && t[TraitIds.fullness] < 0.1) continue;
          final error = (back[id] - t[id]).abs();
          worst = max(worst, error);
          expect(error, lessThanOrEqualTo(tolerance), reason: '$id of $t');
        }
      }
      expect(worst, greaterThan(0), reason: 'the inverse is not exact');
    });

    test('brightness reads neutral below fullness 0.1', () {
      for (final fullness in [0.0, 0.01, 0.03, 0.05, 0.08, 0.099]) {
        for (final brightness in [0.0, 0.3, 1.0]) {
          final back = traitsForInstrument(
            build(
              traits({
                TraitIds.fullness: fullness,
                TraitIds.brightness: brightness,
              }),
            ),
          );
          expect(back[TraitIds.brightness], 0.5, reason: '$fullness');
          expect((back[TraitIds.fullness] - fullness).abs(), lessThan(0.02));
        }
      }
    });

    test('factory instruments and old pad sounds map to in-range traits', () {
      // The five rim recipes of the removed circular pad (UX-107): saved
      // instruments made on it still have to open on the radar.
      Instrument old(
        String name,
        List<double> harmonics,
        int attackMs,
        int decayMs,
        double lowDb,
        double midDb,
        double highDb,
      ) => Instrument(
        id: 'old-pad',
        name: name,
        harmonics: harmonics,
        attackMs: attackMs,
        decayMs: decayMs,
        eq: InstrumentEq(lowDb: lowDb, midDb: midDb, highDb: highDb),
      );
      final instruments = [
        ...factoryInstruments,
        old('warm drone', const [1, 0.35, 0.12, 0.04], 400, 5000, 3, -1, -6),
        old(
          'airy pad',
          const [1, 0.5, 0.6, 0.5, 0.4, 0.3, 0.2, 0.12, 0.08],
          300,
          4000,
          -3,
          0,
          6,
        ),
        old('bass', const [1, 0.6, 0.25, 0.1, 0.04], 2, 500, 6, 0, -6),
        old(
          'guitar',
          const [
            1,
            0.8,
            0.7,
            0.55,
            0.45,
            0.35,
            0.28,
            0.2,
            0.15,
            0.1,
            0.08,
            0.05,
          ],
          1,
          1200,
          -1,
          2,
          3,
        ),
        old(
          'click',
          const [1, 0.75, 0.5, 0.35, 0.25, 0.18, 0.12, 0.08, 0.05, 0.03],
          0,
          40,
          -4,
          4,
          6,
        ),
      ];
      for (final instrument in instruments) {
        final back = traitsForInstrument(instrument);
        for (final id in _ids) {
          expect(back[id], inInclusiveRange(0, 1), reason: instrument.name);
        }
        // And the result can be shown again as an instrument.
        expect(build(back).harmonics.any((a) => a > 0), isTrue);
      }
    });

    test('measures the documented quantities for known recipes', () {
      final back = traitsForInstrument(
        Instrument(
          id: 'x',
          name: 'x',
          harmonics: [1],
          attackMs: 0,
          decayMs: Instrument.maxDecayMs,
          eq: InstrumentEq(lowDb: 12, highDb: -12),
        ),
      );
      expect(back[TraitIds.warmth], 1);
      expect(back[TraitIds.air], 0);
      expect(back[TraitIds.softness], 0);
      expect(back[TraitIds.length], 1);
    });

    test('a bright recipe measures brighter than a dark one', () {
      Instrument rolloff(double slope) => Instrument(
        id: 'x',
        name: 'x',
        harmonics: [for (var k = 1; k <= 12; k++) pow(k, -slope).toDouble()],
        attackMs: 5,
        decayMs: 300,
      );
      expect(
        traitsForInstrument(rolloff(0.3))[TraitIds.brightness],
        greaterThan(traitsForInstrument(rolloff(1.8))[TraitIds.brightness]),
      );
    });
  });
}
