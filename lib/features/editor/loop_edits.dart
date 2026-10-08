import 'dart:math' as math;

import 'package:synesterra_core/synesterra_core.dart';

// Pure edits of a loop document for the Loop panel (docs/product/
// prototype-v0.md). Each one reads scene A and writes the result to scenes A
// and B together, so B is always a copy of A and a topology edit can never
// make the scenes diverge. Every result is built through the core
// constructors, which validate it; an invalid request throws ArgumentError.

const minLoopLayers = 2;
const maxLoopLayers = 4;

/// Most steps a layer may have in one cycle.
const maxLoopSteps = 16;
const minLoopTempo = 20;
const maxLoopTempo = 300;
const minLoopCycleBeats = 1;
const maxLoopCycleBeats = 16;

/// A4, the pitch of a new layer.
const defaultLayerPitch = 69;

/// The instrument of a new layer.
const defaultLayerInstrumentId = 'factory-wood';

/// Steps per beat allowed by the document's minimum step spacing (1/16 beat).
const _stepsPerBeat = 16;

/// The most steps a layer can have in a cycle of [cycleBeats]: at most
/// [maxLoopSteps], and never closer than 1/16 beat apart. With whole-beat
/// cycles the spacing never cuts the 1..16 range, but the rule is kept here
/// so the panel cannot offer a count the document would reject.
int maxStepsForCycle(int cycleBeats) =>
    math.min(maxLoopSteps, cycleBeats * _stepsPerBeat);

/// What a tap on a step shows and plays.
enum StepMark {
  off('off'),
  on('on'),

  /// Accented; "strong" in the UI.
  accent('strong');

  const StepMark(this.label);
  final String label;
}

StepMark stepMark(PatternStep step) => !step.enabled
    ? StepMark.off
    : (step.accent ? StepMark.accent : StepMark.on);

/// A tap cycles on → strong → off → on.
StepMark nextStepMark(StepMark mark) => switch (mark) {
  StepMark.off => StepMark.on,
  StepMark.on => StepMark.accent,
  StepMark.accent => StepMark.off,
};

PatternStep _stepFor(StepMark mark) => PatternStep(
  enabled: mark != StepMark.off,
  velocity: mark == StepMark.accent ? 1 : 0.8,
  accent: mark == StepMark.accent,
  probability: 1,
);

List<RhythmLayer> _layers(SessionDocument document) =>
    document.scenes.first.layers;

int loopLayerCount(SessionDocument document) => _layers(document).length;

/// Layer [index] of scene A.
RhythmLayer loopLayer(SessionDocument document, int index) =>
    _layers(document)[index];

/// [layers] become scene A, and scene B a copy of it.
SessionDocument _withLayers(
  SessionDocument document,
  List<RhythmLayer> layers, {
  SessionTransport? transport,
  String? title,
}) {
  final a = document.scenes.first;
  Scene scene(String id) =>
      Scene(id: id, layers: layers, masterGain: a.masterGain, drone: a.drone);
  return SessionDocument(
    title: title ?? document.title,
    transport: transport ?? document.transport,
    referenceClick: document.referenceClick,
    randomSeed: document.randomSeed,
    scenes: [scene('A'), scene('B')],
    defaultSceneId: document.defaultSceneId,
    presentation: document.presentation,
  );
}

/// A copy of [layer] with some fields replaced. The panel has no swing
/// control, so when a new pattern would put an enabled step off the layer's
/// swing grid, swing is turned off for that layer instead of failing.
RhythmLayer _copy(
  RhythmLayer layer, {
  String? instrumentId,
  int? pitch,
  Pattern? pattern,
  int? phaseSteps,
  LayerMix? mix,
}) {
  RhythmLayer build(Swing swing) => RhythmLayer(
    id: layer.id,
    instrumentId: instrumentId ?? layer.instrumentId,
    pitch: pitch ?? layer.pitch,
    pattern: pattern ?? layer.pattern,
    phaseSteps: phaseSteps ?? layer.phaseSteps,
    swing: swing,
    mix: mix ?? layer.mix,
  );
  if (layer.swing.grid == 'off' || pattern == null) return build(layer.swing);
  try {
    return build(layer.swing);
  } on ArgumentError {
    return build(Swing(grid: 'off', amount: 0));
  }
}

LayerMix _mix(LayerMix mix, {num? gain, bool? muted}) => LayerMix(
  gain: gain ?? mix.gain,
  pan: mix.pan,
  muted: muted ?? mix.muted,
  solo: mix.solo,
);

SessionDocument _editLayer(
  SessionDocument document,
  int index,
  RhythmLayer Function(RhythmLayer layer) edit,
) {
  final layers = [..._layers(document)];
  RangeError.checkValidIndex(index, layers, 'index');
  layers[index] = edit(layers[index]);
  return _withLayers(document, layers);
}

/// On plays the layer, off silences it (the layer's `mute`).
SessionDocument setLayerOn(SessionDocument document, int index, bool on) =>
    _editLayer(
      document,
      index,
      (layer) => _copy(layer, mix: _mix(layer.mix, muted: !on)),
    );

SessionDocument setLayerInstrument(
  SessionDocument document,
  int index,
  String instrumentId,
) => _editLayer(
  document,
  index,
  (layer) => _copy(layer, instrumentId: instrumentId),
);

