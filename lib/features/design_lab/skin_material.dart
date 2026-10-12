import 'dart:math' as math;
import 'dart:ui' show PointMode;

import 'package:flutter/painting.dart';

import 'lab_shapes.dart';
import 'lab_skin.dart';

final _grainCache = <(int, int, int), List<Offset>>{};

/// Material: pebbles and glazed ceramic. Opaque, slightly uneven
/// superellipses lit from the top-left, a soft drop shadow, a faint grain,
/// and concave trays that hold things. Gold is a glazed pebble. Almost
/// nothing moves; the tap flash is a brief slice-offset jitter, like a
/// misregistered print, that snaps back.
class MaterialSkin extends LabSkin {
  const MaterialSkin(super.palette);

  @override
  LabVariant get variant => LabVariant.material;

  @override
  String get tagline => 'Pebbles and glazed ceramic.';

  @override
  LabKind get segmentTrackKind => LabKind.recessed;

  bool get _dark => palette.isDark;

  /// Share of a grain dot's colour; the dots are 1 px.
  static const _grainAlpha = .06;

  Color get _grain => _dark ? palette.text : palette.shade;

  @override
  Path outline(Rect rect, LabForm form, {int seed = 0, double breath = 0}) =>
      pebblePath(rect, seed: seed, exponent: form == LabForm.round ? 2 : 2.5);

  Color _base(LabKind kind) => switch (kind) {
    LabKind.accent => palette.accent,
    LabKind.selected => Color.lerp(
      palette.surface,
      palette.accent,
      _dark ? .2 : .34,
    )!,
    LabKind.raised =>
      _dark
          ? Color.lerp(palette.surface, palette.text, .03)!
          : Color.lerp(palette.surface, palette.light, .6)!,
    LabKind.recessed =>
      _dark
          ? Color.lerp(palette.ground, palette.shade, .25)!
          : Color.lerp(palette.ground, palette.shade, .05)!,
    LabKind.plain =>
      _dark ? palette.surface : Color.lerp(palette.surface, palette.light, .3)!,
  };

  /// Lit (top-left) and shaded (bottom-right) stops of a convex surface;
  /// reversed for a concave one.
  (Color, Color) _stops(LabKind kind) {
    final base = _base(kind);
    return (
      Color.lerp(base, palette.light, _dark ? .045 : .4)!,
      Color.lerp(
        base,
        palette.shade,
        kind == LabKind.accent ? .08 : (_dark ? .22 : .06),
      )!,
    );
  }

