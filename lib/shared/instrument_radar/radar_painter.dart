import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/widgets.dart';

import '../instrument_mist/mist_spec.dart';
import '../living_blobs/living_mist.dart';
import '../living_blobs/living_motion.dart';
import '../theme/ground_palette.dart';
import '../theme/round_shapes.dart';
import '../theme/surfaces.dart';
import 'radar_geometry.dart';

// The instrument stat wheel in visual language v2 (Graphite Blend): a glass
// ring of tick blocks with the trait names written along it, a glass chart
// with graduated spokes and the rank letters E to A, the instrument's mist as
// a soft glow behind it, and over it an organic, translucent shape with
// tactile handles. Three painters (glow, field, shape), so the static field
// and the moving parts sit behind separate RepaintBoundary layers.

/// How much the shape breathes: the largest push of a vertex as a share of
/// its distance from the centre.
const radarBreathAmount = .035;

/// How many slow breaths one breathing bout holds ([radarBreathOffset]).
const radarBreaths = 3;

/// The smallest drawn distance of a vertex (a share of the reach), so a shape
/// with every trait at 0 is a small soft light, not nothing.
const radarMinShown = .06;

/// The push of vertex [index] at bout progress [t] (0..1): [radarBreaths]
/// slow waves, faded in and out with the bout so it starts and ends still.
/// Each vertex has its own phase, so the shape breathes unevenly, like a
/// living thing, and never as a whole.
double radarBreathOffset(double t, int index) {
  if (t <= 0 || t >= 1) return 0;
  final envelope = math.sin(math.pi * t);
  return radarBreathAmount *
      envelope *
      math.sin(2 * math.pi * radarBreaths * t + index * 1.7);
}

WheelLayout _layout(Size size, bool bare, double textScale) =>
    bare ? WheelLayout.bare(size) : WheelLayout.of(size, textScale: textScale);

Color _ink(GroundPalette palette) =>
    palette.isDark ? palette.light : palette.shade;

/// The instrument's mist as a soft glow behind the chart: its halo, core and
/// one blob per audible harmonic, in the instrument's [color]. [swell]
/// (0..1, a bump) brightens and grows it for a moment after a release.
class RadarGlowPainter extends CustomPainter {
  RadarGlowPainter({
    required this.spec,
    required this.color,
    this.swell,
    this.motion,
    this.motionSeed = 0,
    this.textScale = 1,
  }) : super(repaint: Listenable.merge([swell, motion]));

  final MistSpec spec;
  final Color color;
  final Animation<double>? swell;

  /// The living motion (UX-126): drift and morph at three depths, the lean
  /// toward the finger, the hold and the audition pulse. Null is still
  /// (reduce motion).
  final LivingMist? motion;

  /// Seeds the drift and morph: each instrument moves its own way.
  final int motionSeed;

  /// The user's text size, which sizes the name band ([WheelLayout.of]).
  final double textScale;

  /// The glow's strength at rest, a share of the mist's own opacity.
  static const strength = .85;

  @override
  void paint(Canvas canvas, Size size) {
    final layout = WheelLayout.of(size, textScale: textScale);
    final reach = layout.reach;
    if (reach <= 0) return;
    final t = swell?.value ?? 0;
    final bump = t <= 0 || t >= 1 ? 0.0 : math.sin(math.pi * t);
    final m = motion;
    final time = m?.time ?? 0;
    final life = m?.life ?? 0;
    final lean = m?.lean ?? Offset.zero;
    final hold = m?.hold ?? 0;
    final pulse = m?.pulse ?? 0;
    final radius = reach * (1.3 + .08 * bump + .08 * pulse + .04 * hold);
    final glow = strength * (1 + .5 * bump + .7 * pulse + .25 * hold);

    /// Where a blob at depth [layer] sits: drifting on its own while alive
    /// and following the finger, the front layers more (parallax).
    Offset depth(int layer, double share) {
      final drift = parallaxOffset(
        layer: layer,
        time: time,
        seed: motionSeed,
        lean: Offset.zero,
      );
      final follow = parallaxOffset(
        layer: layer,
        time: 0,
        seed: motionSeed,
        lean: lean,
      );
      return (drift * life + follow) * (reach * share);
    }

    void blob(Offset at, double share, double opacity) {
      final r = share * radius;
      if (r <= 0) return;
      final alpha = (opacity * glow).clamp(0.0, 1.0);
      canvas.drawCircle(
        at,
        r,
        Paint()
          ..shader = RadialGradient(
            colors: [
              color.withValues(alpha: alpha),
              color.withValues(alpha: alpha * .4),
              color.withValues(alpha: 0),
            ],
            stops: const [0, .45, 1],
          ).createShader(Rect.fromCircle(center: at, radius: r)),
      );
    }

    final centre = layout.centre;
    blob(centre + depth(2, .1), spec.haloRadius * 1.1, spec.haloOpacity);
    for (final lobe in spec.lobes) {
      // The lobes breathe in and out on the instrument's own slow noise.
      final morph = life == 0
          ? 0.0
          : .14 *
                life *
                morphNoise(motionSeed, lobe.angle / (2 * math.pi), time);
      blob(
        centre +
            Offset(math.cos(lobe.angle), math.sin(lobe.angle)) *
                (lobe.distance * radius * .55 * (1 + morph)) +
            depth(lobe.harmonic % LivingDepth.layers, .16),
        lobe.radius * 1.2,
        lobe.opacity * .8,
      );
    }
    blob(centre + depth(0, .06), spec.coreRadius * 2.4, spec.coreOpacity * .8);
  }

