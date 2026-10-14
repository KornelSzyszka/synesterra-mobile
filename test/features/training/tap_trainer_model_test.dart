import 'package:flutter_test/flutter_test.dart';
import 'package:synesterra/features/training/tap_trainer_model.dart';
import 'package:synesterra_core/synesterra_core.dart';

import 'training_fakes.dart';

void main() {
  // Steady pulse: 80 bpm, 4 beats: 3000 ms cycle, hits every 750 ms.
  final preset = tapPresets.first;
  final cycle = preset.cycleMs;

  late ScriptedPlayback playback;
  late TapTrainerModel model;

  setUp(() {
    playback = ScriptedPlayback();
    model = TapTrainerModel(playback: playback);
  });
  tearDown(() => model.dispose());

  void tapAt(double ms) {
    playback.at(ms, cycleMs: cycle);
    model.tap();
  }

  test('start plays the click; an unsounded target is a muted layer', () async {
    await model.start();
    expect(model.phase, TapPhase.countIn);
    final sounded = playback.documents.single.scenes.first.layers;
    expect(sounded.map((l) => l.mix.muted), [false, false]);
    await model.stop();

    model.selectPreset(tapPresets.firstWhere((p) => p.id == 'three-two'));
    await model.start();
    final layers = playback.documents.last.scenes.first.layers;
    expect(layers.map((l) => l.mix.muted), [false, true]);
    expect(layers.map((l) => l.pattern.steps.length), [2, 3]);
  });

  test('count-in taps are not scored, scoring starts at cycle 1', () async {
    await model.start();
    tapAt(1000);
    expect(model.phase, TapPhase.countIn);
    expect(model.lastResult, isNull);
    tapAt(cycle + 20);
    expect(model.phase, TapPhase.scoring);
    expect(model.lastResult!.errorMs, closeTo(20, 1e-6));
  });

  test(
    'a tap just before the scoring boundary is dropped, not scored',
    () async {
      await model.start();
      tapAt(cycle - 50);
      expect(model.phase, TapPhase.countIn);
      expect(model.lastResult, isNull);
      for (var c = 1; c <= 4; c++) {
        for (final t in preset.targetTimesMs) {
          tapAt(c * cycle + t);
        }
      }
      playback.at(5 * cycle + 300, cycleMs: cycle);
      expect(model.score!.results, hasLength(16));
      expect(model.score!.extraTaps, 0);
      expect(model.score!.meanAbsoluteErrorMs, 0);
    },
  );

  test('a tap exactly on the boundary scores and starts scoring', () async {
    await model.start();
    tapAt(cycle);
    expect(model.phase, TapPhase.scoring);
    expect(model.lastResult!.errorMs, closeTo(0, 1e-6));
  });

  test('a full exercise ends by itself and stops the sound', () async {
    await model.start();
    for (var c = 1; c <= 4; c++) {
      for (final t in preset.targetTimesMs) {
        tapAt(c * cycle + t + 10);
      }
    }
    // Past the end of the last cycle plus the late-tap margin.
    playback.at(5 * cycle + 300, cycleMs: cycle);
    expect(model.phase, TapPhase.done);
    expect(model.score!.matched, 16);
    expect(model.score!.meanErrorMs, closeTo(10, 1e-6));
    expect(playback.stops, 1);
    model.tap();
    expect(model.score!.results, hasLength(16), reason: 'taps after the end');
  });

  test('the latency offset shifts every tap and is clamped', () async {
    model.setOffset(40);
    await model.start();
    tapAt(cycle + 40);
    expect(model.lastResult!.errorMs, closeTo(0, 1e-6));
    model.setOffset(1000);
    expect(model.offsetMs.value, tapOffsetLimitMs);
  });

  test('a start that fails reports the sound as unavailable', () async {
    playback.failStart = true;
    await model.start();
    expect(model.phase, TapPhase.unavailable);
    expect(model.running, isFalse);
  });

  test(
    'choices are locked while running; stop and dispose stop sound',
    () async {
      await model.start();
      model.selectPreset(tapPresets.last);
      expect(model.preset, preset);
      await model.stop();
      expect(model.phase, TapPhase.idle);
      expect(playback.stops, 1);
      await model.start();
      model.dispose();
      expect(playback.stops, 2);
      model = TapTrainerModel(playback: playback);
    },
  );
}
