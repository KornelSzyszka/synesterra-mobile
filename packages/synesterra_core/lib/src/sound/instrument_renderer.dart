import 'dart:math';
import 'dart:typed_data';

import 'biquad.dart';
import 'instrument.dart';

/// Lowest and highest pitch a recipe may be rendered at.
const minRenderFrequencyHz = 20.0;
const maxRenderFrequencyHz = 8000.0;

/// Renders an [Instrument] recipe at [fundamentalHz] to a deterministic mono
/// PCM buffer. The instrument has no pitch of its own; the caller (a loop
/// layer, or the editor's test sound) chooses it.
///
/// The decay value is the time for the exponential envelope to reach -60 dB.
/// The returned buffer is peak-normalised and its first and last samples are
/// zero, so it can be placed in a voice buffer without an edge discontinuity.
Float32List renderInstrument(
  Instrument instrument, {
  required double fundamentalHz,
  int sampleRate = 48000,
}) {
  if (sampleRate < 2) {
    throw ArgumentError.value(sampleRate, 'sampleRate', 'must be at least 2');
  }
  if (!fundamentalHz.isFinite ||
      fundamentalHz < minRenderFrequencyHz ||
      fundamentalHz > maxRenderFrequencyHz) {
    throw ArgumentError.value(
      fundamentalHz,
      'fundamentalHz',
      'must be in $minRenderFrequencyHz..$maxRenderFrequencyHz',
    );
  }

  final sampleCount = _sampleCount(instrument, sampleRate);
  final samples = Float32List(sampleCount);
  final nyquistHz = sampleRate / 2.0;

  for (
    var harmonicIndex = 0;
    harmonicIndex < instrument.harmonics.length;
    harmonicIndex++
  ) {
    final frequencyHz = fundamentalHz * (harmonicIndex + 1);
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
  Biquad.lowShelf(
    frequencyHz: InstrumentEq.lowShelfHz,
    gainDb: eq.lowDb,
    sampleRate: sampleRate,
  ).apply(samples);
  Biquad.peaking(
    frequencyHz: InstrumentEq.midPeakHz,
    gainDb: eq.midDb,
    sampleRate: sampleRate,
  ).apply(samples);
  Biquad.highShelf(
    frequencyHz: InstrumentEq.highShelfHz,
    gainDb: eq.highDb,
    sampleRate: sampleRate,
  ).apply(samples);
}
