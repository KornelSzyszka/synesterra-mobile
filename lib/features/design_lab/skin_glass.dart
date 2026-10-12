import 'dart:math' as math;

import 'package:flutter/animation.dart' show Curves;
import 'package:flutter/painting.dart';

import 'lab_shapes.dart';
import 'lab_skin.dart';

/// Glass: clear lenses. Exact circles and capsules, a translucent fill made
/// of a gradient (no BackdropFilter), a soft inner highlight at the top and a
/// thin light rim. Gold is a lit orb with a soft glow. The tap flash is a
/// polarized sheen that sweeps across the lens.
class GlassSkin extends LabSkin {
  const GlassSkin(super.palette);

  @override
  LabVariant get variant => LabVariant.glass;

  @override
  String get tagline => 'Light through clear lenses.';

  bool get _dark => palette.isDark;

  /// Alpha of the light fill at the top-left and bottom-right of a surface.
  (double, double) _fillAlpha(LabKind kind) => switch ((kind, _dark)) {
    (LabKind.raised, true) => (.1, .05),
    (LabKind.raised, false) => (.72, .5),
    (LabKind.recessed, true) => (.05, .02),
    (LabKind.recessed, false) => (.3, .16),
    (_, true) => (.07, .025),
    (_, false) => (.52, .26),
  };

  double get _highlightAlpha => _dark ? .08 : .34;
  double get _tintAlpha => _dark ? .12 : .26;

  /// Over a lit mist the dark glass has no room for a dim second tier:
  /// secondary text is pulled most of the way to the main text.
  @override
  Color mutedOn(LabKind kind) =>
      _dark ? Color.lerp(palette.muted, palette.text, .65)! : palette.muted;

  @override
  Path outline(Rect rect, LabForm form, {int seed = 0, double breath = 0}) =>
      form == LabForm.round ? circlePath(rect) : capsulePath(rect);

  @override
  List<Color> fillSamples(LabKind kind) {
    final grounds = palette.groundSamples;
    if (kind == LabKind.accent) return _accentStops;
    final (top, bottom) = _fillAlpha(kind);
    var samples = [
      ...veiled(palette.light, top, grounds),
      ...veiled(palette.light, bottom, grounds),
    ];
    if (kind == LabKind.selected) {
      samples = veiled(palette.accent, _tintAlpha, samples);
    }
    return [...samples, ...veiled(palette.light, _highlightAlpha, samples)];
  }

  List<Color> get _accentStops => [
    Color.lerp(palette.accent, palette.light, .32)!,
    palette.accent,
    Color.lerp(palette.accent, palette.shade, .1)!,
  ];

