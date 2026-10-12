import 'dart:math';
import 'dart:ui';

import 'package:synesterra_core/synesterra_core.dart';

// Pure helpers for the circular instrument pad: touch positions to pad points
// and back. The disc is centred in the field; its radius is half the shorter
// side minus [padInset].

/// The margin between the rim of the disc and the edge of the field, so the
/// dot is always fully inside the field, also on the rim.
const padInset = 16.0;

/// How far one accessibility adjustment turns the character around the
/// circle: 15 degrees, so a full turn is 24 steps.
const padStepAngle = pi / 12;

/// How far one accessibility adjustment moves the strength: 10 % of the way
/// from the centre to the rim.
const padStepRadius = 0.1;

/// The direction used when a step starts with no angle yet (nothing touched,
/// or the exact centre): straight up.
const _startAngle = -pi / 2;

/// The strength used when turning starts with no point yet.
const _startRadius = 0.5;

/// The radius of the disc in a field of [size], in logical pixels; 0 when the
/// field is too small to hold it.
double padDiscRadius(Size size, {double inset = padInset}) =>
    max(0, min(size.width, size.height) / 2 - inset);

/// A touch component made safe: NaN counts as the centre, an infinity as very
/// far in its direction.
double _finite(double v) => v.isNaN ? 0 : v.clamp(-1e9, 1e9);

/// The pad point under a touch at [local] in a field of [size]. A touch
/// outside the disc clamps onto the rim in its direction, so the result is
/// always valid.
PadPoint padPointAt(Offset local, Size size, {double inset = padInset}) {
  final reach = padDiscRadius(size, inset: inset);
  if (reach <= 0) return PadPoint(0, 0);
  final dx = _finite(local.dx - size.width / 2) / reach;
  final dy = _finite(local.dy - size.height / 2) / reach;
  final length = sqrt(dx * dx + dy * dy);
  if (length <= 1) return PadPoint(dx, dy);
  return PadPoint(dx / length, dy / length);
}

/// Where [point] is drawn in a field of [size]; the inverse of [padPointAt]
/// inside the disc.
Offset padOffsetOf(PadPoint point, Size size, {double inset = padInset}) {
  final reach = padDiscRadius(size, inset: inset);
  return Offset(
    size.width / 2 + point.x * reach,
    size.height / 2 + point.y * reach,
  );
}

/// [from] turned by [dAngle] radians and pushed by [dRadius], clamped to the
/// disc. Turning keeps the strength and strength keeps the direction. With no
/// point yet, or at the exact centre where the direction is undefined, a step
/// starts straight up (and turning starts at half strength, since turning at
/// the centre would change nothing).
PadPoint stepPadPoint(PadPoint? from, {double dAngle = 0, double dRadius = 0}) {
  final atCentre = from == null || from.radius < 1e-9;
  final angle = atCentre ? _startAngle : from.angle;
  var radius = from?.radius ?? 0;
  if (dAngle != 0 && atCentre) radius = _startRadius;
  radius = (radius + dRadius).clamp(0.0, 1.0);
  return PadPoint.polar(radius, angle + dAngle);
}

/// A strength as a whole percent, for spoken values.
int padPercent(double radius) => (radius * 100).round();

/// The name of the anchor closest to [point] in angle, for spoken values.
String padCharacterName(PadPoint point) {
  double gap(PadAnchor a) {
    final turn = (a.angle - point.angle).abs() % (2 * pi);
    return min(turn, 2 * pi - turn);
  }

  return padAnchors.reduce((a, b) => gap(a) <= gap(b) ? a : b).name;
}
