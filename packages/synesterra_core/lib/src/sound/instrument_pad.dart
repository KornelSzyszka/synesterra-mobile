import 'dart:math';

import 'instrument.dart';

/// The instrument pad: one dot on a disc shapes a timbre.
///
/// The pad is a view on the existing [Instrument] recipe; the model and its
/// JSON do not change. The angle around the disc picks the character (five
/// named anchors sit on the rim); the distance from the centre sets how
/// pronounced it is: the centre is a neutral recipe ([padCenterRecipe]), the
/// rim is the pure character. See `docs/product/instrument-pad.md`.

/// How far outside the unit circle a point may sit and still count as on it.
/// Rim points built from `cos` and `sin` land within about 1e-16 of the
/// circle.
const double _discTolerance = 1e-12;

/// A point on the pad: the unit disc, `x * x + y * y <= 1`. [x] runs left
/// (dark) to right (bright) and [y] runs up (soft) to down (hard), the screen
/// directions; the centre is `(0, 0)`.
class PadPoint {
  PadPoint(this.x, this.y) {
    if (!x.isFinite) {
      throw ArgumentError.value(x, 'x', 'must be finite');
    }
    if (!y.isFinite) {
      throw ArgumentError.value(y, 'y', 'must be finite');
    }
    if (x * x + y * y > 1 + _discTolerance) {
      throw ArgumentError.value(
        '($x, $y)',
        'point',
        'must lie inside the unit disc (x*x + y*y <= 1)',
      );
    }
  }

  /// The point at [radius] (0 centre, 1 rim) and [angle] in radians, measured
  /// from +x towards +y (clockwise on screen). The angle is irrelevant at the
  /// centre.
  factory PadPoint.polar(double radius, double angle) {
    if (!radius.isFinite || radius < 0 || radius > 1) {
      throw ArgumentError.value(radius, 'radius', 'must be finite, in 0..1');
    }
    if (!angle.isFinite) {
      throw ArgumentError.value(angle, 'angle', 'must be finite');
    }
    return PadPoint(radius * cos(angle), radius * sin(angle));
  }

  final double x;
  final double y;

  /// Distance from the centre, 0..1.
  double get radius => min(1.0, sqrt(x * x + y * y));

  /// Direction in radians, `(-pi, pi]`, from +x towards +y; 0 at the centre,
  /// where the direction is undefined.
  double get angle => atan2(y, x);

  @override
  bool operator ==(Object other) =>
      other is PadPoint && x == other.x && y == other.y;

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() => 'PadPoint($x, $y)';
}

/// A recipe the pad can blend: the sound-defining part of an [Instrument].
class PadRecipe {
  const PadRecipe({
    required this.harmonics,
    required this.attackMs,
    required this.decayMs,
    required this.eq,
  });

  /// A plain sine with a short fade: an alternative [padCenterRecipe].
  static final PadRecipe pureSine = PadRecipe(
    harmonics: const [1],
    attackMs: 5,
    decayMs: 800,
    eq: InstrumentEq(lowDb: 0, midDb: 0, highDb: 0),
  );

  /// Amplitudes; shorter lists are treated as padded with zeros.
  final List<double> harmonics;
  final int attackMs;
  final int decayMs;
  final InstrumentEq eq;
}

/// A named recipe at a fixed place on the rim of the pad.
///
/// **untuned**: the values below are a first proposal derived from the factory
/// instruments and the character names. They are tuned by ear later (`musical`
/// gate, Founder).
class PadAnchor extends PadRecipe {
  const PadAnchor({
    required this.name,
    required this.angle,
    required super.harmonics,
    required super.attackMs,
    required super.decayMs,
    required super.eq,
  });

  final String name;

  /// Place on the rim in radians, from +x towards +y.
  final double angle;

  /// The rim point of this anchor.
  PadPoint get point => PadPoint.polar(1, angle);
}

/// The five Founder-named anchors (2026-10-04, moved to the rim 2026-10-13).
/// **untuned** values.
///
/// They sit where the old square put them, on the circle inscribed in it:
/// `warm drone` top left, `airy pad` top right, `guitar` bottom right, `bass`
/// bottom left and `click` at the bottom (soft at the top, hard at the bottom,
/// dark on the left, bright on the right). The soft side uses a slow attack
/// and a long decay inside the model limits (a true sustain is a later model
/// change). Keep the list ordered so the angles are not needed to read it; the
/// mapping sorts them itself.
final List<PadAnchor> padAnchors = List.unmodifiable([
  PadAnchor(
    name: 'warm drone',
    angle: -3 * pi / 4,
    harmonics: const [1, 0.35, 0.12, 0.04],
    attackMs: 400,
    decayMs: 5000,
    eq: InstrumentEq(lowDb: 3, midDb: -1, highDb: -6),
  ),
  PadAnchor(
    name: 'airy pad',
    angle: -pi / 4,
    harmonics: const [1, 0.5, 0.6, 0.5, 0.4, 0.3, 0.2, 0.12, 0.08],
    attackMs: 300,
    decayMs: 4000,
    eq: InstrumentEq(lowDb: -3, midDb: 0, highDb: 6),
  ),
  PadAnchor(
    name: 'bass',
    angle: 3 * pi / 4,
    harmonics: const [1, 0.6, 0.25, 0.1, 0.04],
    attackMs: 2,
    decayMs: 500,
    eq: InstrumentEq(lowDb: 6, midDb: 0, highDb: -6),
  ),
  PadAnchor(
    name: 'guitar',
    angle: pi / 4,
    harmonics: const [
      1, 0.8, 0.7, 0.55, 0.45, 0.35, 0.28, 0.2, 0.15, 0.1, 0.08, 0.05, //
    ],
    attackMs: 1,
    decayMs: 1200,
    eq: InstrumentEq(lowDb: -1, midDb: 2, highDb: 3),
  ),
  PadAnchor(
    name: 'click',
    angle: pi / 2,
    harmonics: const [1, 0.75, 0.5, 0.35, 0.25, 0.18, 0.12, 0.08, 0.05, 0.03],
    attackMs: 0,
    decayMs: 40,
    eq: InstrumentEq(lowDb: -4, midDb: 4, highDb: 6),
  ),
]);

