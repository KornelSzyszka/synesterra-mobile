import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:synesterra_core/synesterra_core.dart';

import '../theme/synesterra_theme.dart';
import 'mist_spec.dart';

/// The mist of an instrument: soft glowing blobs that follow the recipe.
/// Interactive mists play their pulse (visual only) when tapped.
class InstrumentMist extends StatefulWidget {
  const InstrumentMist({
    super.key,
    required this.instrument,
    this.size = 56,
    this.interactive = false,
    this.onTap,
    this.pulseToken = 0,
  });

  final Instrument instrument;
  final double size;
  final bool interactive;

  /// Called when an interactive mist is tapped. Without it the tap plays the
  /// pulse itself; with it the caller decides what a tap does (for example
  /// play the sound) and pulses the mist by changing [pulseToken].
  final VoidCallback? onTap;

  /// Every change plays the pulse once.
  final int pulseToken;

  @override
  State<InstrumentMist> createState() => _InstrumentMistState();
}

class _InstrumentMistState extends State<InstrumentMist>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this);
  late MistSpec _spec = buildMistSpec(widget.instrument);

  @override
  void didUpdateWidget(covariant InstrumentMist oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.instrument != widget.instrument) {
      _spec = buildMistSpec(widget.instrument);
    }
    if (oldWidget.pulseToken != widget.pulseToken) _pulse();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// The envelope as a 0..1 level: it rises over the attack, then fades over
  /// the decay.
  double _level(double progress) {
    final attack = _spec.attack.inMicroseconds.toDouble();
    final total = attack + _spec.decay.inMicroseconds;
    final elapsed = progress * total;
    return elapsed < attack
        ? elapsed / attack
        : 1 - (elapsed - attack) / (total - attack);
  }

  void _pulse() {
    if (MediaQuery.of(context).disableAnimations) return;
    _controller
      ..duration = _spec.attack + _spec.decay
      ..forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = SynesterraTokens.of(context);
    final color = tokens.layerColors[_spec.pitchClass];
    final mist = RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => CustomPaint(
          size: Size.square(widget.size),
          painter: MistPainter(
            spec: _spec,
            color: color,
            pulse: _controller.isAnimating ? _level(_controller.value) : 0,
          ),
        ),
      ),
    );
    if (!widget.interactive) return ExcludeSemantics(child: mist);
    final onTap = widget.onTap ?? _pulse;
    return Semantics(
      button: true,
      label: widget.onTap == null
          ? 'Mist of ${widget.instrument.name}. Tap to see its pulse.'
          : 'Mist of ${widget.instrument.name}. Tap to hear it.',
      onTap: onTap,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: mist,
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
