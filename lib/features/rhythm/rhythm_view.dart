import 'package:flutter/material.dart';

import '../../shared/theme/design_scale.dart';
import '../../shared/theme/surfaces.dart';
import '../../shared/theme/synesterra_theme.dart';
import '../../shared/widgets/design_components.dart';
import '../../shared/widgets/palette_menu_button.dart';
import '../../shared/widgets/round_components.dart';
import '../../shared/widgets/round_screen.dart';
import 'rhythm_view_model.dart';

/// The rhythm layers and the tempo, in visual language v2: each layer is a
/// soft organic card with a round on/off button, and the tempo has one of its
/// own.
class RhythmView extends StatelessWidget {
  const RhythmView({
    super.key,
    required this.viewModel,
    this.palette = SynesterraPalette.graphite,
    this.onPaletteChanged,
  });

  final RhythmViewModel viewModel;
  final SynesterraPalette palette;
  final ValueChanged<SynesterraPalette>? onPaletteChanged;

  @override
  Widget build(BuildContext context) {
    return RoundScreen(
      title: '◉  synesterra',
      actions: [
        if (onPaletteChanged != null)
          PaletteMenuButton(
            palette: palette,
            onPaletteChanged: onPaletteChanged!,
          ),
      ],
      child: AnimatedBuilder(
        animation: viewModel,
        builder: (context, _) {
          final state = viewModel.state;
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              Space.lg,
              Space.md,
              Space.lg,
              Space.xl,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const RoundSectionHeader('Independent voices'),
                Padding(
                  padding: const EdgeInsets.only(
                    left: Space.md,
                    right: Space.md,
                    bottom: Space.md,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Warstwy rytmu',
                          style: roundText(
                            context,
                            color: groundOf(context).text,
                            size: TypeScale.headline,
                            serif: true,
                          ),
                        ),
                      ),
                      Text(
                        '${state.layers.length}',
                        style: roundText(
                          context,
                          color: groundOf(context).muted,
                          size: TypeScale.bodyLarge,
                        ),
                      ),
                    ],
                  ),
                ),
                for (var index = 0; index < state.layers.length; index++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Space.md),
                    child: _LayerCard(
                      index: index,
                      enabled: state.layers[index].enabled,
                      beats: state.layers[index].beatsPerCycle,
                      onEnabled: (value) => viewModel.setLayerEnabled.execute(
                        RhythmLayerEnabledCommand(index, value),
                      ),
                      onBeats: (value) => viewModel.setLayerBeats.execute(
                        RhythmLayerBeatsCommand(index, value),
                      ),
                    ),
                  ),
                const SizedBox(height: Space.md),
                OrganicCard(
                  seed: 21,
                  padding: const EdgeInsets.fromLTRB(
                    Space.xl,
                    Space.md,
                    Space.lg,
                    Space.md,
                  ),
                  child: Row(
                    children: [
                      const Expanded(child: RoundSectionHeader('Tempo')),
                      NumberStepper(
                        key: const Key('tempo-stepper'),
                        value: state.tempoBpm,
                        min: 20,
                        max: 300,
                        label: 'BPM',
                        color: textOn(context, SurfaceStyle.organic),
                        onChanged: (value) => viewModel.setTempo.execute(value),
                        repeatOnHold: true,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// One layer: a round badge in the layer's colour, its name, a round on/off
/// button, its colour as a small disc and its beats per cycle.
class _LayerCard extends StatelessWidget {
  const _LayerCard({
    required this.index,
    required this.enabled,
    required this.beats,
    required this.onEnabled,
    required this.onBeats,
  });

  final int index;
  final bool enabled;
  final int beats;
  final ValueChanged<bool> onEnabled;
  final ValueChanged<int> onBeats;

  @override
  Widget build(BuildContext context) {
    final tokens = SynesterraTokens.of(context);
    final layerColor = tokens.layerColors[index];
    // The colour is data and stays on a disc; the words stay in the text
    // colours of the surface, so their contrast does not depend on the layer.
    final disc = enabled ? layerColor : tokens.disabledLayerSwatch(layerColor);
    final name = enabled
        ? textOn(context, SurfaceStyle.organic)
        : mutedTextOn(context, SurfaceStyle.organic);
    return OrganicCard(
      seed: 4 + index * 7,
      padding: const EdgeInsets.fromLTRB(
        Space.xl,
        Space.md,
        Space.lg,
        Space.md,
      ),
      child: Column(
        children: [
          Row(
            children: [
              _Badge(number: index + 1, color: disc),
              const SizedBox(width: Space.md),
              Expanded(
                child: Text(
                  'Layer ${index + 1}',
                  style: roundText(
                    context,
                    color: name,
                    size: TypeScale.bodyLarge,
                    weight: enabled ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
              RoundIconButton(
                key: Key('layer-$index-enabled'),
                icon: Icons.graphic_eq_rounded,
                label: 'Layer ${index + 1}',
                selected: enabled,
                onPressed: () => onEnabled(!enabled),
              ),
            ],
          ),
          Row(
            children: [
              Semantics(
                label: 'Layer ${index + 1} colour',
                child: SizedBox.square(
                  dimension: 48,
                  child: Center(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: disc,
                      ),
                      child: const SizedBox.square(dimension: 20),
                    ),
                  ),
                ),
              ),
              const Spacer(),
              NumberStepper(
                key: Key('layer-$index-beats'),
                value: beats,
                min: 1,
                max: 16,
                label: 'beats / cycle',
                color: name,
                onChanged: onBeats,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The layer's number in a round badge ringed in its colour.
class _Badge extends StatelessWidget {
  const _Badge({required this.number, required this.color});

  final int number;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 40,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: color, width: 2),
        ),
        child: Center(
          child: Text(
            number.toString().padLeft(2, '0'),
            style: roundText(
              context,
              color: textOn(context, SurfaceStyle.organic),
              size: TypeScale.caption,
              weight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
