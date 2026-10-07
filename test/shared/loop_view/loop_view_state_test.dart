import 'package:flutter_test/flutter_test.dart';
import 'package:synesterra/shared/loop_view/loop_examples.dart';
import 'package:synesterra/shared/loop_view/loop_semantics.dart';
import 'package:synesterra/shared/loop_view/loop_view_state.dart';

void main() {
  test('3:2 example has a layer of 3 steps next to a layer of 2', () {
    final state = LoopViewState.fromDocument(exampleLoop32());
    expect(state.cycleBeats, 4);
    expect(state.layers.map((l) => l.stepCount), [3, 2]);
    expect(state.layers.map((l) => l.number), [1, 2]);
    expect(state.layers.map((l) => l.colorIndex), [0, 1]);
    expect(state.layers.first.steps, [true, true, true]);
  });

  test('5:4 example has 5 and 4 steps', () {
    final state = LoopViewState.fromDocument(exampleLoop54());
    expect(state.layers.map((l) => l.stepCount), [5, 4]);
  });

  test('disabled steps, phase and mute come through', () {
    final state = LoopViewState.fromDocument(exampleLoopMixed());
    final layer = state.layers.first;
    expect(layer.steps, [true, false, true, true]);
    expect(layer.hitCount, 3);
    expect(layer.phaseSteps, 1);
    expect(state.layers.last.muted, isTrue);
  });

  test('has value equality', () {
    expect(
      LoopViewState.fromDocument(exampleLoop32()),
      LoopViewState.fromDocument(exampleLoop32()),
    );
    expect(
      LoopViewState.fromDocument(exampleLoop32()),
      isNot(LoopViewState.fromDocument(exampleLoop54())),
    );
  });

  test('describeLoop says the loop in plain words', () {
    final text = describeLoop(
      LoopViewState.fromDocument(exampleLoop32()),
      LoopViewMode.circle,
    );
    expect(text, contains('3 against 2'));
    expect(text, contains('4 beats'));
    expect(text, contains('Layer 1: 3 hits'));
    expect(text, contains('Layer 2: 2 hits'));
    expect(text, contains('circle'));
  });

  test('describeLoop mentions mute, singular hit and the view', () {
    final text = describeLoop(
      LoopViewState.fromDocument(exampleLoopMixed()),
      LoopViewMode.polygons,
    );
    expect(text, contains('muted'));
    expect(text, contains('polygons'));
    expect(text, contains('Layer 2: 1 hit,'));
    expect(describeLoopPosition(playing: true), 'Playing');
    expect(describeLoopPosition(playing: false), 'Stopped');
  });

  test('a layer without steps is rejected', () {
    expect(
      () => LoopLayerView(number: 1, colorIndex: 0, steps: const []),
      throwsArgumentError,
    );
  });

  test('layer fields outside their documented range are rejected', () {
    LoopLayerView layer({int number = 1, int color = 0, int phase = 0}) =>
        LoopLayerView(
          number: number,
          colorIndex: color,
          steps: const [true, true],
          phaseSteps: phase,
        );
    expect(() => layer(number: 0), throwsArgumentError);
    expect(() => layer(color: -1), throwsArgumentError);
    expect(() => layer(phase: -1), throwsArgumentError);
    expect(() => layer(phase: 2), throwsArgumentError);
    expect(layer(phase: 1).phaseSteps, 1);
  });

  test('a state needs layers and a positive finite cycle', () {
    final one = LoopLayerView(number: 1, colorIndex: 0, steps: const [true]);
    expect(
      () => LoopViewState(layers: const [], cycleBeats: 4),
      throwsArgumentError,
    );
    for (final bad in [0, -1, double.nan, double.infinity]) {
      expect(
        () => LoopViewState(layers: [one], cycleBeats: bad),
        throwsArgumentError,
        reason: '$bad',
      );
    }
  });
}
