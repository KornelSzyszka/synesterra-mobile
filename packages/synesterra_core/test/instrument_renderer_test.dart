import 'dart:math';

import 'package:synesterra_core/synesterra_core.dart';
import 'package:test/test.dart';

Instrument _instrument({
  double fundamentalHz = 440,
  List<double> harmonics = const [1],
  int attackMs = 20,
  int decayMs = 200,
  InstrumentEq? eq,
}) => Instrument(
  id: 'render-test',
  name: 'Render test',
  fundamentalHz: fundamentalHz,
  harmonics: harmonics,
  attackMs: attackMs,
  decayMs: decayMs,
  eq: eq,
);

List<double> _twoToneHarmonics(int highHarmonic) {
  final harmonics = List<double>.filled(highHarmonic, 0);
  harmonics[0] = 1;
  harmonics[highHarmonic - 1] = 1;
  return harmonics;
}

double _magnitude(List<double> samples, double frequencyHz, int sampleRate) {
  var real = 0.0;
  var imaginary = 0.0;
  for (var index = 0; index < samples.length; index++) {
    final angle = 2 * pi * frequencyHz * index / sampleRate;
    real += samples[index] * cos(angle);
    imaginary -= samples[index] * sin(angle);
  }
  return sqrt(real * real + imaginary * imaginary);
}

double _db(double ratio) => 20 * log(ratio) / ln10;

void main() {
  group('renderInstrument', () {
    test(
      'returns deterministic, peak-limited mono samples with zero edges',
      () {
        final instrument = _instrument(harmonics: [1, 0.5, 0.25]);
        final first = renderInstrument(instrument);
        final second = renderInstrument(instrument);

        expect(first, second);
        expect(first.first, 0);
        expect(first.last, 0);
        expect(first.every((sample) => sample.abs() <= 1), isTrue);
      },
    );

    test('uses a linear attack and an exponential decay to -60 dB', () {
      final samples = renderInstrument(
        _instrument(fundamentalHz: 125, attackMs: 100, decayMs: 200),
        sampleRate: 10000,
      );

      expect(samples.length, 3001);
      expect(samples.first, 0);
      expect(samples.last, 0);
      expect(samples[500].abs(), greaterThan(samples[250].abs()));
      expect(samples[2999].abs(), lessThan(samples[1001].abs() * 0.002));
    });

    test('keeps harmonic DFT magnitudes proportional to the recipe', () {
      const sampleRate = 48000;
      final samples = renderInstrument(
        _instrument(
          fundamentalHz: 400,
          harmonics: [1, 0.5, 0.25],
          attackMs: 0,
          decayMs: 1000,
        ),
        sampleRate: sampleRate,
      );
      final fundamental = _magnitude(samples, 400, sampleRate);

      expect(
        _magnitude(samples, 800, sampleRate) / fundamental,
        closeTo(0.5, 0.03),
      );
      expect(
        _magnitude(samples, 1200, sampleRate) / fundamental,
        closeTo(0.25, 0.03),
      );
    });

    test('skips harmonics at and above Nyquist', () {
      const sampleRate = 8000;
      final samples = renderInstrument(
        _instrument(
          fundamentalHz: 1000,
          harmonics: [0, 0, 0, 1],
          attackMs: 0,
          decayMs: 1000,
        ),
        sampleRate: sampleRate,
      );

      expect(_magnitude(samples, 4000, sampleRate), lessThan(1e-5));
      expect(samples.every((sample) => sample == 0), isTrue);
    });

    test('applies EQ band gains with broad-band DFT tolerances', () {
      const sampleRate = 48000;
      final flat = renderInstrument(
        _instrument(
          fundamentalHz: 400,
          harmonics: _twoToneHarmonics(20),
          attackMs: 0,
          decayMs: 1000,
        ),
        sampleRate: sampleRate,
      );
      final bright = renderInstrument(
        _instrument(
          fundamentalHz: 400,
          harmonics: _twoToneHarmonics(20),
          attackMs: 0,
          decayMs: 1000,
          eq: InstrumentEq(highDb: 12),
        ),
        sampleRate: sampleRate,
      );

      final flatRatio =
          _magnitude(flat, 8000, sampleRate) /
          _magnitude(flat, 400, sampleRate);
      final brightRatio =
          _magnitude(bright, 8000, sampleRate) /
          _magnitude(bright, 400, sampleRate);
      expect(_db(brightRatio / flatRatio), closeTo(12, 1.0));
    });

    test('applies low shelf and mid peak gains within 1 dB', () {
      const sampleRate = 48000;
      final lowHarmonics = _twoToneHarmonics(20);
      final flatLow = renderInstrument(
        _instrument(
          fundamentalHz: 100,
          harmonics: lowHarmonics,
          attackMs: 0,
          decayMs: 1000,
        ),
        sampleRate: sampleRate,
      );
      final boostedLow = renderInstrument(
        _instrument(
          fundamentalHz: 100,
          harmonics: lowHarmonics,
          attackMs: 0,
          decayMs: 1000,
          eq: InstrumentEq(lowDb: 12),
        ),
        sampleRate: sampleRate,
      );
      final midHarmonics = _twoToneHarmonics(4);
      final flatMid = renderInstrument(
        _instrument(
          fundamentalHz: 1000,
          harmonics: midHarmonics,
          attackMs: 0,
          decayMs: 1000,
        ),
        sampleRate: sampleRate,
      );
      final boostedMid = renderInstrument(
        _instrument(
          fundamentalHz: 1000,
          harmonics: midHarmonics,
          attackMs: 0,
          decayMs: 1000,
          eq: InstrumentEq(midDb: 12),
        ),
        sampleRate: sampleRate,
      );

      final lowGain = _db(
        (_magnitude(boostedLow, 100, sampleRate) /
                _magnitude(boostedLow, 2000, sampleRate)) /
            (_magnitude(flatLow, 100, sampleRate) /
                _magnitude(flatLow, 2000, sampleRate)),
      );
      final midGain = _db(
        (_magnitude(boostedMid, 1000, sampleRate) /
                _magnitude(boostedMid, 4000, sampleRate)) /
            (_magnitude(flatMid, 1000, sampleRate) /
                _magnitude(flatMid, 4000, sampleRate)),
      );
      expect(lowGain, closeTo(12, 1.0));
      expect(midGain, closeTo(12, 1.0));
    });

    test('caps a rendered envelope at six seconds', () {
      final samples = renderInstrument(
        _instrument(attackMs: 500, decayMs: 5000),
        sampleRate: 48000,
      );
      expect(samples.length, lessThanOrEqualTo(6 * 48000));
    });
  });
}
