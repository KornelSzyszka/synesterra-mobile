import 'dart:math' as math;
import 'dart:ui';

/// A circle in the middle of [rect].
Path circlePath(Rect rect) => Path()
  ..addOval(
    Rect.fromCircle(center: rect.center, radius: rect.shortestSide / 2),
  );

/// A capsule: two half circles joined by straight lines. A circle when
/// [rect] is square.
Path capsulePath(Rect rect) => Path()
  ..addRRect(
    RRect.fromRectAndRadius(rect, Radius.circular(rect.shortestSide / 2)),
  );

/// A smooth closed curve through [points] (Catmull-Rom as cubic Béziers).
Path smoothClosedPath(List<Offset> points) {
  final path = Path();
  final n = points.length;
  if (n < 3) return path;
  path.moveTo(points[0].dx, points[0].dy);
  for (var i = 0; i < n; i++) {
    final p0 = points[(i - 1 + n) % n];
    final p1 = points[i];
    final p2 = points[(i + 1) % n];
    final p3 = points[(i + 2) % n];
    final c1 = p1 + (p2 - p0) / 6;
    final c2 = p2 - (p3 - p1) / 6;
    path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p2.dx, p2.dy);
  }
  return path..close();
}

/// Three slow waves of one blob: wave numbers, weights and phases from
/// [seed], so each element has its own, stable asymmetry.
List<(int, double, double)> _waves(int seed) {
  final random = math.Random(seed);
  return [
    (2, .55 + .3 * random.nextDouble(), random.nextDouble() * 2 * math.pi),
    (3, .35 + .3 * random.nextDouble(), random.nextDouble() * 2 * math.pi),
    (5, .12 + .1 * random.nextDouble(), random.nextDouble() * 2 * math.pi),
  ];
}

/// The capsule (a circle when square) through [rect] with its edge pushed in
/// and out along the normal by slow waves: a soft blob. [amount] is the
/// largest push as a share of the half height; [phase] (radians) makes it
/// breathe, each wave at its own whole-number speed so a full turn loops.
Path blobPath(
  Rect rect, {
  required int seed,
  double amount = .07,
  double phase = 0,
  int samples = 64,
}) {
  final base = capsulePath(rect);
  final metric = base.computeMetrics().first;
  final reach = rect.shortestSide / 2 * amount;
  final waves = _waves(seed);
  const speeds = [1, -1, 2];
  final points = <Offset>[];
  for (var i = 0; i < samples; i++) {
    final u = i / samples;
    final tangent = metric.getTangentForOffset(metric.length * u)!;
    var normal = Offset(tangent.vector.dy, -tangent.vector.dx);
    if ((tangent.position - rect.center).dx * normal.dx +
            (tangent.position - rect.center).dy * normal.dy <
        0) {
      normal = -normal;
    }
    var push = 0.0;
    for (var w = 0; w < waves.length; w++) {
      final (k, weight, offset) = waves[w];
      push +=
          weight * math.sin(k * 2 * math.pi * u + offset + speeds[w] * phase);
    }
    points.add(tangent.position + normal * (push * reach));
  }
  return smoothClosedPath(points);
}

/// A pebble: a superellipse `|x/a|^n + |y/b|^n = 1` (n = 2 is an ellipse,
/// larger is fuller) with a faint hand-made unevenness from [seed].
Path pebblePath(Rect rect, {required int seed, double exponent = 2.4}) {
  final a = rect.width / 2;
  final b = rect.height / 2;
  final waves = _waves(seed);
  final unevenness = rect.shortestSide / 2 * .018;
  const samples = 72;
  final points = <Offset>[];
  for (var i = 0; i < samples; i++) {
    final t = 2 * math.pi * i / samples;
    final c = math.cos(t);
    final s = math.sin(t);
    final x = a * c.sign * math.pow(c.abs(), 2 / exponent);
    final y = b * s.sign * math.pow(s.abs(), 2 / exponent);
    var push = 0.0;
    for (final (k, weight, offset) in waves) {
      push += weight * math.sin(k * t + offset);
    }
    final direction = Offset(c, s);
    points.add(rect.center + Offset(x, y) + direction * (push * unevenness));
  }
  return smoothClosedPath(points);
}