/// The recipe at the centre of the pad.
///
/// Working default (coordinator, not decided by the Founder): the neutral
/// blend of the five anchors. To change it, replace the right-hand side with
/// another [PadRecipe], for example `PadRecipe.pureSine`; nothing else reads
/// the centre decision.
final PadRecipe padCenterRecipe = _neutralBlend();

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

  factory _Blend.of(PadRecipe recipe, int length) => _Blend(
    [
      for (var h = 0; h < length; h++)
        h < recipe.harmonics.length ? recipe.harmonics[h] : 0.0,
    ],
    log(1 + recipe.attackMs),
    log(recipe.decayMs.toDouble()),
    recipe.eq.lowDb,
    recipe.eq.midDb,
    recipe.eq.highDb,
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

/// The longest harmonic list among the anchors.
final int _anchorLength = padAnchors.map((a) => a.harmonics.length).reduce(max);

/// Equal-weight mean of the anchors in the blending domain, as a recipe.
PadRecipe _neutralBlend() {
  final blends = [for (final a in padAnchors) _Blend.of(a, _anchorLength)];
  double mean(double Function(_Blend) pick) =>
      blends.map(pick).reduce((a, b) => a + b) / blends.length;
  return PadRecipe(
    harmonics: [
      for (var h = 0; h < blends.first.harmonics.length; h++)
        mean((b) => b.harmonics[h]),
    ],
    attackMs: (exp(mean((b) => b.attackLog)) - 1).round(),
    decayMs: exp(mean((b) => b.decayLog)).round(),
    eq: InstrumentEq(
      lowDb: mean((b) => b.lowDb),
      midDb: mean((b) => b.midDb),
      highDb: mean((b) => b.highDb),
    ),
  );
}

/// The anchors in ascending angle, starting at the smallest one.
final List<PadAnchor> _ring = List.unmodifiable(
  [...padAnchors]..sort((a, b) => a.angle.compareTo(b.angle)),
);

/// The pure character at [angle]: the neighbouring anchors on the rim blended
/// linearly in angle, wrapping around the seam.
_Blend _rimAt(double angle, int length) {
  const turn = 2 * pi;
  final first = _ring.first.angle;
  var a = angle;
  while (a < first) {
    a += turn;
  }
  while (a >= first + turn) {
    a -= turn;
  }
  for (var i = 0; i < _ring.length; i++) {
    final lo = _ring[i].angle;
    final last = i == _ring.length - 1;
    final hi = last ? first + turn : _ring[i + 1].angle;
    if (a < hi || last) {
      final t = ((a - lo) / (hi - lo)).clamp(0.0, 1.0);
      return _Blend.mix(
        _Blend.of(_ring[i], length),
        _Blend.of(_ring[(i + 1) % _ring.length], length),
        t,
      );
    }
  }
  throw StateError('unreachable');
}

/// Maps [point] to a valid [Instrument].
///
/// Scheme (polar):
///
/// 1. the rim character at the point's angle is the linear blend, in angle, of
///    the two neighbouring [padAnchors] (the anchors are on the rim and the
///    blend wraps around the seam);
/// 2. the result blends [padCenterRecipe] to that rim character linearly with
///    the radius: the centre is the neutral recipe, the rim the pure
///    character.
///
/// Every blend is linear in a domain that suits the field: harmonic lists are
/// padded with zeros to a common length and blended in amplitude; attack
/// (`ln(1 + ms)`) and decay (`ln(ms)`) are blended in the log domain, so a move
/// changes short and long times by a similar perceived amount; EQ gains are
/// blended in dB. A rim anchor returns its anchor recipe and the centre returns
/// [padCenterRecipe]. The result is deterministic, continuous (also across the
/// angular seam and at the centre, where the angle does not matter) and always
/// satisfies the [Instrument] constructor, because each value is a convex
/// combination of in-range recipe values. Farther from the centre every field
/// moves monotonically toward the rim character.
///
/// [id], [name] and [tags] are passed to [Instrument] and validated there.
Instrument instrumentForPad(
  PadPoint point, {
  required String id,
  required String name,
  List<String> tags = const [],
}) {
  final length = max(_anchorLength, padCenterRecipe.harmonics.length);
  final result = _Blend.mix(
    _Blend.of(padCenterRecipe, length),
    _rimAt(point.angle, length),
    point.radius,
  );

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
