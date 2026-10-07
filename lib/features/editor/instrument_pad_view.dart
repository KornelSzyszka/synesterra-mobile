import 'package:flutter/material.dart';
import 'package:synesterra_core/synesterra_core.dart';

import '../../shared/theme/design_scale.dart';
import '../../shared/theme/synesterra_theme.dart';
import 'immediate_pan.dart';
import 'pad_geometry.dart';

/// The 2D field that shapes a sound: dark to bright from left to right, soft
/// to hard from top to bottom. It reports the touched [PadPoint] while the
/// finger is down ([onPoint]) and the lift ([onRelease]); it holds no state.
///
/// It is the whole touch target and takes the gesture at once, so touching it
/// never scrolls the page. Screen readers get one adjustable control per axis
/// instead of a drag.
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

  static const horizontalLabel = 'Brightness, dark to bright';
  static const verticalLabel = 'Hardness, soft to hard';

  static String _spoken(double? coordinate) =>
      coordinate == null ? 'Not set' : '${padPercent(coordinate)} percent';

  void _adjust({double dx = 0, double dy = 0}) {
    onPoint(stepPadPoint(point, dx: dx, dy: dy));
    onRelease();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = SynesterraTokens.of(context);
    final x = point?.x;
    final y = point?.y;
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
                label: horizontalLabel,
                value: _spoken(x),
                increasedValue: _spoken(stepPadPoint(point, dx: padStep).x),
                decreasedValue: _spoken(stepPadPoint(point, dx: -padStep).x),
                onIncrease: () => _adjust(dx: padStep),
                onDecrease: () => _adjust(dx: -padStep),
                child: const SizedBox.expand(),
              ),
              Semantics(
                container: true,
                label: verticalLabel,
                value: _spoken(y),
                increasedValue: _spoken(stepPadPoint(point, dy: padStep).y),
                decreasedValue: _spoken(stepPadPoint(point, dy: -padStep).y),
                onIncrease: () => _adjust(dy: padStep),
                onDecrease: () => _adjust(dy: -padStep),
                child: const SizedBox.expand(),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Draws the field, the faint anchor names and the dot.
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

  @override
  void paint(Canvas canvas, Size size) {
    final field = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(Radii.lg),
    );
    canvas
      ..drawRRect(field, Paint()..color = background)
      ..drawRRect(
        field.deflate(0.5),
        Paint()
          ..color = border
          ..style = PaintingStyle.stroke,
      );

    for (final anchor in anchors) {
      final painter = TextPainter(
        text: TextSpan(
          text: anchor.name,
          style: TextStyle(color: label.withValues(alpha: 0.7), fontSize: TypeScale.caption),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();
      final center = padOffsetOf(PadPoint(anchor.x, anchor.y), size);
      final left = (center.dx - painter.width / 2).clamp(
        Space.sm,
        (size.width - painter.width - Space.sm).clamp(Space.sm, double.infinity),
      );
      final top = (center.dy - painter.height / 2).clamp(
        Space.sm,
        (size.height - painter.height - Space.sm).clamp(Space.sm, double.infinity),
      );
      painter.paint(canvas, Offset(left, top));
    }

    final p = point;
    if (p == null) return;
    // Three layers keep the dot visible on every background: a dark outline,
    // a light ring and the accent fill.
    final center = padOffsetOf(p, size);
    canvas
      ..drawCircle(center, dotRadius + Space.xs, Paint()..color = dotOutline)
      ..drawCircle(center, dotRadius + 2, Paint()..color = dotRing)
      ..drawCircle(center, dotRadius, Paint()..color = dot);
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
