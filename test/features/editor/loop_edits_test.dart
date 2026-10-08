import 'package:flutter_test/flutter_test.dart';
import 'package:synesterra/data/repositories/loop.dart';
import 'package:synesterra/features/editor/loop_edits.dart';
import 'package:synesterra_core/synesterra_core.dart';

SessionDocument base({List<int> hits = const [3, 2], int cycle = 4}) =>
    simpleLoopDocument(
      title: 'Test',
      bpm: 90,
      cycleBeats: cycle,
      layers: [
        for (final h in hits)
          LoopLayerSpec(instrumentId: 'factory-wood', pitch: 69, hits: h),
      ],
    );

/// The edit is accepted by the real parser and by the prototype's loop rules,
/// and scene B is exactly scene A.
void expectValidLoop(SessionDocument document) {
  final parsed = parseSessionDocument(document.serialize());
  expect(parsed.isSuccess, isTrue, reason: '${parsed.errors}');
  expect(parsed.value, document);
  expect(() => Loop(id: 'l', name: 'n', document: document), returnsNormally);
  final a = document.scenes[0];
  final b = document.scenes[1];
  expect(b.layers, a.layers);
  expect(b.masterGain, a.masterGain);
  expect(b.drone, a.drone);
}

List<StepMark> marks(SessionDocument d, int layer) => [
  for (final step in loopLayer(d, layer).pattern.steps) stepMark(step),
];

