import 'dart:math' as math;

import 'package:flutter/gestures.dart' show kTouchSlop;
import 'package:flutter/material.dart';

import '../theme/ambient_scope.dart';
import '../theme/ground_palette.dart';
import '../theme/round_shapes.dart';
import '../theme/tap_effect.dart';

/// The tap effect of visual language v2: a short polarized split. When
/// [child] is tapped, a cool and a warm copy of its outline slip apart and
/// snap back while the rim catches the light, inside [shape] only.
///
/// Safety: one flash lasts [glitchDuration] (220 ms); the [FlashGate] in
/// scope allows at most [maxFlashesPerSecond] across the screen (a faster
/// retap still reaches the child, it just does not flash); under reduce
/// motion the flash is a plain short fade with no movement. [strength]
/// overrides the scope and `SynesterraTokens.tapEffect`.
///
/// It only watches the pointer; the child keeps its own gestures and
/// semantics. Do not wrap things that are dragged (a drag never flashes, but
/// a pad full of short touches would).
class TapGlitch extends StatefulWidget {
  const TapGlitch({
    super.key,
    required this.child,
    this.shape = RoundShape.circle,
    this.strength,
  });

  final Widget child;
  final RoundShape shape;
  final GlitchStrength? strength;

  @override
  State<TapGlitch> createState() => _TapGlitchState();
}

class _TapGlitchState extends State<TapGlitch>
    with SingleTickerProviderStateMixin {
  late final AnimationController _flash = AnimationController(
    vsync: this,
    duration: glitchDuration,
  );
  int _seed = 0;
  int? _pointer;
  Offset? _down;

  GlitchStrength get _strength =>
      widget.strength ?? AmbientScope.tapStrengthOf(context);

  GlitchMode get _mode => glitchModeFor(
    _strength,
    reduceMotion: MediaQuery.maybeDisableAnimationsOf(context) ?? false,
  );

  @override
  void dispose() {
    _flash.dispose();
    super.dispose();
  }

  void _onDown(PointerDownEvent event) {
    _pointer = event.pointer;
    _down = event.position;
  }

  void _onUp(PointerUpEvent event) {
    final down = _down;
    final isTap =
        event.pointer == _pointer &&
        down != null &&
        (event.position - down).distance < kTouchSlop;
    _pointer = null;
    _down = null;
    if (!isTap || _mode == GlitchMode.none) return;
    if (!AmbientScope.gateOf(context).tryFlashNow()) return;
    _seed++;
    _flash.forward(from: 0);
  }

  void _onCancel(PointerCancelEvent event) {
    _pointer = null;
    _down = null;
  }

  @override
  Widget build(BuildContext context) {
    final mode = _mode;
    return Listener(
      onPointerDown: _onDown,
      onPointerUp: _onUp,
      onPointerCancel: _onCancel,
      child: RepaintBoundary(
        child: CustomPaint(
          foregroundPainter: mode == GlitchMode.none
              ? null
              : TapGlitchPainter(
                  palette: AmbientScope.paletteOf(context),
                  shape: widget.shape,
                  flash: _flash,
                  mode: mode,
                  amount: _strength.amount,
                  seed: _seed,
                ),
          child: widget.child,
        ),
      ),
    );
  }
}

/// Paints one running flash of [TapGlitch]; nothing when idle.
class TapGlitchPainter extends CustomPainter {
  TapGlitchPainter({
    required this.palette,
    required this.shape,
    required this.flash,
    required this.mode,
    required this.amount,
    required this.seed,
  }) : super(repaint: flash);

  final GroundPalette palette;
  final RoundShape shape;
  final Animation<double> flash;
  final GlitchMode mode;
  final double amount;
  final int seed;

  /// The cool and the warm half of the split.
  static const cool = Color(0xff6fe0ff);
  static const warm = Color(0xffff7ab8);

  @override
  void paint(Canvas canvas, Size size) {
    final t = flash.value;
    if (!flash.isAnimating || t <= 0 || t >= 1) return;
    final rect = Offset.zero & size;
    final path = shape.outline(rect);
    switch (mode) {
      case GlitchMode.none:
        return;
      case GlitchMode.fade:
        final alpha = (palette.isDark ? .16 : .22) * amount * (1 - t);
        canvas.drawPath(
          path,
          Paint()..color = palette.accent.withValues(alpha: alpha),
        );
      case GlitchMode.full:
        _paintSplit(canvas, path, t);
    }
  }

  void _paintSplit(Canvas canvas, Path path, double t) {
    final snap = math.pow(1 - t, 2).toDouble();
    final shift = (2 + 5 * amount) * snap;
    // Each tap tilts the split its own way.
    final tilt = seed.isEven ? 1.0 : -1.0;
    final alpha = (palette.isDark ? .3 : .24) * amount * snap;
    final blend = palette.isDark ? BlendMode.screen : BlendMode.multiply;
    for (final (offset, color) in [
      (Offset(shift, -shift * .3 * tilt), cool),
      (Offset(-shift, shift * .3 * tilt), warm),
    ]) {
      final moved = path.shift(offset);
      canvas
        ..drawPath(
          moved,
          Paint()
            ..blendMode = blend
            ..color = color.withValues(alpha: alpha),
        )
        ..drawPath(
          moved,
          Paint()
            ..blendMode = blend
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2
            ..color = color.withValues(alpha: math.min(1, alpha * 2)),
        );
    }
    // Polarization: the rim catches the light and lets it go.
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = palette.light.withValues(
          alpha: .5 * amount * math.sin(math.pi * t),
        ),
    );
  }

  @override
  bool shouldRepaint(TapGlitchPainter old) =>
      old.palette != palette ||
      old.shape != shape ||
      old.flash != flash ||
      old.mode != mode ||
      old.amount != amount ||
      old.seed != seed;
}