  @override
  List<Color> fillSamples(LabKind kind) {
    final (lit, shaded) = _stops(kind);
    final stops = [lit, Color.lerp(lit, shaded, .5)!, shaded];
    if (kind == LabKind.accent) {
      return [...stops, ...veiled(palette.light, .45, stops)];
    }
    return [...stops, ...veiled(_grain, _grainAlpha, stops)];
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
    final concave = pressed || kind == LabKind.recessed;
    if (!concave) {
      final lift = math.min(6.0, rect.shortestSide / 10);
      canvas
        ..drawPath(
          path.shift(Offset(lift * .5, lift)),
          Paint()
            ..color = palette.shade.withValues(alpha: _dark ? .55 : .18)
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, lift * 1.6),
        )
        ..drawPath(
          path.shift(Offset(-lift * .4, -lift * .5)),
          Paint()
            ..color = palette.light.withValues(alpha: _dark ? .035 : .75)
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, lift * 1.2),
        );
    }
    final (lit, shaded) = _stops(kind);
    canvas.drawPath(
      path,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: concave ? [shaded, lit] : [lit, shaded],
        ).createShader(rect),
    );
    canvas
      ..save()
      ..clipPath(path);
    if (concave) {
      // Inner shadow under the top-left lip.
      canvas.drawPath(
        path.shift(const Offset(2.5, 3.5)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 7
          ..color = palette.shade.withValues(alpha: _dark ? .5 : .14)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
      );
    }
    _paintGrain(canvas, rect, seed);
    if (kind == LabKind.accent && !concave) {
      final glaze = Rect.fromLTWH(
        rect.left + rect.width * .2,
        rect.top + rect.height * .12,
        rect.width * .32,
        rect.height * .2,
      );
      canvas.drawOval(
        glaze,
        Paint()
          ..color = palette.light.withValues(alpha: .45)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
      );
    }
    canvas.restore();
  }

  /// A faint, fixed grain: about one 1 px dot per 30 square pixels.
  /// Computed once per size and seed, so a repaint only draws.
  void _paintGrain(Canvas canvas, Rect rect, int seed) {
    final key = (seed, rect.width.round(), rect.height.round());
    final points = _grainCache.putIfAbsent(key, () {
      final random = labRandom(seed + key.$2);
      final count = (rect.width * rect.height / 30).clamp(0, 2400).round();
      return [
        for (var i = 0; i < count; i++)
          Offset(
            random.nextDouble() * rect.width,
            random.nextDouble() * rect.height,
          ),
      ];
    });
    canvas
      ..save()
      ..translate(rect.left, rect.top)
      ..drawPoints(
        PointMode.points,
        points,
        Paint()
          ..color = _grain.withValues(alpha: _grainAlpha)
          ..strokeWidth = 1,
      )
      ..restore();
  }

  @override
  void paintTrack(Canvas canvas, Rect rect, double value) {
    final groove = Rect.fromCenter(
      center: rect.center,
      width: rect.width - rect.height + 14,
      height: 12,
    );
    paintSurface(canvas, capsulePath(groove), groove, LabKind.recessed);
    final inner = groove.deflate(3);
    final at =
        inner.left + (inner.width - inner.height) * value + inner.height / 2;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(inner.left, inner.top, at, inner.bottom),
        Radius.circular(inner.height / 2),
      ),
      Paint()..color = palette.accent,
    );
    final thumb = Rect.fromCircle(
      center: Offset(at, rect.center.dy),
      radius: 14,
    );
    paintSurface(
      canvas,
      outline(thumb, LabForm.round, seed: 41),
      thumb,
      LabKind.raised,
      seed: 41,
    );
    canvas.drawCircle(thumb.center, 3.5, Paint()..color = palette.accent);
  }

  @override
  void paintPad(
    Canvas canvas,
    Rect rect, {
    required void Function(Canvas canvas, Rect square) paintMist,
    required Offset dot,
    required double breath,
  }) {
    // A ceramic bowl: a raised rim around a concave, mist-glazed well.
    final rim = outline(rect, LabForm.round, seed: 2);
    paintSurface(canvas, rim, rect, LabKind.plain, seed: 2);
    final wellRect = rect.deflate(rect.width * .05);
    final well = circlePath(wellRect);
    paintSurface(canvas, well, wellRect, LabKind.recessed, seed: 3);
    canvas
      ..save()
      ..clipPath(well);
    paintMist(canvas, wellRect.deflate(wellRect.width * .06));
    canvas.restore();

    final at = rect.center + Offset(dot.dx, dot.dy) * (wellRect.width / 2 * .8);
    final pebble = Rect.fromCircle(center: at, radius: 11);
    paintSurface(
      canvas,
      outline(pebble, LabForm.round, seed: 13),
      pebble,
      LabKind.accent,
      seed: 13,
    );
    // The glint on the glaze comes and goes very slowly.
    canvas.drawCircle(
      at + const Offset(-3, -4),
      2,
      Paint()
        ..color = palette.light.withValues(alpha: .35 + .3 * math.sin(breath)),
    );
  }

  @override
  void paintMark(Canvas canvas, Rect rect) {
    final pebble = Rect.fromCircle(center: rect.center, radius: 5);
    paintSurface(
      canvas,
      outline(pebble, LabForm.round, seed: 4),
      pebble,
      LabKind.accent,
    );
  }

  @override
  Path sheetOutline(Rect rect) {
    // A ceramic slab: the top half of a full superellipse, straight sides.
    const cap = 40.0;
    final a = rect.width / 2;
    final points = <Offset>[];
    const steps = 48;
    for (var i = 0; i <= steps; i++) {
      final t = math.pi + math.pi * i / steps;
      final c = math.cos(t);
      final s = math.sin(t);
      points.add(
        Offset(
          rect.center.dx + a * c.sign * math.pow(c.abs(), 2 / 4),
          rect.top + cap + cap * s.sign * math.pow(s.abs(), 2 / 4),
        ),
      );
    }
    final path = Path()..moveTo(rect.left, rect.bottom);
    for (final p in points) {
      path.lineTo(p.dx, p.dy);
    }
    return path
      ..lineTo(rect.right, rect.bottom)
      ..close();
  }

  /// Slice jitter: a few horizontal slices of the element slip sideways by
  /// a few pixels, with a faint light or dark edge, and snap back.
  @override
  void paintGlitch(
    Canvas canvas,
    Path path,
    Rect rect,
    double t,
    double amount,
    int seed,
  ) {
    final snap = t < .7 ? 1.0 : 1 - (t - .7) / .3;
    final random = labRandom(seed);
    final slices = 5;
    final height = rect.height / slices;
    canvas
      ..save()
      ..clipPath(path.shift(Offset.zero));
    for (var i = 0; i < slices; i++) {
      if (random.nextDouble() < .35) continue;
      final dx = (random.nextDouble() * 2 - 1) * (3 + 6 * amount) * snap;
      // The jitter steps through three frames instead of sliding.
      final step = (t * 3).floor().isEven ? dx : -dx * .5;
      final band = Rect.fromLTWH(
        rect.left,
        rect.top + i * height,
        rect.width,
        height,
      );
      final shift = Offset(step, 0);
      canvas.drawRect(
        band.shift(shift),
        Paint()
          ..color = (i.isEven ? palette.light : palette.shade).withValues(
            alpha: (_dark ? .1 : .16) * amount * snap,
          ),
      );
      canvas.drawLine(
        band.topLeft + shift,
        band.topRight + shift,
        Paint()
          ..strokeWidth = 1
          ..color = palette.accent.withValues(alpha: .5 * amount * snap),
      );
    }
    canvas.restore();
  }
}
