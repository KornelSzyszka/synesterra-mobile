import 'dart:math' as math;
import 'dart:ui';

import '../theme/design_scale.dart';

/// Pure geometry for the loop views. No canvas, no widgets: every function is
/// a number in, a number or point out, so it is unit-tested directly.
///
/// Fractions are positions in a cycle, in [0, 1). Angles are radians in canvas
/// space: 0 points right, positive turns clockwise, and a cycle starts at
/// 12 o'clock.

/// Where step [stepIndex] of [stepCount] hits in the cycle. Steps are evenly
/// spaced; [phaseSteps] moves every step forward and wraps (the planner's
/// rule).
double stepFraction(int stepIndex, int stepCount, {int phaseSteps = 0}) =>
    ((stepIndex + phaseSteps) % stepCount) / stepCount;

/// The angle of the playhead at [cyclePosition]: 12 o'clock, clockwise.
double playheadAngle(double cyclePosition) =>
    -math.pi / 2 + 2 * math.pi * cyclePosition;

/// The point at [angle] on the circle of [radius] around [center].
Offset pointOnCircle(Offset center, double radius, double angle) =>
    center + Offset(math.cos(angle), math.sin(angle)) * radius;

/// The radius of ring [layerIndex] of [layerCount], the first layer outermost.
/// The innermost ring keeps at least a third of [outerRadius].
double ringRadius(int layerIndex, int layerCount, double outerRadius) {
  if (layerCount <= 1) return outerRadius;
  const innerFraction = 0.36;
  final t = layerIndex / (layerCount - 1);
  return outerRadius * (1 - (1 - innerFraction) * t);
}

/// The vertices of a regular polygon with [count] vertices on the circle of
/// [radius]: vertex 0 at the top, then clockwise. Two vertices make a line
/// through the centre, one vertex a point.
List<Offset> polygonVertices(Offset center, double radius, int count) => [
  for (var i = 0; i < count; i++)
    pointOnCircle(center, radius, playheadAngle(i / count)),
];

/// Where the dot is on the closed polygon at [cyclePosition]: on vertex `k`
/// exactly when step `k` hits (see [stepFraction]) and on the edge to the next
/// vertex in between. A line is walked there and back.
Offset polygonDotPoint(
  List<Offset> vertices,
  double cyclePosition, {
  int phaseSteps = 0,
}) {
  final n = vertices.length;
  if (n == 1) return vertices.first;
  final u = ((cyclePosition * n - phaseSteps) % n + n) % n;
  final from = u.floor() % n;
  final t = u - u.floor();
  return Offset.lerp(vertices[from], vertices[(from + 1) % n], t)!;
}

/// The x of the playhead on a timeline that starts at [left] and is [width]
/// wide.
double timelineX(double cyclePosition, double left, double width) =>
    left + width * cyclePosition;

/// A hit pulse: 1 at the hit, fading linearly to 0 over [window] of a cycle
/// after it, 0 before it. Wraps around the end of the cycle.
double stepPulse(
  double cyclePosition,
  double stepFraction, {
  double window = 0.12,
}) {
  final since = ((cyclePosition - stepFraction) % 1 + 1) % 1;
  return since >= window ? 0 : 1 - since / window;
}

/// The ring view's centre and outer radius inside [size].
class RingLayout {
  RingLayout(this.size)
    : center = size.center(Offset.zero),
      outerRadius = math.max(1, size.shortestSide / 2 - Space.xl);

  final Size size;
  final Offset center;
  final double outerRadius;
}

/// The timeline view's plot area and rows inside [size]: a left gutter for
/// the layer number, then the cycle.
class TimelineLayout {
  TimelineLayout(this.size, this.layerCount)
    : left = Space.xl + Space.md,
      right = size.width - Space.lg,
      top = Space.lg,
      bottom = size.height - Space.lg;

  final Size size;
  final int layerCount;
  final double left;
  final double right;
  final double top;
  final double bottom;

  double get width => right - left;
  double get rowHeight => (bottom - top) / layerCount;
  double rowCenterY(int layerIndex) => top + rowHeight * (layerIndex + 0.5);
}

/// One cell per layer for the polygons view: one column for one layer, two
/// columns from two, filled row by row.
List<Rect> polygonCells(Size size, int layerCount) {
  final columns = layerCount <= 1 ? 1 : 2;
  final rows = (layerCount + columns - 1) ~/ columns;
  final w = size.width / columns;
  final h = size.height / rows;
  return [
    for (var i = 0; i < layerCount; i++)
      Rect.fromLTWH((i % columns) * w, (i ~/ columns) * h, w, h),
  ];
}

/// The polygon radius that fits [cell] with room for the number and the dot.
double polygonRadius(Rect cell) =>
    math.max(1, cell.shortestSide / 2 - Space.xl);
