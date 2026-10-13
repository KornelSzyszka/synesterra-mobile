import 'package:flutter/material.dart';

import '../../shared/theme/ambient_scope.dart';
import '../../shared/theme/design_scale.dart';
import '../../shared/theme/ground_palette.dart';
import '../../shared/theme/round_shapes.dart';
import '../../shared/theme/surfaces.dart';
import '../../shared/theme/tap_effect.dart';
import '../../shared/widgets/tap_glitch.dart';
import 'loop_edits.dart' show StepMark;

/// One layer's steps as round, tactile buttons: an empty well (off), a raised
/// disc with a coloured core (on), a disc full of the layer's colour with a
/// soft glow (strong). Every step is a 48 dp button labelled
/// "[layerLabel], hit n: mark".
///
/// Cheap on purpose, for long patterns: the cells are plain painters without
/// their own layers or controllers. One controller per grid runs the tap
/// glitch of the last tapped step, through the [FlashGate] in scope (at most
/// three flashes a second; a plain fade under reduce motion).
class StepGrid extends StatefulWidget {
  const StepGrid({
    super.key,
    required this.layerIndex,
    required this.layerLabel,
    required this.marks,
    required this.color,
    required this.onToggle,
  });

  /// For the keys: `step-<layerIndex>-<step>`.
  final int layerIndex;

  /// How screen readers name the layer, such as "Layer 1".
  final String layerLabel;
  final List<StepMark> marks;
  final Color color;
  final ValueChanged<int> onToggle;

  @override
  State<StepGrid> createState() => _StepGridState();
}

class _StepGridState extends State<StepGrid>
    with SingleTickerProviderStateMixin {
  late final AnimationController _flash = AnimationController(
    vsync: this,
    duration: glitchDuration,
  );
  int? _flashing;
  int _seed = 0;

  @override
  void dispose() {
    _flash.dispose();
    super.dispose();
  }

  GlitchMode get _mode => glitchModeFor(
    AmbientScope.tapStrengthOf(context),
    reduceMotion: MediaQuery.maybeDisableAnimationsOf(context) ?? false,
  );

  void _tap(int step) {
    if (_mode != GlitchMode.none &&
        AmbientScope.gateOf(context).tryFlashNow()) {
      setState(() {
        _flashing = step;
        _seed++;
      });
      _flash.forward(from: 0);
    }
    widget.onToggle(step);
  }

  @override
  Widget build(BuildContext context) {
    final palette = AmbientScope.paletteOf(context);
    final mode = _mode;
    final amount = AmbientScope.tapStrengthOf(context).amount;
    return RepaintBoundary(
      child: Wrap(
        spacing: Space.xs,
        runSpacing: Space.xs,
        children: [
          for (var s = 0; s < widget.marks.length; s++)
            StepCell(
              key: Key('step-${widget.layerIndex}-$s'),
              label: '${widget.layerLabel}, hit ${s + 1}',
              mark: widget.marks[s],
              color: widget.color,
              palette: palette,
              onTap: () => _tap(s),
              glitch: _flashing == s && mode != GlitchMode.none
                  ? (flash: _flash, mode: mode, amount: amount, seed: _seed)
                  : null,
            ),
        ],
      ),
    );
  }
}

/// The running tap glitch of one step.
typedef StepGlitch = ({
  Animation<double> flash,
  GlitchMode mode,
  double amount,
  int seed,
});

/// One step: a 48 dp button with a round disc.
class StepCell extends StatefulWidget {
  const StepCell({
    super.key,
    required this.label,
    required this.mark,
    required this.color,
    required this.palette,
    required this.onTap,
    this.glitch,
  });

  final String label;
  final StepMark mark;
  final Color color;
  final GroundPalette palette;
  final VoidCallback onTap;
  final StepGlitch? glitch;

  @override
  State<StepCell> createState() => _StepCellState();
}

class _StepCellState extends State<StepCell> {
  bool _pressed = false;

  void _set(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: '${widget.label}: ${widget.mark.label}',
    excludeSemantics: true,
    onTap: widget.onTap,
    child: GestureDetector(
      excludeFromSemantics: true,
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _set(true),
      onTapUp: (_) => _set(false),
      onTapCancel: () => _set(false),
      onTap: widget.onTap,
      child: SizedBox.square(
        dimension: 48,
        child: CustomPaint(
          painter: StepPainter(
            surfaces: Surfaces(widget.palette),
            mark: widget.mark,
            color: widget.color,
            pressed: _pressed,
            glitch: widget.glitch,
          ),
        ),
      ),
    ),
  );
}

class StepPainter extends CustomPainter {
  StepPainter({
    required this.surfaces,
    required this.mark,
    required this.color,
    required this.pressed,
    this.glitch,
  }) : super(repaint: glitch?.flash);

  final Surfaces surfaces;
  final StepMark mark;
  final Color color;
  final bool pressed;
  final StepGlitch? glitch;

  /// Radius of the visible disc inside the 48 dp cell.
  static const radius = 15.0;

  @override
  void paint(Canvas canvas, Size size) {
    final palette = surfaces.palette;
    final c = size.center(Offset.zero);
    final disc = Rect.fromCircle(center: c, radius: radius);
    final path = circlePath(disc);
    switch (mark) {
      case StepMark.off:
        // An empty well with a faint ring of the layer's colour.
        surfaces.paint(canvas, path, disc, SurfaceStyle.tray);
        canvas.drawCircle(
          c,
          radius - .75,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2
            ..color = color.withValues(alpha: pressed ? .5 : .28),
        );
      case StepMark.on:
        // A raised disc with a core of the layer's colour.
        surfaces.paint(
          canvas,
          path,
          disc,
          SurfaceStyle.tactile,
          pressed: pressed,
        );
        canvas
          ..drawCircle(
            c,
            radius - .75,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.2
              ..color = color.withValues(alpha: .45),
          )
          ..drawCircle(c, 5.5, Paint()..color = color);
      case StepMark.accent:
        // Full of colour, glazed, with a soft glow of its own.
        canvas.drawCircle(
          c,
          radius + 1,
          Paint()
            ..color = color.withValues(alpha: pressed ? .6 : .42)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
        );
        canvas.drawCircle(
          c,
          radius,
          Paint()
            ..shader = RadialGradient(
              center: pressed ? Alignment.center : const Alignment(-.35, -.4),
              radius: 1,
              colors: [
                Color.lerp(color, palette.light, .28)!,
                color,
                Color.lerp(color, palette.shade, .22)!,
              ],
              stops: const [0, .55, 1],
            ).createShader(disc),
        );
        if (!pressed) {
          canvas.drawOval(
            Rect.fromLTWH(
              disc.left + radius * .5,
              disc.top + radius * .28,
              radius * .62,
              radius * .38,
            ),
            Paint()
              ..color = palette.light.withValues(alpha: .38)
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5),
          );
        }
    }
    final glitch = this.glitch;
    if (glitch != null) {
      canvas
        ..save()
        ..translate(disc.left, disc.top);
      TapGlitchPainter(
        palette: palette,
        shape: RoundShape.circle,
        flash: glitch.flash,
        mode: glitch.mode,
        amount: glitch.amount,
        seed: glitch.seed,
      ).paint(canvas, disc.size);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(StepPainter old) =>
      old.surfaces.palette != surfaces.palette ||
      old.mark != mark ||
      old.color != color ||
      old.pressed != pressed ||
      old.glitch != glitch;
}
