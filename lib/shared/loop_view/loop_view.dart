import 'package:flutter/material.dart';

import '../theme/design_scale.dart';
import '../theme/synesterra_theme.dart';
import '../widgets/design_components.dart';
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
          SegmentedButton<LoopViewMode>(
            showSelectedIcon: false,
            segments: [
              for (final mode in LoopViewMode.values)
                ButtonSegment(value: mode, label: Text(mode.label)),
            ],
            selected: {_mode},
            onSelectionChanged: (selection) => _select(selection.single),
          ),
          const SizedBox(height: Space.md),
          Wrap(
            spacing: Space.sm,
            runSpacing: Space.sm,
            children: [
              for (final layer in state.layers)
                LayerChip(
                  number: layer.number,
                  color:
                      tokens.layerColors[layer.colorIndex %
                          tokens.layerColors.length],
                ),
            ],
          ),
          const SizedBox(height: Space.md),
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
