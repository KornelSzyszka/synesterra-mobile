import 'package:synesterra_core/synesterra_core.dart';

/// Example loops for demos and tests. Other screens can reuse them.

SessionDocument _loop(
  String title,
  List<RhythmLayer> layers, {
  int cycleBeats = 4,
}) {
  Scene scene(String id) => Scene(
    id: id,
    layers: layers,
    masterGain: 1,
    drone: Drone(
      enabled: false,
      root: 0,
      octave: 1,
      mode: '',
      chord: 'root',
      gain: 0,
      filterHz: 100,
      spread: 0,
    ),
  );
  return SessionDocument(
    title: title,
    transport: SessionTransport(
      bpm: 90,
      practiceCycleBeats: Rational(cycleBeats, 1),
    ),
    referenceClick: ReferenceClick(0),
    randomSeed: 0,
    scenes: [scene('A'), scene('B')],
    defaultSceneId: 'A',
    presentation: Presentation('circle'),
  );
}

RhythmLayer _layer(
  String id,
  List<bool> steps, {
  int cycleBeats = 4,
  int phase = 0,
  bool muted = false,
  String instrumentId = 'factory-wood',
}) => RhythmLayer(
  id: id,
  instrumentId: instrumentId,
  pitch: 69,
  pattern: Pattern(
    durationBeats: Rational(cycleBeats, 1),
    steps: [
      for (final enabled in steps)
        PatternStep(
          enabled: enabled,
          velocity: 1,
          accent: false,
          probability: 1,
        ),
    ],
  ),
  phaseSteps: phase,
  swing: Swing(grid: 'off', amount: 0),
  mix: LayerMix(gain: 1, pan: 0, muted: muted, solo: false),
);

List<bool> _all(int count) => List.filled(count, true);

/// Three against two in one 4-beat cycle: a triangle and a line.
SessionDocument exampleLoop32() => _loop('3 against 2', [
  _layer('layer-1', _all(3)),
  _layer('layer-2', _all(2), instrumentId: 'factory-sine'),
]);

/// Five against four in one 4-beat cycle: a pentagon and a square.
SessionDocument exampleLoop54() => _loop('5 against 4', [
  _layer('layer-1', _all(5)),
  _layer('layer-2', _all(4), instrumentId: 'factory-sine'),
]);

/// A loop with a gap, a phase offset and a muted layer.
SessionDocument exampleLoopMixed() => _loop('Mixed', [
  _layer('layer-1', [true, false, true, true], phase: 1),
  _layer('layer-2', [false, false, true, false], muted: true),
]);
