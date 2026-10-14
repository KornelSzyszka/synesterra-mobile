import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../shared/theme/ground_palette.dart';

/// Cents shown on the dial: the bead sits at the edge at +-[dialRange].
const double dialRange = 50;

/// Within this many cents the dial counts as in tune and glows.
const double inTuneCents = 5;

/// The sweep of the dial: 270 degrees, open at the bottom.
const double _sweep = 1.5 * math.pi;

/// Angle of [cents] on the canvas (0 cents points straight up).
double dialAngle(double cents) =>
    -math.pi / 2 + cents.clamp(-dialRange, dialRange) / dialRange * _sweep / 2;

/// The ring of the Tuner: ticks every 10 cents, a gold mark at 0, a bead for
/// the measured pitch and a soft gold glow while it is in tune. [cents] is
/// null when no pitch is heard (the bead rests at the top, dimmed).
class TunerDialPainter extends CustomPainter {
  TunerDialPainter({
    required this.palette,
    required this.cents,
    required this.glow,
  });

  final GroundPalette palette;
  final double? cents;

  /// 0..1 strength of the in-tune glow.
  final double glow;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - 14;
    final rect = Rect.fromCircle(center: center, radius: radius);
    const start = -math.pi / 2 - _sweep / 2;

    if (glow > 0) {
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..color = palette.accent.withValues(alpha: .34 * glow)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 18
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16),
      );
    }

    canvas.drawArc(
      rect,
      start,
      _sweep,
      false,
      Paint()
        ..color = palette.muted.withValues(alpha: .28)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round,
    );

    for (var c = -50; c <= 50; c += 10) {
      final angle = dialAngle(c.toDouble());
      final major = c % 50 == 0;
      final inner = radius - (major ? 16 : 10);
      canvas.drawLine(
        center + Offset.fromDirection(angle, inner),
        center + Offset.fromDirection(angle, radius - 4),
        Paint()
          ..color = (c == 0 ? palette.accent : palette.muted).withValues(
            alpha: c == 0 ? 1 : .6,
          )
          ..strokeWidth = c == 0 ? 3 : 2
          ..strokeCap = StrokeCap.round,
      );
    }

    final heard = cents != null;
    final bead = center + Offset.fromDirection(dialAngle(cents ?? 0), radius);
    canvas.drawCircle(
      bead,
      11,
      Paint()
        ..color = (heard ? palette.accent : palette.muted).withValues(
          alpha: heard ? 1 : .35,
        ),
    );
    if (heard) {
      canvas.drawCircle(
        bead,
        11,
        Paint()
          ..color = palette.light.withValues(alpha: .35)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }
  }

  @override
  bool shouldRepaint(TunerDialPainter old) =>
      old.cents != cents || old.glow != glow || old.palette != palette;
}
