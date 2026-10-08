import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:synesterra/data/repositories/impl/in_memory_instrument_library_repository.dart';
import 'package:synesterra/data/repositories/impl/in_memory_loop_library_repository.dart';
import 'package:synesterra/data/repositories/loop.dart';
import 'package:synesterra/data/repositories/playback_repository.dart';
import 'package:synesterra/features/editor/loop_edits.dart';
import 'package:synesterra/features/editor/loop_editor_view_model.dart';
import 'package:synesterra_core/synesterra_core.dart';

import '../../data/playback_fakes.dart';
import 'loop_fakes.dart';

Loop mine(String id, {String name = 'Mine'}) => Loop(
  id: id,
  name: name,
  document: simpleLoopDocument(
    bpm: 120,
    cycleBeats: 4,
    layers: const [
      LoopLayerSpec(instrumentId: 'factory-wood', pitch: 69, hits: 3),
      LoopLayerSpec(instrumentId: 'gone', pitch: 60, hits: 2),
    ],
  ),
);

/// A library whose save waits until the test lets it finish.
class SlowLoops extends InMemoryLoopLibraryRepository {
  final gate = Completer<void>();

  @override
  Future<void> save(Loop loop) async {
    await gate.future;
    await super.save(loop);
  }
}

/// [loop] with scene B different from scene A (valid for the parser).
Loop diverged(Loop loop) {
  final d = loop.document;
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
  return loop.copyWith(
    document: SessionDocument(
      title: d.title,
      transport: d.transport,
      referenceClick: d.referenceClick,
      randomSeed: d.randomSeed,
      scenes: [a, b],
      defaultSceneId: 'B',
      presentation: d.presentation,
    ),
  );
}