  @override
  bool shouldRepaint(RadarGlowPainter old) =>
      old.spec != spec ||
      old.color != color ||
      old.swell != swell ||
      old.motion != motion ||
      old.motionSeed != motionSeed ||
      old.textScale != textScale;
}

/// The static field. With [labels] (the editor) it is the whole wheel: the
/// glass ring of tick blocks, the names along it, the chart disc with its
/// graduated spokes and the rank letters. [bare] (a thumbnail) draws only the
/// chart disc and a few faint rings.
class RadarFieldPainter extends CustomPainter {
  const RadarFieldPainter({
    required this.palette,
    required this.count,
    this.labels = const [],
    this.labelStyle,
    this.bare = false,
    this.textScale = 1,
  });

  final GroundPalette palette;
  final int count;
  final List<String> labels;

  /// The style of the names (upper case is applied here) and, smaller, of the
  /// rank letters.
  final TextStyle? labelStyle;
  final bool bare;

  /// The user's text size: it scales the names (and their band).
  final double textScale;

  /// Hint rings of a bare wheel, as shares of the reach.
  static const bareRings = [1 / 3, 2 / 3, 1.0];

  @override
  void paint(Canvas canvas, Size size) {
    if (count < 3) return;
    final layout = _layout(size, bare, textScale);
    final reach = layout.reach;
    if (reach <= 0) return;
    final surfaces = Surfaces(palette);
    final centre = layout.centre;
    final ink = _ink(palette);
    final dark = palette.isDark;

    final disc = Rect.fromCircle(center: centre, radius: reach + 3);
    surfaces.paint(canvas, circlePath(disc), disc, SurfaceStyle.glass);

    final faint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = ink.withValues(alpha: dark ? .07 : .1);
    if (bare) {
      for (final ring in bareRings) {
        canvas.drawCircle(centre, reach * ring, faint);
      }
      return;
    }

    _paintRing(canvas, layout, surfaces);

    // Faint rings through the rank letters, so a rank reads across spokes.
    final rankRing = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = .8
      ..color = ink.withValues(alpha: dark ? .035 : .06);
    for (var rank = 0; rank < rankLetters.length; rank++) {
      canvas.drawCircle(
        centre,
        reach * rankValue(rankLetterStep(rank)),
        rankRing,
      );
    }

    // Spokes with their graduation.
    final spoke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = ink.withValues(alpha: dark ? .1 : .14);
    final mark = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < count; i++) {
      final direction = radarAxisDirection(i, count);
      final across = Offset(-direction.dy, direction.dx);
      canvas.drawLine(centre, centre + direction * reach, spoke);
      for (final tick in spokeTicks()) {
        final at = centre + direction * (tick.value * reach);
        final half = tick.letter ? 4.0 : 2.4;
        mark
          ..strokeWidth = tick.letter ? 1.2 : 1
          ..color = ink.withValues(
            alpha: tick.letter ? (dark ? .3 : .36) : (dark ? .16 : .22),
          );
        canvas.drawLine(at - across * half, at + across * half, mark);
      }
    }

