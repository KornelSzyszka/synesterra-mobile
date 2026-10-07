import 'loop_view_state.dart';

/// The loop in plain words, for a screen reader: cycle length, the layers'
/// hits against each other ("3 against 2"), each layer, and the current view.
String describeLoop(LoopViewState state, LoopViewMode mode) {
  final beats = state.cycleBeats == state.cycleBeats.round()
      ? state.cycleBeats.round().toString()
      : state.cycleBeats.toStringAsFixed(2);
  final layerWord = state.layers.length == 1 ? 'layer' : 'layers';
  final ratio = state.layers.length > 1
      ? ', ${state.layers.map((l) => l.hitCount).join(' against ')}'
      : '';
  final parts = [
    'Loop of $beats beats with ${state.layers.length} $layerWord$ratio',
    for (final layer in state.layers)
      'Layer ${layer.number}: ${layer.hitCount} ${layer.hitCount == 1 ? 'hit' : 'hits'}'
          '${layer.muted ? ', muted' : ''}',
    '${mode.name} view',
  ];
  return '${parts.join('. ')}.';
}

/// "Playing" or "Stopped".
String describeLoopPosition({required bool playing}) =>
    playing ? 'Playing' : 'Stopped';
