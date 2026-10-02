import 'dart:math';

import 'biquad.dart';
import 'instrument.dart';

/// Combined gain of the three EQ bands at [hz], in dB. It uses the same
/// filters as [renderInstrument], so it describes what the sound does.
double eqResponseDb(InstrumentEq eq, double hz, {int sampleRate = 48000}) =>
    Biquad.lowShelf(
      frequencyHz: InstrumentEq.lowShelfHz,
      gainDb: eq.lowDb,
      sampleRate: sampleRate,
    ).magnitudeDb(hz, sampleRate) +
    Biquad.peaking(
      frequencyHz: InstrumentEq.midPeakHz,
      gainDb: eq.midDb,
      sampleRate: sampleRate,
    ).magnitudeDb(hz, sampleRate) +
    Biquad.highShelf(
      frequencyHz: InstrumentEq.highShelfHz,
      gainDb: eq.highDb,
      sampleRate: sampleRate,
    ).magnitudeDb(hz, sampleRate);

/// The amplitude of each harmonic as it sounds when the instrument plays at
/// [fundamentalHz]: the recipe's amplitude times the EQ gain at that
/// harmonic's frequency. A harmonic at or above Nyquist is 0, as in the
/// renderer. The EQ acts on frequencies, so the result depends on the pitch.
List<double> shapedHarmonics(
  Instrument instrument, {
  required double fundamentalHz,
  int sampleRate = 48000,
}) {
  final nyquist = sampleRate / 2;
  return [
    for (var n = 0; n < instrument.harmonics.length; n++)
      if (fundamentalHz * (n + 1) >= nyquist)
        0.0
      else
        instrument.harmonics[n] *
            pow(
              10,
              eqResponseDb(
                    instrument.eq,
                    fundamentalHz * (n + 1),
                    sampleRate: sampleRate,
                  ) /
                  20,
            ),
  ];
}
