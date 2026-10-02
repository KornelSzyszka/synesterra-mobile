import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:synesterra_core/synesterra_core.dart';

import '../theme/synesterra_theme.dart';
import 'mist_spec.dart';

/// A small, static mist of an instrument, for lists and cards. The editor's
/// interactive preview with its pulse is `InstrumentSoundView`.
class InstrumentMist extends StatefulWidget {
  const InstrumentMist({super.key, required this.instrument, this.size = 56});

  final Instrument instrument;
  final double size;

  @override
  State<InstrumentMist> createState() => _InstrumentMistState();
}

class _InstrumentMistState extends State<InstrumentMist> {
  late MistSpec _spec = buildMistSpec(widget.instrument);

  @override
  void didUpdateWidget(covariant InstrumentMist oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.instrument != widget.instrument) {
      _spec = buildMistSpec(widget.instrument);
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = SynesterraTokens.of(context).layerColors[_spec.colorIndex];
    return ExcludeSemantics(
      child: RepaintBoundary(
        child: CustomPaint(
          size: Size.square(widget.size),
          painter: MistPainter(spec: _spec, color: color),
        ),
      ),
    );
  }
}

class MistPainter extends CustomPainter {
  const MistPainter({required this.spec, required this.color, this.pulse = 0});

  final MistSpec spec;
  final Color color;

  /// 0..1; grows and brightens the mist while a pulse plays.
  final double pulse;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = size.center(Offset.zero);
    final radius = size.shortestSide / 2;
    final grow = 1 + 0.08 * pulse;
    final glow = 0.75 + 0.25 * pulse;

    void blob(Offset at, double blobRadius, double opacity) {
      final r = blobRadius * radius * grow;
      if (r <= 0) return;
      final alpha = (opacity * glow * 1.25).clamp(0.0, 1.0);
      final paint = Paint()
        ..shader = RadialGradient(
          colors: [
            color.withValues(alpha: alpha),
            color.withValues(alpha: alpha * 0.5),
            color.withValues(alpha: 0),
          ],
          stops: const [0, 0.45, 1],
        ).createShader(Rect.fromCircle(center: at, radius: r));
      canvas.drawCircle(at, r, paint);
    }

    blob(centre, spec.haloRadius, spec.haloOpacity);
    for (final lobe in spec.lobes) {
      blob(
        centre +
            Offset(math.cos(lobe.angle), math.sin(lobe.angle)) *
                (lobe.distance * radius * 0.62),
        lobe.radius * 1.3,
        lobe.opacity,
      );
    }
    blob(centre, spec.coreRadius * 2.1, spec.coreOpacity);
  }

  @override
  bool shouldRepaint(covariant MistPainter oldDelegate) =>
      oldDelegate.spec != spec ||
      oldDelegate.color != color ||
      oldDelegate.pulse != pulse;
}
