import 'package:flutter/material.dart';

import 'rhythm_view_model.dart';

class RhythmView extends StatelessWidget {
  const RhythmView({super.key, required this.viewModel});

  final RhythmViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Synesterra')),
      body: AnimatedBuilder(
        animation: viewModel,
        builder: (context, _) {
          final state = viewModel.state;
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Rhythm',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 16),
                Text('Tempo: ${state.tempoBpm} BPM'),
                Slider(
                  key: const Key('tempo-slider'),
                  min: 20,
                  max: 300,
                  divisions: 280,
                  value: state.tempoBpm.toDouble(),
                  label: '${state.tempoBpm} BPM',
                  onChanged: (value) => viewModel.setTempo(value.round()),
                ),
                const SizedBox(height: 16),
                for (var index = 0; index < state.layers.length; index++)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SwitchListTile(
                            key: Key('layer-$index-enabled'),
                            contentPadding: EdgeInsets.zero,
                            title: Text('Layer ${index + 1}'),
                            value: state.layers[index].enabled,
                            onChanged: (value) =>
                                viewModel.setLayerEnabled(index, value),
                          ),
                          Text(
                            'Beats per cycle: ${state.layers[index].beatsPerCycle}',
                          ),
                          Slider(
                            key: Key('layer-$index-beats'),
                            min: 1,
                            max: 16,
                            divisions: 15,
                            value: state.layers[index].beatsPerCycle.toDouble(),
                            label: '${state.layers[index].beatsPerCycle}',
                            onChanged: (value) =>
                                viewModel.setLayerBeats(index, value.round()),
                          ),
                        ],
                      ),
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
