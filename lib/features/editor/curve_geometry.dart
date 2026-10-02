// Pure geometry for the envelope and EQ graphs: how times, frequencies and
// gains map to positions, and which handle a touch picks.
import 'dart:math' as math;
import 'dart:ui' show Offset;

double _clamp(double value, double min, double max) =>
    value < min ? min : (value > max ? max : value);

/// The longest envelope the graph shows: the largest attack plus the largest
/// decay an instrument can have.
const envelopeSpanSeconds = 5.5;

/// A square-root time axis, so a 2 ms click and a 5 s tail are both readable.
double envelopeTimeToX(double seconds, double width) =>
    math.sqrt(_clamp(seconds / envelopeSpanSeconds, 0, 1)) * width;

double envelopeXToTime(double x, double width) {
  if (width <= 0) return 0;
  final fraction = _clamp(x / width, 0, 1);
  return fraction * fraction * envelopeSpanSeconds;
}

/// The frequency range of the EQ graph, with a logarithmic axis.
const eqMinHz = 20.0;
const eqMaxHz = 20000.0;

double hzToX(double hz, double width) =>
    math.log(_clamp(hz, eqMinHz, eqMaxHz) / eqMinHz) /
    math.log(eqMaxHz / eqMinHz) *
    width;

double xToHz(double x, double width) {
  if (width <= 0) return eqMinHz;
  final fraction = _clamp(x / width, 0, 1);
  return eqMinHz * math.pow(eqMaxHz / eqMinHz, fraction);
}

/// The gain range of the EQ graph, in dB.
const eqGraphDb = 12.0;

/// +12 dB is the top, -12 dB the bottom.
double dbToY(double db, double height) =>
    (1 - (_clamp(db, -eqGraphDb, eqGraphDb) + eqGraphDb) / (2 * eqGraphDb)) *
    height;

/// The gain for a touch at [y], clamped to ±12 dB and rounded to 0.5 dB so a
/// handle does not jitter.
double yToDb(double y, double height) {
  if (height <= 0) return 0;
  final db = (1 - _clamp(y / height, 0, 1)) * 2 * eqGraphDb - eqGraphDb;
  return (db * 2).round() / 2;
}

/// How far from a handle a touch still grabs it, in logical pixels.
const handleGrabRadius = 28.0;

/// The handle closest to [touch] within [radius], or null when none is
/// close enough.
int? nearestHandle(
  Offset touch,
  List<Offset> handles, {
  double radius = handleGrabRadius,
}) {
  int? best;
  var bestDistance = radius;
  for (var i = 0; i < handles.length; i++) {
    final distance = (handles[i] - touch).distance;
    if (distance <= bestDistance) {
      best = i;
      bestDistance = distance;
    }
  }
  return best;
}
