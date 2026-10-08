import 'package:flutter_test/flutter_test.dart';
import 'package:synesterra/data/repositories/impl/in_memory_arrangement_library_repository.dart';
import 'package:synesterra/data/repositories/impl/in_memory_loop_library_repository.dart';
import 'package:synesterra/data/repositories/loop.dart';
import 'package:synesterra/data/repositories/playback_repository.dart';
import 'package:synesterra/features/arrangement/arrangement_panel_view_model.dart';
import 'package:synesterra/shared/loop_view/arrangement_strip.dart';
import 'package:synesterra_core/synesterra_core.dart';

import 'arrangement_fakes.dart';

void main() {
  late InMemoryLoopLibraryRepository loops;
  late InMemoryArrangementLibraryRepository arrangements;
  late RecordingPlayback playback;

  setUp(() async {
    loops = InMemoryLoopLibraryRepository([userLoop('mine', 'My loop')]);
    arrangements = InMemoryArrangementLibraryRepository();
    playback = RecordingPlayback();
    await loops.load();
    await arrangements.load();
  });

  ArrangementPanelViewModel model([Arrangement? initial]) =>
      ArrangementPanelViewModel(
        loops: loops,
        arrangements: arrangements,
        playback: playback,
        initial: initial,
        newId: () => 'arrangement-new',
      );

  group('editing', () {
    test('a new arrangement starts empty, unnamed draft and not saveable', () {
      final vm = model();
      expect(vm.sections, isEmpty);
      expect(vm.name, 'New arrangement');
      expect(vm.canSave, isFalse);
      expect(vm.saveBlockedReason, 'Add a loop to save.');
      expect(vm.canPlay, isFalse);
      expect(vm.playBlockedReason, 'Add a loop to play.');
    });

    test('add, change repeats, reorder and remove sections', () {
      final vm = model();
      vm.addSection('factory-loop-3-2');
      vm.addSection('mine');
      vm.addSection('factory-loop-5-4');
      expect(vm.sections.map((s) => s.loopId), [
        'factory-loop-3-2',
        'mine',
        'factory-loop-5-4',
      ]);
      expect(vm.sections.every((s) => s.repeats == 2), isTrue);

      vm.setRepeats(1, 32);
      vm.setRepeats(0, 1);
      vm.moveSection(2, 0);
      expect(vm.sections.map((s) => (s.loopId, s.repeats)), [
        ('factory-loop-5-4', 2),
        ('factory-loop-3-2', 1),
        ('mine', 32),
      ]);

      vm.removeSection(1);
      expect(vm.sections.map((s) => s.loopId), ['factory-loop-5-4', 'mine']);
      vm.replaceLoop(1, 'factory-loop-4-3-2');
      expect(
        vm.sections[1],
        ArrangementSection(loopId: 'factory-loop-4-3-2', repeats: 32),
      );
    });

    test('repeats stay in 1..32 and sections in 1..16', () {
      final vm = model();
      vm.addSection('mine');
      expect(() => vm.setRepeats(0, 0), throwsArgumentError);
      expect(() => vm.setRepeats(0, 33), throwsArgumentError);
      for (var i = 1; i < 16; i++) {
        vm.addSection('mine');
      }
      expect(vm.sections, hasLength(16));
      expect(vm.canAddSection, isFalse);
      expect(() => vm.addSection('mine'), throwsStateError);
    });

    test('the loop choices are the factory loops then the user loops', () {
      final ids = model().loopChoices.map((l) => l.id).toList();
      expect(ids, [
        'factory-loop-3-2',
        'factory-loop-5-4',
        'factory-loop-4-3-2',
        'mine',
      ]);
    });

    test('an invalid name blocks saving with a plain reason', () {
      final vm = model()..addSection('mine');
      vm.setName('   ');
      expect(vm.canSave, isFalse);
      expect(vm.saveBlockedReason, 'Give the arrangement a name.');
      vm.setName('Song');
      expect(vm.canSave, isTrue);
      expect(vm.saveBlockedReason, isNull);
    });
  });

  group('missing loops', () {
    test(
      'a missing loop is marked and skipped, keeping original indexes',
      () async {
        final vm = model(
          arrangementOf('a1', 'Song', [
            ('gone', 3),
            ('factory-loop-3-2', 2),
            ('also-gone', 1),
            ('mine', 4),
          ]),
        );
        expect(
          [for (var i = 0; i < 4; i++) vm.isMissing(i)],
          [true, false, true, false],
        );
        expect(vm.stripSections, [
          StripSection(label: 'Missing loop', repeats: 3, missing: true),
          StripSection(label: 'Three against two', repeats: 2),
          StripSection(label: 'Missing loop', repeats: 1, missing: true),
          StripSection(label: 'My loop', repeats: 4),
        ]);
        expect(vm.canPlay, isTrue);

        await vm.play();
        final (sections, repeatAll) = playback.sequences.single;
        expect(sections.map((s) => s.originalIndex), [1, 3]);
        expect(sections.map((s) => s.repeats), [2, 4]);
        expect(
          sections[1].document,
          loops.snapshot.value.items.single.document,
        );
        expect(repeatAll, isFalse);
      },
    );

    test('nothing playable disables Play with a plain reason', () async {
      final vm = model(arrangementOf('a1', 'Song', [('gone', 3), ('gone', 1)]));
      expect(vm.canPlay, isFalse);
      expect(
        vm.playBlockedReason,
        'Nothing to play: the loops of every section are missing. '
        'Pick a loop for a section.',
      );
      await vm.play();
      expect(playback.sequences, isEmpty);
    });

    test('a loop deleted from the library becomes missing', () async {
      final vm = model()..addSection('mine');
      var notified = 0;
      vm.addListener(() => notified++);
      await loops.delete('mine');
      expect(notified, greaterThan(0));
      expect(vm.isMissing(0), isTrue);
      expect(vm.canPlay, isFalse);
    });
  });

  group('playback', () {
    test(
      'play sends repeat all; stop stops; status drives isPlaying',
      () async {
        final vm = model()..addSection('factory-loop-3-2');
        vm.setRepeatAll(true);
        expect(vm.isPlaying, isFalse);
        await vm.play();
        expect(playback.sequences.single.$2, isTrue);
        expect(vm.isPlaying, isTrue);
        await vm.stop();
        expect(playback.stops, 1);
        expect(vm.isPlaying, isFalse);
      },
    );

    test('a finished sequence is no longer playing', () async {
      final vm = model()..addSection('factory-loop-3-2');
      await vm.play();
      playback.finish();
      expect(vm.isPlaying, isFalse);
    });

    test(
      'an edit while playing restarts the sequence with the new sections',
      () async {
        final vm = model()..addSection('factory-loop-3-2');
        await vm.play();
        vm.addSection('mine');
        await pumpEventQueue();
        expect(playback.sequences, hasLength(2));
        expect(playback.sequences.last.$1.map((s) => s.originalIndex), [0, 1]);
        vm.setRepeatAll(true);
        await pumpEventQueue();
        expect(playback.sequences.last.$2, isTrue);
      },
    );

    test('deleting one of several loops while playing drops it from the '
        'running sequence, keeping original indexes', () async {
      await loops.save(userLoop('other', 'Other loop'));
      final vm = model()
        ..addSection('mine')
        ..addSection('factory-loop-3-2')
        ..addSection('other');
      await vm.play();
      expect(playback.sequences.single.$1.map((s) => s.originalIndex), [
        0,
        1,
        2,
      ]);
      await loops.delete('other');
      await pumpEventQueue();
      expect(playback.sequences, hasLength(2));
      expect(playback.sequences.last.$1.map((s) => s.originalIndex), [0, 1]);
      expect(vm.isPlaying, isTrue);
    });

    test('deleting the loop that is playing replays without it', () async {
      final vm = model()
        ..addSection('mine')
        ..addSection('factory-loop-3-2');
      await vm.play();
      // The sequence is on section 0 ('mine').
      expect(playback.position.value.sectionIndex, 0);
      await loops.delete('mine');
      await pumpEventQueue();
      expect(playback.sequences.last.$1.map((s) => s.originalIndex), [1]);
      expect(
        playback.sequences.last.$1.single.document,
        factoryLoops.first.document,
      );
    });

    test('a library change that does not touch the sections keeps playing '
        'without a restart', () async {
      final vm = model()..addSection('factory-loop-3-2');
      await vm.play();
      await loops.save(userLoop('unrelated', 'Unrelated'));
      await pumpEventQueue();
      expect(playback.sequences, hasLength(1));
    });

    test(
      'a loop deleted while another panel plays changes nothing there',
      () async {
        final vm = model()
          ..addSection('mine')
          ..addSection('factory-loop-3-2');
        await vm.play();
        await playback.play(factoryLoops[1].document, owner: Object());
        await loops.delete('mine');
        await pumpEventQueue();
        expect(playback.sequences, hasLength(1));
        expect(playback.stops, 0);
      },
    );

    test('removing the last playable section while playing stops', () async {
      final vm = model()..addSection('factory-loop-3-2');
      await vm.play();
      vm.removeSection(0);
      await pumpEventQueue();
      expect(playback.stops, 1);
      expect(vm.isPlaying, isFalse);
    });

    test('an edit while stopped does not start playback', () async {
      final vm = model()..addSection('factory-loop-3-2');
      vm.setRepeats(0, 5);
      await pumpEventQueue();
      expect(playback.sequences, isEmpty);
    });

    test('a loop played by another panel is not this panel playing', () async {
      final vm = model()..addSection('factory-loop-3-2');
      playback.statusNotifier.value = PlaybackStatus(
        state: PlaybackState.playing,
      );
      expect(vm.isPlaying, isFalse);
    });

    test(
      'playback started by another panel is never stopped from here',
      () async {
        final vm = model()..addSection('factory-loop-3-2');
        await vm.play();
        expect(playback.status.value.owner, same(vm));
        final loopPanel = Object();
        await playback.play(factoryLoops.first.document, owner: loopPanel);
        expect(vm.isPlaying, isFalse);

        // Edits, opening, a deleted loop and dispose leave it alone.
        vm.setRepeats(0, 3);
        vm.addSection('mine');
        await loops.delete('mine');
        vm.open(arrangementOf('a2', 'Other', [('factory-loop-5-4', 1)]));
        vm.dispose();
        await pumpEventQueue();
        expect(playback.stops, 0);
        expect(playback.sequences, hasLength(1));
        expect(playback.status.value.owner, same(loopPanel));
      },
    );

    test('dispose stops a sequence this panel started', () async {
      final vm = model()..addSection('factory-loop-3-2');
      await vm.play();
      vm.dispose();
      expect(playback.stops, 1);
    });

    test('an engine error is reported in plain words', () async {
      final vm = model()..addSection('factory-loop-3-2');
      await vm.play();
      playback.statusNotifier.value = PlaybackStatus(
        stopReason: PlaybackStopReason.error,
        error: 'SoLoudInitFailed',
      );
      expect(vm.isPlaying, isFalse);
      expect(vm.playbackNote, 'Playback stopped because of a problem.');
    });

    test('missing sounds are mentioned while playing', () async {
      final vm = model()..addSection('factory-loop-3-2');
      await vm.play();
      playback.statusNotifier.value = PlaybackStatus(
        state: PlaybackState.playing,
        missingInstrumentIds: {'gone-sound'},
        owner: vm,
      );
      expect(vm.playbackNote, 'Some sounds are missing and play silence.');
    });
  });

  group('save and open', () {
    test('save stores the arrangement and reports it', () async {
      final vm = model()
        ..addSection('mine')
        ..setName('Song');
      expect(vm.hasUnsavedChanges, isTrue);
      final saved = await vm.save();
      expect(saved, arrangementOf('arrangement-new', 'Song', [('mine', 2)]));
      expect(arrangements.snapshot.value.items, [saved]);
      expect(vm.hasUnsavedChanges, isFalse);
    });

    test(
      'opening from the library keeps its id, so saving replaces it',
      () async {
        final original = arrangementOf('a1', 'Song', [('mine', 2)]);
        await arrangements.save(original);
        final vm = model(original);
        expect(vm.hasUnsavedChanges, isFalse);
        vm.setRepeats(0, 3);
        expect(vm.hasUnsavedChanges, isTrue);
        await vm.save();
        expect(arrangements.snapshot.value.items, [
          arrangementOf('a1', 'Song', [('mine', 3)]),
        ]);
      },
    );

    test('open replaces the draft and stops this panel playing', () async {
      final vm = model()..addSection('factory-loop-3-2');
      await vm.play();
      vm.open(arrangementOf('a2', 'Other', [('mine', 7)]));
      await pumpEventQueue();
      expect(vm.id, 'a2');
      expect(vm.name, 'Other');
      expect(vm.sections.single.repeats, 7);
      expect(vm.hasUnsavedChanges, isFalse);
      expect(playback.stops, 1);
    });

    test('start new clears the draft with a fresh id', () {
      final vm = model(arrangementOf('a1', 'Song', [('mine', 2)]));
      vm.startNew();
      expect(vm.id, 'arrangement-new');
      expect(vm.sections, isEmpty);
    });

    test('a failed save keeps the draft and says so', () async {
      final vm = ArrangementPanelViewModel(
        loops: loops,
        arrangements: _FailingArrangements(),
        playback: playback,
      )..addSection('mine');
      expect(await vm.save(), isNull);
      expect(vm.saveError, 'Could not save. Try again.');
      expect(vm.hasUnsavedChanges, isTrue);
    });
  });
}

class _FailingArrangements extends InMemoryArrangementLibraryRepository {
  @override
  Future<void> save(Arrangement arrangement) async =>
      throw Exception('disk full');
}
