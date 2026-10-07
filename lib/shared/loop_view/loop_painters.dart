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
          ..strokeWidth = 1.2
          ..color = tokens.muted.withValues(alpha: .6),
      );
      return;
    }
    if (pulse > 0) {
      canvas.drawCircle(
        at,
        radius + 8 * pulse,
        Paint()..color = color.withValues(alpha: .35 * pulse),
      );
    }
    canvas.drawCircle(at, radius * (1 + .35 * pulse), Paint()..color = color);
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
      canvas.drawCircle(
        layout.center,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = shown(layer).withValues(alpha: layer.muted ? .15 : .35),
      );
      for (var i = 0; i < layer.stepCount; i++) {
        final at = pointOnCircle(
          layout.center,
          radius,
          playheadAngle(
            stepFraction(i, layer.stepCount, phaseSteps: layer.phaseSteps),
          ),
        );
        paintStepDot(canvas, layer, at, layer.steps[i], pulseOf(layer, i));
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
    canvas.drawLine(
      layout.center,
      tip,
      Paint()
        ..color = tokens.accent
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(tip, 3, Paint()..color = tokens.accent);
  }
}

/// One row per layer across the cycle, steps as blocks, a moving playhead
/// line and a tick per beat.
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
    final tick = Paint()
      ..color = tokens.border
      ..strokeWidth = 1;
    final beats = math.max(1, state.cycleBeats.ceil());
    for (var b = 0; b <= beats; b++) {
      final x = timelineX(b / beats, layout.left, layout.width);
      canvas.drawLine(
        Offset(x, layout.bottom),
        Offset(x, layout.bottom + Space.xs),
        tick,
      );
    }
    for (var l = 0; l < count; l++) {
      final layer = state.layers[l];
      final y = layout.rowCenterY(l);
      canvas.drawLine(
        Offset(layout.left, y),
        Offset(layout.right, y),
        Paint()
          ..color = shown(layer).withValues(alpha: layer.muted ? .15 : .3)
          ..strokeWidth = 1,
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
        final rrect = RRect.fromRectAndRadius(
          rect,
          const Radius.circular(Radii.xs),
        );
        if (layer.steps[i]) {
          canvas.drawRRect(
            rrect,
            Paint()
              ..color = shown(layer)
                  .withValues(alpha: layer.muted ? .4 : .55 + .45 * pulse),
          );
        } else {
          canvas.drawRRect(
            rrect,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.2
              ..color = tokens.muted.withValues(alpha: .5),
          );
        }
      }
    }
    final x = timelineX(position.cyclePosition, layout.left, layout.width);
    canvas.drawLine(
      Offset(x, layout.top),
      Offset(x, layout.bottom),
      Paint()
        ..color = tokens.accent
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );
  }
}

/// A polygon per layer with one vertex per step: 3 steps give a triangle,
/// 2 a line, 4 a square, 5 a pentagon. A dot travels along each polygon and
/// is on a vertex exactly when that step hits.
class PolygonsPainter extends LoopPainter {
  PolygonsPainter({
    required super.state,
    required super.source,
    required super.tokens,
    required super.labelStyle,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cells = polygonCells(size, state.layers.length);
    for (var l = 0; l < state.layers.length; l++) {
      final layer = state.layers[l];
      final cell = cells[l];
      final vertices = polygonVertices(
        cell.center,
        polygonRadius(cell),
        layer.stepCount,
      );
      final outline = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeJoin = StrokeJoin.round
        ..color = shown(layer).withValues(alpha: layer.muted ? .2 : .55);
      if (vertices.length > 1) {
        final path = Path()..moveTo(vertices.first.dx, vertices.first.dy);
        for (final v in vertices.skip(1)) {
          path.lineTo(v.dx, v.dy);
        }
        canvas.drawPath(path..close(), outline);
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
      canvas.drawCircle(dot, 5.5, Paint()..color = tokens.text);
      canvas.drawCircle(
        dot,
        5.5,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = tokens.accent,
      );
      paintNumber(
        canvas,
        layer,
        cell.topLeft + const Offset(Space.md, Space.md),
      );
    }
  }
}
