import 'package:flutter/foundation.dart';
import 'package:synesterra_core/synesterra_core.dart';

/// The ways to look at the same loop. The choice is UI state only: Polygons is
/// never stored in a document, whose `presentation.visualMode` stays `circle`
/// or `timeline`.
enum LoopViewMode {
  circle('Circle'),
  timeline('Timeline'),
  polygons('Polygons');

  const LoopViewMode(this.label);
  final String label;
}

/// One layer as the views draw it.
@immutable
class LoopLayerView {
  LoopLayerView({
    required this.number,
    required this.colorIndex,
    required List<bool> steps,
    this.phaseSteps = 0,
    this.muted = false,
  }) : steps = List.unmodifiable(steps) {
    if (steps.isEmpty) {
      throw ArgumentError.value(
        steps,
        'steps',
        'a layer needs at least a step',
      );
    }
  }

  /// 1-based. With the colour it is the layer's identity: the number is always
  /// drawn, so colour is never the only cue.
  final int number;

  /// Index into the theme's `layerColors`.
  final int colorIndex;

  /// One entry per step of the pattern; true when the step is enabled.
  final List<bool> steps;
  final int phaseSteps;
  final bool muted;

  /// Steps in the cycle (the layer's "beats").
  int get stepCount => steps.length;

  /// Enabled steps.
  int get hitCount => steps.where((enabled) => enabled).length;

  @override
  bool operator ==(Object other) =>
      other is LoopLayerView &&
      number == other.number &&
      colorIndex == other.colorIndex &&
      listEquals(steps, other.steps) &&
      phaseSteps == other.phaseSteps &&
      muted == other.muted;

  @override
  int get hashCode =>
      Object.hash(number, colorIndex, Object.hashAll(steps), phaseSteps, muted);
}

/// What the loop views need to know about a loop, and nothing else.
@immutable
class LoopViewState {
  LoopViewState({required List<LoopLayerView> layers, required this.cycleBeats})
    : layers = List.unmodifiable(layers);

  /// Reads the layers of the document's default scene. In the prototype every
  /// layer's pattern spans the practice cycle, so a step's place in the cycle
  /// is its index over the step count.
  factory LoopViewState.fromDocument(SessionDocument document) {
    final scene = document.scenes.firstWhere(
      (scene) => scene.id == document.defaultSceneId,
    );
    return LoopViewState(
      cycleBeats: document.transport.practiceCycleBeats.value,
      layers: [
        for (var i = 0; i < scene.layers.length; i++)
          LoopLayerView(
            number: i + 1,
            colorIndex: i,
            steps: [
              for (final step in scene.layers[i].pattern.steps) step.enabled,
            ],
            phaseSteps: scene.layers[i].phaseSteps,
            muted: scene.layers[i].mix.muted,
          ),
      ],
    );
  }

  final List<LoopLayerView> layers;

  /// Length of the cycle in quarter-note beats.
  final num cycleBeats;

  @override
  bool operator ==(Object other) =>
      other is LoopViewState &&
      cycleBeats == other.cycleBeats &&
      listEquals(layers, other.layers);

  @override
  int get hashCode => Object.hash(cycleBeats, Object.hashAll(layers));
}
