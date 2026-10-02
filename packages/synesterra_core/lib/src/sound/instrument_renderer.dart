import 'dart:math';
import 'dart:typed_data';

import 'instrument.dart';

/// Renders an [Instrument] recipe to a deterministic mono PCM buffer.
///
/// The decay value is the time for the exponential envelope to reach -60 dB.
/// The returned buffer is peak-normalised and its first and last samples are
/// zero, so it can be placed in a voice buffer without an edge discontinuity.
Float32List renderInstrument(Instrument instrument, {int sampleRate = 48000}) {
  if (sampleRate < 2) {
    throw ArgumentError.value(sampleRate, 'sampleRate', 'must be at least 2');
  }

  final sampleCount = _sampleCount(instrument, sampleRate);
  final samples = Float32List(sampleCount);
  final nyquistHz = sampleRate / 2.0;

  for (
    var harmonicIndex = 0;
    harmonicIndex < instrument.harmonics.length;
    harmonicIndex++
  ) {
    final frequencyHz = instrument.fundamentalHz * (harmonicIndex + 1);
    if (frequencyHz >= nyquistHz) continue;

    final amplitude = instrument.harmonics[harmonicIndex];
    if (amplitude == 0) continue;
    final phaseStep = 2 * pi * frequencyHz / sampleRate;
    for (var sampleIndex = 0; sampleIndex < sampleCount; sampleIndex++) {
      samples[sampleIndex] += amplitude * sin(phaseStep * sampleIndex);
    }
  }

  _applyEq(samples, instrument.eq, sampleRate);
  _applyEnvelope(samples, instrument, sampleRate);
  _normalise(samples);
  return samples;
}

const _maximumDurationSeconds = 6.0;
const _decayFloor = 0.001; // -60 dB amplitude.

int _sampleCount(Instrument instrument, int sampleRate) {
  final durationSeconds = min(
    _maximumDurationSeconds,
    (instrument.attackMs + instrument.decayMs) / 1000,
  );
  return max(2, (durationSeconds * sampleRate).ceil() + 1);
}

void _applyEnvelope(
  Float32List samples,
  Instrument instrument,
  int sampleRate,
) {
  final attackSeconds = instrument.attackMs / 1000.0;
  final decaySeconds = instrument.decayMs / 1000.0;
  final lastIndex = samples.length - 1;

  for (var index = 0; index < samples.length; index++) {
    if (index == 0 || index == lastIndex) {
      samples[index] = 0;
      continue;
    }

    final timeSeconds = index / sampleRate;
    final envelope = timeSeconds < attackSeconds
        ? timeSeconds / attackSeconds
        : pow(
            _decayFloor,
            ((timeSeconds - attackSeconds) / decaySeconds).clamp(0.0, 1.0),
          ).toDouble();
    samples[index] *= envelope;
  }
}

void _normalise(Float32List samples) {
  var peak = 0.0;
  for (final sample in samples) {
    peak = max(peak, sample.abs());
  }
  if (peak <= 1.0) return;
  for (var index = 0; index < samples.length; index++) {
    samples[index] /= peak;
  }
}

void _applyEq(Float32List samples, InstrumentEq eq, int sampleRate) {
  _Biquad.lowShelf(
    frequencyHz: InstrumentEq.lowShelfHz,
    gainDb: eq.lowDb,
    sampleRate: sampleRate,
  ).apply(samples);
  _Biquad.peaking(
    frequencyHz: InstrumentEq.midPeakHz,
    gainDb: eq.midDb,
    sampleRate: sampleRate,
  ).apply(samples);
  _Biquad.highShelf(
    frequencyHz: InstrumentEq.highShelfHz,
    gainDb: eq.highDb,
    sampleRate: sampleRate,
  ).apply(samples);
}

class _Biquad {
  const _Biquad(this.b0, this.b1, this.b2, this.a1, this.a2);

  factory _Biquad.peaking({
    required double frequencyHz,
    required double gainDb,
    required int sampleRate,
  }) {
    final coefficients = _coefficients(frequencyHz, gainDb, sampleRate);
    final a = coefficients.a;
    final alpha = coefficients.alpha;
    return _Biquad._normalised(
      1 + alpha * a,
      -2 * coefficients.cosine,
      1 - alpha * a,
      1 + alpha / a,
      -2 * coefficients.cosine,
      1 - alpha / a,
    );
  }

  factory _Biquad.lowShelf({
    required double frequencyHz,
    required double gainDb,
    required int sampleRate,
  }) {
    final c = _coefficients(frequencyHz, gainDb, sampleRate, shelf: true);
    final rootA = sqrt(c.a);
    return _Biquad._normalised(
      c.a * ((c.a + 1) - (c.a - 1) * c.cosine + 2 * rootA * c.alpha),
      2 * c.a * ((c.a - 1) - (c.a + 1) * c.cosine),
      c.a * ((c.a + 1) - (c.a - 1) * c.cosine - 2 * rootA * c.alpha),
      (c.a + 1) + (c.a - 1) * c.cosine + 2 * rootA * c.alpha,
      -2 * ((c.a - 1) + (c.a + 1) * c.cosine),
      (c.a + 1) + (c.a - 1) * c.cosine - 2 * rootA * c.alpha,
    );
  }

  factory _Biquad.highShelf({
    required double frequencyHz,
    required double gainDb,
    required int sampleRate,
  }) {
    final c = _coefficients(frequencyHz, gainDb, sampleRate, shelf: true);
    final rootA = sqrt(c.a);
    return _Biquad._normalised(
      c.a * ((c.a + 1) + (c.a - 1) * c.cosine + 2 * rootA * c.alpha),
      -2 * c.a * ((c.a - 1) + (c.a + 1) * c.cosine),
      c.a * ((c.a + 1) + (c.a - 1) * c.cosine - 2 * rootA * c.alpha),
      (c.a + 1) - (c.a - 1) * c.cosine + 2 * rootA * c.alpha,
      2 * ((c.a - 1) - (c.a + 1) * c.cosine),
      (c.a + 1) - (c.a - 1) * c.cosine - 2 * rootA * c.alpha,
    );
  }

  factory _Biquad._normalised(
    double b0,
    double b1,
    double b2,
    double a0,
    double a1,
    double a2,
  ) => _Biquad(b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0);

  final double b0;
  final double b1;
  final double b2;
  final double a1;
  final double a2;

  void apply(Float32List samples) {
    var x1 = 0.0;
    var x2 = 0.0;
    var y1 = 0.0;
    var y2 = 0.0;
    for (var index = 0; index < samples.length; index++) {
      final x0 = samples[index];
      final y0 = b0 * x0 + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2;
      samples[index] = y0;
      x2 = x1;
      x1 = x0;
      y2 = y1;
      y1 = y0;
    }
  }
}

_BiquadCoefficients _coefficients(
  double frequencyHz,
  double gainDb,
  int sampleRate, {
  bool shelf = false,
}) {
  final omega = 2 * pi * frequencyHz / sampleRate;
  final a = pow(10, gainDb / 40).toDouble();
  final sine = sin(omega);
  final cosine = cos(omega);
  // Shelf slope S and peaking Q are both 1.0: broad, predictable bands.
  final alpha = shelf ? sine / sqrt(2) : sine / 2;
  return _BiquadCoefficients(a, alpha, cosine);
}

class _BiquadCoefficients {
  const _BiquadCoefficients(this.a, this.alpha, this.cosine);

  final double a;
  final double alpha;
  final double cosine;
}
