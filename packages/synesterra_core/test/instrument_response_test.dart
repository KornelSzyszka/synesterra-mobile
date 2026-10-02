import 'dart:math';

import 'package:synesterra_core/synesterra_core.dart';
import 'package:test/test.dart';

Instrument recipe({
  double hz = 440,
  List<double> harmonics = const [1, 0.5, 0.25],
  InstrumentEq? eq,
  int attackMs = 0,
  int decayMs = 1000,
}) => Instrument(
  id: 'response-test',
  name: 'Response test',
  fundamentalHz: hz,
  harmonics: harmonics,
  attackMs: attackMs,
  decayMs: decayMs,
  eq: eq,
);

void main() {
  group('eqResponseDb', () {
    test('a flat EQ is 0 dB everywhere', () {
      for (final hz in <double>[30, 200, 1000, 4000, 12000, 20000]) {
        expect(eqResponseDb(InstrumentEq(), hz), closeTo(0, 1e-9));
      }
    });

    test('the mid peak gives its full gain at 1 kHz and little far away', () {
      final eq = InstrumentEq(midDb: 12);
      expect(eqResponseDb(eq, InstrumentEq.midPeakHz), closeTo(12, 0.05));
      expect(eqResponseDb(eq, 40).abs(), lessThan(1));
      expect(eqResponseDb(eq, 16000).abs(), lessThan(1.5));
    });

    test('the high shelf gives half its gain at the corner and all above', () {
      final eq = InstrumentEq(highDb: 12);
      expect(eqResponseDb(eq, 100).abs(), lessThan(0.5));
      expect(eqResponseDb(eq, InstrumentEq.highShelfHz), closeTo(6, 1));
      expect(eqResponseDb(eq, 15000), closeTo(12, 1));
    });

    test('the low shelf gives half its gain at the corner and all below', () {
      final eq = InstrumentEq(lowDb: 12);
      expect(eqResponseDb(eq, 40), closeTo(12, 1.5));
      expect(eqResponseDb(eq, InstrumentEq.lowShelfHz), closeTo(6, 1));
      expect(eqResponseDb(eq, 8000).abs(), lessThan(0.5));
    });

    test('a cut mirrors the same boost', () {
      for (final hz in <double>[60, 300, 1000, 3000, 9000]) {
        final up = eqResponseDb(
          InstrumentEq(lowDb: 9, midDb: 6, highDb: 12),
          hz,
        );
        final down = eqResponseDb(
          InstrumentEq(lowDb: -9, midDb: -6, highDb: -12),
          hz,
        );
        expect(down, closeTo(-up, 1e-6), reason: '$hz Hz');
      }
    });

    test('the bands add up in dB', () {
      const hz = 700.0;
      final all = eqResponseDb(
        InstrumentEq(lowDb: 3, midDb: -4, highDb: 5),
        hz,
      );
      final parts =
          eqResponseDb(InstrumentEq(lowDb: 3), hz) +
          eqResponseDb(InstrumentEq(midDb: -4), hz) +
          eqResponseDb(InstrumentEq(highDb: 5), hz);
      expect(all, closeTo(parts, 1e-9));
    });
  });

  group('shapedHarmonics', () {
    test('a flat EQ leaves the recipe amplitudes alone', () {
      final shaped = shapedHarmonics(recipe());
      for (var n = 0; n < shaped.length; n++) {
        expect(shaped[n], closeTo(recipe().harmonics[n], 1e-9));
      }
    });

    test('a harmonic at or above Nyquist is silent', () {
      final shaped = shapedHarmonics(
        recipe(hz: 2000, harmonics: List.filled(12, 1.0)),
      );
      expect(shaped[10], greaterThan(0), reason: '22 kHz is below 24 kHz');
      expect(shaped[11], 0, reason: '24 kHz is exactly Nyquist');
    });

    test('the high shelf scales a 10 kHz harmonic by about 12 dB', () {
      final flat = shapedHarmonics(
        recipe(hz: 2000, harmonics: [0, 0, 0, 0, 1]),
      )[4];
      final bright = shapedHarmonics(
        recipe(
          hz: 2000,
          harmonics: [0, 0, 0, 0, 1],
          eq: InstrumentEq(highDb: 12),
        ),
      )[4];
      expect(bright / flat, closeTo(pow(10, 12 / 20), 0.4));
    });

    test('it predicts what the renderer does to a tone', () {
      // Project the rendered tone on its own frequency: with the same
      // envelope, the ratio of the two projections is the EQ gain.
      double projection(Instrument instrument) {
        final samples = renderInstrument(instrument);
        var sum = 0.0;
        for (var i = 0; i < samples.length; i++) {
          sum +=
              samples[i] * sin(2 * pi * instrument.fundamentalHz * i / 48000);
        }
        return sum;
      }

      final flat = recipe(hz: 1000, harmonics: [0.1]);
      final boosted = recipe(
        hz: 1000,
        harmonics: [0.1],
        eq: InstrumentEq(midDb: 12),
      );
      final measured = projection(boosted) / projection(flat);
      final predicted =
          shapedHarmonics(boosted).first / shapedHarmonics(flat).first;
      expect(measured, closeTo(predicted, predicted * 0.03));
    });
  });
}
