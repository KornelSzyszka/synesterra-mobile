import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/design_scale.dart';
import '../theme/synesterra_theme.dart';
import 'loop_geometry.dart';
import 'loop_view_state.dart';
import 'position_source.dart';

/// Shared by the three loop painters. They repaint when [source] changes and
/// read nothing else for time: no timer, no animation of their own. A hit
/// pulse is a function of the position ([stepPulse]), so a stopped or paused
/// view is still and a resumed view is exact.
///
/// Visual language v2: soft, round marks. Steps are small lit pearls, a hit
/// blooms into a soft halo, the playhead is a gold line with a glow and a
/// small light at its tip. Glows use small blurs only, because a playing view
/// repaints every frame.
abstract class LoopPainter extends CustomPainter {
  LoopPainter({
    required this.state,
    required this.source,
    required this.tokens,
    required this.labelStyle,
  }) : super(repaint: source);

  final LoopViewState state;
  final PositionSource source;
  final SynesterraTokens tokens;

  /// Style of the layer numbers (monospace, from the theme).
  final TextStyle labelStyle;

  LoopPosition get position => source.value;

  Color layerColor(LoopLayerView layer) =>
      tokens.layerColors[layer.colorIndex % tokens.layerColors.length];

  /// A muted layer keeps its number and colour but is drawn faded.
  Color shown(LoopLayerView layer) =>
      layerColor(layer).withValues(alpha: layer.muted ? .4 : 1);

  /// Pulse of step [index] of [layer]; 0 unless playing.
  double pulseOf(LoopLayerView layer, int index) => position.playing
      ? stepPulse(
          position.cyclePosition,
          stepFraction(index, layer.stepCount, phaseSteps: layer.phaseSteps),
        )
      : 0;

  /// Draws a layer number. [anchor] is the corner or edge point given by
  /// [alignX]: 0 = text starts at anchor, 1 = text ends at anchor.
  void paintNumber(
    Canvas canvas,
    LoopLayerView layer,
    Offset anchor, {
    double alignX = 0,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: layer.number.toString().padLeft(2, '0'),
        style: labelStyle.copyWith(color: shown(layer)),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      Offset(
        anchor.dx - painter.width * alignX,
        anchor.dy - painter.height / 2,
      ),
    );
  }

  /// A step: a lit pearl of the layer's colour that blooms on its hit, or a
  /// faint ring when it makes no hit.
  void paintStepDot(
    Canvas canvas,
    LoopLayerView layer,
    Offset at,
    bool enabled,
    double pulse, {
    double radius = 5,
  }) {
    final color = shown(layer);
    if (!enabled) {
      canvas.drawCircle(
        at,
        radius * .6,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.1
          ..color = tokens.muted.withValues(alpha: .45),
      );
      return;
    }
    if (pulse > 0) {
      canvas.drawCircle(
        at,
        radius + 7 * pulse,
        Paint()
          ..color = color.withValues(alpha: .4 * pulse)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 3 + 4 * pulse),
      );
    }
    final r = radius * (1 + .35 * pulse);
    canvas.drawCircle(at, r, Paint()..color = color);
    // The pearl's light, top-left.
    canvas.drawCircle(
      at + Offset(-r * .32, -r * .32),
      r * .38,
      Paint()..color = Colors.white.withValues(alpha: .28 + .2 * pulse),
    );
  }

  /// A soft gold light: the playhead's tip, the polygons' travelling dot.
  void paintLight(Canvas canvas, Offset at, double radius) {
    canvas
      ..drawCircle(
        at,
        radius * 2,
        Paint()
          ..color = tokens.accent.withValues(alpha: .35)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius),
      )
      ..drawCircle(at, radius, Paint()..color = tokens.accent)
      ..drawCircle(
        at + Offset(-radius * .3, -radius * .3),
        radius * .35,
        Paint()..color = Colors.white.withValues(alpha: .55),
      );
  }

  /// The playhead from [from] to [to]: a soft glow under a thin gold line.
  void paintPlayhead(Canvas canvas, Offset from, Offset to) {
    canvas
      ..drawLine(
        from,
        to,
        Paint()
          ..color = tokens.accent.withValues(alpha: .22)
          ..strokeWidth = 7
          ..strokeCap = StrokeCap.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
      )
      ..drawLine(
        from,
        to,
        Paint()
          ..color = tokens.accent
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round,
      );
  }

  @override
  bool shouldRepaint(covariant LoopPainter oldDelegate) =>
      oldDelegate.runtimeType != runtimeType ||
      oldDelegate.state != state ||
      oldDelegate.source != source ||
      oldDelegate.tokens != tokens ||
      oldDelegate.labelStyle != labelStyle;
}

