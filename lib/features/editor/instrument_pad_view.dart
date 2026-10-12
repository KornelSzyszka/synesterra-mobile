import 'dart:math';

import 'package:flutter/material.dart';
import 'package:synesterra_core/synesterra_core.dart';

import '../../shared/theme/design_scale.dart';
import '../../shared/theme/synesterra_theme.dart';
import 'immediate_pan.dart';
import 'pad_geometry.dart';

/// The disc that shapes a sound: the angle around it picks the character
/// (the five anchor names sit on the rim) and the distance from the centre
/// sets how pronounced it is (centre neutral, rim pure). It reports the
/// touched [PadPoint] while the finger is down ([onPoint]) and the lift
/// ([onRelease]); it holds no state.
///
/// The whole square around the disc is the touch target and takes the gesture
/// at once, so touching it never scrolls the page; a touch outside the disc
/// puts the dot on the rim. Screen readers get one adjustable control for the
/// character and one for the strength instead of a drag.
class InstrumentPad extends StatelessWidget {
  const InstrumentPad({
    super.key,
    required this.point,
    required this.onPoint,
    required this.onRelease,
  });

  /// Where the dot is; null hides it.
  final PadPoint? point;
  final ValueChanged<PadPoint> onPoint;
  final VoidCallback onRelease;

  static const characterLabel = 'Character, turn around the circle';
  static const strengthLabel = 'Strength, centre to rim';

  static String _character(PadPoint? point) =>
      point == null ? 'Not set' : 'Closest to ${padCharacterName(point)}';

  static String _strength(PadPoint? point) =>
      point == null ? 'Not set' : '${padPercent(point.radius)} percent';

  void _adjust({double dAngle = 0, double dRadius = 0}) {
    onPoint(stepPadPoint(point, dAngle: dAngle, dRadius: dRadius));
    onRelease();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = SynesterraTokens.of(context);
    return AspectRatio(
      aspectRatio: 1,
      child: LayoutBuilder(
        builder: (context, box) {
          final size = box.biggest;
          void touch(Offset local) => onPoint(padPointAt(local, size));
          return Stack(
            children: [
              ExcludeSemantics(
                child: ImmediatePanDetector(
                  onDown: touch,
                  onUpdate: touch,
                  onEnd: onRelease,
                  child: CustomPaint(
                    size: size,
                    painter: InstrumentPadPainter(
                      point: point,
                      anchors: padAnchors,
                      background: tokens.surface,
                      border: tokens.border,
                      label: tokens.muted,
                      dot: tokens.accent,
                      dotRing: tokens.text,
                      dotOutline: tokens.background,
                    ),
                  ),
                ),
              ),
              Semantics(
                container: true,
                label: characterLabel,
                value: _character(point),
                increasedValue: _character(
                  stepPadPoint(point, dAngle: padStepAngle),
                ),
                decreasedValue: _character(
                  stepPadPoint(point, dAngle: -padStepAngle),
                ),
                onIncrease: () => _adjust(dAngle: padStepAngle),
                onDecrease: () => _adjust(dAngle: -padStepAngle),
                child: const SizedBox.expand(),
              ),
              Semantics(
                container: true,
                label: strengthLabel,
                value: _strength(point),
                increasedValue: _strength(
                  stepPadPoint(point, dRadius: padStepRadius),
                ),
                decreasedValue: _strength(
                  stepPadPoint(point, dRadius: -padStepRadius),
                ),
                onIncrease: () => _adjust(dRadius: padStepRadius),
                onDecrease: () => _adjust(dRadius: -padStepRadius),
                child: const SizedBox.expand(),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Draws the disc, its hint rings, the faint anchor names on the rim and the
/// dot.
class InstrumentPadPainter extends CustomPainter {
  const InstrumentPadPainter({
    required this.point,
    required this.anchors,
    required this.background,
    required this.border,
    required this.label,
    required this.dot,
    required this.dotRing,
    required this.dotOutline,
  });

  final PadPoint? point;
  final List<PadAnchor> anchors;
  final Color background;
  final Color border;
  final Color label;
  final Color dot;
  final Color dotRing;
  final Color dotOutline;

  /// The dot's radius; the ring and outline are drawn outside it.
  static const dotRadius = 10.0;

  /// Concentric hint rings as fractions of the disc radius: the rim is the
  /// pure character, each ring marks a step toward the neutral centre.
  static const ringFractions = [1 / 3, 2 / 3];

  @override
  void paint(Canvas canvas, Size size) {
    final centre = size.center(Offset.zero);
    final reach = padDiscRadius(size);
    canvas
      ..drawCircle(centre, reach, Paint()..color = background)
      ..drawCircle(
        centre,
        reach - 0.5,
        Paint()
          ..color = border
          ..style = PaintingStyle.stroke,
      );
    for (final fraction in ringFractions) {
      canvas.drawCircle(
        centre,
        reach * fraction,
        Paint()
          ..color = border.withValues(alpha: 0.45)
          ..style = PaintingStyle.stroke,
      );
    }

    for (final anchor in anchors) {
      final painter = TextPainter(
        text: TextSpan(
          text: anchor.name,
          style: TextStyle(
            color: label.withValues(alpha: 0.7),
            fontSize: TypeScale.caption,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();
      // Centred on the anchor's place on the rim, kept inside the field.
      final rim = padOffsetOf(anchor.point, size);
      final left = (rim.dx - painter.width / 2).clamp(
        Space.xs,
        max(Space.xs, size.width - painter.width - Space.xs),
      );
      final top = (rim.dy - painter.height / 2).clamp(
        Space.xs,
        max(Space.xs, size.height - painter.height - Space.xs),
      );
      painter.paint(canvas, Offset(left.toDouble(), top.toDouble()));
    }

    final p = point;
    if (p == null) return;
    // Three layers keep the dot visible on every background: a dark outline,
    // a light ring and the accent fill.
    final at = padOffsetOf(p, size);
    canvas
      ..drawCircle(at, dotRadius + Space.xs, Paint()..color = dotOutline)
      ..drawCircle(at, dotRadius + 2, Paint()..color = dotRing)
      ..drawCircle(at, dotRadius, Paint()..color = dot);
  }

  @override
  bool shouldRepaint(InstrumentPadPainter old) =>
      old.point != point ||
      old.anchors != anchors ||
      old.background != background ||
      old.border != border ||
      old.label != label ||
      old.dot != dot ||
      old.dotRing != dotRing ||
      old.dotOutline != dotOutline;
}
