import 'dart:math';

import 'instrument.dart';

/// The instrument pad: one dot on a 2D field shapes a timbre.
///
/// The pad is a view on the existing [Instrument] recipe; the model and its
/// JSON do not change. Horizontal: dark (0) to bright (1). Vertical: soft and
/// airy (0, top) to hard and sharp (1, bottom). See
/// `docs/product/instrument-pad.md`.

/// A point on the pad. [x] runs dark to bright, [y] runs soft (top) to hard
/// (bottom); both are in 0..1.
class PadPoint {
  PadPoint(this.x, this.y) {
    _check(x, 'x');
    _check(y, 'y');
  }

  final double x;
  final double y;

  static void _check(double value, String name) {
    if (!value.isFinite || value < 0 || value > 1) {
      throw ArgumentError.value(value, name, 'must be finite and in 0..1');
    }
  }

  @override
  bool operator ==(Object other) =>
      other is PadPoint && x == other.x && y == other.y;

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() => 'PadPoint($x, $y)';
}

/// A named recipe at a fixed place on the pad.
///
/// **untuned**: the values below are a first proposal derived from the factory
/// instruments and the character names. They are tuned by ear later (`musical`
/// gate, Founder).
class PadAnchor {
  const PadAnchor({
    required this.name,
    required this.x,
    required this.y,
    required this.harmonics,
    required this.attackMs,
    required this.decayMs,
    required this.eq,
  });

  final String name;
  final double x;
  final double y;

  /// Amplitudes; shorter lists are treated as padded with zeros.
  final List<double> harmonics;
  final int attackMs;
  final int decayMs;
  final InstrumentEq eq;
}

/// The five Founder-named anchors (2026-10-04). **untuned** values.
///
/// `warm drone` (0, 0) dark and soft; `airy pad` (1, 0) bright and soft;
/// `bass` (0, 1) dark and hard; `guitar` (1, 1) bright and hard; `click`
/// (0.5, 1) the hardest. The soft half uses a slow attack and a long decay
/// inside the model limits (a true sustain is a later model change).
final List<PadAnchor> padAnchors = List.unmodifiable([
  PadAnchor(
    name: 'warm drone',
    x: 0,
    y: 0,
    harmonics: const [1, 0.35, 0.12, 0.04],
    attackMs: 400,
    decayMs: 5000,
    eq: InstrumentEq(lowDb: 3, midDb: -1, highDb: -6),
  ),
  PadAnchor(
    name: 'airy pad',
    x: 1,
    y: 0,
    harmonics: const [1, 0.5, 0.6, 0.5, 0.4, 0.3, 0.2, 0.12, 0.08],
    attackMs: 300,
    decayMs: 4000,
    eq: InstrumentEq(lowDb: -3, midDb: 0, highDb: 6),
  ),
  PadAnchor(
    name: 'bass',
    x: 0,
    y: 1,
    harmonics: const [1, 0.6, 0.25, 0.1, 0.04],
    attackMs: 2,
    decayMs: 500,
    eq: InstrumentEq(lowDb: 6, midDb: 0, highDb: -6),
  ),
  PadAnchor(
    name: 'guitar',
    x: 1,
    y: 1,
    harmonics: const [
      1, 0.8, 0.7, 0.55, 0.45, 0.35, 0.28, 0.2, 0.15, 0.1, 0.08, 0.05, //
    ],
    attackMs: 1,
    decayMs: 1200,
    eq: InstrumentEq(lowDb: -1, midDb: 2, highDb: 3),
  ),
  PadAnchor(
    name: 'click',
    x: 0.5,
    y: 1,
    harmonics: const [1, 0.75, 0.5, 0.35, 0.25, 0.18, 0.12, 0.08, 0.05, 0.03],
    attackMs: 0,
    decayMs: 40,
    eq: InstrumentEq(lowDb: -4, midDb: 4, highDb: 6),
  ),
]);