    final style = labelStyle;
    if (style == null) return;
    _paintNames(canvas, layout, style);
  }

  void _paintRing(Canvas canvas, WheelLayout layout, Surfaces surfaces) {
    final centre = layout.centre;
    final outer = Rect.fromCircle(center: centre, radius: layout.outer);
    final band = Path()
      ..fillType = PathFillType.evenOdd
      ..addOval(outer)
      ..addOval(Rect.fromCircle(center: centre, radius: layout.ringInner));
    surfaces.paint(canvas, band, outer, SurfaceStyle.glass);

    final ink = _ink(palette);
    final dark = palette.isDark;
    final block = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final width = layout.outer - layout.ringInner;
    for (final tick in ringTicks(count)) {
      final direction = Offset(math.cos(tick.angle), math.sin(tick.angle));
      final (inset, stroke, color) = switch (tick.kind) {
        RingTickKind.divider => (
          width * .2,
          3.2,
          ink.withValues(alpha: dark ? .34 : .4),
        ),
        RingTickKind.axis => (
          width * .26,
          2.2,
          palette.accent.withValues(alpha: dark ? .7 : .85),
        ),
        RingTickKind.minor => (
          width * .34,
          1.4,
          ink.withValues(alpha: dark ? .16 : .2),
        ),
      };
      block
        ..strokeWidth = stroke
        ..color = color;
      canvas.drawLine(
        centre + direction * (layout.ringInner + inset),
        centre + direction * (layout.outer - inset),
        block,
      );
    }
  }

  void _paintNames(Canvas canvas, WheelLayout layout, TextStyle style) {
    final color = Color.lerp(palette.muted, palette.text, .45)!;
    final glyphStyle = style.copyWith(color: color);
    final scaler = TextScaler.linear(textScale);
    TextPainter glyph(String c) => TextPainter(
      text: TextSpan(text: c, style: glyphStyle),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
      maxLines: 1,
    )..layout();
    final all = [
      for (var i = 0; i < math.min(count, labels.length); i++)
        [for (final c in labels[i].toUpperCase().characters) glyph(c)],
    ];
    final ellipsis = glyph('…');
    final fit = ringLabelFit(
      [
        for (final glyphs in all) [for (final g in glyphs) g.width],
      ],
      radius: layout.nameRadius,
      count: count,
      ellipsis: ellipsis.width,
    );
    final scale = fit.scale;
    for (final (i, full) in all.indexed) {
      final keep = fit.keep[i];
      if (keep == 0) continue;
      // A name that does not fit is cut and ends with an ellipsis.
      final glyphs = [
        ...full.sublist(0, keep),
        if (keep < full.length) ellipsis,
      ];
      final placed = ringGlyphs(
        centre: layout.centre,
        radius: layout.nameRadius,
        angle: radarAxisAngle(i, count),
        advances: [for (final g in glyphs) g.width * scale],
      );
      for (final (j, glyph) in glyphs.indexed) {
        final at = placed[j];
        canvas
          ..save()
          ..translate(at.position.dx, at.position.dy)
          ..rotate(at.rotation)
          ..scale(scale);
        // Tracking adds space after a glyph; centre the ink, not the box.
        final tracking = glyphStyle.letterSpacing ?? 0;
        glyph.paint(
          canvas,
          Offset(-(glyph.width - tracking) / 2, -glyph.height / 2),
        );
        canvas.restore();
      }
    }
    for (final glyphs in all) {
      for (final g in glyphs) {
        g.dispose();
      }
    }
    ellipsis.dispose();
  }

  @override
  bool shouldRepaint(RadarFieldPainter old) =>
      old.palette != palette ||
      old.count != count ||
      !listEquals(old.labels, labels) ||
      old.labelStyle != labelStyle ||
      old.bare != bare ||
      old.textScale != textScale;
}

/// The rank letters E to A beside the first spoke, over the shape so they
/// stay readable (a static layer of its own). [style] is the names' style;
/// the letters are drawn a little smaller.
class RadarRankPainter extends CustomPainter {
  const RadarRankPainter({
    required this.palette,
    required this.count,
    required this.style,
    this.textScale = 1,
  });

  final GroundPalette palette;
  final int count;
  final TextStyle style;

  /// The user's text size: it scales the letters (and the name band).
  final double textScale;

  @override
  void paint(Canvas canvas, Size size) {
    if (count < 3) return;
    final reach = WheelLayout.of(size, textScale: textScale).reach;
    if (reach <= 0) return;
    final letterStyle = style.copyWith(
      color: Color.lerp(palette.muted, palette.text, .25),
      fontSize: (style.fontSize ?? 11) * .86,
      letterSpacing: 0,
      shadows: [
        Shadow(color: palette.ground.withValues(alpha: .8), blurRadius: 3),
      ],
    );
    for (var rank = 0; rank < rankLetters.length; rank++) {
      final text = TextPainter(
        text: TextSpan(text: rankLetters[rank], style: letterStyle),
        textDirection: TextDirection.ltr,
        textScaler: TextScaler.linear(textScale),
        maxLines: 1,
      )..layout();
      final at = rankLetterPoint(rankLetterStep(rank), count, size, reach);
      text
        ..paint(canvas, at - Offset(0, text.height / 2))
        ..dispose();
    }
  }

