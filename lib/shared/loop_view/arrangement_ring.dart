import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../theme/ambient_scope.dart';
import '../theme/design_scale.dart';
import '../theme/ground_palette.dart';
import '../theme/synesterra_theme.dart';
import 'arrangement_ring_geometry.dart';
import 'arrangement_strip.dart';
import 'loop_geometry.dart';
import 'position_source.dart';
import 'source_semantics.dart';

/// The arrangement as a ring of sections (UX-123): a circular timeline where
/// each section is an arc as long as its repeats, in its loop's colour, with
/// its number outside and its loop's small figure inside. While playing, a
/// light walks around the ring; the current section glows and fills, the
/// sections already played this pass are dimmed, and a missing loop is a
/// dashed grey arc.
///
/// Driven only by [source] (the painter repaints through it; the widget tree
/// is not rebuilt per frame). Under reduce motion the light moves once a
/// cycle instead of continuously.
class ArrangementRing extends StatelessWidget {
  const ArrangementRing({
    super.key,
    required this.sections,
    required this.source,
    this.maxSide = 320,
  });

  final List<StripSection> sections;
  final PositionSource source;

  /// The ring is a square as wide as its parent, up to this.
  final double maxSide;

  @override
  Widget build(BuildContext context) {
    final platform = Theme.of(context).platform;
    final tokens = SynesterraTokens.of(context);
    final palette = AmbientScope.paletteOf(context);
    final continuous = !MediaQuery.disableAnimationsOf(context);
    final textScaler = MediaQuery.textScalerOf(context);
    return Semantics(
      container: true,
      label: describeArrangement(sections),
      child: SourceSemantics(
        source: source,
        label: (p) => describeArrangementPosition(sections, p),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final side = constraints.maxWidth.isFinite
                ? math.min(constraints.maxWidth, maxSide)
                : maxSide;
            return Center(
              child: RepaintBoundary(
                child: CustomPaint(
                  key: const ValueKey('arrangement-ring-canvas'),
                  size: Size.square(side),
                  painter: ArrangementRingPainter(
                    sections: sections,
                    source: source,
                    colors: ArrangementRingColors.of(palette, tokens),
                    labelStyle: TextStyle(
                      fontFamily: SynesterraFonts.monospace(platform),
                      fontFamilyFallback: SynesterraFonts.monospaceFallback(
                        platform,
                      ),
                      fontSize: TypeScale.caption,
                      fontWeight: FontWeight.w600,
                    ),
                    numberStyle: TextStyle(
                      fontFamily: SynesterraFonts.serif(platform),
                      fontFamilyFallback: SynesterraFonts.serifFallback(
                        platform,
                      ),
                      fontSize: TypeScale.headline,
                    ),
                    captionStyle: TextStyle(
                      fontFamily: SynesterraFonts.ui(platform),
                      fontFamilyFallback: SynesterraFonts.uiFallback(platform),
                      fontSize: TypeScale.caption,
                    ),
                    textScaler: textScaler,
                    continuous: continuous,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// The colours the ring paints with.
@immutable
class ArrangementRingColors {
  const ArrangementRingColors({
    required this.text,
    required this.muted,
    required this.accent,
    required this.light,
    required this.layerColors,
  });

  factory ArrangementRingColors.of(
    GroundPalette palette,
    SynesterraTokens tokens,
  ) => ArrangementRingColors(
    text: palette.text,
    muted: palette.muted,
    accent: palette.accent,
    light: palette.light,
    layerColors: tokens.layerColors,
  );

  final Color text;
  final Color muted;
  final Color accent;
  final Color light;
  final List<Color> layerColors;

  @override
  bool operator ==(Object other) =>
      other is ArrangementRingColors &&
      text == other.text &&
      muted == other.muted &&
      accent == other.accent &&
      light == other.light &&
      listEquals(layerColors, other.layerColors);

  @override
  int get hashCode =>
      Object.hash(text, muted, accent, light, Object.hashAll(layerColors));
}

class ArrangementRingPainter extends CustomPainter {
  ArrangementRingPainter({
    required this.sections,
    required this.source,
    required this.colors,
    required this.labelStyle,
    required this.numberStyle,
    required this.captionStyle,
    this.textScaler = TextScaler.noScaling,
    this.continuous = true,
  }) : super(repaint: source);

  final List<StripSection> sections;
  final PositionSource source;
  final ArrangementRingColors colors;
  final TextStyle labelStyle;
  final TextStyle numberStyle;
  final TextStyle captionStyle;
  final TextScaler textScaler;

  /// False under reduce motion: the light moves once a cycle.
  final bool continuous;

  /// Alpha of the current section's gold glow.
  static const glowAlpha = .26;

  /// Every opaque colour a section number can sit on: the ground samples,
  /// also veiled by a neighbouring section's glow at full strength. Numbers
  /// are always in the text colour, since the muted colour has no room for
  /// a gold veil (played and missing sections are dimmed by their arcs).
  static List<Color> numberGrounds(GroundPalette palette) => [
    ...palette.groundSamples,
    for (final c in palette.groundSamples)
      Color.alphaBlend(palette.accent.withValues(alpha: glowAlpha), c),
  ];

  /// Every opaque colour the centre text sits on: the plain ground samples
  /// (nothing is painted in the middle of the ring).
  static List<Color> centreGrounds(GroundPalette palette) =>
      palette.groundSamples;

  /// The section the light is in, or null when nothing plays here.
  int? currentSection(LoopPosition p) {
    final index = p.sectionIndex;
    if (!p.playing || index == null || index >= sections.length) return null;
    return sections[index].missing ? null : index;
  }

  /// The ring's measures inside [size]: band width, the radius of the band's
  /// centre line, of the number labels, of the small figures, the figures'
  /// size, and the radius left free in the middle.
  ({
    double band,
    double radius,
    double labelRadius,
    double figureRadius,
    double figureSize,
    double innerRadius,
  })
  measures(Size size) {
    final side = size.shortestSide;
    final label = textScaler.scale(TypeScale.caption) * 1.3;
    final band = (side * .045).clamp(8.0, 13.0);
    final labelRadius = side / 2 - label * .7 - 2;
    final radius = math.max(
      1.0,
      labelRadius - label * .75 - band / 2 - Space.sm,
    );
    final figureSize = (side * .075).clamp(12.0, 22.0);
    final figureRadius = radius - band / 2 - Space.md - figureSize / 2;
    return (
      band: band,
      radius: radius,
      labelRadius: labelRadius,
      figureRadius: figureRadius,
      figureSize: figureSize,
      innerRadius: math.max(0.0, figureRadius - figureSize / 2 - Space.sm),
    );
  }

  /// Where the light is: the centre of the band at the playhead, or null.
  Offset? playheadPoint(Size size) {
    final p = source.value;
    final current = currentSection(p);
    if (current == null || sections.isEmpty) return null;
    final arcs = ringArcs([for (final s in sections) s.repeats]);
    final m = measures(size);
    final progress = ringProgress(
      p,
      sections[current].repeats,
      continuous: continuous,
    );
    return pointOnCircle(
      size.center(Offset.zero),
      m.radius,
      ringPlayheadAngle(arcs[current], progress),
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (sections.isEmpty) return;
    final arcs = ringArcs([for (final s in sections) s.repeats]);
    final center = size.center(Offset.zero);
    final m = measures(size);
    final r = m.radius;
    final band = m.band;
    final p = source.value;
    final current = currentSection(p);
    final bandRect = Rect.fromCircle(center: center, radius: r);

    // The vessel: a faint glass groove with a hairline rim.
    canvas
      ..drawCircle(
        center,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = band + 6
          ..color = colors.light.withValues(alpha: .025),
      )
      ..drawCircle(
        center,
        r + band / 2 + 3,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = .8
          ..color = colors.light.withValues(alpha: .07),
      );

    // Round caps reach past the sweep by half the band; start and end
    // inside it so the gaps stay open.
    final cap = (band / 2) / r;
    for (var i = 0; i < sections.length; i++) {
      final section = sections[i];
      final arc = arcs[i];
      final color =
          colors.layerColors[section.colorIndex % colors.layerColors.length];
      final played = current != null && i < current;
      final isCurrent = current == i;
      final from = arc.start + cap;
      final sweep = math.max(arc.sweep - 2 * cap, .0001);
      if (section.missing) {
        _dashedArc(canvas, bandRect, arc, band, r);
      } else {
        if (isCurrent) {
          canvas.drawArc(
            bandRect,
            from,
            sweep,
            false,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeCap = StrokeCap.round
              ..strokeWidth = band + 6
              ..color = colors.accent.withValues(alpha: glowAlpha)
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
          );
        }
        canvas.drawArc(
          bandRect,
          from,
          sweep,
          false,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            ..strokeWidth = band
            ..color = color.withValues(
              alpha: played ? .16 : (isCurrent ? .42 : .32),
            ),
        );
        // A glass highlight along the inner edge of the band.
        canvas.drawArc(
          Rect.fromCircle(center: center, radius: r - band / 2 + 1.6),
          from,
          sweep,
          false,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            ..strokeWidth = 1
            ..color = colors.light.withValues(alpha: played ? .05 : .12),
        );
        if (isCurrent) {
          final progress = ringProgress(
            p,
            section.repeats,
            continuous: continuous,
          );
          final filled = arc.sweep * progress - cap;
          if (filled > 0) {
            canvas.drawArc(
              bandRect,
              from,
              math.min(filled, sweep),
              false,
              Paint()
                ..style = PaintingStyle.stroke
                ..strokeCap = StrokeCap.round
                ..strokeWidth = band
                ..color = color.withValues(alpha: .95),
            );
          }
          // A gold rim along the outside of the current section.
          canvas.drawArc(
            Rect.fromCircle(center: center, radius: r + band / 2 + 1.5),
            from,
            sweep,
            false,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeCap = StrokeCap.round
              ..strokeWidth = 1.4
              ..color = colors.accent,
          );
        }
        if (section.layerSteps.isNotEmpty &&
            arcFits(arc, m.figureRadius, m.figureSize + Space.xs)) {
          _figure(
            canvas,
            pointOnCircle(center, m.figureRadius, arc.mid),
            m.figureSize / 2,
            section.layerSteps,
            color.withValues(alpha: isCurrent ? .95 : (played ? .35 : .7)),
          );
        }
      }
      // The number outside the arc, when it fits along it (with the gap).
      final number = _text('${i + 1}', labelStyle.copyWith(color: colors.text));
      if (arcFits(
        RingArc(start: arc.start, sweep: arc.sweep + ringGap),
        m.labelRadius,
        number.width + 2,
      )) {
        final at = pointOnCircle(center, m.labelRadius, arc.mid);
        number.paint(canvas, at - Offset(number.width / 2, number.height / 2));
      }
      number.dispose();
    }

    // The start of the arrangement: a small gold point at 12 o'clock.
    canvas.drawCircle(
      pointOnCircle(center, r, -math.pi / 2),
      1.6,
      Paint()..color = colors.accent.withValues(alpha: .7),
    );

    if (current != null) {
      final light = playheadPoint(size)!;
      canvas
        ..drawCircle(
          light,
          band * .75,
          Paint()
            ..color = colors.accent.withValues(alpha: .45)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
        )
        ..drawCircle(light, band * .42, Paint()..color = colors.accent)
        ..drawCircle(
          light,
          band * .16,
          Paint()..color = colors.light.withValues(alpha: .85),
        );
    }
    _centre(canvas, center, m.innerRadius, p, current);
  }

  /// A missing loop: a dashed grey arc, no fill.
  void _dashedArc(
    Canvas canvas,
    Rect rect,
    RingArc arc,
    double band,
    double r,
  ) {
    final width = band * .4;
    final dash = 4 / r;
    final cap = (width / 2) / r;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = width
      ..color = colors.muted.withValues(alpha: .55);
    final end = arc.end - cap;
    for (var a = arc.start + cap; a < end; a += 2 * dash) {
      canvas.drawArc(
        rect,
        a,
        math.max(.0001, math.min(dash, end - a)),
        false,
        paint,
      );
    }
  }

  /// The loop's small figure: one regular polygon per layer, a vertex per
  /// step, nested from the outside in (the Polygons view in miniature).
  void _figure(
    Canvas canvas,
    Offset at,
    double radius,
    List<int> layerSteps,
    Color color,
  ) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round
      ..color = color;
    for (var k = 0; k < layerSteps.length; k++) {
      final layerRadius =
          radius * (1 - .3 * k / math.max(1, layerSteps.length - 1));
      final vertices = polygonVertices(at, layerRadius, layerSteps[k]);
      if (vertices.length == 1) {
        canvas.drawCircle(vertices.single, 1.4, Paint()..color = color);
      } else {
        canvas.drawPath(Path()..addPolygon(vertices, true), paint);
      }
    }
  }

  /// The middle of the ring: the current section's number, loop and cycle
  /// while playing, otherwise how many sections and cycles there are. Lines
  /// that do not fit (large text on a small ring) are left out from the
  /// bottom.
  void _centre(
    Canvas canvas,
    Offset center,
    double innerRadius,
    LoopPosition p,
    int? current,
  ) {
    if (innerRadius <= 0) return;
    final width = innerRadius * 1.5;
    final List<TextPainter> lines;
    if (current != null) {
      final section = sections[current];
      lines = [
        _text('${current + 1}', numberStyle.copyWith(color: colors.text)),
        _text(
          section.label,
          captionStyle.copyWith(color: colors.text),
          maxWidth: width,
        ),
        _text(
          'cycle ${(p.cycleIndex % section.repeats) + 1} of ${section.repeats}',
          captionStyle.copyWith(color: colors.muted),
          maxWidth: width,
        ),
      ];
    } else {
      final cycles = sections
          .where((s) => !s.missing)
          .fold<int>(0, (sum, s) => sum + s.repeats);
      lines = [
        _text('${sections.length}', numberStyle.copyWith(color: colors.text)),
        _text(
          sections.length == 1 ? 'section' : 'sections',
          captionStyle.copyWith(color: colors.muted),
          maxWidth: width,
        ),
        _text(
          '$cycles ${cycles == 1 ? 'cycle' : 'cycles'}',
          captionStyle.copyWith(color: colors.muted),
          maxWidth: width,
        ),
      ];
    }
    var count = lines.length;
    double height() => lines.take(count).fold(0.0, (h, t) => h + t.height);
    while (count > 0 && height() > innerRadius * 1.7) {
      count--;
    }
    var y = center.dy - height() / 2;
    for (final line in lines.take(count)) {
      line.paint(canvas, Offset(center.dx - line.width / 2, y));
      y += line.height;
    }
    for (final line in lines) {
      line.dispose();
    }
  }

  TextPainter _text(String text, TextStyle style, {double? maxWidth}) =>
      TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: TextDirection.ltr,
        textScaler: textScaler,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: maxWidth ?? double.infinity);

  @override
  bool shouldRepaint(covariant ArrangementRingPainter oldDelegate) =>
      !listEquals(oldDelegate.sections, sections) ||
      oldDelegate.source != source ||
      oldDelegate.colors != colors ||
      oldDelegate.labelStyle != labelStyle ||
      oldDelegate.numberStyle != numberStyle ||
      oldDelegate.captionStyle != captionStyle ||
      oldDelegate.textScaler != textScaler ||
      oldDelegate.continuous != continuous;
}