void main() {
  late InMemoryLoopLibraryRepository loops;
  late InMemoryInstrumentLibraryRepository instruments;
  late RecordingPlayback playback;

  LoopEditorViewModel create({Loop? loop, bool existing = false}) {
    final vm = LoopEditorViewModel(
      library: loops,
      instruments: instruments,
      playback: playback,
      loop: loop,
      existing: existing,
    );
    addTearDown(vm.dispose);
    return vm;
  }

  setUp(() {
    loops = InMemoryLoopLibraryRepository();
    instruments = InMemoryInstrumentLibraryRepository();
    playback = RecordingPlayback();
  });

  group('starting point', () {
    test('a new loop is an unsaved copy of the first factory loop', () {
      final vm = create();
      expect(vm.loop.id, isNot(startsWith('factory-')));
      expect(vm.name, 'Three against two copy');
      expect(vm.document.scenes, factoryLoops.first.document.scenes);
      expect(vm.dirty, isFalse);
      expect(vm.persisted, isFalse);
      expect(vm.canSave, isTrue);
    });

    test('a factory loop is opened as a copy', () {
      final vm = create(loop: factoryLoops[1]);
      expect(vm.loop.id, isNot(factoryLoops[1].id));
      expect(vm.name, 'Five against four copy');
      expect(vm.persisted, isFalse);
    });

    test('one of my loops is edited in place', () {
      final vm = create(loop: mine('m1'), existing: true);
      expect(vm.loop.id, 'm1');
      expect(vm.persisted, isTrue);
      expect(vm.canSave, isFalse);
    });
  });

  group('editing', () {
    test('edits change the document, mark it changed and keep B = A', () {
      final vm = create();
      vm.toggleStep(0, 1);
      vm.setLayerSteps(1, 5);
      vm.setLayerPitch(0, 72);
      vm.setLayerInstrument(1, 'factory-bell');
      vm.setLayerOn(1, false);
      vm.setLayerVolume(0, 0.5);
      vm.setTempo(140);
      vm.setCycleBeats(6);
      vm.addLayer();
      expect(vm.dirty, isTrue);
      final d = vm.document;
      expect(d.scenes[1].layers, d.scenes[0].layers);
      expect(vm.layerCount, 3);
      expect(loopLayer(d, 1).pattern.steps.length, 5);
      expect(loopLayer(d, 0).pitch, 72);
      expect(loopLayer(d, 1).instrumentId, 'factory-bell');
      expect(loopLayer(d, 1).mix.muted, isTrue);
      expect(d.transport.bpm, 140);
      expect(d.transport.practiceCycleBeats, Rational(6, 1));
      expect(parseSessionDocument(d.serialize()).isSuccess, isTrue);
    });

    test('add and remove stay within 2..4 layers', () {
      final vm = create();
      expect(vm.canRemoveLayer, isFalse);
      vm.removeLayer(0); // ignored
      expect(vm.layerCount, 2);
      vm
        ..addLayer()
        ..addLayer();
      expect(vm.canAddLayer, isFalse);
      vm.addLayer(); // ignored
      expect(vm.layerCount, 4);
      vm.removeLayer(3);
      expect(vm.layerCount, 3);
    });

    test('a missing instrument is reported, a library one resolves', () async {
      final vm = create(loop: mine('m1'), existing: true);
      expect(vm.instrumentFor('factory-wood')?.id, 'factory-wood');
      expect(vm.instrumentFor('gone'), isNull);
      expect(vm.isMissing(1), isTrue);
      final gone = factoryInstruments.first.copyWith(id: 'gone', name: 'Back');
      await instruments.save(gone);
      expect(vm.instrumentFor('gone')?.name, 'Back');
      expect(vm.isMissing(1), isFalse);
      expect(vm.availableInstruments.map((i) => i.id), contains('gone'));
    });
  });

  group('save and open', () {
    test('save writes the loop with its name and makes it persisted', () async {
      final vm = create();
      vm.setName('Groove');
      vm.toggleStep(0, 0);
      expect(await vm.save(), isTrue);
      final saved = loops.snapshot.value.items.single;
      expect(saved.name, 'Groove');
      expect(saved.document.title, 'Groove');
      expect(saved.document.scenes, vm.document.scenes);
      expect(vm.dirty, isFalse);
      expect(vm.persisted, isTrue);
      expect(vm.canSave, isFalse);
    });

    test('an edit made while saving is kept and stays unsaved', () async {
      final slow = SlowLoops();
      loops = slow;
      final vm = create();
      final saving = vm.save();
      vm.toggleStep(0, 1);
      final edited = vm.document;
      slow.gate.complete();
      expect(await saving, isTrue);
      expect(
        loopLayer(vm.document, 0).pattern.steps,
        loopLayer(edited, 0).pattern.steps,
      );
      expect(vm.dirty, isTrue);
      expect(vm.canSave, isTrue);
      expect(
        loopLayer(slow.snapshot.value.items.single.document, 0).pattern.steps,
        isNot(loopLayer(edited, 0).pattern.steps),
      );
    });

    test('a save that finishes after another loop was opened does not touch '
        'the opened loop', () async {
      final slow = SlowLoops();
      loops = slow;
      final vm = create();
      final firstId = vm.loop.id;
      final saving = vm.save();
      vm.open(mine('m5', name: 'Other'), existing: true);
      vm.toggleStep(0, 0);
      slow.gate.complete();
      expect(await saving, isTrue);
      // The first loop is in the library under its own id.
      expect(slow.snapshot.value.items.single.id, firstId);
      // The opened loop keeps its identity, name, edits and unsaved state.
      expect(vm.loop.id, 'm5');
      expect(vm.name, 'Other');
      expect(vm.dirty, isTrue);
      expect(vm.saving, isFalse);
      expect(vm.canSave, isTrue);
      expect(await vm.save(), isTrue);
      expect(slow.snapshot.value.items.map((l) => l.id).toSet(), {
        firstId,
        'm5',
      });
    });

    test('a stored loop whose scene B differs opens with B a copy of A', () {
      final source = diverged(mine('m3'));
      expect(
        source.document.scenes[1].layers,
        isNot(source.document.scenes[0].layers),
      );
      final vm = create(loop: source, existing: true);
      final d = vm.document;
      expect(d.scenes[1].layers, d.scenes[0].layers);
      expect(d.scenes[1].masterGain, d.scenes[0].masterGain);
      expect(loopLayer(d, 0).instrumentId, 'factory-wood');
      expect(vm.dirty, isFalse);
      vm.open(diverged(mine('m4')), existing: false);
      expect(vm.document.scenes[1].layers, vm.document.scenes[0].layers);
    });

    test('an invalid name cannot be saved', () async {
      final vm = create();
      vm.setName('   ');
      expect(vm.nameValid, isFalse);
      expect(vm.canSave, isFalse);
      expect(await vm.save(), isFalse);
      expect(loops.snapshot.value.items, isEmpty);
    });

    test('open replaces the loop being edited', () {
      final vm = create();
      vm.toggleStep(0, 0);
      vm.open(mine('m2', name: 'Other'), existing: true);
      expect(vm.loop.id, 'm2');
      expect(vm.name, 'Other');
      expect(vm.dirty, isFalse);
      vm.open(factoryLoops[2], existing: false);
      expect(vm.name, 'Three layers copy');
      expect(vm.persisted, isFalse);
    });
  });

  group('transport', () {
    test('play sends the document; edits while playing are sent too', () async {
      final vm = create();
      vm.toggleStep(0, 1); // stopped: nothing is sent
      expect(playback.played, isEmpty);
      await vm.play();
      expect(vm.playing, isTrue);
      expect(playback.played.single, vm.document);
      vm.setLayerVolume(0, 0.3);
      vm.setTempo(100);
      vm.toggleStep(1, 0);
      expect(playback.played, hasLength(4));
      expect(playback.played.last, vm.document);
      await vm.stop();
      expect(vm.playing, isFalse);
      vm.toggleStep(1, 0);
      expect(playback.played, hasLength(4));
    });

    test('opening another loop while playing plays the new one', () async {
      final vm = create();
      await vm.play();
      vm.open(factoryLoops[1], existing: false);
      expect(playback.played.last, vm.document);
    });

    test(
      'a sequence started elsewhere is not driven by the loop panel',
      () async {
        final vm = create();
        await vm.play();
        await playback.playSequence([
          PlaybackSection(
            originalIndex: 0,
            document: factoryLoops[0].document,
            repeats: 1,
          ),
        ], repeatAll: false);
        expect(vm.playing, isFalse);
        vm.toggleStep(0, 0);
        expect(playback.played, hasLength(1));
      },
    );

    test(
      'playback taken over by another owner is never stopped here',
      () async {
        final vm = LoopEditorViewModel(
          library: loops,
          instruments: instruments,
          playback: playback,
        );
        await vm.play();
        final other = Object();
        await playback.play(factoryLoops[1].document, owner: other);
        expect(vm.playing, isFalse);
        vm.toggleStep(0, 0);
        vm.appHidden();
        vm.dispose();
        await pumpEventQueue();
        expect(playback.status.value.owner, same(other));
        expect(playback.status.value.state, PlaybackState.playing);
      },
    );

    test('dispose stops the loop it plays', () async {
      final vm = LoopEditorViewModel(
        library: loops,
        instruments: instruments,
        playback: playback,
      );
      await vm.play();
      vm.dispose();
      expect(playback.commands.last, 'stop');
    });

    test('pausing the app stops playback', () async {
      final vm = create();
      await vm.play();
      vm.appHidden();
      await pumpEventQueue();
      expect(playback.commands.last, 'stop');
      expect(vm.playing, isFalse);
    });
  });

  group('with the real playback repository on fakes', () {
    // 120 BPM, 4-beat cycle: one cycle is 2 s. Beat 0 is at 40 ms.
    late Harness h;
    late LoopEditorViewModel vm;

    setUp(() async {
      h = Harness();
      addTearDown(h.repository.dispose);
      vm = LoopEditorViewModel(
        library: loops,
        instruments: instruments,
        playback: h.repository,
        loop: mine('m1'),
        existing: true,
      );
      addTearDown(vm.dispose);
      await vm.play();
      h.runTo(1040000); // half a cycle
    });

    PlaybackPosition now() => h.repository.readPosition();

    test('volume applies without a new generation or a restart', () async {
      final before = now();
      vm.setLayerVolume(0, 0.2);
      await pumpEventQueue();
      h.runTo(1100000);
      expect(now().generation, before.generation);
      expect(now().cyclePosition, greaterThan(before.cyclePosition));
    });

    test('tempo keeps the phase under a new generation', () async {
      final before = now();
      vm.setTempo(60);
      await pumpEventQueue();
      final after = now();
      expect(after.generation, greaterThan(before.generation));
      expect(after.cyclePosition, closeTo(before.cyclePosition, 0.02));
      expect(h.repository.status.value.bpm, 60);
    });

    test('a volume drag (many changes) never restarts and reaches the '
        'next hits', () async {
      final before = now();
      for (var i = 0; i < 20; i++) {
        vm.setLayerVolume(0, 0.8 - i * 0.03);
      }
      await pumpEventQueue();
      h.runTo(2100000);
      expect(now().generation, before.generation);
      expect(now().cycleIndex, 1, reason: 'kept running into cycle 2');
      final layerOneGains = [
        for (final e in h.sink.scheduled)
          if (e.event.sound == 'playback-0' &&
              e.event.at.microseconds > 1300000)
            e.event.gain,
      ];
      expect(layerOneGains, isNotEmpty);
      // 0.23 layer gain instead of 0.8: the new volume is used.
      expect(layerOneGains.every((g) => g < 0.2), isTrue);
    });

    test('holding tempo + (many changes) keeps the phase', () async {
      final before = now();
      for (var bpm = 121; bpm <= 130; bpm++) {
        vm.setTempo(bpm);
      }
      await pumpEventQueue();
      expect(now().cyclePosition, closeTo(before.cyclePosition, 0.02));
      expect(now().cycleIndex, before.cycleIndex);
      expect(h.repository.status.value.bpm, 130);
    });

    test('a structural edit restarts from the cycle start', () async {
      final before = now();
      vm.toggleStep(0, 1);
      await pumpEventQueue();
      final after = now();
      expect(after.generation, greaterThan(before.generation));
      expect(after.cyclePosition, lessThan(0.05));
      expect(after.cycleIndex, 0);
    });
  });
}
