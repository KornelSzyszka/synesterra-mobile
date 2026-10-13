import 'dart:math';
import 'dart:ui';

// Pure helpers for the instrument radar: where each axis points, where a
// value sits on it, which axis a touch grabs and how a touch projects onto an
// axis. Every function works for any number of axes from three up, because
// the traits are data (`defaultTraitDefinitions`). The radar is centred in its
// field; its reach (the distance from the centre to value 1) comes from
// [radarReach].

/// The touch target of a vertex handle, in logical pixels (at least 48 dp).
const radarHandleTarget = 48.0;

/// The space kept for one axis label outside the reach. Labels are drawn
/// inside this box; a longer one is scaled down to fit.
const radarLabelBox = Size(80, 22);

/// The gap between the end of an axis and its label.
const radarLabelGap = 10.0;

/// The room kept around the reach for a handle and the soft glow of the shape.
const radarMargin = 12.0;

/// How far one screen-reader step moves a trait: a tenth of the axis.
const radarStepSize = 0.1;

void _checkAxis(int index, int count) {
  if (count < 3) {
    throw ArgumentError.value(count, 'count', 'a radar needs three axes');
  }
  if (index < 0 || index >= count) {
    throw ArgumentError.value(index, 'index', 'must be in 0..${count - 1}');
  }
}

/// The angle of axis [index] of [count] in radians, from +x towards +y
/// (clockwise on screen). The first axis points straight up and the others
/// follow clockwise at equal steps.
double radarAxisAngle(int index, int count) {
  _checkAxis(index, count);
  return -pi / 2 + 2 * pi * index / count;
}

/// The unit vector of axis [index] of [count], in screen coordinates.
Offset radarAxisDirection(int index, int count) {
  final angle = radarAxisAngle(index, count);
  return Offset(cos(angle), sin(angle));
}

/// The largest reach in a field of [size] that keeps a [label] box (placed
/// [gap] beyond each axis end, see [radarLabelRect]) and the [margin] inside
/// the field; 0 when nothing fits.
double radarReach(
  Size size,
  int count, {
  Size label = radarLabelBox,
  double gap = radarLabelGap,
  double margin = radarMargin,
}) {
  var reach = min(size.width, size.height) / 2 - margin;
  for (var i = 0; i < count; i++) {
    final direction = radarAxisDirection(i, count);
    for (final (along, half, extent) in [
      (direction.dx.abs(), size.width / 2, label.width),
      (direction.dy.abs(), size.height / 2, label.height),
    ]) {
      if (along < 1e-9) continue;
      reach = min(reach, (half - extent * (1 + along) / 2) / along - gap);
    }
  }
  return max(0, reach);
}

/// The box of the label of axis [index]: its edge nearest to the centre sits
/// [gap] beyond the end of the axis, so it reads outward from the shape.
Rect radarLabelRect(
  int index,
  int count,
  Size size,
  double reach, {
  Size label = radarLabelBox,
  double gap = radarLabelGap,
}) {
  final direction = radarAxisDirection(index, count);
  final at = size.center(Offset.zero) + direction * (reach + gap);
  return Rect.fromLTWH(
    at.dx - label.width * (1 - direction.dx) / 2,
    at.dy - label.height * (1 - direction.dy) / 2,
    label.width,
    label.height,
  );
}

/// Where [value] (0 centre, 1 edge) of axis [index] is drawn.
Offset radarPoint(int index, int count, double value, Size size, double reach) {
  return size.center(Offset.zero) +
      radarAxisDirection(index, count) * (value * reach);
}

/// The value under a touch at [local] when it drags axis [index]: the touch
/// projected onto the axis (only the part along the axis counts), as a share
/// of [reach], clamped to 0..1. A touch with a NaN coordinate counts as the
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

/// The axis a touch at [local] grabs, or null. The nearest handle within half
/// of [target] wins; otherwise the axis whose line (centre to edge, plus half
/// the target at each end) passes closest, within half of [target].
int? radarHitAxis(
  Offset local,
  List<double> values,
  Size size,
  double reach, {
  double target = radarHandleTarget,
}) {
  if (!local.dx.isFinite || !local.dy.isFinite) return null;
  final count = values.length;
  final half = target / 2;
  int? best;
  var bestDistance = double.infinity;
  for (var i = 0; i < count; i++) {
    final distance =
        (local - radarPoint(i, count, values[i], size, reach)).distance;
    if (distance <= half && distance < bestDistance) {
      best = i;
      bestDistance = distance;
    }
  }
  if (best != null) return best;

  final from = local - size.center(Offset.zero);
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

/// [value] moved one screen-reader step up ([direction] > 0) or down, to the
/// next whole tenth, so stepping from 0.53 gives 0.6 or 0.5. Clamped to 0..1.
double radarStep(double value, int direction) {
  final steps = (1 / radarStepSize).round();
  final at = value * steps;
  final next = direction > 0 ? (at + 1e-9).floor() + 1 : (at - 1e-9).ceil() - 1;
  return (next / steps).clamp(0.0, 1.0);
}

/// A value as a whole percent, for spoken levels.
int radarPercent(double value) => (value * 100).round();
