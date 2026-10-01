import 'package:flutter/material.dart';

import '../../shared/theme/synesterra_theme.dart';
import '../../shared/widgets/design_components.dart';
import 'rhythm_view_model.dart';

class RhythmView extends StatelessWidget {
  const RhythmView({
    super.key,
    required this.viewModel,
    this.palette = SynesterraPalette.forest,
    this.onPaletteChanged,
  });

  final RhythmViewModel viewModel;
  final SynesterraPalette palette;
  final ValueChanged<SynesterraPalette>? onPaletteChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = SynesterraTokens.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          '◉  synesterra',
          style: TextStyle(
            color: tokens.text,
            fontFamily: 'serif',
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          if (onPaletteChanged != null)
            PopupMenuButton<SynesterraPalette>(
              tooltip: 'Choose palette',
              icon: const Icon(Icons.palette_outlined),
              initialValue: palette,
              onSelected: onPaletteChanged,
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: SynesterraPalette.forest,
                  child: Text('Forest'),
                ),
                PopupMenuItem(
                  value: SynesterraPalette.autumn,
                  child: Text('Autumn'),
                ),
                PopupMenuItem(
                  value: SynesterraPalette.highContrast,
                  child: Text('High contrast'),
                ),
              ],
            ),
        ],
      ),
      body: AnimatedBuilder(
        animation: viewModel,
        builder: (context, _) {
          final state = viewModel.state;
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DesignPanel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SectionLabel('Independent voices'),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Warstwy rytmu',
                              style: Theme.of(context).textTheme.headlineSmall
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                          ),
                          Text(
                            '${state.layers.length}',
                            style: TextStyle(
                              color: tokens.muted,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      for (var index = 0; index < state.layers.length; index++)
                        _LayerRow(
                          index: index,
                          enabled: state.layers[index].enabled,
                          beats: state.layers[index].beatsPerCycle,
                          onEnabled: (value) =>
                              viewModel.setLayerEnabled(index, value),
                          onBeats: (value) =>
                              viewModel.setLayerBeats(index, value),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                DesignPanel(
                  child: Row(
                    children: [
                      const Expanded(child: SectionLabel('Tempo')),
                      NumberStepper(
                        key: const Key('tempo-stepper'),
                        value: state.tempoBpm,
                        min: 20,
                        max: 300,
                        label: 'BPM',
                        color: tokens.text,
                        onChanged: viewModel.setTempo,
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

class _LayerRow extends StatelessWidget {
  const _LayerRow({
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
    final displayColor = enabled ? layerColor : tokens.muted;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: tokens.border)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              LayerChip(number: index + 1, color: displayColor),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  'Layer ${index + 1}',
                  style: TextStyle(
                    color: displayColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              LayerToggle(
                key: Key('layer-$index-enabled'),
                value: enabled,
                color: layerColor,
                onChanged: onEnabled,
              ),
            ],
          ),
          Row(
            children: [
              Semantics(
                label: 'Layer ${index + 1} colour',
                child: Container(
                  width: 48,
                  height: 48,
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    border: Border.all(color: tokens.border),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: ColoredBox(color: enabled ? layerColor : tokens.muted),
                ),
              ),
              const Spacer(),
              NumberStepper(
                key: Key('layer-$index-beats'),
                value: beats,
                min: 1,
                max: 16,
                label: 'beats / cycle',
                color: displayColor,
                onChanged: enabled ? onBeats : null,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