  @override
  void paintSurface(
    Canvas canvas,
    Path path,
    Rect rect,
    LabKind kind, {
    bool pressed = false,
    int seed = 0,
  }) {
    if (kind == LabKind.accent) {
      _paintOrb(canvas, path, rect, pressed: pressed);
      return;
    }
    final paintKind = pressed && kind == LabKind.plain ? LabKind.raised : kind;
    if (!_dark) {
      canvas.drawPath(
        path.shift(const Offset(0, 5)),
        Paint()
          ..color = palette.shade.withValues(alpha: .07)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
      );
    }
    final (top, bottom) = _fillAlpha(paintKind);
    canvas.drawPath(
      path,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            palette.light.withValues(alpha: top),
            palette.light.withValues(alpha: bottom),
          ],
        ).createShader(rect),
    );
    if (kind == LabKind.selected) {
      canvas.drawPath(
        path,
        Paint()..color = palette.accent.withValues(alpha: _tintAlpha),
      );
    }
    _paintHighlight(canvas, path, rect);
    _paintRim(
      canvas,
      path,
      rect,
      kind == LabKind.selected ? palette.accent : null,
    );
  }

  /// The soft crescent of light inside the top of a lens.
  void _paintHighlight(Canvas canvas, Path path, Rect rect) {
    canvas
      ..save()
      ..clipPath(path);
    final crescent = Rect.fromLTWH(
      rect.left + rect.width * .06,
      rect.top - rect.height * .18,
      rect.width * .88,
      rect.height * .62,
    );
    canvas.drawOval(
      crescent,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            palette.light.withValues(alpha: _highlightAlpha),
            palette.light.withValues(alpha: 0),
          ],
        ).createShader(crescent),
    );
    canvas.restore();
  }

  /// The thin rim: bright at the top-left, fading to the bottom-right.
  void _paintRim(Canvas canvas, Path path, Rect rect, Color? tint) {
    final top = tint ?? palette.light;
    final bottom = tint ?? (_dark ? palette.light : palette.shade);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            top.withValues(alpha: _dark ? .5 : .95),
            bottom.withValues(alpha: _dark ? .07 : .16),
          ],
        ).createShader(rect),
    );
  }

  void _paintOrb(Canvas canvas, Path path, Rect rect, {bool pressed = false}) {
    canvas.drawPath(
      path,
      Paint()
        ..color = palette.accent.withValues(alpha: pressed ? .55 : .38)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
    );
    final stops = _accentStops;
    canvas.drawPath(
      path,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-.35, -.45),
          radius: 1.1,
          colors: stops,
          stops: const [0, .55, 1],
        ).createShader(rect),
    );
    _paintRim(canvas, path, rect, null);
  }

  @override
  void paintTrack(Canvas canvas, Rect rect, double value) {
    final y = rect.center.dy;
    final inset = rect.height / 2;
    final start = Offset(rect.left + inset, y);
    final end = Offset(rect.right - inset, y);
    final at = Offset.lerp(start, end, value)!;
    canvas.drawLine(
      start,
      end,
      Paint()
        ..color = (_dark ? palette.light : palette.shade).withValues(
          alpha: _dark ? .22 : .2,
        )
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round,
    );
    final active = Paint()
      ..color = palette.accent
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    canvas
      ..drawLine(
        start,
        at,
        Paint()
          ..color = palette.accent.withValues(alpha: .45)
          ..strokeWidth = 6
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      )
      ..drawLine(start, at, active);
    final thumb = Rect.fromCircle(center: at, radius: 13);
    paintSurface(canvas, circlePath(thumb), thumb, LabKind.raised);
    canvas.drawCircle(at, 3.5, Paint()..color = palette.accent);
  }

  @override
  void paintPad(
    Canvas canvas,
    Rect rect, {
    required void Function(Canvas canvas, Rect square) paintMist,
    required Offset dot,
    required double breath,
  }) {
    final disc = circlePath(rect);
    paintSurface(canvas, disc, rect, LabKind.recessed);
    canvas
      ..save()
      ..clipPath(disc);
    paintMist(canvas, rect.deflate(rect.width * .08));
    canvas.restore();
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = (_dark ? palette.light : palette.shade).withValues(alpha: .07);
    for (final share in const [.34, .67]) {
      canvas.drawCircle(rect.center, rect.width / 2 * share, ring);
    }
    _paintHighlight(canvas, disc, rect);
    _paintRim(canvas, disc, rect, null);

    final at = rect.center + Offset(dot.dx, dot.dy) * (rect.width / 2 * .82);
    final glow = .42 + .18 * math.sin(breath);
    canvas
      ..drawCircle(
        at,
        20,
        Paint()
          ..color = palette.accent.withValues(alpha: glow)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
      )
      ..drawCircle(at, 8, Paint()..color = palette.accent)
      ..drawCircle(
        at,
        8,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = palette.light.withValues(alpha: .8),
      )
      ..drawCircle(
        at + const Offset(-2.5, -2.5),
        2.2,
        Paint()..color = palette.light.withValues(alpha: .85),
      );
  }

  @override
  void paintMark(Canvas canvas, Rect rect) {
    final c = rect.center;
    canvas
      ..drawCircle(
        c,
        6,
        Paint()
          ..color = palette.accent.withValues(alpha: .45)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      )
      ..drawCircle(c, 3, Paint()..color = palette.accent);
  }

  @override
  Path sheetOutline(Rect rect) {
    // A lens-like top: one shallow circular arc.
    const rise = 22.0;
    final radius = (rect.width * rect.width / 4 + rise * rise) / (2 * rise);
    return Path()
      ..moveTo(rect.left, rect.bottom)
      ..lineTo(rect.left, rect.top + rise)
      ..arcToPoint(
        Offset(rect.right, rect.top + rise),
        radius: Radius.circular(radius),
      )
      ..lineTo(rect.right, rect.bottom)
      ..close();
  }

  /// Polarized sheen: a narrow band of interference colours (violet, cyan,
  /// gold) sweeps once across the lens, left to right.
  @override
  void paintGlitch(
    Canvas canvas,
    Path path,
    Rect rect,
    double t,
    double amount,
    int seed,
  ) {
    final span = rect.width + rect.height;
    final x = rect.left - rect.height + span * Curves.easeOutCubic.transform(t);
    final band = Rect.fromLTWH(
      x - rect.height * .6,
      rect.top,
      1.2 * rect.height,
      rect.height,
    );
    final fade = math.sin(math.pi * t);
    final alpha = (_dark ? .34 : .4) * amount * fade;
    canvas
      ..save()
      ..clipPath(path);
    canvas.drawRect(
      band.inflate(rect.height),
      Paint()
        ..blendMode = _dark ? BlendMode.plus : BlendMode.srcOver
        ..shader = LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          transform: const GradientRotation(-.5),
          colors: [
            const Color(0x00000000),
            const Color(0xff9f8cff).withValues(alpha: alpha),
            const Color(0xff7fe3f0).withValues(alpha: alpha),
            palette.accent.withValues(alpha: alpha),
            const Color(0x00000000),
          ],
          stops: const [0, .3, .5, .7, 1],
        ).createShader(band),
    );
    canvas.restore();
    // The rim catches the light as the band passes.
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = palette.light.withValues(alpha: .5 * amount * fade),
    );
  }
}
