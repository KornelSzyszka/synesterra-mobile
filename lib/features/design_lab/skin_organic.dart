import 'dart:math' as math;

import 'package:flutter/painting.dart';

import 'lab_shapes.dart';
import 'lab_skin.dart';

/// Organic: soft blobs with a gentle asymmetry, no borders, light that falls
/// off the top-left into a faint halo of the instrument's colour. The pad and
/// the primary action breathe slowly. The tap flash is a short chromatic
/// split: two tinted copies of the outline slip apart and snap back.
class OrganicSkin extends LabSkin {
  const OrganicSkin(super.palette);

  @override
  LabVariant get variant => LabVariant.organic;

  @override
  String get tagline => 'Soft forms that breathe.';

  @override
  bool get primaryBreathes => true;

  @override
  bool get separateSegments => true;

  bool get _dark => palette.isDark;

  @override
  Path outline(Rect rect, LabForm form, {int seed = 0, double breath = 0}) =>
      blobPath(
        rect,
        seed: seed,
        amount: form == LabForm.round ? .075 : .16,
        phase: breath,
      );

  /// The two stops of the radial fill (lit centre, outer edge).
  (Color, Color) _fill(LabKind kind) {
    final s = palette.surface;
    final a = palette.accent;
    return switch ((kind, _dark)) {
      (LabKind.accent, _) => (Color.lerp(a, palette.light, .28)!, a),
      (LabKind.selected, true) => (
        Color.lerp(s, a, .24)!,
        Color.lerp(s, a, .14)!,
      ),
      (LabKind.selected, false) => (
        Color.lerp(s, a, .44)!,
        Color.lerp(s, a, .3)!,
      ),
      (LabKind.raised, true) => (
        Color.lerp(s, palette.text, .15)!,
        Color.lerp(s, palette.aura, .08)!,
      ),
      (LabKind.raised, false) => (
        Color.lerp(s, palette.light, .8)!,
        Color.lerp(s, palette.aura, .1)!,
      ),
      (_, true) => (
        Color.lerp(s, palette.text, .1)!,
        Color.lerp(s, palette.aura, .06)!,
      ),
      (_, false) => (
        Color.lerp(s, palette.light, .55)!,
        Color.lerp(s, palette.aura, .14)!,
      ),
    };
  }

  @override
  List<Color> fillSamples(LabKind kind) {
    final (centre, edge) = _fill(kind);
    return [centre, Color.lerp(centre, edge, .5)!, edge];
  }

  @override
  void paintSurface(
    Canvas canvas,
    Path path,
    Rect rect,
    LabKind kind, {
    bool pressed = false,
    int seed = 0,
  }) {
    final halo = kind == LabKind.accent ? palette.accent : palette.aura;
    canvas.drawPath(
      path,
      Paint()
        ..color = halo.withValues(
          alpha:
              (kind == LabKind.accent ? .4 : (_dark ? .16 : .26)) *
              (pressed ? 1.5 : 1),
        )
        ..maskFilter = MaskFilter.blur(
          BlurStyle.normal,
          math.min(14, rect.shortestSide / 4),
        ),
    );
    final (centre, edge) = _fill(kind);
    canvas.drawPath(
      path,
      Paint()
        ..shader = RadialGradient(
          center: pressed ? Alignment.center : const Alignment(-.3, -.4),
          radius: 1.05,
          colors: [centre, edge],
        ).createShader(rect),
    );
  }

