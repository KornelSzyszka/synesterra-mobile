import 'dart:math' as math;
import 'dart:typed_data';

/// A pitch found in one buffer: [frequencyHz] and how periodic the signal was.
class PitchEstimate {
  const PitchEstimate({required this.frequencyHz, required this.clarity});

  final double frequencyHz;

  /// 0..1, higher is a cleaner periodic signal (`1 - YIN aperiodicity`).
  final double clarity;
}

/// Monophonic pitch detection with the YIN algorithm
/// (de Cheveigne and Kawahara, 2002), over a buffer of mono samples.
///
/// Pure: the caller passes the samples and their [sampleRate]; the core never
/// reads a microphone. [detect] returns `null` ("no pitch") for silence, noise
/// and anything not clearly periodic inside [minFrequencyHz]..[maxFrequencyHz].
///
/// Window choice: YIN compares the buffer with itself shifted by up to one
/// period of the lowest note, and needs a comparison window at least as long
/// as that shift. For [minFrequencyHz] = 40 Hz at 44.1 kHz the longest period
/// is 1103 samples (25 ms), so [minSamples] is about 2200 and the app uses
/// 4096 samples (93 ms): the comparison window of about 3000 samples holds
/// roughly three periods of E1 (41.2 Hz). Overlapping buffers (a hop shorter
/// than the buffer) keep updates frequent; the cost is up to one buffer length
/// of latency when a new note starts.
class PitchDetector {
  PitchDetector({
    required this.sampleRate,
    this.minFrequencyHz = 40,
    this.maxFrequencyHz = 2000,
    this.threshold = 0.15,
    this.minRms = 0.005,
  }) {
    if (sampleRate < 8000) {
      throw ArgumentError.value(sampleRate, 'sampleRate', 'at least 8000');
    }
    if (minFrequencyHz <= 0 || maxFrequencyHz <= minFrequencyHz) {
      throw ArgumentError.value(maxFrequencyHz, 'maxFrequencyHz', 'bad range');
    }
    if (maxFrequencyHz * 2 > sampleRate) {
      throw ArgumentError.value(
        maxFrequencyHz,
        'maxFrequencyHz',
        'above the Nyquist limit',
      );
    }
    if (threshold <= 0 || threshold >= 1) {
      throw ArgumentError.value(threshold, 'threshold', 'between 0 and 1');
    }
    if (minRms < 0) {
      throw ArgumentError.value(minRms, 'minRms', 'not negative');
    }
  }

  final double sampleRate;
  final double minFrequencyHz;
  final double maxFrequencyHz;

  /// Aperiodicity below which a lag is accepted as the period. Lower is
  /// stricter (fewer false pitches, more "no pitch").
  final double threshold;

  /// Buffers quieter than this RMS (full scale = 1.0) are silence.
  final double minRms;

  int get _maxLag => (sampleRate / minFrequencyHz).ceil();
  int get _minLag => math.max(2, (sampleRate / maxFrequencyHz).floor());

  /// Shortest buffer [detect] accepts: two longest periods.
  int get minSamples => _maxLag * 2;

  /// The pitch in [samples] (mono, -1..1), or `null` if there is none.
  PitchEstimate? detect(Float32List samples) {
    final maxLag = _maxLag;
    final minLag = _minLag;
    if (samples.length < minSamples) {
      throw ArgumentError.value(
        samples.length,
        'samples.length',
        'needs at least $minSamples samples',
      );
    }

    var energy = 0.0;
    for (final s in samples) {
      energy += s * s;
    }
    if (math.sqrt(energy / samples.length) < minRms) return null;

    final window = samples.length - maxLag;
    // Difference function, then cumulative mean normalisation.
    final cmnd = Float64List(maxLag + 1);
    cmnd[0] = 1;
    var running = 0.0;
    for (var tau = 1; tau <= maxLag; tau++) {
      var sum = 0.0;
      for (var j = 0; j < window; j++) {
        final delta = samples[j] - samples[j + tau];
        sum += delta * delta;
      }
      running += sum;
      cmnd[tau] = running == 0 ? 1 : sum * tau / running;
    }

    // First lag under the threshold, followed down to its local minimum.
    var tau = -1;
    for (var t = minLag; t < maxLag; t++) {
      if (cmnd[t] < threshold) {
        while (t + 1 < maxLag && cmnd[t + 1] < cmnd[t]) {
          t++;
        }
        tau = t;
        break;
      }
    }
    if (tau < 0) return null;

    // Parabolic interpolation around the minimum for sub-sample accuracy.
    var better = tau.toDouble();
    if (tau > 1 && tau < maxLag) {
      final a = cmnd[tau - 1];
      final b = cmnd[tau];
      final c = cmnd[tau + 1];
      final denominator = a - 2 * b + c;
      if (denominator != 0) better += (a - c) / (2 * denominator);
    }
    final frequency = sampleRate / better;
    // One percent of slack: interpolation may land just past the limits.
    if (frequency < minFrequencyHz * 0.99 ||
        frequency > maxFrequencyHz * 1.01) {
      return null;
    }
    return PitchEstimate(
      frequencyHz: frequency,
      clarity: (1 - cmnd[tau]).clamp(0.0, 1.0),
    );
  }
}