  @override
  bool shouldRepaint(RadarRankPainter old) =>
      old.palette != palette ||
      old.count != count ||
      old.style != style ||
      old.textScale != textScale;
}

/// The shape: a soft polygon through the trait [values] (0 centre, 1 edge),
/// translucent, filled with a gradient from a gold core into the
/// instrument's [color], with a halo and a light rim. [breath] (0..1 over
/// one bout, see [radarBreathOffset]) makes it breathe; the handles stay
/// exactly on the values. [active] marks the handle being dragged.
class RadarShapePainter extends CustomPainter {
  RadarShapePainter({
    required this.values,
    required this.palette,
    required this.color,
    this.breath,
    this.active,
    this.handles = true,
    this.bare = false,
    this.textScale = 1,
  }) : super(repaint: breath);

  final List<double> values;
  final GroundPalette palette;
  final Color color;
  final Animation<double>? breath;
  final int? active;
  final bool handles;
  final bool bare;

  /// The user's text size, which sizes the name band ([WheelLayout.of]).
  final double textScale;

  /// The drawn radius of a handle; its touch target is [radarHandleTarget].
  static const handleRadius = 8.0;

  @override
  void paint(Canvas canvas, Size size) {
    final count = values.length;
    if (count < 3) return;
    final layout = _layout(size, bare, textScale);
    final reach = layout.reach;
    if (reach <= 0) return;
    final centre = layout.centre;
    final t = breath?.value ?? 0;
    Offset point(int i, double value) =>
        centre + radarAxisDirection(i, count) * (value * reach);
    final points = [
      for (var i = 0; i < count; i++)
        point(
          i,
          math.max(values[i], radarMinShown) * (1 + radarBreathOffset(t, i)),
        ),
    ];
    final shape = smoothClosedPath(points);
    final field = Rect.fromCircle(center: centre, radius: reach);
    final dark = palette.isDark;

    canvas
      ..drawPath(
        shape,
        Paint()
          ..color = color.withValues(alpha: dark ? .3 : .36)
          ..maskFilter = MaskFilter.blur(
            BlurStyle.normal,
            math.min(14, reach / 6),
          ),
      )
      ..drawPath(
        shape,
        Paint()
          ..shader = RadialGradient(
            colors: [
              palette.accent.withValues(alpha: dark ? .5 : .6),
              color.withValues(alpha: dark ? .42 : .48),
              color.withValues(alpha: dark ? .2 : .26),
            ],
            stops: const [0, .45, 1],
          ).createShader(field),
      )
      ..drawPath(
        shape,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..color = dark
              ? Color.lerp(color, palette.light, .55)!.withValues(alpha: .85)
              : Color.lerp(color, palette.shade, .35)!.withValues(alpha: .85),
      );

    if (!handles) return;
    for (var i = 0; i < count; i++) {
      _paintHandle(canvas, point(i, values[i]), i == active);
    }
  }

  void _paintHandle(Canvas canvas, Offset at, bool active) {
    if (active) {
      canvas.drawCircle(
        at,
        handleRadius + 8,
        Paint()
          ..color = palette.accent.withValues(alpha: .35)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
    }
    final radius = active ? handleRadius + 2 : handleRadius;
    final body = Rect.fromCircle(center: at, radius: radius);
    final surface = palette.isDark
        ? palette.surface
        : Color.lerp(palette.surface, palette.light, .5)!;
    canvas
      ..drawCircle(
        at + const Offset(.6, 1.6),
        radius,
        Paint()
          ..color = palette.shade.withValues(alpha: palette.isDark ? .5 : .2),
      )
      ..drawCircle(
        at,
        radius,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color.lerp(surface, palette.light, palette.isDark ? .14 : .5)!,
              Color.lerp(surface, palette.shade, palette.isDark ? .2 : .08)!,
            ],
          ).createShader(body),
      )
      ..drawCircle(
        at,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = palette.light.withValues(alpha: palette.isDark ? .22 : .7),
      )
      ..drawCircle(at, active ? 4 : 3, Paint()..color = palette.accent);
  }

  @override
  bool shouldRepaint(RadarShapePainter old) =>
      !listEquals(old.values, values) ||
      old.palette != palette ||
      old.color != color ||
      old.breath != breath ||
      old.active != active ||
      old.handles != handles ||
      old.bare != bare ||
      old.textScale != textScale;
}
