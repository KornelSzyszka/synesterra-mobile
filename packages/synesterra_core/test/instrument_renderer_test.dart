import 'dart:math';
import 'dart:typed_data';

import 'package:synesterra_core/synesterra_core.dart';
import 'package:test/test.dart';

/// A recipe and the pitch to play it at (the instrument itself has none).
class _Voice {
  _Voice(this.instrument, this.hz);

  final Instrument instrument;
  final double hz;
}

_Voice _instrument({
  double fundamentalHz = 440,
  List<double> harmonics = const [1],
  int attackMs = 20,
  int decayMs = 200,
  InstrumentEq? eq,
}) => _Voice(
  Instrument(
    id: 'render-test',
    name: 'Render test',
    harmonics: harmonics,
    attackMs: attackMs,
    decayMs: decayMs,
    eq: eq,
  ),
  fundamentalHz,
);

Float32List _render(_Voice voice, {int sampleRate = 48000}) => renderInstrument(
  voice.instrument,
  fundamentalHz: voice.hz,
  sampleRate: sampleRate,
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
        final first = _render(instrument);
        final second = _render(instrument);

        expect(first, second);
        expect(first.first, 0);
        expect(first.last, 0);
        expect(first.every((sample) => sample.abs() <= 1), isTrue);
      },
    );

    test('uses a linear attack and an exponential decay to -60 dB', () {
      final samples = _render(
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
      final samples = _render(
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
      final samples = _render(
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
      final flat = _render(
        _instrument(
          fundamentalHz: 400,
          harmonics: _twoToneHarmonics(20),
          attackMs: 0,
          decayMs: 1000,
        ),
        sampleRate: sampleRate,
      );
      final bright = _render(
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
      final flatLow = _render(
        _instrument(
          fundamentalHz: 100,
          harmonics: lowHarmonics,
          attackMs: 0,
          decayMs: 1000,
        ),
        sampleRate: sampleRate,
      );
      final boostedLow = _render(
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
      final flatMid = _render(
        _instrument(
          fundamentalHz: 1000,
          harmonics: midHarmonics,
          attackMs: 0,
          decayMs: 1000,
        ),
        sampleRate: sampleRate,
      );
      final boostedMid = _render(
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

    test('a valid envelope is at most five and a half seconds', () {
      final samples = _render(
        _instrument(attackMs: 500, decayMs: 5000),
        sampleRate: 48000,
      );
      expect(samples.length, 5.5 * 48000 + 1);
    });

    test('reports an eighth harmonic at B7 as unrenderable at 48 kHz', () {
      final instrument = _instrument(
        fundamentalHz: 3951.066410048992,
        harmonics: const [0, 0, 0, 0, 0, 0, 0, 1],
      ).instrument;

      expect(
        hasRenderableHarmonic(instrument, fundamentalHz: 3951.066410048992),
        isFalse,
      );
    });
  });

  group('pitch is an argument, not part of the instrument', () {
    test('the same instrument renders at the pitch it is asked for', () {
      final instrument = Instrument(
        id: 'pitch-test',
        name: 'Pitch test',
        harmonics: const [1],
        attackMs: 0,
        decayMs: 500,
      );
      for (final hz in <double>[110, 440, 1760]) {
        final samples = renderInstrument(instrument, fundamentalHz: hz);
        final at = _magnitude(samples, hz, 48000);
        final off = _magnitude(samples, hz * 1.5, 48000);
        expect(at, greaterThan(off * 20), reason: '$hz Hz');
      }
    });

    test('a pitch outside the renderable range is rejected', () {
      final instrument = Instrument(
        id: 'pitch-test',
        name: 'Pitch test',
        harmonics: const [1],
        attackMs: 0,
        decayMs: 100,
      );
      for (final hz in <double>[
        0,
        19.9,
        8000.1,
        double.nan,
        double.infinity,
        -440,
      ]) {
        expect(
          () => renderInstrument(instrument, fundamentalHz: hz),
          throwsArgumentError,
          reason: '$hz',
        );
      }
      expect(
        renderInstrument(instrument, fundamentalHz: minRenderFrequencyHz),
        isNotEmpty,
      );
      expect(
        renderInstrument(instrument, fundamentalHz: maxRenderFrequencyHz),
        isNotEmpty,
      );
    });
  });
}
