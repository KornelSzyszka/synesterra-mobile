import 'dart:math' as math;

import 'package:flutter/painting.dart';

import 'ground_palette.dart';

/// The three materials of visual language v2, each with one job:
enum SurfaceKind {
  /// Floating layers over the mist (panels, sheets, the transport bar):
  /// translucent light, a top highlight and a thin rim. No `BackdropFilter`.
  glass,

  /// Shapes and figures (cards, the pad, the instrument figure): opaque soft
  /// light that falls off the top-left into a faint halo of the instrument's
  /// colour; may breathe slowly.
  organic,

  /// Things you press (Play, steps, chips, segments): opaque, lit from the
  /// top-left with a soft drop shadow; pressed, it turns concave.
  tactile,
}

/// Every surface the components paint: a [SurfaceKind] and its emphasis.
enum SurfaceStyle {
  glass(SurfaceKind.glass),
  organic(SurfaceKind.organic),

  /// A quiet tactile control.
  tactile(SurfaceKind.tactile),

  /// A chosen chip or segment: tactile, tinted with gold.
  tactileSelected(SurfaceKind.tactile),

  /// The primary action: a glazed gold disc with a soft glow.
  primary(SurfaceKind.tactile),

  /// A concave tray that holds other controls (segment track, slider groove).
  tray(SurfaceKind.tactile);

  const SurfaceStyle(this.kind);
  final SurfaceKind kind;
}

/// Shadow and lift of the surfaces, in logical pixels.
abstract final class Elevation {
  /// How far a tactile control stands off the ground (shadow offset); the
  /// shadow blur is 1.6 times this.
  static const tactileLift = 5.0;

  /// Blur of the faint shadow under a floating glass layer (light ground
  /// only; on a dark ground glass floats by its rim).
  static const floatingBlur = 10.0;
}

/// The soft lights of the visual language.
abstract final class Glow {
  /// Blur of the gold glow around the primary action.
  static const accentBlur = 14.0;

  /// Alpha of that glow at rest and pressed.
  static const accentAlpha = .34;
  static const accentPressedAlpha = .52;

  /// Largest blur of the instrument-coloured halo around organic shapes.
  static const haloBlur = 14.0;
}

/// Paints every [SurfaceStyle] for one [GroundPalette], and lists the opaque
/// colours text can sit on, so the contrast test checks what is drawn.
class Surfaces {
  const Surfaces(this.palette);

  final GroundPalette palette;

  bool get _dark => palette.isDark;

  // Glass ------------------------------------------------------------------

  (double, double) get _glassAlpha => _dark ? (.07, .025) : (.52, .26);
  double get _glassHighlight => _dark ? .08 : .34;

  // Organic ----------------------------------------------------------------

  /// Lit centre and outer edge of the radial fill.
  (Color, Color) get _organicFill {
    final s = palette.surface;
    return _dark
        ? (Color.lerp(s, palette.text, .1)!, Color.lerp(s, palette.aura, .06)!)
        : (
            Color.lerp(s, palette.light, .55)!,
            Color.lerp(s, palette.aura, .14)!,
          );
  }

  // Tactile ----------------------------------------------------------------

  Color _tactileBase(SurfaceStyle style) => switch (style) {
    SurfaceStyle.primary => palette.accent,
    SurfaceStyle.tactileSelected => Color.lerp(
      palette.surface,
      palette.accent,
      _dark ? .2 : .34,
    )!,
    SurfaceStyle.tray =>
      _dark
          ? Color.lerp(palette.ground, palette.shade, .25)!
          : Color.lerp(palette.ground, palette.shade, .05)!,
    _ =>
      _dark ? palette.surface : Color.lerp(palette.surface, palette.light, .3)!,
  };

  /// Lit (top-left) and shaded (bottom-right) stops of a tactile surface.
  (Color, Color) _tactileStops(SurfaceStyle style) {
    final base = _tactileBase(style);
    return (
      Color.lerp(base, palette.light, _dark ? .045 : .4)!,
      Color.lerp(
        base,
        palette.shade,
        style == SurfaceStyle.primary ? .08 : (_dark ? .22 : .06),
      )!,
    );
  }

