import 'package:flutter_test/flutter_test.dart';
import 'package:synesterra/data/repositories/impl/in_memory_instrument_library_repository.dart';
import 'package:synesterra/data/repositories/impl/noop_instrument_audition_repository.dart';
import 'package:synesterra/data/repositories/instrument_library_repository.dart';
import 'package:synesterra/features/editor/instrument_editor_view_model.dart';
import 'package:synesterra_core/synesterra_core.dart';

class FailingRepository extends InMemoryInstrumentLibraryRepository {
  @override
  Future<void> save(Instrument instrument) =>
      Future.error(Exception('disk full'));
}

Instrument stored({String id = 'mine-1', String name = 'Mine'}) => Instrument(
  id: id,
  name: name,
  fundamentalHz: 440,
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
  }) => InstrumentEditorViewModel(
    repository: repository,
    audition: NoopInstrumentAuditionRepository(),
    instrument: instrument,
    existing: existing,
    newId: newId,
  );

  setUp(() {
    repository = InMemoryInstrumentLibraryRepository();
    counter = 0;
  });

  group('starting', () {
    test('a new instrument starts from the sine preset under a new id', () {
      final vm = create();
      expect(vm.instrument.id, 'new-1');
      expect(vm.name, 'New instrument');
      expect(vm.instrument.harmonics, factoryInstruments[1].harmonics);
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
        ..setPitchHz(5000)
        ..setAttackMs(9999)
        ..setDecayMs(1)
        ..setEq(lowDb: -50, midDb: 3.5, highDb: 50);
      expect(vm.instrument.fundamentalHz, Instrument.maxFundamentalHz);
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
        ..setPitchHz(300)
        ..setName('Other');
      expect(calls, 2);
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
        vm.setPitchHz(300);
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
}