/// One ring per layer (the first outermost), a dot per step, a rotating
/// playhead.
class CirclePainter extends LoopPainter {
  CirclePainter({
    required super.state,
    required super.source,
    required super.tokens,
    required super.labelStyle,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final layout = RingLayout(size);
    final count = state.layers.length;
    for (var l = 0; l < count; l++) {
      final layer = state.layers[l];
      final radius = ringRadius(l, count, layout.outerRadius);
      final ring = shown(layer);
      // A soft band under a hairline: the ring reads as light, not as wire.
      canvas
        ..drawCircle(
          layout.center,
          radius,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 6
            ..color = ring.withValues(alpha: layer.muted ? .03 : .07),
        )
        ..drawCircle(
          layout.center,
          radius,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2
            ..color = ring.withValues(alpha: layer.muted ? .14 : .32),
        );
      for (var i = 0; i < layer.stepCount; i++) {
        final at = pointOnCircle(
          layout.center,
          radius,
          playheadAngle(
            stepFraction(i, layer.stepCount, phaseSteps: layer.phaseSteps),
          ),
        );
        // Disabled steps make no hit, so the circle does not draw them.
        if (!layer.steps[i]) continue;
        paintStepDot(canvas, layer, at, true, pulseOf(layer, i));
      }
      // The number sits left of 12 o'clock, off the first step's dot.
      paintNumber(
        canvas,
        layer,
        Offset(layout.center.dx - 9, layout.center.dy - radius),
        alignX: 1,
      );
    }
    final angle = playheadAngle(position.cyclePosition);
    final tip = pointOnCircle(layout.center, layout.outerRadius, angle);
    paintPlayhead(canvas, layout.center, tip);
    canvas.drawCircle(
      layout.center,
      3,
      Paint()..color = tokens.accent.withValues(alpha: .7),
    );
    paintLight(canvas, tip, 3.5);
  }
}

/// One row per layer across the cycle, steps as soft capsules, a moving
/// playhead line and a small light per beat.
class TimelinePainter extends LoopPainter {
  TimelinePainter({
    required super.state,
    required super.source,
    required super.tokens,
    required super.labelStyle,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final count = state.layers.length;
    final layout = TimelineLayout(size, count);
    final beat = Paint()..color = tokens.muted.withValues(alpha: .5);
    final beats = math.max(1, state.cycleBeats.ceil());
    for (var b = 0; b <= beats; b++) {
      final x = timelineX(b / beats, layout.left, layout.width);
      canvas.drawCircle(Offset(x, layout.bottom + Space.xs), 1.4, beat);
    }
    for (var l = 0; l < count; l++) {
      final layer = state.layers[l];
      final y = layout.rowCenterY(l);
      canvas.drawLine(
        Offset(layout.left, y),
        Offset(layout.right, y),
        Paint()
          ..color = shown(layer).withValues(alpha: layer.muted ? .1 : .2)
          ..strokeWidth = 1
          ..strokeCap = StrokeCap.round,
      );
      paintNumber(canvas, layer, Offset(Space.xs, y));
      final blockHeight = math.min(layout.rowHeight * .55, 28.0);
      final blockWidth = math.max(
        4.0,
        math.min(layout.width / layer.stepCount * .55, 28.0),
      );
      for (var i = 0; i < layer.stepCount; i++) {
        final x = timelineX(
          stepFraction(i, layer.stepCount, phaseSteps: layer.phaseSteps),
          layout.left,
          layout.width,
        );
        final pulse = pulseOf(layer, i);
        final rect = Rect.fromCenter(
          center: Offset(x + blockWidth / 2, y),
          width: blockWidth,
          height: blockHeight * (1 + .3 * pulse),
        );
        final capsule = RRect.fromRectAndRadius(
          rect,
          Radius.circular(rect.shortestSide / 2),
        );
        if (layer.steps[i]) {
          final color = layerColor(layer)
              .withValues(alpha: layer.muted ? .4 : .55 + .45 * pulse);
          if (pulse > 0) {
            canvas.drawRRect(
              capsule.inflate(3 * pulse),
              Paint()
                ..color = color.withValues(alpha: .4 * pulse)
                ..maskFilter = MaskFilter.blur(BlurStyle.normal, 2 + 4 * pulse),
            );
          }
          canvas.drawRRect(
            capsule,
            Paint()
              ..shader = LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color.lerp(color, Colors.white, .18)!, color],
              ).createShader(rect),
          );
        } else {
          canvas.drawRRect(
            capsule,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.1
              ..color = tokens.muted.withValues(alpha: .4),
          );
        }
      }
    }
    final x = timelineX(position.cyclePosition, layout.left, layout.width);
    paintPlayhead(canvas, Offset(x, layout.top), Offset(x, layout.bottom));
    paintLight(canvas, Offset(x, layout.top), 3);
  }
}

