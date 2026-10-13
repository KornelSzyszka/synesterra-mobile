import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/widgets.dart';

import '../theme/ground_palette.dart';
import '../theme/round_shapes.dart';
import '../theme/surfaces.dart';
import 'radar_geometry.dart';

// The instrument radar in visual language v2: a glass field (rings, axes and
// labels on glass) and over it an organic shape (a soft, rounded polygon with
// a gradient fill and a halo in the instrument's colour) with tactile vertex
// handles. Two painters so the static field and the moving shape sit behind
// separate RepaintBoundary layers.

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

/// The static field: a glass disc with faint rings and axes, and the axis
/// [labels] on small glass capsules. With no labels (a thumbnail) only the
/// disc and the rings are drawn.
class RadarFieldPainter extends CustomPainter {
  const RadarFieldPainter({
    required this.palette,
    required this.count,
    this.labels = const [],
    this.labelStyle,
    this.labelBox = radarLabelBox,
  });

  final GroundPalette palette;
  final int count;
  final List<String> labels;
  final TextStyle? labelStyle;

  /// The room kept for each label; [Size.zero] for a thumbnail.
  final Size labelBox;

  /// Hint rings as shares of the reach.
  static const rings = [1 / 3, 2 / 3, 1.0];

  @override
  void paint(Canvas canvas, Size size) {
    final surfaces = Surfaces(palette);
    final reach = radarReach(size, count, label: labelBox, gap: _gap);
    if (reach <= 0) return;
    final centre = size.center(Offset.zero);
    final disc = Rect.fromCircle(
      center: centre,
      radius: reach + radarMargin / 2,
    );
    surfaces.paint(canvas, circlePath(disc), disc, SurfaceStyle.glass);

    final ink = palette.isDark ? palette.light : palette.shade;
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = ink.withValues(alpha: palette.isDark ? .07 : .1);
    for (final ring in rings) {
      canvas.drawCircle(centre, reach * ring, line);
    }
    if (labels.isEmpty) return;
    for (var i = 0; i < count; i++) {
      canvas.drawLine(centre, radarPoint(i, count, 1, size, reach), line);
    }

    final style = labelStyle;
    if (style == null) return;
    for (var i = 0; i < math.min(count, labels.length); i++) {
      final box = radarLabelRect(i, count, size, reach, label: labelBox);
      final text = TextPainter(
        text: TextSpan(
          text: labels[i],
          style: style.copyWith(color: surfaces.mutedOn(SurfaceStyle.glass)),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: math.max(0, box.width - 2 * _pillPadding));
      final pill = Rect.fromCenter(
        center: box.center,
        width: text.width + 2 * _pillPadding,
        height: math.min(box.height, text.height + 4),
      );
      surfaces.paint(canvas, capsulePath(pill), pill, SurfaceStyle.glass);
      text.paint(canvas, pill.center - Offset(text.width / 2, text.height / 2));
      text.dispose();
    }
  }

  double get _gap => labelBox == Size.zero ? 0 : radarLabelGap;

  static const _pillPadding = 8.0;

  @override
  bool shouldRepaint(RadarFieldPainter old) =>
      old.palette != palette ||
      old.count != count ||
      !listEquals(old.labels, labels) ||
      old.labelStyle != labelStyle ||
      old.labelBox != labelBox;
}

/// The shape: a soft polygon through the trait [values] (0 centre, 1 edge),
/// filled with a gradient from a gold core into the instrument's [color], a
/// halo and a glass rim. [breath] (0..1 over one bout, see
/// [radarBreathOffset]) makes it breathe; the handles stay exactly on the
/// values. [active] marks the handle being dragged.
class RadarShapePainter extends CustomPainter {
  RadarShapePainter({
    required this.values,
    required this.palette,
    required this.color,
    this.breath,
    this.active,
    this.handles = true,
    this.labelBox = radarLabelBox,
  }) : super(repaint: breath);

  final List<double> values;
  final GroundPalette palette;
  final Color color;
  final Animation<double>? breath;
  final int? active;
  final bool handles;
  final Size labelBox;

  /// The drawn radius of a handle; its touch target is [radarHandleTarget].
  static const handleRadius = 8.0;

  @override
  void paint(Canvas canvas, Size size) {
    final count = values.length;
    if (count < 3) return;
    final reach = radarReach(
      size,
      count,
      label: labelBox,
      gap: labelBox == Size.zero ? 0 : radarLabelGap,
    );
    if (reach <= 0) return;
    final centre = size.center(Offset.zero);
    final t = breath?.value ?? 0;
    final points = [
      for (var i = 0; i < count; i++)
        radarPoint(
          i,
          count,
          math.max(values[i], radarMinShown) * (1 + radarBreathOffset(t, i)),
          size,
          reach,
        ),
    ];
    final shape = smoothClosedPath(points);
    final field = Rect.fromCircle(center: centre, radius: reach);
    final dark = palette.isDark;

    canvas
      ..drawPath(
        shape,
        Paint()
          ..color = color.withValues(alpha: dark ? .32 : .4)
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
              palette.accent.withValues(alpha: dark ? .6 : .7),
              color.withValues(alpha: dark ? .5 : .55),
              color.withValues(alpha: dark ? .24 : .3),
            ],
            stops: const [0, .42, 1],
          ).createShader(field),
      )
      ..drawPath(
        shape,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..color = dark
              ? Color.lerp(color, palette.light, .55)!.withValues(alpha: .8)
              : Color.lerp(color, palette.shade, .35)!.withValues(alpha: .85),
      );

    if (!handles) return;
    for (var i = 0; i < count; i++) {
      _paintHandle(
        canvas,
        radarPoint(i, count, values[i], size, reach),
        i == active,
      );
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
      old.labelBox != labelBox;
}
