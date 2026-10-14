import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart' show immutable;

// Visual language v2: round shapes. Circles, capsules, soft organic blobs and
// pebbles (superellipses). The rounded-rectangle `Radii` in design_scale.dart
// stay for screens that have not moved to these shapes yet.

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
}) => smoothClosedPath(
  blobSamples(
    rect,
    seed: seed,
    amount: amount,
    phase: phase,
    samples: samples,
  ).points,
);

/// The points [blobPath] smooths, with the outward unit normal of the
/// capsule at each: the base a living blob moves its edge from.
({List<Offset> points, List<Offset> normals}) blobSamples(
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
  final normals = <Offset>[];
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
    normals.add(normal);
  }
  return (points: points, normals: normals);
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

/// A sheet top shaped like a lens: one shallow circular arc rising [rise]
/// above the sides, open (straight) at the bottom edge.
Path lensPath(Rect rect, {double rise = 22}) {
  final r = math.min(rise, rect.height / 2);
  final radius = (rect.width * rect.width / 4 + r * r) / (2 * r);
  return Path()
    ..moveTo(rect.left, rect.bottom)
    ..lineTo(rect.left, rect.top + r)
    ..arcToPoint(
      Offset(rect.right, rect.top + r),
      radius: Radius.circular(radius),
    )
    ..lineTo(rect.right, rect.bottom)
    ..close();
}

/// How far a blob's edge may wander, as a share of its half height: the
/// organic "radius sets" of the visual language.
abstract final class BlobAmount {
  /// Large, slow things (the pad's pond): barely uneven.
  static const still = .05;

  /// Round things (orbs, the vessel of a card).
  static const round = .075;

  /// Wide things (cards, chips): visibly soft.
  static const wide = .16;
}

/// A shape token: the outline of an element in a rectangle. Every shape of
/// visual language v2 is round: no straight corner anywhere.
@immutable
sealed class RoundShape {
  const RoundShape();

  /// An exact circle in the middle of the rectangle.
  static const circle = CircleShape();

  /// Two half circles joined by straight lines (bars, chips, tracks).
  static const capsule = CapsuleShape();

  /// A sheet with a shallow lens-shaped top.
  static const lens = LensShape();

  /// The outline in [rect]. [breath] (radians) moves shapes that breathe;
  /// the others ignore it.
  Path outline(Rect rect, {double breath = 0});
}

final class CircleShape extends RoundShape {
  const CircleShape();

  @override
  Path outline(Rect rect, {double breath = 0}) => circlePath(rect);
}

final class CapsuleShape extends RoundShape {
  const CapsuleShape();

  @override
  Path outline(Rect rect, {double breath = 0}) => capsulePath(rect);
}

final class LensShape extends RoundShape {
  const LensShape({this.rise = 22});

  final double rise;

  @override
  Path outline(Rect rect, {double breath = 0}) => lensPath(rect, rise: rise);

  @override
  bool operator ==(Object other) => other is LensShape && other.rise == rise;

  @override
  int get hashCode => Object.hash(LensShape, rise);
}

/// A soft blob; [seed] gives each element its own stable asymmetry and
/// [amount] is one of [BlobAmount].
final class BlobShape extends RoundShape {
  const BlobShape({required this.seed, this.amount = BlobAmount.round});

  final int seed;
  final double amount;

  @override
  Path outline(Rect rect, {double breath = 0}) =>
      blobPath(rect, seed: seed, amount: amount, phase: breath);

  @override
  bool operator ==(Object other) =>
      other is BlobShape && other.seed == seed && other.amount == amount;

  @override
  int get hashCode => Object.hash(BlobShape, seed, amount);
}

/// A pebble (superellipse). An [exponent] of 2 is an ellipse; about 4 is a
/// full, soft "squircle" for panels that hold several lines.
final class PebbleShape extends RoundShape {
  const PebbleShape({this.seed = 0, this.exponent = 4});

  final int seed;
  final double exponent;

  @override
  Path outline(Rect rect, {double breath = 0}) =>
      pebblePath(rect, seed: seed, exponent: exponent);

  @override
  bool operator ==(Object other) =>
      other is PebbleShape && other.seed == seed && other.exponent == exponent;

  @override
  int get hashCode => Object.hash(PebbleShape, seed, exponent);
}
