import 'package:synesterra_core/synesterra_core.dart';

import '../../data/repositories/loop.dart';

/// The click for a tap exercise: a wood click on [TapPreset.clickHits] and a
/// bell on [TapPreset.targetHits], both cycles of [TapPreset.cycleBeats]
/// beats at [TapPreset.bpm].
///
/// A scene needs 2..4 layers, so the target layer is always present; when the
/// preset does not sound its target the layer is muted (it still documents
/// where the user is meant to tap).
SessionDocument tapExerciseDocument(TapPreset preset) {
  final full = simpleLoopDocument(
    title: preset.name,
    bpm: preset.bpm,
    cycleBeats: preset.cycleBeats,
    layers: [
      LoopLayerSpec(
        instrumentId: 'factory-wood',
        pitch: 76,
        hits: preset.clickHits,
      ),
      LoopLayerSpec(
        instrumentId: 'factory-bell',
        pitch: 84,
        hits: preset.targetHits,
      ),
    ],
  );
  if (preset.playTarget) return full;
  return SessionDocument(
    title: full.title,
    transport: full.transport,
    referenceClick: full.referenceClick,
    randomSeed: full.randomSeed,
    scenes: [for (final scene in full.scenes) _muteTarget(scene)],
    defaultSceneId: full.defaultSceneId,
    presentation: full.presentation,
  );
}

Scene _muteTarget(Scene scene) => Scene(
  id: scene.id,
  layers: [
    scene.layers.first,
    for (final layer in scene.layers.skip(1))
      RhythmLayer(
        id: layer.id,
        instrumentId: layer.instrumentId,
        pitch: layer.pitch,
        pattern: layer.pattern,
        phaseSteps: layer.phaseSteps,
        swing: layer.swing,
        mix: LayerMix(
          gain: layer.mix.gain,
          pan: layer.mix.pan,
          muted: true,
          solo: false,
        ),
      ),
  ],
  masterGain: scene.masterGain,
  drone: scene.drone,
);
