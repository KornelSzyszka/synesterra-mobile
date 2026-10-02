import 'package:flutter/material.dart';

/// Draws [curve] (points within the unit disc) with a soft glow made of
/// layered strokes, not a blur filter.
class FigurePainter extends CustomPainter {
  const FigurePainter({
    required this.curve,
    required this.color,
    this.pulse = 0,
  });

  final List<Offset> curve;
  final Color color;

  /// 0..1; grows and brightens the figure while a pulse plays.
  final double pulse;

  @override
  void paint(Canvas canvas, Size size) {
    if (curve.length < 2) return;
    final centre = size.center(Offset.zero);
    final radius = size.shortestSide / 2 * 0.9 * (1 + 0.06 * pulse);
    final path = Path()
      ..moveTo(
        centre.dx + curve.first.dx * radius,
        centre.dy + curve.first.dy * radius,
      );
    for (final point in curve.skip(1)) {
      path.lineTo(centre.dx + point.dx * radius, centre.dy + point.dy * radius);
    }
    path.close();
    _glow(canvas, path, color, pulse);
  }

  @override
  bool shouldRepaint(covariant FigurePainter oldDelegate) =>
      oldDelegate.curve != curve ||
      oldDelegate.color != color ||
      oldDelegate.pulse != pulse;
}

/// Draws one period of a waveform (values in -1..1) across the width.
class WavePainter extends CustomPainter {
  const WavePainter({
    required this.wave,
    required this.color,
    required this.axisColor,
    this.pulse = 0,
  });

  final List<double> wave;
  final Color color;
  final Color axisColor;
  final double pulse;

  @override
  void paint(Canvas canvas, Size size) {
    if (wave.length < 2) return;
    final middle = size.height / 2;
    canvas.drawLine(
      Offset(0, middle),
      Offset(size.width, middle),
      Paint()
        ..color = axisColor
        ..strokeWidth = 1,
    );
    final amplitude = size.height / 2 * 0.82 * (1 + 0.06 * pulse);
    final path = Path();
    for (var i = 0; i < wave.length; i++) {
      final x = size.width * i / (wave.length - 1);
      final y = middle - wave[i] * amplitude;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    _glow(canvas, path, color, pulse);
  }

  @override
  bool shouldRepaint(covariant WavePainter oldDelegate) =>
      oldDelegate.wave != wave ||
      oldDelegate.color != color ||
      oldDelegate.axisColor != axisColor ||
      oldDelegate.pulse != pulse;
}

void _glow(Canvas canvas, Path path, Color color, double pulse) {
  final glow = 0.7 + 0.3 * pulse;
  for (final (width, alpha) in const [(9.0, 0.08), (5.0, 0.2), (1.8, 0.95)]) {
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round
        ..strokeWidth = width
        ..color = color.withValues(alpha: (alpha * glow).clamp(0.0, 1.0)),
    );
  }
}