/// [pitch] is a MIDI note, C1 (24) to B7 (107).
SessionDocument setLayerPitch(SessionDocument document, int index, int pitch) {
  if (pitch < minLayerPitch || pitch > maxLayerPitch) {
    throw ArgumentError.value(pitch, 'pitch', 'must be C1..B7');
  }
  return _editLayer(document, index, (layer) => _copy(layer, pitch: pitch));
}

/// [volume] is 0..1, the layer's gain.
SessionDocument setLayerVolume(
  SessionDocument document,
  int index,
  double volume,
) => _editLayer(
  document,
  index,
  (layer) => _copy(layer, mix: _mix(layer.mix, gain: volume)),
);

/// Changes how many evenly spaced steps the layer has in the cycle. Steps
/// that stay keep their state; new ones are plain hits.
SessionDocument setLayerSteps(SessionDocument document, int index, int count) {
  final cycle = document.transport.practiceCycleBeats.numerator;
  if (count < 1 || count > maxStepsForCycle(cycle)) {
    throw ArgumentError.value(count, 'count', 'must be 1..max steps');
  }
  return _editLayer(document, index, (layer) {
    final old = layer.pattern.steps;
    final steps = [
      for (var i = 0; i < count; i++)
        i < old.length ? old[i] : _stepFor(StepMark.on),
    ];
    return _copy(
      layer,
      pattern: Pattern(
        durationBeats: layer.pattern.durationBeats,
        steps: steps,
      ),
      phaseSteps: layer.phaseSteps < count ? layer.phaseSteps : 0,
    );
  });
}

/// A tap on step [step] of layer [index]: on → strong → off → on.
SessionDocument toggleStep(SessionDocument document, int index, int step) =>
    _editLayer(document, index, (layer) {
      final steps = [...layer.pattern.steps];
      RangeError.checkValidIndex(step, steps, 'step');
      steps[step] = _stepFor(nextStepMark(stepMark(steps[step])));
      return _copy(
        layer,
        pattern: Pattern(
          durationBeats: layer.pattern.durationBeats,
          steps: steps,
        ),
      );
    });

SessionDocument setLoopTempo(SessionDocument document, int bpm) {
  if (bpm < minLoopTempo || bpm > maxLoopTempo) {
    throw ArgumentError.value(bpm, 'bpm', 'must be 20..300');
  }
  return _withLayers(
    document,
    _layers(document),
    transport: SessionTransport(
      bpm: bpm,
      practiceCycleBeats: document.transport.practiceCycleBeats,
    ),
  );
}

/// Sets the cycle length; every layer keeps spanning exactly one cycle.
SessionDocument setCycleBeats(SessionDocument document, int beats) {
  if (beats < minLoopCycleBeats || beats > maxLoopCycleBeats) {
    throw ArgumentError.value(beats, 'beats', 'must be 1..16');
  }
  final cycle = Rational(beats, 1);
  final limit = maxStepsForCycle(beats);
  return _withLayers(
    document,
    [
      for (final layer in _layers(document))
        _copy(
          layer,
          pattern: Pattern(
            durationBeats: cycle,
            steps: layer.pattern.steps.take(limit).toList(),
          ),
          phaseSteps: layer.phaseSteps < limit ? layer.phaseSteps : 0,
        ),
    ],
    transport: SessionTransport(
      bpm: document.transport.bpm,
      practiceCycleBeats: cycle,
    ),
  );
}

/// Adds a layer at the end: [instrumentId] at A4, one hit per beat of the
/// cycle (the first one strong), switched on.
SessionDocument addLoopLayer(
  SessionDocument document, {
  String instrumentId = defaultLayerInstrumentId,
}) {
  final layers = _layers(document);
  if (layers.length >= maxLoopLayers) {
    throw ArgumentError('A loop has at most $maxLoopLayers layers');
  }
  final ids = {for (final layer in layers) layer.id};
  var n = layers.length + 1;
  while (ids.contains('layer-$n')) {
    n++;
  }
  final cycle = document.transport.practiceCycleBeats;
  final count = math.min(cycle.numerator, maxStepsForCycle(cycle.numerator));
  final layer = RhythmLayer(
    id: 'layer-$n',
    instrumentId: instrumentId,
    pitch: defaultLayerPitch,
    pattern: Pattern(
      durationBeats: cycle,
      steps: [
        for (var i = 0; i < count; i++)
          _stepFor(i == 0 ? StepMark.accent : StepMark.on),
      ],
    ),
    phaseSteps: 0,
    swing: Swing(grid: 'off', amount: 0),
    mix: LayerMix(gain: 0.8, pan: 0, muted: false, solo: false),
  );
  return _withLayers(document, [...layers, layer]);
}

SessionDocument removeLoopLayer(SessionDocument document, int index) {
  final layers = [..._layers(document)];
  if (layers.length <= minLoopLayers) {
    throw ArgumentError('A loop has at least $minLoopLayers layers');
  }
  RangeError.checkValidIndex(index, layers, 'index');
  layers.removeAt(index);
  return _withLayers(document, layers);
}

/// The document with [title] (the loop's name, saved with it).
SessionDocument withTitle(SessionDocument document, String title) =>
    _withLayers(document, _layers(document), title: title);