/// The recipe in the domain where it is blended: harmonic amplitudes padded
/// to a common length, `ln(1 + attackMs)`, `ln(decayMs)` and EQ gains in dB.
class _Blend {
  _Blend(
    this.harmonics,
    this.attackLog,
    this.decayLog,
    this.lowDb,
    this.midDb,
    this.highDb,
  );

  factory _Blend.of(PadAnchor anchor) => _Blend(
    [
      for (var h = 0; h < _harmonicCount; h++)
        h < anchor.harmonics.length ? anchor.harmonics[h] : 0.0,
    ],
    log(1 + anchor.attackMs),
    log(anchor.decayMs.toDouble()),
    anchor.eq.lowDb,
    anchor.eq.midDb,
    anchor.eq.highDb,
  );

  final List<double> harmonics;
  final double attackLog;
  final double decayLog;
  final double lowDb;
  final double midDb;
  final double highDb;

  /// `a * (1 - t) + b * t`: exactly [a] at 0 and exactly [b] at 1.
  static double _mix(double a, double b, double t) => a * (1 - t) + b * t;

  static _Blend mix(_Blend a, _Blend b, double t) => _Blend(
    [
      for (var h = 0; h < a.harmonics.length; h++)
        _mix(a.harmonics[h], b.harmonics[h], t),
    ],
    _mix(a.attackLog, b.attackLog, t),
    _mix(a.decayLog, b.decayLog, t),
    _mix(a.lowDb, b.lowDb, t),
    _mix(a.midDb, b.midDb, t),
    _mix(a.highDb, b.highDb, t),
  );
}

final int _harmonicCount = padAnchors
    .map((a) => a.harmonics.length)
    .reduce(max);

_Blend _anchor(String name) =>
    _Blend.of(padAnchors.firstWhere((a) => a.name == name));

/// Maps [point] to a valid [Instrument] by blending the five [padAnchors].
///
/// Scheme (edge interpolation, chosen over inverse-distance weighting because
/// it keeps the brightness ordering along every row):
///
/// 1. the top edge blends `warm drone` to `airy pad` with `x`;
/// 2. the bottom edge blends `bass` to `click` (x 0..0.5) and `click` to
///    `guitar` (x 0.5..1) piecewise linearly;
/// 3. the point blends the top-edge recipe to the bottom-edge recipe with `y`.
///
/// Every blend is linear in a domain that suits the field: harmonic lists are
/// padded with zeros to a common length and blended in amplitude; attack
/// (`ln(1 + ms)`) and decay (`ln(ms)`) are blended in the log domain, so a move
/// changes short and long times by a similar perceived amount; EQ gains are
/// blended in dB. An anchor point returns its anchor recipe exactly. The
/// result is deterministic, continuous (piecewise linear in `x` and `y`) and
/// always satisfies the [Instrument] constructor, because each value is a
/// convex combination of in-range anchor values.
///
/// [id], [name] and [tags] are passed to [Instrument] and validated there.
Instrument instrumentForPad(
  PadPoint point, {
  required String id,
  required String name,
  List<String> tags = const [],
}) {
  final top = _Blend.mix(_anchor('warm drone'), _anchor('airy pad'), point.x);
  final bottom = point.x <= 0.5
      ? _Blend.mix(_anchor('bass'), _anchor('click'), point.x * 2)
      : _Blend.mix(_anchor('click'), _anchor('guitar'), point.x * 2 - 1);
  final result = _Blend.mix(top, bottom, point.y);

  const gain = InstrumentEq.maxGainDb;
  return Instrument(
    id: id,
    name: name,
    tags: tags,
    harmonics: [for (final h in result.harmonics) h.clamp(0.0, 1.0)],
    attackMs: (exp(result.attackLog) - 1).round().clamp(
      0,
      Instrument.maxAttackMs,
    ),
    decayMs: exp(result.decayLog)
        .round()
        .clamp(Instrument.minDecayMs, Instrument.maxDecayMs),
    eq: InstrumentEq(
      lowDb: result.lowDb.clamp(-gain, gain),
      midDb: result.midDb.clamp(-gain, gain),
      highDb: result.highDb.clamp(-gain, gain),
    ),
  );
}
