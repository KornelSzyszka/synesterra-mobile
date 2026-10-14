import 'package:synesterra_core/synesterra_core.dart';

import '../../data/repositories/loop.dart';
import '../../data/repositories/playback_repository.dart';

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
  return preset.playTarget ? full : _muteLayers(full, {1});
}

/// A copy of [document] with the layers at [indexes] muted (both scenes).
SessionDocument _muteLayers(SessionDocument document, Set<int> indexes) =>
    SessionDocument(
      title: document.title,
      transport: document.transport,
      referenceClick: document.referenceClick,
      randomSeed: document.randomSeed,
      scenes: [for (final scene in document.scenes) _muteIn(scene, indexes)],
      defaultSceneId: document.defaultSceneId,
      presentation: document.presentation,
    );

Scene _muteIn(Scene scene, Set<int> indexes) => Scene(
  id: scene.id,
  layers: [
    for (var i = 0; i < scene.layers.length; i++)
      indexes.contains(i) ? _muted(scene.layers[i]) : scene.layers[i],
  ],
  masterGain: scene.masterGain,
  drone: scene.drone,
);

RhythmLayer _muted(RhythmLayer layer) => RhythmLayer(
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
);

/// Tempo of an ear-training chord: one chord is one two-beat cycle.
const earBpm = 72;

/// One chord (or note) as a one-cycle document. A scene needs 2..4 layers, so
/// a single note gets a muted twin. Pitches are 1..3 distinct values.
SessionDocument earSectionDocument(List<int> pitches) {
  final distinct = pitches.toSet().toList();
  if (distinct.isEmpty || distinct.length > 3) {
    throw ArgumentError.value(pitches, 'pitches', 'needs 1..3 pitches');
  }
  final document = simpleLoopDocument(
    title: 'Ear training',
    bpm: earBpm,
    cycleBeats: 2,
    layers: [
      for (final pitch in distinct)
        LoopLayerSpec(instrumentId: 'factory-sine', pitch: pitch, hits: 1),
      if (distinct.length == 1)
        LoopLayerSpec(
          instrumentId: 'factory-sine',
          pitch: distinct.first,
          hits: 1,
        ),
    ],
  );
  return distinct.length == 1 ? _muteLayers(document, {1}) : document;
}

/// The sections that play [question] in order, one chord per section, each
/// for one cycle; the sequence ends by itself.
List<PlaybackSection> earSections(EarQuestion question) => [
  for (var i = 0; i < question.steps.length; i++)
    PlaybackSection(
      originalIndex: i,
      document: earSectionDocument(question.steps[i]),
      repeats: 1,
    ),
];
