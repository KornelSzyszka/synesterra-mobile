import 'dart:math';
import 'dart:typed_data';

/// One second-order filter section from the Audio EQ Cookbook (RBJ). Shared
/// by the PCM renderer and by the EQ response, so what the picture shows is
/// what the filter does. Internal to the core: not exported.
///
/// Shelf slope S and peaking Q are both 1.0: broad, predictable bands.
class Biquad {
  const Biquad._(this.b0, this.b1, this.b2, this.a1, this.a2);

  factory Biquad.peaking({
    required double frequencyHz,
    required double gainDb,
    required int sampleRate,
  }) {
    final c = _Coefficients(frequencyHz, gainDb, sampleRate, shelf: false);
    return Biquad._normalised(
      1 + c.alpha * c.a,
      -2 * c.cosine,
      1 - c.alpha * c.a,
      1 + c.alpha / c.a,
      -2 * c.cosine,
      1 - c.alpha / c.a,
    );
  }

  factory Biquad.lowShelf({
    required double frequencyHz,
    required double gainDb,
    required int sampleRate,
  }) {
    final c = _Coefficients(frequencyHz, gainDb, sampleRate, shelf: true);
    final rootA = sqrt(c.a);
    return Biquad._normalised(
      c.a * ((c.a + 1) - (c.a - 1) * c.cosine + 2 * rootA * c.alpha),
      2 * c.a * ((c.a - 1) - (c.a + 1) * c.cosine),
      c.a * ((c.a + 1) - (c.a - 1) * c.cosine - 2 * rootA * c.alpha),
      (c.a + 1) + (c.a - 1) * c.cosine + 2 * rootA * c.alpha,
      -2 * ((c.a - 1) + (c.a + 1) * c.cosine),
      (c.a + 1) + (c.a - 1) * c.cosine - 2 * rootA * c.alpha,
    );
  }

  factory Biquad.highShelf({
    required double frequencyHz,
    required double gainDb,
    required int sampleRate,
  }) {
    final c = _Coefficients(frequencyHz, gainDb, sampleRate, shelf: true);
    final rootA = sqrt(c.a);
    return Biquad._normalised(
      c.a * ((c.a + 1) + (c.a - 1) * c.cosine + 2 * rootA * c.alpha),
      -2 * c.a * ((c.a - 1) + (c.a + 1) * c.cosine),
      c.a * ((c.a + 1) + (c.a - 1) * c.cosine - 2 * rootA * c.alpha),
      (c.a + 1) - (c.a - 1) * c.cosine + 2 * rootA * c.alpha,
      2 * ((c.a - 1) - (c.a + 1) * c.cosine),
      (c.a + 1) - (c.a - 1) * c.cosine - 2 * rootA * c.alpha,
    );
  }

  factory Biquad._normalised(
    double b0,
    double b1,
    double b2,
    double a0,
    double a1,
    double a2,
  ) => Biquad._(b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0);

  final double b0;
  final double b1;
  final double b2;
  final double a1;
  final double a2;

  /// Filters [samples] in place.
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

  /// Gain of this section at [frequencyHz], in dB: 20 log10 |H(e^jw)|.
  double magnitudeDb(double frequencyHz, int sampleRate) {
    final w = 2 * pi * frequencyHz / sampleRate;
    final c1 = cos(w);
    final s1 = sin(w);
    final c2 = cos(2 * w);
    final s2 = sin(2 * w);
    final numeratorReal = b0 + b1 * c1 + b2 * c2;
    final numeratorImaginary = -(b1 * s1 + b2 * s2);
    final denominatorReal = 1 + a1 * c1 + a2 * c2;
    final denominatorImaginary = -(a1 * s1 + a2 * s2);
    final squared =
        (numeratorReal * numeratorReal +
            numeratorImaginary * numeratorImaginary) /
        (denominatorReal * denominatorReal +
            denominatorImaginary * denominatorImaginary);
    return 10 * log(squared) / ln10;
  }
}

class _Coefficients {
  _Coefficients(
    double frequencyHz,
    double gainDb,
    int sampleRate, {
    required bool shelf,
  }) {
    final omega = 2 * pi * frequencyHz / sampleRate;
    a = pow(10, gainDb / 40).toDouble();
    final sine = sin(omega);
    cosine = cos(omega);
    alpha = shelf ? sine / sqrt(2) : sine / 2;
  }

  late final double a;
  late final double alpha;
  late final double cosine;
}
