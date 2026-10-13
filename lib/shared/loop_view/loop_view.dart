import 'package:flutter/material.dart';

import '../theme/design_scale.dart';
import '../theme/synesterra_theme.dart';
import '../widgets/round_components.dart';
import 'loop_painters.dart';
import 'loop_semantics.dart';
import 'loop_view_state.dart';
import 'position_source.dart';
import 'source_semantics.dart';

export 'arrangement_strip.dart';
export 'loop_view_state.dart' show LoopViewMode;

/// A loop drawn as a circle, a timeline or polygons, with a switch between
/// the three. It reads [source] and nothing else for time; the switch is UI
/// state and is not stored in the document.
class LoopView extends StatefulWidget {
  const LoopView({
    super.key,
    required this.state,
    required this.source,
    this.initialMode = LoopViewMode.circle,
    this.showModeSwitch = true,
    this.onModeChanged,
  });

  final LoopViewState state;
  final PositionSource source;
  final LoopViewMode initialMode;

  /// False hides the switch and the layer legend (a fixed picture, as in a
  /// lesson).
  final bool showModeSwitch;
  final ValueChanged<LoopViewMode>? onModeChanged;

  @override
  State<LoopView> createState() => _LoopViewState();
}

class _LoopViewState extends State<LoopView> {
  late LoopViewMode _mode = widget.initialMode;

  void _select(LoopViewMode mode) {
    setState(() => _mode = mode);
    widget.onModeChanged?.call(mode);
  }

  /// Width over height of the drawing for the current view.
  double get _aspect => switch (_mode) {
    LoopViewMode.circle => 1,
    LoopViewMode.timeline => phi,
    LoopViewMode.polygons => widget.state.layers.length == 2 ? 2 : 1,
  };

  @override
  Widget build(BuildContext context) {
    final tokens = SynesterraTokens.of(context);
    final platform = Theme.of(context).platform;
    final labelStyle = TextStyle(
      fontFamily: SynesterraFonts.monospace(platform),
      fontFamilyFallback: SynesterraFonts.monospaceFallback(platform),
      fontSize: TypeScale.caption,
    );
    final state = widget.state;
    final source = widget.source;
    final CustomPainter painter = switch (_mode) {
      LoopViewMode.circle => CirclePainter(
        state: state,
        source: source,
        tokens: tokens,
        labelStyle: labelStyle,
      ),
      LoopViewMode.timeline => TimelinePainter(
        state: state,
        source: source,
        tokens: tokens,
        labelStyle: labelStyle,
      ),
      LoopViewMode.polygons => PolygonsPainter(
        state: state,
        source: source,
        tokens: tokens,
        labelStyle: labelStyle,
      ),
    };
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.showModeSwitch) ...[
          RoundSegmented<LoopViewMode>(
            options: [
              for (final mode in LoopViewMode.values) (mode, mode.label),
            ],
            value: _mode,
            onChanged: _select,
          ),
          const SizedBox(height: Space.md),
          Wrap(
            spacing: Space.lg,
            runSpacing: Space.sm,
            children: [
              for (final layer in state.layers)
                _LegendMark(
                  number: layer.number,
                  color:
                      tokens.layerColors[layer.colorIndex %
                          tokens.layerColors.length],
                  style: labelStyle,
                ),
            ],
          ),
          const SizedBox(height: Space.sm),
        ],
        SourceSemantics(
          source: source,
          label: (position) =>
              '${describeLoop(state, _mode)} '
              '${describeLoopPosition(playing: position.playing)}.',
          child: AspectRatio(
            aspectRatio: _aspect,
            child: RepaintBoundary(
              child: CustomPaint(
                key: const ValueKey('loop-canvas'),
                painter: painter,
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// A layer in the legend: a small light of its colour and its number.
class _LegendMark extends StatelessWidget {
  const _LegendMark({
    required this.number,
    required this.color,
    required this.style,
  });

  final int number;
  final Color color;
  final TextStyle style;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(color: color.withValues(alpha: .5), blurRadius: 6),
          ],
        ),
      ),
      const SizedBox(width: Space.sm),
      Text(
        number.toString().padLeft(2, '0'),
        style: style.copyWith(color: color, fontWeight: FontWeight.w600),
      ),
    ],
  );
}