  static const _glazeAlpha = .45;

  /// The colour of body text on [style].
  Color textOn(SurfaceStyle style) =>
      style == SurfaceStyle.primary ? palette.onAccent : palette.text;

  /// The colour of secondary text on [style]. Over a lit mist, dark glass has
  /// no room for a dim second tier, so it is pulled toward the main text.
  Color mutedOn(SurfaceStyle style) => switch (style) {
    SurfaceStyle.primary => palette.onAccent,
    // The gold tint leaves no room for a dim second tier either.
    SurfaceStyle.tactileSelected => palette.text,
    SurfaceStyle.glass when _dark => Color.lerp(
      palette.muted,
      palette.text,
      .65,
    )!,
    _ => palette.muted,
  };

  /// The opaque colours text can sit on, on [style]: gradient stops and
  /// highlights, and for glass its translucency over every ground sample.
  List<Color> fillSamples(SurfaceStyle style) {
    switch (style.kind) {
      case SurfaceKind.glass:
        final grounds = palette.groundSamples;
        final (top, bottom) = _glassAlpha;
        final samples = [
          ...veiled(palette.light, top, grounds),
          ...veiled(palette.light, bottom, grounds),
        ];
        return [...samples, ...veiled(palette.light, _glassHighlight, samples)];
      case SurfaceKind.organic:
        final (centre, edge) = _organicFill;
        return [centre, Color.lerp(centre, edge, .5)!, edge];
      case SurfaceKind.tactile:
        final (lit, shaded) = _tactileStops(style);
        final stops = [lit, Color.lerp(lit, shaded, .5)!, shaded];
        return style == SurfaceStyle.primary
            ? [...stops, ...veiled(palette.light, _glazeAlpha, stops)]
            : stops;
    }
  }

  /// Every text colour with every surface it is drawn on.
  List<TextContrastPair> textPairs() {
    final name = palette.tone.label;
    final grounds = palette.groundSamples;
    return [
      TextContrastPair('$name text on ground', palette.text, grounds),
      TextContrastPair('$name muted on ground', palette.muted, grounds),
      TextContrastPair(
        '$name accent text on ground',
        palette.accentText,
        grounds,
      ),
      for (final style in SurfaceStyle.values) ...[
        TextContrastPair(
          '$name text on ${style.name}',
          textOn(style),
          fillSamples(style),
        ),
        TextContrastPair(
          '$name muted on ${style.name}',
          mutedOn(style),
          fillSamples(style),
        ),
      ],
    ];
  }

  /// Paints [style] filling [path] inside [rect]. [pressed] turns tactile
  /// surfaces concave and lifts glass and organic surfaces a little.
  void paint(
    Canvas canvas,
    Path path,
    Rect rect,
    SurfaceStyle style, {
    bool pressed = false,
  }) {
    switch (style.kind) {
      case SurfaceKind.glass:
        _paintGlass(canvas, path, rect, pressed: pressed);
      case SurfaceKind.organic:
        _paintOrganic(canvas, path, rect, pressed: pressed);
      case SurfaceKind.tactile:
        _paintTactile(canvas, path, rect, style, pressed: pressed);
    }
  }

