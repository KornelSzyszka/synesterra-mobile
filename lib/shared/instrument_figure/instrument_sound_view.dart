import 'package:flutter/material.dart';
import 'package:synesterra_core/synesterra_core.dart';

import '../instrument_mist/instrument_mist.dart';
import '../instrument_mist/mist_spec.dart';
import '../theme/synesterra_theme.dart';
import 'figure_spec.dart';
import 'sound_painters.dart';
import '../theme/design_scale.dart';

/// The ways to look at the same recipe.
enum SoundView {
  mist('Mist'),
  figure('Figure'),
  wave('Wave');

  const SoundView(this.label);
  final String label;
}

/// A preview of an instrument with a switch between its views. Tapping the
/// preview calls [onTap]; every change of [pulseToken] plays the pulse (the
/// envelope, visually) once, so the picture and the sound start together.
class InstrumentSoundView extends StatefulWidget {
  const InstrumentSoundView({
    super.key,
    required this.instrument,
    required this.testHz,
    this.size = 220,
    this.onTap,
    this.pulseToken = 0,
    this.showViewSwitch = true,
  });

  final Instrument instrument;

  /// The root frequency of the test sound: the Figure and Wave views show
  /// the instrument as it sounds at this pitch.
  final double testHz;
  final double size;
  final VoidCallback? onTap;
  final int pulseToken;

  /// False shows only the mist, without the Mist, Figure and Wave switch.
  final bool showViewSwitch;

  @override
  State<InstrumentSoundView> createState() => _InstrumentSoundViewState();
}

class _InstrumentSoundViewState extends State<InstrumentSoundView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this);
  SoundView _view = SoundView.mist;

  // Cached per recipe, so a repaint during a pulse does not recompute them.
  late MistSpec _mist = buildMistSpec(widget.instrument);
  List<Offset>? _figure;
  List<double>? _wave;

  @override
  void didUpdateWidget(covariant InstrumentSoundView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.instrument != widget.instrument ||
        oldWidget.testHz != widget.testHz) {
      _mist = buildMistSpec(widget.instrument);
      _figure = null;
      _wave = null;
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
    final attack = _mist.attack.inMicroseconds.toDouble();
    final total = attack + _mist.decay.inMicroseconds;
    final elapsed = progress * total;
    return elapsed < attack
        ? elapsed / attack
        : 1 - (elapsed - attack) / (total - attack);
  }

  void _pulse() {
    if (MediaQuery.of(context).disableAnimations) return;
    _controller
      ..duration = _mist.attack + _mist.decay
      ..forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = SynesterraTokens.of(context);
    final color = tokens.layerColors[_mist.colorIndex];
    final onTap = widget.onTap ?? _pulse;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.showViewSwitch) ...[
          SegmentedButton<SoundView>(
            key: const Key('instrument-view-switch'),
            showSelectedIcon: false,
            style: const ButtonStyle(
              minimumSize: WidgetStatePropertyAll(Size(0, 48)),
            ),
            segments: [
              for (final view in SoundView.values)
                ButtonSegment(value: view, label: Text(view.label)),
            ],
            selected: {_view},
            onSelectionChanged: (selection) =>
                setState(() => _view = selection.single),
          ),
          const SizedBox(height: Space.md),
        ],
        Semantics(
          button: true,
          label:
              '${_view.label} view of ${widget.instrument.name}. Tap to hear it.',
          onTap: onTap,
          excludeSemantics: true,
          child: GestureDetector(
            key: Key('instrument-preview-${_view.name}'),
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: RepaintBoundary(
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, _) {
                  final pulse = _controller.isAnimating
                      ? _level(_controller.value)
                      : 0.0;
                  return CustomPaint(
                    size: Size(widget.size, widget.size),
                    painter: switch (_view) {
                      SoundView.mist => MistPainter(
                        spec: _mist,
                        color: color,
                        pulse: pulse,
                      ),
                      SoundView.figure => FigurePainter(
                        curve: _figure ??= buildFigure(
                          widget.instrument,
                          fundamentalHz: widget.testHz,
                        ),
                        color: color,
                        pulse: pulse,
                      ),
                      SoundView.wave => WavePainter(
                        wave: _wave ??= buildPeriodWave(
                          widget.instrument,
                          fundamentalHz: widget.testHz,
                        ),
                        color: color,
                        axisColor: tokens.border,
                        pulse: pulse,
                      ),
                    },
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}
