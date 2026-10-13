import 'dart:math';
import 'dart:ui';

// Pure helpers for the instrument stat wheel: an outer ring of tick blocks
// with the trait names written along it, and inside it a chart with one
// spoke per trait, graduated in ten steps with the rank letters E to A. Every
// function works for any number of spokes from three up, because the traits
// are data (`defaultTraitDefinitions`).

/// The touch target of a vertex handle, in logical pixels (at least 48 dp).
const radarHandleTarget = 48.0;

void _checkAxis(int index, int count) {
  if (count < 3) {
    throw ArgumentError.value(count, 'count', 'a radar needs three axes');
  }
  if (index < 0 || index >= count) {
    throw ArgumentError.value(index, 'index', 'must be in 0..${count - 1}');
  }
}

/// The angle of spoke [index] of [count] in radians, from +x towards +y
/// (clockwise on screen). The first spoke points straight up and the others
/// follow clockwise at equal steps.
double radarAxisAngle(int index, int count) {
  _checkAxis(index, count);
  return -pi / 2 + 2 * pi * index / count;
}

/// The unit vector of spoke [index] of [count], in screen coordinates.
Offset radarAxisDirection(int index, int count) {
  final angle = radarAxisAngle(index, count);
  return Offset(cos(angle), sin(angle));
}

// ---------------------------------------------------------------------------
// Layout

/// Space kept outside the tick ring for its soft light.
const wheelMargin = 4.0;

/// Width of the outer band that holds the tick blocks.
const wheelTickBand = 11.0;

/// Gap between the tick band and the names.
const wheelRingGap = 5.0;

/// Height of the band the names are written in.
const wheelNameHeight = 14.0;

/// Gap between the names and the edge of the chart: room for a handle at
/// value 1 and its glow.
const wheelNameGap = 16.0;

/// Margin of a bare wheel (a thumbnail) around its chart: room for the
/// shape's soft halo.
const wheelBareMargin = 12.0;

/// The radii of the wheel in a field: the tick ring from [ringInner] to
/// [outer], the names centred on [nameRadius], and the chart with value 1 at
/// [reach]. A bare wheel (a thumbnail) is only the chart.
class WheelLayout {
  const WheelLayout._({
    required this.centre,
    required this.outer,
    required this.ringInner,
    required this.nameRadius,
    required this.reach,
    required this.hasRing,
  });

  /// The full wheel, centred in [size] and as large as its shorter side.
  factory WheelLayout.of(Size size) {
    final outer = max(0.0, size.shortestSide / 2 - wheelMargin);
    final ringInner = max(0.0, outer - wheelTickBand);
    final nameRadius = max(0.0, ringInner - wheelRingGap - wheelNameHeight / 2);
    return WheelLayout._(
      centre: size.center(Offset.zero),
      outer: outer,
      ringInner: ringInner,
      nameRadius: nameRadius,
      reach: max(0.0, nameRadius - wheelNameHeight / 2 - wheelNameGap),
      hasRing: true,
    );
  }

  /// Only the chart, [wheelBareMargin] inside [size]: for thumbnails.
  factory WheelLayout.bare(Size size) {
    final reach = max(0.0, size.shortestSide / 2 - wheelBareMargin);
    return WheelLayout._(
      centre: size.center(Offset.zero),
      outer: reach,
      ringInner: reach,
      nameRadius: reach,
      reach: reach,
      hasRing: false,
    );
  }

  final Offset centre;
  final double outer;
  final double ringInner;
  final double nameRadius;
  final double reach;

  /// False for a bare wheel.
  final bool hasRing;
}

// ---------------------------------------------------------------------------
// Spokes and touches

/// Where [value] (0 centre, 1 edge) of spoke [index] is drawn.
Offset radarPoint(int index, int count, double value, Size size, double reach) {
  return size.center(Offset.zero) +
      radarAxisDirection(index, count) * (value * reach);
}

/// The value under a touch at [local] when it drags spoke [index]: the touch
/// projected onto the spoke (only the part along it counts), as a share of
/// [reach], clamped to 0..1. A touch with a NaN coordinate counts as the
/// centre and an infinite one as very far.
double radarProject(
  Offset local,
  int index,
  int count,
  Size size,
  double reach,
) {
  final direction = radarAxisDirection(index, count);
  if (reach <= 0 || local.dx.isNaN || local.dy.isNaN) return 0;
  final from = size.center(Offset.zero);
  final dx = (local.dx - from.dx).clamp(-1e9, 1e9);
  final dy = (local.dy - from.dy).clamp(-1e9, 1e9);
  return ((dx * direction.dx + dy * direction.dy) / reach).clamp(0.0, 1.0);
}