  void _paintGlass(
    Canvas canvas,
    Path path,
    Rect rect, {
    bool pressed = false,
  }) {
    if (!_dark) {
      // A faint shadow outside the glass only: through the translucent fill
      // it would darken the text ground.
      canvas
        ..save()
        ..clipPath(
          Path.combine(
            PathOperation.difference,
            Path()..addRect(rect.inflate(Elevation.floatingBlur * 3)),
            path,
          ),
        )
        ..drawPath(
          path.shift(const Offset(0, 4)),
          Paint()
            ..color = palette.shade.withValues(alpha: .08)
            ..maskFilter = const MaskFilter.blur(
              BlurStyle.normal,
              Elevation.floatingBlur,
            ),
        )
        ..restore();
    }
    final (top, bottom) = _glassAlpha;
    final lift = pressed ? .03 : 0.0;
    canvas.drawPath(
      path,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            palette.light.withValues(alpha: top + lift),
            palette.light.withValues(alpha: bottom + lift),
          ],
        ).createShader(rect),
    );
    paintHighlight(canvas, path, rect);
    paintRim(canvas, path, rect);
  }

  /// The soft crescent of light inside the top of a glass shape.
  void paintHighlight(Canvas canvas, Path path, Rect rect) {
    canvas
      ..save()
      ..clipPath(path);
    final crescent = Rect.fromLTWH(
      rect.left + rect.width * .06,
      rect.top - math.min(rect.height * .18, 24),
      rect.width * .88,
      math.min(rect.height * .62, 84),
    );
    canvas.drawOval(
      crescent,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            palette.light.withValues(alpha: _glassHighlight),
            palette.light.withValues(alpha: 0),
          ],
        ).createShader(crescent),
    );
    canvas.restore();
  }

  /// The thin glass rim: bright at the top-left, fading to the bottom-right.
  void paintRim(Canvas canvas, Path path, Rect rect) {
    final bottom = _dark ? palette.light : palette.shade;
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            palette.light.withValues(alpha: _dark ? .5 : .95),
            bottom.withValues(alpha: _dark ? .07 : .16),
          ],
        ).createShader(rect),
    );
  }

  void _paintOrganic(
    Canvas canvas,
    Path path,
    Rect rect, {
    bool pressed = false,
  }) {
    canvas.drawPath(
      path,
      Paint()
        ..color = palette.aura.withValues(
          alpha: (_dark ? .16 : .26) * (pressed ? 1.5 : 1),
        )
        ..maskFilter = MaskFilter.blur(
          BlurStyle.normal,
          math.min(Glow.haloBlur, rect.shortestSide / 4),
        ),
    );
    final (centre, edge) = _organicFill;
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

  void _paintTactile(
    Canvas canvas,
    Path path,
    Rect rect,
    SurfaceStyle style, {
    bool pressed = false,
  }) {
    final concave = pressed || style == SurfaceStyle.tray;
    if (style == SurfaceStyle.primary) {
      canvas.drawPath(
        path,
        Paint()
          ..color = palette.accent.withValues(
            alpha: pressed ? Glow.accentPressedAlpha : Glow.accentAlpha,
          )
          ..maskFilter = const MaskFilter.blur(
            BlurStyle.normal,
            Glow.accentBlur,
          ),
      );
    } else if (!concave) {
      final lift = math.min(Elevation.tactileLift, rect.shortestSide / 10);
      canvas.drawPath(
        path.shift(Offset(lift * .4, lift)),
        Paint()
          ..color = palette.shade.withValues(alpha: _dark ? .5 : .16)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, lift * 1.6),
      );
    }
    final (lit, shaded) = _tactileStops(style);
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
        path.shift(const Offset(2, 3)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6
          ..color = palette.shade.withValues(alpha: _dark ? .45 : .12)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
    } else if (style == SurfaceStyle.primary) {
      // The glaze: a small soft highlight at the top-left.
      final glaze = Rect.fromLTWH(
        rect.left + rect.width * .2,
        rect.top + rect.height * .12,
        rect.width * .32,
        rect.height * .2,
      );
      canvas.drawOval(
        glaze,
        Paint()
          ..color = palette.light.withValues(alpha: _glazeAlpha)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
      );
    } else {
      // A hairline of light along the top edge: the lit lip.
      canvas.drawPath(
        path.shift(const Offset(0, 1)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.center,
            colors: [
              palette.light.withValues(alpha: _dark ? .1 : .6),
              palette.light.withValues(alpha: 0),
            ],
          ).createShader(rect),
      );
    }
    canvas.restore();
  }
}