void main() {
  group('limits', () {
    test('steps are limited by the minimum step spacing of 1/16 beat', () {
      // 16 steps per beat at most, and never more than 16 in a cycle.
      expect(maxStepsForCycle(1), 16);
      expect(maxStepsForCycle(4), 16);
      expect(maxStepsForCycle(16), 16);
      // A whole-beat cycle always fits 16 steps, so the panel's 1..16 range
      // is never cut; a shorter cycle would be.
      for (var beats = 1; beats <= 16; beats++) {
        final spacing = Rational(beats, 1).value / maxStepsForCycle(beats);
        expect(spacing, greaterThanOrEqualTo(1 / 16));
      }
    });
  });

  group('every edit writes scenes A and B together', () {
    final d = base();

    test('layer on and off', () {
      final off = setLayerOn(d, 1, false);
      expectValidLoop(off);
      expect(loopLayer(off, 1).mix.muted, isTrue);
      expect(loopLayer(setLayerOn(off, 1, true), 1).mix.muted, isFalse);
    });

    test('instrument', () {
      final next = setLayerInstrument(d, 0, 'my-bell');
      expectValidLoop(next);
      expect(loopLayer(next, 0).instrumentId, 'my-bell');
      expect(loopLayer(next, 1).instrumentId, 'factory-wood');
    });

    test('pitch C1..B7', () {
      expectValidLoop(setLayerPitch(d, 0, minLayerPitch));
      expect(loopLayer(setLayerPitch(d, 0, 107), 0).pitch, 107);
      expect(() => setLayerPitch(d, 0, 23), throwsArgumentError);
      expect(() => setLayerPitch(d, 0, 108), throwsArgumentError);
    });

    test('volume', () {
      final next = setLayerVolume(d, 1, 0.25);
      expectValidLoop(next);
      expect(loopLayer(next, 1).mix.gain, 0.25);
      expect(() => setLayerVolume(d, 1, 1.5), throwsArgumentError);
    });

    test('tempo 20..300', () {
      final next = setLoopTempo(d, 140);
      expectValidLoop(next);
      expect(next.transport.bpm, 140);
      expect(() => setLoopTempo(d, 19), throwsArgumentError);
      expect(() => setLoopTempo(d, 301), throwsArgumentError);
    });

    test('cycle length 1..16 moves every layer with it', () {
      final next = setCycleBeats(d, 7);
      expectValidLoop(next);
      expect(next.transport.practiceCycleBeats, Rational(7, 1));
      for (final scene in next.scenes) {
        for (final layer in scene.layers) {
          expect(layer.pattern.durationBeats, Rational(7, 1));
        }
      }
      expect(loopLayer(next, 0).pattern.steps.length, 3);
      expect(() => setCycleBeats(d, 0), throwsArgumentError);
      expect(() => setCycleBeats(d, 17), throwsArgumentError);
    });
  });

  group('steps', () {
    test('a tap moves a step from on to strong to off and back', () {
      var d = base();
      expect(marks(d, 0), [StepMark.accent, StepMark.on, StepMark.on]);
      d = toggleStep(d, 0, 1);
      expect(marks(d, 0)[1], StepMark.accent);
      d = toggleStep(d, 0, 1);
      expect(marks(d, 0)[1], StepMark.off);
      d = toggleStep(d, 0, 1);
      expect(marks(d, 0)[1], StepMark.on);
      expectValidLoop(d);
      expect(nextStepMark(StepMark.accent), StepMark.off);
    });

    test('more steps keep the existing ones and add plain hits', () {
      var d = toggleStep(base(), 0, 1); // on -> strong
      d = setLayerSteps(d, 0, 5);
      expectValidLoop(d);
      expect(marks(d, 0), [
        StepMark.accent,
        StepMark.accent,
        StepMark.on,
        StepMark.on,
        StepMark.on,
      ]);
    });

    test('fewer steps drop the last ones and keep the phase in range', () {
      final layers = [
        for (final layer in base().scenes.first.layers)
          RhythmLayer(
            id: layer.id,
            instrumentId: layer.instrumentId,
            pitch: layer.pitch,
            pattern: layer.pattern,
            phaseSteps: layer.pattern.steps.length - 1,
            swing: layer.swing,
            mix: layer.mix,
          ),
      ];
      final shifted = base().withSceneLayersForTest(layers);
      final next = setLayerSteps(shifted, 0, 1);
      expectValidLoop(next);
      expect(loopLayer(next, 0).pattern.steps.length, 1);
      expect(loopLayer(next, 0).phaseSteps, 0);
    });

    test('step count is 1..16', () {
      expect(() => setLayerSteps(base(), 0, 0), throwsArgumentError);
      expect(() => setLayerSteps(base(), 0, 17), throwsArgumentError);
      expectValidLoop(setLayerSteps(base(cycle: 1), 0, 16));
    });
  });

  group('layers', () {
    test('add a layer up to four, with a fresh id and A4', () {
      var d = addLoopLayer(base());
      expectValidLoop(d);
      expect(loopLayerCount(d), 3);
      final added = loopLayer(d, 2);
      expect(added.id, 'layer-3');
      expect(added.pitch, defaultLayerPitch);
      expect(added.pitch, 69);
      expect(added.pattern.durationBeats, Rational(4, 1));
      expect(added.mix.muted, isFalse);
      d = addLoopLayer(d);
      expect(loopLayerCount(d), 4);
      expect(() => addLoopLayer(d), throwsArgumentError);
    });

    test('a new layer never reuses an id still in use', () {
      final d = addLoopLayer(removeLoopLayer(addLoopLayer(base()), 0));
      expectValidLoop(d);
      final ids = [for (final l in d.scenes.first.layers) l.id];
      expect(ids.toSet().length, ids.length);
    });

    test('remove a layer down to two', () {
      final three = addLoopLayer(base());
      final d = removeLoopLayer(three, 0);
      expectValidLoop(d);
      expect(
        [for (final l in d.scenes.first.layers) l.id],
        ['layer-2', 'layer-3'],
      );
      expect(() => removeLoopLayer(d, 0), throwsArgumentError);
    });
  });

  test('edits leave scene B a copy of A even when B differed', () {
    final d = base();
    final a = d.scenes[0];
    final b = Scene(
      id: 'B',
      layers: [
        for (final layer in a.layers)
          RhythmLayer(
            id: layer.id,
            instrumentId: 'factory-bell',
            pitch: 40,
            pattern: layer.pattern,
            phaseSteps: 0,
            swing: layer.swing,
            mix: layer.mix,
          ),
      ],
      masterGain: 0.3,
      drone: a.drone,
    );
    final diverged = SessionDocument(
      title: d.title,
      transport: d.transport,
      referenceClick: d.referenceClick,
      randomSeed: d.randomSeed,
      scenes: [a, b],
      defaultSceneId: 'A',
      presentation: d.presentation,
    );
    expectValidLoop(setLoopTempo(diverged, 100));
  });

  test('a swing that a new step would break is turned off', () {
    final d = base(hits: [2, 2]);
    final layers = [
      for (final layer in d.scenes.first.layers)
        RhythmLayer(
          id: layer.id,
          instrumentId: layer.instrumentId,
          pitch: layer.pitch,
          pattern: layer.pattern,
          phaseSteps: 0,
          swing: Swing(grid: 'eighth', amount: 0.5),
          mix: layer.mix,
        ),
    ];
    final swung = d.withSceneLayersForTest(layers);
    // 4 beats / 7 steps puts steps off the eighth grid.
    final next = setLayerSteps(swung, 0, 7);
    expectValidLoop(next);
    expect(loopLayer(next, 0).swing.grid, 'off');
    expect(loopLayer(next, 1).swing.grid, 'eighth');
  });

  test('titleFor keeps the document title in step with the name', () {
    expect(withTitle(base(), 'My loop').title, 'My loop');
    expectValidLoop(withTitle(base(), 'My loop'));
  });
}

extension on SessionDocument {
  SessionDocument withSceneLayersForTest(List<RhythmLayer> layers) =>
      SessionDocument(
        title: title,
        transport: transport,
        referenceClick: referenceClick,
        randomSeed: randomSeed,
        scenes: [
          for (final scene in scenes)
            Scene(
              id: scene.id,
              layers: layers,
              masterGain: scene.masterGain,
              drone: scene.drone,
            ),
        ],
        defaultSceneId: defaultSceneId,
        presentation: presentation,
      );
}