/// The spokes whose handle is within half of [target] of [local], nearest
/// first; several when handles are stacked (all at the centre, say).
List<int> radarHandlesAt(
  Offset local,
  List<double> values,
  Size size,
  double reach, {
  double target = radarHandleTarget,
}) {
  if (!local.dx.isFinite || !local.dy.isFinite) return const [];
  final count = values.length;
  final hits = <(int, double)>[];
  for (var i = 0; i < count; i++) {
    final distance =
        (local - radarPoint(i, count, values[i], size, reach)).distance;
    if (distance <= target / 2) hits.add((i, distance));
  }
  // Equal distances (stacked handles) keep spoke order.
  hits.sort((a, b) {
    final byDistance = a.$2.compareTo(b.$2);
    return byDistance != 0 ? byDistance : a.$1.compareTo(b.$1);
  });
  return [for (final (i, _) in hits) i];
}

/// The spoke a touch at [local] grabs, or null. The nearest handle within
/// half of [target] wins; otherwise the spoke whose line (centre to edge,
/// plus half the target at each end) passes closest, within half of
/// [target].
int? radarHitAxis(
  Offset local,
  List<double> values,
  Size size,
  double reach, {
  double target = radarHandleTarget,
}) {
  final handles = radarHandlesAt(local, values, size, reach, target: target);
  if (handles.isNotEmpty) return handles.first;
  if (!local.dx.isFinite || !local.dy.isFinite) return null;

  final count = values.length;
  final half = target / 2;
  final from = local - size.center(Offset.zero);
  int? best;
  var bestDistance = double.infinity;
  for (var i = 0; i < count; i++) {
    final direction = radarAxisDirection(i, count);
    final along = from.dx * direction.dx + from.dy * direction.dy;
    final across = (from.dx * direction.dy - from.dy * direction.dx).abs();
    if (along >= -half &&
        along <= reach + half &&
        across <= half &&
        across < bestDistance) {
      best = i;
      bestDistance = across;
    }
  }
  return best;
}

/// Of stacked [candidates], the spoke a first move [delta] points along most.
int radarPickByDirection(List<int> candidates, Offset delta, int count) {
  var best = candidates.first;
  var bestDot = double.negativeInfinity;
  for (final i in candidates) {
    final direction = radarAxisDirection(i, count);
    final dot = delta.dx * direction.dx + delta.dy * direction.dy;
    if (dot > bestDot) {
      best = i;
      bestDot = dot;
    }
  }
  return best;
}

// ---------------------------------------------------------------------------
// Ranks: ten steps from the centre, five letters

/// Steps from the centre (0) to the edge.
const rankSteps = 10;

/// The rank letters from the centre outward. Each rank spans two steps: its
/// letter (an odd step) and the half-step above it (`+`).
const rankLetters = ['E', 'D', 'C', 'B', 'A'];

/// The step (0..[rankSteps]) nearest to [value]; NaN counts as 0.
int rankStep(double value) {
  if (value.isNaN) return 0;
  return (value.clamp(0.0, 1.0) * rankSteps).round();
}

/// The value of [step].
double rankValue(int step) => step.clamp(0, rankSteps) / rankSteps;

/// [value] snapped to the nearest step.
double snapToRank(double value) => rankValue(rankStep(value));

/// True for the steps that carry a letter (1, 3, 5, 7, 9).
bool isLetterStep(int step) => step > 0 && step <= rankSteps && step.isOdd;

/// The step of letter [rank] (0 = E .. 4 = A).
int rankLetterStep(int rank) => 2 * rank + 1;

/// The short name of [step]: `none` at the centre, then E, E+, D, D+ .. A+.
String rankName(int step) {
  final s = step.clamp(0, rankSteps);
  if (s == 0) return 'none';
  final letter = rankLetters[(s - 1) ~/ 2];
  return s.isOdd ? letter : '$letter+';
}

/// [rankName] for screen readers: `C plus` instead of `C+`.
String rankSpoken(int step) => rankName(step).replaceAll('+', ' plus');

/// The value one step up ([direction] > 0) or down from [value]'s nearest
/// step, clamped to 0..1.
double rankStepFrom(double value, int direction) =>
    rankValue(rankStep(value) + direction.sign);

/// A graduation mark on a spoke.
typedef SpokeTick = ({int step, double value, bool letter});

