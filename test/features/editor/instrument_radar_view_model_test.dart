import 'package:flutter_test/flutter_test.dart';
import 'package:synesterra/data/repositories/impl/in_memory_instrument_library_repository.dart';
import 'package:synesterra/features/editor/instrument_editor_view_model.dart';
import 'package:synesterra_core/synesterra_core.dart';

import 'audition_fakes.dart';

void main() {
  late RecordingAudition audition;
  late InMemoryInstrumentLibraryRepository library;

  InstrumentEditorViewModel create({
    Instrument? instrument,
    bool existing = false,
  }) => InstrumentEditorViewModel(
    repository: library,
    audition: audition,
    instrument: instrument,
    existing: existing,
  );

  TraitPreset preset(String name) =>
      traitPresets.singleWhere((p) => p.name == name);

  setUp(() {
    audition = RecordingAudition();
    library = InMemoryInstrumentLibraryRepository();
  });

  test('a new instrument starts from the plain Sine, which sits exactly on '
      'the radar', () {
    final vm = create();
    addTearDown(vm.dispose);
    final sine = factoryInstruments[1];
    expect(vm.instrument.harmonics, sine.harmonics);
    expect(vm.traits, traitsForInstrument(sine));
    expect(vm.approximated, isFalse);
    expect(vm.activePreset, isNull);
  });

  test('setTrait changes that trait only and maps the recipe, keeping id, '
      'name and tags', () {
    final vm = create();
    addTearDown(vm.dispose);
    vm
      ..setName('Mine')
      ..addTag('click');
    final id = vm.instrument.id;
    final before = vm.traits;

    vm.setTrait(TraitIds.warmth, 0.9);

    expect(vm.traits[TraitIds.warmth], 0.9);
    for (final definition in defaultTraitDefinitions) {
      if (definition.id == TraitIds.warmth) continue;
      expect(vm.traits[definition.id], before[definition.id], reason: '$id');
    }
    expect(
      vm.instrument,
      instrumentForTraits(vm.traits, id: id, name: 'Mine', tags: ['click']),
    );
    expect(vm.dirty, isTrue);
    expect(vm.activePreset, isNull);
  });

  test('setTrait clamps to 0..1', () {
    final vm = create();
    addTearDown(vm.dispose);
    vm.setTrait(TraitIds.air, 4);
    expect(vm.traits[TraitIds.air], 1);
    vm.setTrait(TraitIds.air, -2);
    expect(vm.traits[TraitIds.air], 0);
  });

  test('setTrait notifies listeners but never plays', () {
    final vm = create();
    addTearDown(vm.dispose);
    var calls = 0;
    vm.addListener(() => calls++);
    vm.setTrait(TraitIds.brightness, 0.8);
    expect(calls, 1);
    expect(audition.played, isEmpty);
    expect(vm.auditionCount, 0);

    vm.setTrait(TraitIds.brightness, 0.8);
    expect(calls, 1, reason: 'the same value is not a change');
  });

  test('releaseTraits plays the current recipe once, at once', () {
    final vm = create();
    addTearDown(vm.dispose);
    vm
      ..setTrait(TraitIds.length, 0.1)
      ..setTrait(TraitIds.length, 0.7);
    expect(audition.played, isEmpty);

    vm.releaseTraits();

    expect(audition.played, hasLength(1));
    expect(audition.played.single, vm.instrument);
    expect(vm.auditionCount, 1);
  });

  test('every preset sets its traits and plays once', () {
    final vm = create();
    addTearDown(vm.dispose);
    for (final (i, p) in traitPresets.indexed) {
      vm.applyPreset(p);
      expect(vm.traits, p.traits, reason: p.name);
      expect(vm.activePreset, p);
      expect(
        vm.instrument,
        instrumentForTraits(
          p.traits,
          id: vm.instrument.id,
          name: vm.instrument.name,
        ),
      );
      expect(audition.played, hasLength(i + 1));
    }
  });

  test('a preset keeps the name and tags', () {
    final vm = create();
    addTearDown(vm.dispose);
    vm
      ..setName('Soft one')
      ..addTag('pad')
      ..applyPreset(preset('airy pad'));
    expect(vm.instrument.name, 'Soft one');
    expect(vm.instrument.tags, ['pad']);
  });

  group('opening a saved instrument', () {
    final bell = factoryInstruments[2].copyWith(id: 'saved-1', name: 'Bell');

    test('shows its approximate traits and changes nothing', () {
      final vm = create(instrument: bell, existing: true);
      addTearDown(vm.dispose);
      expect(vm.traits, traitsForInstrument(bell));
      expect(vm.instrument, bell);
      expect(vm.dirty, isFalse);
      expect(vm.approximated, isTrue, reason: 'the Bell is not on the radar');
    });

    test('an instrument made on the radar opens exactly, without the note', () {
      final made = instrumentForTraits(
        preset('guitar').traits,
        id: 'saved-2',
        name: 'Pluck',
      );
      final vm = create(instrument: made, existing: true);
      addTearDown(vm.dispose);
      expect(vm.approximated, isFalse);
      expect(vm.activePreset?.name, 'guitar');
    });

    test('the first move replaces the recipe and clears the note; the '
        'library keeps the old one until Save', () async {
      await library.save(bell);
      final vm = create(instrument: bell, existing: true);
      addTearDown(vm.dispose);

      vm.setTrait(TraitIds.softness, 0.9);
      expect(vm.approximated, isFalse);
      expect(vm.instrument.id, 'saved-1');
      expect(vm.instrument.name, 'Bell');
      expect(vm.instrument.harmonics, isNot(bell.harmonics));
      expect(library.snapshot.value.instruments.single, bell);

      expect(await vm.save(), isTrue);
      final stored = library.snapshot.value.instruments.single;
      expect(
        stored,
        instrumentForTraits(
          vm.traits,
          id: 'saved-1',
          name: 'Bell',
          tags: bell.tags,
        ),
      );
    });
  });

  test('startFrom reads the traits of the copied instrument', () {
    final vm = create();
    addTearDown(vm.dispose);
    vm
      ..setTrait(TraitIds.air, 0.9)
      ..startFrom(factoryInstruments.first);
    expect(vm.traits, traitsForInstrument(factoryInstruments.first));
    expect(vm.approximated, isTrue);
  });

  test('a technical edit moves the shape to the new recipe', () {
    final vm = create();
    addTearDown(vm.dispose);
    vm.setEnvelope(400, 4000);
    expect(vm.traits, traitsForInstrument(vm.instrument));
  });

  test('an invalid name stays in the field and the radar keeps the last '
      'valid one', () {
    final vm = create();
    addTearDown(vm.dispose);
    vm
      ..setName('Good')
      ..setName('')
      ..setTrait(TraitIds.fullness, 0.4);
    expect(vm.instrument.name, 'Good');
    expect(vm.name, '');
    expect(vm.canSave, isFalse);
  });
}