/// A polygon per layer with one vertex per step, nested around one shared
/// centre like a spider chart (the first layer outermost): 3 steps give a
/// triangle, 2 a line, 4 a square, 5 a pentagon. A dot travels along each polygon and
/// is on a vertex exactly when that step hits. The polygon is a soft shape of
/// light: a faint fill, a glowing band and a fine edge with round joins.
class PolygonsPainter extends LoopPainter {
  PolygonsPainter({
    required super.state,
    required super.source,
    required super.tokens,
    required super.labelStyle,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final outer = polygonOuterRadius(size);
    for (var l = 0; l < state.layers.length; l++) {
      final layer = state.layers[l];
      final radius = polygonLayerRadius(l, state.layers.length, outer);
      final vertices = polygonVertices(center, radius, layer.stepCount);
      final color = shown(layer);
      if (vertices.length > 1) {
        final path = Path()..moveTo(vertices.first.dx, vertices.first.dy);
        for (final v in vertices.skip(1)) {
          path.lineTo(v.dx, v.dy);
        }
        path.close();
        if (vertices.length > 2) {
          canvas.drawPath(
            path,
            Paint()..color = color.withValues(alpha: layer.muted ? .03 : .07),
          );
        }
        canvas
          ..drawPath(
            path,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 6
              ..strokeJoin = StrokeJoin.round
              ..strokeCap = StrokeCap.round
              ..color = color.withValues(alpha: layer.muted ? .04 : .09),
          )
          ..drawPath(
            path,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.4
              ..strokeJoin = StrokeJoin.round
              ..strokeCap = StrokeCap.round
              ..color = color.withValues(alpha: layer.muted ? .2 : .55),
          );
      }
      for (var i = 0; i < vertices.length; i++) {
        paintStepDot(
          canvas,
          layer,
          vertices[i],
          layer.steps[i],
          pulseOf(layer, i),
          radius: 4.5,
        );
      }
      final dot = polygonDotPoint(
        vertices,
        position.cyclePosition,
        phaseSteps: layer.phaseSteps,
      );
      paintLight(canvas, dot, 5);
      paintNumber(
        canvas,
        layer,
        Offset(vertices.first.dx - 9, vertices.first.dy),
        alignX: 1,
      );
    }
  }
}