/// The marks on every spoke: one per step from 1 to [rankSteps]; the letter
/// steps are drawn longer.
List<SpokeTick> spokeTicks() => [
  for (var step = 1; step <= rankSteps; step++)
    (step: step, value: rankValue(step), letter: isLetterStep(step)),
];

/// Distance of the rank letters from the first spoke.
const rankLetterOffset = 16.0;

/// Where the letter of [step] starts: beside the first spoke (on its
/// clockwise side, clear of a handle on it), level with the step.
Offset rankLetterPoint(int step, int count, Size size, double reach) {
  final direction = radarAxisDirection(0, count);
  final side = Offset(-direction.dy, direction.dx);
  return radarPoint(0, count, rankValue(step), size, reach) +
      side * rankLetterOffset;
}

// ---------------------------------------------------------------------------
// The outer ring

/// Tick blocks per sector of the ring (one sector per spoke). Even, so one
/// block points at each name.
const ringTicksPerSector = 6;

enum RingTickKind {
  /// Between two names.
  divider,

  /// Over a name, on its spoke's angle.
  axis,

  /// Every other block.
  minor,
}

typedef RingTick = ({double angle, RingTickKind kind});

/// The tick blocks of the ring for [count] spokes, clockwise from the
/// divider before the first name, evenly spaced: in each sector a divider,
/// minor blocks, and one block on the spoke's angle, over its name.
List<RingTick> ringTicks(int count) {
  _checkAxis(0, count);
  final sector = 2 * pi / count;
  const half = ringTicksPerSector ~/ 2;
  return [
    for (var i = 0; i < count; i++)
      for (var k = 0; k < ringTicksPerSector; k++)
        (
          angle:
              radarAxisAngle(i, count) +
              sector * (k - half) / ringTicksPerSector,
          kind: k == 0
              ? RingTickKind.divider
              : k == half
              ? RingTickKind.axis
              : RingTickKind.minor,
        ),
  ];
}

// ---------------------------------------------------------------------------
// Names along the ring

/// The smallest scale a name is drawn at before it is squeezed in anyway.
const ringMinLabelScale = .6;

/// The least arc, in logical pixels, kept free between two names.
const ringLabelGap = 14.0;

/// True when a name centred at [angle] is on the bottom half of the ring:
/// it is written counter-clockwise there, so it reads left to right, upright.
bool ringReadsReversed(double angle) => sin(angle) > 1e-9;

/// The arc (radians) a name with glyph [advances] takes at [radius].
double ringLabelSpan(List<double> advances, double radius) {
  if (radius <= 0) return 0;
  var total = 0.0;
  for (final a in advances) {
    total += a;
  }
  return total / radius;
}

/// One scale for all names so the longest fits its sector with
/// [ringLabelGap] to each neighbour: at most 1, at least
/// [ringMinLabelScale].
double ringLabelScale(
  List<List<double>> labels, {
  required double radius,
  required int count,
}) {
  if (radius <= 0) return ringMinLabelScale;
  final room = 2 * pi / count - ringLabelGap / radius;
  var scale = 1.0;
  for (final label in labels) {
    final span = ringLabelSpan(label, radius);
    if (span > room) scale = min(scale, room / span);
  }
  return scale.clamp(ringMinLabelScale, 1.0);
}

/// Where one letter of a name on the ring is drawn: its centre [position]
/// (on the ring), the [angle] of that point and the [rotation] to draw it
/// with so its top faces outward (top half) or toward the centre (bottom
/// half).
typedef RingGlyph = ({Offset position, double angle, double rotation});

/// The letters of a name with glyph [advances] (in reading order) written
/// along a ring of [radius] round [centre], centred on [angle].
List<RingGlyph> ringGlyphs({
  required Offset centre,
  required double radius,
  required double angle,
  required List<double> advances,
}) {
  if (radius <= 0) return const [];
  final reversed = ringReadsReversed(angle);
  final span = ringLabelSpan(advances, radius);
  final direction = reversed ? -1.0 : 1.0;
  var along = -span / 2;
  final glyphs = <RingGlyph>[];
  for (final advance in advances) {
    final half = advance / 2 / radius;
    final at = angle + direction * (along + half);
    glyphs.add((
      position: centre + Offset(cos(at), sin(at)) * radius,
      angle: at,
      rotation: reversed ? at - pi / 2 : at + pi / 2,
    ));
    along += 2 * half;
  }
  return glyphs;
}
