import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:synesterra/data/repositories/impl/in_memory_instrument_library_repository.dart';
import 'package:synesterra/data/repositories/impl/noop_instrument_audition_repository.dart';
import 'package:synesterra/data/repositories/instrument_library_repository.dart';
import 'package:synesterra/features/editor/instrument_editor_view_model.dart';
import 'package:synesterra/features/editor/test_sound.dart';
import 'package:synesterra_core/synesterra_core.dart';

class FailingRepository extends InMemoryInstrumentLibraryRepository {
  @override
  Future<void> save(Instrument instrument) =>
      Future.error(Exception('disk full'));
}

class DelayedRepository extends InMemoryInstrumentLibraryRepository {
  final saveStarted = Completer<void>();
  final allowSave = Completer<void>();

  @override
  Future<void> save(Instrument instrument) async {
    saveStarted.complete();
    await allowSave.future;
    await super.save(instrument);
  }
}

Instrument stored({String id = 'mine-1', String name = 'Mine'}) => Instrument(
  id: id,
  name: name,
  harmonics: InstrumentEditorViewModel.spectrum(4, 0.5),
  attackMs: 2,
  decayMs: 200,
);

void main() {
  late InMemoryInstrumentLibraryRepository repository;
  var counter = 0;
  String newId() => 'new-${++counter}';

  InstrumentEditorViewModel create({
    Instrument? instrument,
    bool existing = false,
    int? firstRollSeed,
  }) => InstrumentEditorViewModel(
    repository: repository,
    audition: NoopInstrumentAuditionRepository(),
    instrument: instrument,
    existing: existing,
    newId: newId,
    firstRollSeed: firstRollSeed,
  );

  setUp(() {
    repository = InMemoryInstrumentLibraryRepository();
    counter = 0;
  });

  group('randomize', () {
    test(
      'a roll sets the seeded traits, keeps id and name, marks it dirty',
      () {
        final vm = create(
          instrument: stored(),
          existing: true,
          firstRollSeed: 5,
        );
        expect(vm.canUndoRandomize, isFalse);
        vm.randomize();
        final traits = randomInstrumentTraits(seed: 5);
        expect(vm.traits, traits);
        expect(
          vm.instrument,
          instrumentForTraits(traits, id: 'mine-1', name: 'Mine'),
        );
        expect(vm.approximated, isFalse);
        expect(vm.dirty, isTrue);
        expect(vm.canUndoRandomize, isTrue);
      },
    );

    test('the next roll takes the next seed, wrapping inside uint32', () {
      final vm = create(firstRollSeed: 0xffffffff);
      vm
        ..randomize()
        ..randomize();
      expect(vm.traits, randomInstrumentTraits(seed: 0));
    });

    test('the roll plays the new sound once', () {
      final vm = create(firstRollSeed: 1);
      final before = vm.auditionCount;
      vm.randomize();
      expect(vm.auditionCount, before + 1);
    });

    test('undo steps back through every roll to the exact original', () {
      final original = stored();
      final vm = create(instrument: original, existing: true, firstRollSeed: 9);
      vm.randomize();
      final first = vm.instrument;
      vm
        ..randomize()
        ..undoRandomize();
      expect(vm.instrument, first);
      expect(vm.canUndoRandomize, isTrue);
      vm.undoRandomize();
      expect(vm.instrument, original);
      expect(vm.dirty, isFalse);
      expect(vm.canUndoRandomize, isFalse);
      vm.undoRandomize(); // nothing left
      expect(vm.instrument, original);
    });

    test('undo keeps the name and tags as they are now', () {
      final vm = create(instrument: stored(), existing: true, firstRollSeed: 2)
        ..randomize()
        ..setName('Renamed');
      vm.addTag('warm');
      vm.undoRandomize();
      expect(vm.instrument.name, 'Renamed');
      expect(vm.tags, ['warm']);
    });

    test('starting from a preset forgets the rolls', () {
      final vm = create(firstRollSeed: 2)..randomize();
      vm.startFrom(factoryInstruments.first);
      expect(vm.canUndoRandomize, isFalse);
    });

    test('rejects a first seed outside uint32', () {
      expect(() => create(firstRollSeed: -1), throwsArgumentError);
    });
  });

  group('starting', () {
    test('a new instrument starts from the neutral shape under a new id', () {
      final vm = create();
      expect(vm.instrument.id, 'new-1');
      expect(vm.name, 'New instrument');
      expect(
        vm.instrument,
        instrumentForTraits(
          InstrumentTraits.neutral(),
          id: 'new-1',
          name: 'New instrument',
        ),
      );
      expect(vm.dirty, isFalse);
      expect(vm.canSave, isTrue, reason: 'a new instrument can be saved as is');
    });

    test('a factory preset is copied under a new id', () {
      final preset = factoryInstruments.first;
      final vm = create(instrument: preset);
      expect(vm.instrument.id, isNot(preset.id));
      expect(vm.name, preset.name);
      expect(vm.canSave, isTrue);
    });

    test('a library instrument keeps its id and has nothing to save yet', () {
      final vm = create(instrument: stored(), existing: true);
      expect(vm.instrument.id, 'mine-1');
      expect(vm.dirty, isFalse);
      expect(vm.canSave, isFalse);
    });
  });

  group('editing', () {
    test('each setter changes the draft and clamps to the valid range', () {
      final vm = create()
        ..setAttackMs(9999)
        ..setDecayMs(1)
        ..setEq(lowDb: -50, midDb: 3.5, highDb: 50);
      expect(vm.instrument.attackMs, Instrument.maxAttackMs);
      expect(vm.instrument.decayMs, Instrument.minDecayMs);
      expect(vm.instrument.eq.lowDb, -InstrumentEq.maxGainDb);
      expect(vm.instrument.eq.midDb, 3.5);
      expect(vm.instrument.eq.highDb, InstrumentEq.maxGainDb);
      expect(vm.dirty, isTrue);
    });

    test('setEq changes only the bands it is given', () {
      final vm = create()
        ..setEq(lowDb: 2)
        ..setEq(highDb: -4);
      expect(vm.instrument.eq, InstrumentEq(lowDb: 2, highDb: -4));
    });

    test('the harmonic count and brightness shape the spectrum', () {
      final vm = create()
        ..setBrightness(1)
        ..setHarmonicCount(5);
      expect(vm.instrument.harmonics, List.filled(5, 1.0));
      vm.setBrightness(0);
      expect(vm.instrument.harmonics[1], closeTo(1 / 8, 1e-9));
      expect(vm.instrument.harmonics.first, 1);
      vm
        ..setHarmonicCount(0)
        ..setHarmonicCount(99);
      expect(vm.harmonicCount, Instrument.maxHarmonics);
    });

    test('brightness is fitted back from an existing spectrum', () {
      for (final brightness in [0.0, 0.3, 0.7, 1.0]) {
        final fitted = InstrumentEditorViewModel.fitBrightness(
          InstrumentEditorViewModel.spectrum(6, brightness),
        );
        expect(fitted, closeTo(brightness, 1e-9));
      }
      expect(InstrumentEditorViewModel.fitBrightness(const [1]), 0.5);
      expect(InstrumentEditorViewModel.fitBrightness(const [1, 0]), 0.5);
      final vm = create(instrument: stored(), existing: true);
      expect(vm.brightness, closeTo(0.5, 1e-9));
    });

    test('listeners are told about every change', () {
      final vm = create();
      var calls = 0;
      vm.addListener(() => calls++);
      vm
        ..setDecayMs(300)
        ..setName('Other');
      expect(calls, 2);
    });
  });

  group('tags', () {
    test('a new instrument starts untagged and tags are part of the draft', () {
      final vm = create();
      expect(vm.tags, isEmpty);
      expect(vm.addTag('Click'), isTrue);
      expect(vm.tags, ['click']);
      expect(vm.instrument.tags, ['click']);
      expect(vm.dirty, isTrue);
    });

    test('a tag is normalized, and bad or repeated tags are refused', () {
      final vm = create();
      expect(vm.addTag('  Big   Bell '), isTrue);
      expect(vm.tags, ['big bell']);
      expect(vm.addTag('BIG BELL'), isFalse, reason: 'already there');
      expect(vm.addTag(''), isFalse);
      expect(vm.addTag('a_b'), isFalse);
      expect(vm.addTag('x' * 25), isFalse);
      expect(vm.tags, ['big bell']);
    });

    test('there is a limit, and removing a tag frees a place', () {
      final vm = create();
      for (final tag in ['a', 'b', 'c', 'd', 'e', 'f']) {
        expect(vm.addTag(tag), isTrue);
      }
      expect(vm.canAddTag, isFalse);
      expect(vm.addTag('g'), isFalse);
      vm.removeTag('c');
      expect(vm.canAddTag, isTrue);
      expect(vm.tags, ['a', 'b', 'd', 'e', 'f']);
      expect(vm.addTag('g'), isTrue);
    });

    test('removing a tag that is not there changes nothing', () {
      final vm = create();
      var calls = 0;
      vm.addListener(() => calls++);
      vm.removeTag('nope');
      expect(calls, 0);
    });

    test('tags are saved with the instrument', () async {
      final vm = create()..addTag('wood');
      await vm.save();
      expect(repository.snapshot.value.instruments.single.tags, ['wood']);
    });

    test('a preset keeps its tags when it is copied', () {
      final vm = create(instrument: factoryInstruments.first);
      expect(vm.tags, factoryInstruments.first.tags);
    });

    test(
      'removing the only difference from the saved tags is not a change',
      () {
        final vm = create(
          instrument: stored().copyWith(tags: ['a']),
          existing: true,
        );
        vm.removeTag('a');
        expect(vm.dirty, isTrue);
        vm.addTag('a');
        expect(vm.dirty, isFalse);
      },
    );
  });

  group('test sound', () {
    test('it starts as the note A4', () {
      final vm = create();
      expect(vm.testSound, TestSound.defaultNote);
      expect(vm.testHz, closeTo(440, 1e-9));
    });

    test('choosing a note or a chord is not a change to the instrument', () {
      final vm = create(instrument: stored(), existing: true);
      vm
        ..setTestSound(const TestNote(60))
        ..setTestSound(const TestChord(48, ChordQuality.minor7));
      expect(vm.dirty, isFalse);
      expect(vm.canSave, isFalse);
      expect(vm.instrument, stored());
    });

    test('choosing the same sound again does nothing', () {
      final vm = create();
      var calls = 0;
      vm.addListener(() => calls++);
      vm.setTestSound(TestSound.defaultNote);
      expect(calls, 0);
    });

    test('a different instrument keeps the chosen test sound', () {
      final vm = create()..setTestSound(const TestNote(48));
      vm.startFrom(factoryInstruments.last);
      expect(vm.testSound, const TestNote(48));
    });

    test('does not accept harmonics that are silent at the selected pitch', () {
      final vm = create(instrument: stored(), existing: true)
        ..setHarmonicCount(8)
        ..setTestSound(const TestNote(TestSound.highestMidi));

      final before = vm.instrument.harmonics;
      vm.setHarmonics({for (var index = 0; index < 7; index++) index: 0, 7: 1});

      expect(vm.instrument.harmonics, before);
    });
    test('keeps the test sound when it would silence the instrument', () {
      final vm = create(instrument: stored(), existing: true)
        ..setHarmonicCount(8)
        ..setHarmonics({for (var index = 0; index < 7; index++) index: 0, 7: 1})
        ..setTestSound(const TestNote(48));

      vm.setTestSound(const TestNote(TestSound.highestMidi));

      expect(vm.testSound, const TestNote(48));
    });
  });

  group('name', () {
    test(
      'a blank or over-long name blocks saving but keeps the last valid one',
      () {
        final vm = create()..setName('Clap');
        expect(vm.instrument.name, 'Clap');
        vm.setName('   ');
        expect(vm.nameValid, isFalse);
        expect(vm.canSave, isFalse);
        expect(vm.instrument.name, 'Clap');
        vm.setName('x' * 41);
        expect(vm.nameValid, isFalse);
        vm.setName('Snare');
        expect(vm.nameValid, isTrue);
        expect(vm.canSave, isTrue);
        expect(vm.instrument.name, 'Snare');
      },
    );

    test('changing only the name counts as a change', () {
      final vm = create(instrument: stored(), existing: true)
        ..setName('Renamed');
      expect(vm.dirty, isTrue);
      vm.setName('Mine');
      expect(vm.dirty, isFalse);
    });
  });

  group('saving', () {
    test('saving stores the instrument and clears the changes', () async {
      final vm = create()
        ..setName('Click')
        ..setDecayMs(80);
      expect(await vm.save(), isTrue);
      expect(repository.snapshot.value.instruments.single, vm.instrument);
      expect(vm.instrument.name, 'Click');
      expect(vm.dirty, isFalse);
      expect(vm.canSave, isFalse);
      expect(vm.saveError, isNull);
    });

    test(
      'saving an edited library instrument replaces it, keeping the id',
      () async {
        await repository.save(stored());
        final vm = create(instrument: stored(), existing: true)
          ..setDecayMs(900);
        expect(await vm.save(), isTrue);
        final all = repository.snapshot.value.instruments;
        expect(all, hasLength(1));
        expect(all.single.id, 'mine-1');
        expect(all.single.decayMs, 900);
      },
    );

    test('saving a preset leaves the preset and adds a copy', () async {
      final preset = factoryInstruments.first;
      final vm = create(instrument: preset);
      await vm.save();
      expect(repository.snapshot.value.instruments.single.id, isNot(preset.id));
      expect(factoryInstruments.first, preset);
    });

    test('does nothing when saving is not allowed', () async {
      final vm = create()..setName('');
      expect(await vm.save(), isFalse);
      expect(repository.snapshot.value.instruments, isEmpty);
    });

    test(
      'an edit during a save remains dirty after that save finishes',
      () async {
        final delayedRepository = DelayedRepository();
        final vm = InstrumentEditorViewModel(
          repository: delayedRepository,
          audition: NoopInstrumentAuditionRepository(),
          newId: newId,
        )..setName('Saved name');

        final saving = vm.save();
        await delayedRepository.saveStarted.future;
        vm.setDecayMs(900);
        delayedRepository.allowSave.complete();

        expect(await saving, isTrue);
        expect(vm.instrument.name, 'Saved name');
        expect(vm.instrument.decayMs, 900);
        expect(vm.dirty, isTrue);
      },
    );

    test(
      'a failed save is reported, nothing is called saved, the draft stays',
      () async {
        final vm = InstrumentEditorViewModel(
          repository: FailingRepository(),
          audition: NoopInstrumentAuditionRepository(),
          newId: newId,
        )..setName('Click');
        expect(await vm.save(), isFalse);
        expect(vm.saveError, isNotNull);
        expect(vm.saving, isFalse);
        expect(vm.canSave, isTrue, reason: 'the user can try again');
        vm.setDecayMs(300);
        expect(vm.saveError, isNull, reason: 'an edit clears the old error');
      },
    );
  });

  test('startFrom replaces the draft with a copy of the preset', () async {
    final vm = create(instrument: stored(), existing: true)..setDecayMs(900);
    vm.startFrom(factoryInstruments.last);
    expect(vm.name, 'Bell');
    expect(vm.instrument.id, isNot('mine-1'));
    expect(vm.dirty, isFalse);
    expect(vm.canSave, isTrue);
    await vm.save();
    expect(repository.snapshot.value.instruments.single.name, 'Bell');
  });

  test('repositories are used through the abstract type', () {
    expect(repository, isA<InstrumentLibraryRepository>());
  });

  group('drawing the spectrum', () {
    test('setHarmonics sets bars at once and selects the last one', () {
      final vm = create()
        ..setHarmonicCount(6)
        ..setHarmonics({1: 0.8, 2: 0.6, 3: 0.4});
      expect(vm.instrument.harmonics[1], 0.8);
      expect(vm.instrument.harmonics[2], 0.6);
      expect(vm.instrument.harmonics[3], 0.4);
      expect(vm.selectedHarmonic, 3);
      expect(vm.dirty, isTrue);
    });

    test('one change notifies once, however many bars it sets', () {
      final vm = create()..setHarmonicCount(8);
      var calls = 0;
      vm.addListener(() => calls++);
      vm.setHarmonics({0: 1, 1: 0.9, 2: 0.8, 3: 0.7, 4: 0.6});
      expect(calls, 1);
    });

    test('amplitudes are clamped and bars outside the range are ignored', () {
      final vm = create()
        ..setHarmonicCount(4)
        ..setHarmonics({0: 3, 1: -2, 9: 0.5, -1: 0.5});
      expect(vm.instrument.harmonics[0], 1);
      expect(vm.instrument.harmonics[1], 0);
      expect(vm.instrument.harmonics, hasLength(4));
    });

    test('the instrument can never become silent', () {
      // From the plain Sine: a single harmonic.
      final vm = create(instrument: factoryInstruments[1]);
      expect(vm.instrument.harmonics, [1]);
      vm.setHarmonic(0, 0);
      expect(vm.instrument.harmonics, [1], reason: 'ignored, still audible');

      vm
        ..setHarmonicCount(3)
        ..setHarmonics({1: 0.5, 2: 0.5})
        ..setHarmonics({0: 0})
        ..setHarmonics({1: 0, 2: 0});
      expect(vm.instrument.harmonics.any((a) => a > 0), isTrue);
    });

    test('selecting is clamped and does not change the instrument', () {
      final vm = create(instrument: stored(), existing: true);
      vm.selectHarmonic(99);
      expect(vm.selectedHarmonic, 3);
      vm.selectHarmonic(-4);
      expect(vm.selectedHarmonic, 0);
      expect(vm.dirty, isFalse);
    });

    test('drawing refits the brightness to the new shape', () {
      final vm = create()
        ..setHarmonicCount(6)
        ..setHarmonics({0: 1, 1: 1, 2: 1, 3: 1, 4: 1, 5: 1});
      expect(vm.brightness, closeTo(1, 1e-9));
      vm.setHarmonics({1: 0.125});
      expect(vm.brightness, closeTo(0, 1e-9));
    });

    test('changing the count keeps the bars that are already drawn', () {
      final vm = create()
        ..setHarmonicCount(4)
        ..setHarmonics({0: 0.9, 1: 0.2, 2: 0.7, 3: 0.4});
      vm.setHarmonicCount(6);
      expect(vm.instrument.harmonics.take(4), [0.9, 0.2, 0.7, 0.4]);
      expect(vm.instrument.harmonics, hasLength(6));
      vm.setHarmonicCount(2);
      expect(vm.instrument.harmonics, [0.9, 0.2]);
    });

    test('new bars continue the brightness curve', () {
      final vm = create()
        ..setBrightness(1)
        ..setHarmonicCount(5);
      expect(vm.instrument.harmonics, List.filled(5, 1.0));
    });

    test(
      'cutting off every bar that had sound still leaves an audible one',
      () {
        final vm = create()
          ..setHarmonicCount(4)
          ..setHarmonics({0: 0.0, 1: 0.5, 2: 0.5, 3: 0.5});
        vm.setHarmonicCount(1);
        expect(vm.instrument.harmonics.any((a) => a > 0), isTrue);
      },
    );

    test('the selection stays valid when the count shrinks', () {
      final vm = create()
        ..setHarmonicCount(8)
        ..selectHarmonic(7);
      vm.setHarmonicCount(3);
      expect(vm.selectedHarmonic, 2);
    });

    test('quick shapes redraw every bar for the current count', () {
      final vm = create()..setHarmonicCount(6);
      vm.applySpectrumShape(SpectrumShape.sine);
      expect(vm.instrument.harmonics, [1, 0, 0, 0, 0, 0]);
      vm.applySpectrumShape(SpectrumShape.saw);
      expect(vm.instrument.harmonics[1], closeTo(1 / 2, 1e-9));
      expect(vm.instrument.harmonics[5], closeTo(1 / 6, 1e-9));
      vm.applySpectrumShape(SpectrumShape.square);
      expect(vm.instrument.harmonics, [
        1,
        0,
        closeTo(1 / 3, 1e-9),
        0,
        closeTo(1 / 5, 1e-9),
        0,
      ]);
      vm.applySpectrumShape(SpectrumShape.soft);
      expect(vm.instrument.harmonics[2], closeTo(1 / 9, 1e-9));
    });

    test('every shape is audible and valid at every count', () {
      for (final shape in SpectrumShape.values) {
        for (var count = 1; count <= Instrument.maxHarmonics; count++) {
          final amplitudes = shape.amplitudes(count);
          expect(amplitudes, hasLength(count));
          expect(amplitudes.any((a) => a > 0), isTrue, reason: '$shape $count');
          expect(amplitudes.every((a) => a >= 0 && a <= 1), isTrue);
        }
      }
    });
  });
}