  /// A tail that swells from thin to full: the slider track.
  Path _tail(Offset start, Offset end, double thin, double thick) {
    final top = <Offset>[];
    final bottom = <Offset>[];
    const steps = 24;
    for (var i = 0; i <= steps; i++) {
      final u = i / steps;
      final p = Offset.lerp(start, end, u)!;
      final half = (thin + (thick - thin) * math.pow(u, 1.4)) / 2;
      top.add(p - Offset(0, half));
      bottom.add(p + Offset(0, half));
    }
    final path = Path()..moveTo(top.first.dx, top.first.dy);
    for (final p in top.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    path.arcToPoint(
      bottom.last,
      radius: Radius.circular(thick / 2),
      clockwise: true,
    );
    for (final p in bottom.reversed.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    path.arcToPoint(top.first, radius: Radius.circular(thin / 2));
    return path..close();
  }

  @override
  void paintTrack(Canvas canvas, Rect rect, double value) {
    final y = rect.center.dy;
    final inset = rect.height / 2;
    final start = Offset(rect.left + inset, y);
    final end = Offset(rect.right - inset, y);
    final at = Offset.lerp(start, end, value)!;
    final tail = _tail(start, end, 2, 10);
    canvas.drawPath(
      tail,
      Paint()..color = palette.muted.withValues(alpha: _dark ? .3 : .34),
    );
    canvas
      ..save()
      ..clipRect(Rect.fromLTRB(rect.left, rect.top, at.dx, rect.bottom))
      ..drawPath(tail, Paint()..color = palette.accent)
      ..restore();
    final thumb = Rect.fromCircle(center: at, radius: 14);
    final blob = outline(thumb, LabForm.round, seed: 31);
    paintSurface(canvas, blob, thumb, LabKind.accent);
  }

  @override
  void paintPad(
    Canvas canvas,
    Rect rect, {
    required void Function(Canvas canvas, Rect square) paintMist,
    required Offset dot,
    required double breath,
  }) {
    final pond = blobPath(rect, seed: 5, amount: .05, phase: breath);
    paintSurface(canvas, pond, rect, LabKind.plain);
    canvas
      ..save()
      ..clipPath(pond);
    paintMist(canvas, rect.deflate(rect.width * .04));
    canvas.restore();

    final at = rect.center + Offset(dot.dx, dot.dy) * (rect.width / 2 * .8);
    final ripple = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    canvas
      ..drawCircle(
        at,
        30,
        ripple..color = palette.accent.withValues(alpha: .12),
      )
      ..drawCircle(
        at,
        19,
        ripple..color = palette.accent.withValues(alpha: .26),
      );
    final seedRect = Rect.fromCircle(center: at, radius: 9);
    canvas.drawCircle(
      at,
      18,
      Paint()
        ..color = palette.accent.withValues(alpha: .3 + .15 * math.sin(breath))
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );
    canvas.drawPath(
      blobPath(seedRect, seed: 9, amount: .12, phase: breath),
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-.3, -.3),
          colors: [
            Color.lerp(palette.accent, palette.light, .4)!,
            palette.accent,
          ],
        ).createShader(seedRect),
    );
  }

  @override
  void paintMark(Canvas canvas, Rect rect) {
    final blob = blobPath(
      Rect.fromCircle(center: rect.center, radius: 5),
      seed: 3,
      amount: .2,
    );
    canvas
      ..drawPath(
        blob,
        Paint()
          ..color = palette.accent.withValues(alpha: .4)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      )
      ..drawPath(blob, Paint()..color = palette.accent);
  }

  @override
  Path sheetOutline(Rect rect) {
    // A slow wave along the top, higher on the left.
    final points = <Offset>[];
    const steps = 40;
    for (var i = 0; i <= steps; i++) {
      final u = i / steps;
      final y =
          rect.top +
          16 +
          10 * math.sin(2 * math.pi * (u * .9 + .15)) * (1 - u * .4);
      points.add(Offset(rect.left + rect.width * u, y));
    }
    final path = Path()
      ..moveTo(rect.left, rect.bottom)
      ..lineTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length; i++) {
      final mid = Offset.lerp(points[i - 1], points[i], .5)!;
      path.quadraticBezierTo(
        points[i - 1].dx,
        points[i - 1].dy,
        mid.dx,
        mid.dy,
      );
    }
    return path
      ..lineTo(rect.right, points.last.dy)
      ..lineTo(rect.right, rect.bottom)
      ..close();
  }

  /// Chromatic split: a cool and a warm copy of the outline slip sideways
  /// and snap back.
  @override
  void paintGlitch(
    Canvas canvas,
    Path path,
    Rect rect,
    double t,
    double amount,
    int seed,
  ) {
    final snap = math.pow(1 - t, 2).toDouble();
    final shift = (2 + 5 * amount) * snap;
    final tilt = labRandom(seed).nextBool() ? 1.0 : -1.0;
    final alpha = (_dark ? .32 : .26) * amount * snap;
    final mode = _dark ? BlendMode.screen : BlendMode.multiply;
    for (final (offset, color) in [
      (Offset(shift, -shift * .3 * tilt), const Color(0xff6fe0ff)),
      (Offset(-shift, shift * .3 * tilt), const Color(0xffff7ab8)),
    ]) {
      canvas.drawPath(
        path.shift(offset),
        Paint()
          ..blendMode = mode
          ..color = color.withValues(alpha: alpha),
      );
      canvas.drawPath(
        path.shift(offset),
        Paint()
          ..blendMode = mode
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = color.withValues(alpha: math.min(1, alpha * 2)),
      );
    }
  }
}
