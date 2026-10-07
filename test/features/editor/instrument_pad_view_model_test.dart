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

  setUp(() {
    audition = RecordingAudition();
    library = InMemoryInstrumentLibraryRepository();
  });

  test('a new editor has no pad point and says nothing about a new sound', () {
    final vm = create();
    addTearDown(vm.dispose);
    expect(vm.padPoint, isNull);
    expect(vm.startsNewSound, isFalse);
  });

  test('setPadPoint replaces the recipe with instrumentForPad, keeping id, '
      'name and tags', () {
    final vm = create();
    addTearDown(vm.dispose);
    vm
      ..setName('Mine')
      ..addTag('click');
    final id = vm.instrument.id;

    vm.setPadPoint(PadPoint(0.3, 0.9));

    final expected = instrumentForPad(
      PadPoint(0.3, 0.9),
      id: id,
      name: 'Mine',
      tags: const ['click'],
    );
    expect(vm.instrument, expected);
    expect(vm.padPoint, PadPoint(0.3, 0.9));
    expect(vm.dirty, isTrue);
  });

  test('setPadPoint notifies listeners but never plays', () {
    final vm = create();
    addTearDown(vm.dispose);
    var calls = 0;
    vm.addListener(() => calls++);
    vm.setPadPoint(PadPoint(0.5, 0.5));
    expect(calls, 1);
    expect(audition.played, isEmpty);
    expect(vm.auditionCount, 0);
  });

  test('releasePad plays the current recipe once, at once', () {
    final vm = create();
    addTearDown(vm.dispose);
    vm
      ..setPadPoint(PadPoint(0.1, 0.1))
      ..setPadPoint(PadPoint(0.9, 0.9));
    expect(audition.played, isEmpty);

    vm.releasePad();

    expect(audition.played, hasLength(1));
    expect(audition.played.single, vm.instrument);
    expect(vm.auditionCount, 1);
  });

  test('an existing instrument has no pad point and starts a new sound on '
      'touch', () {
    final saved = factoryInstruments[2].copyWith(id: 'saved-1');
    final vm = create(instrument: saved, existing: true);
    addTearDown(vm.dispose);
    expect(vm.padPoint, isNull);
    expect(vm.startsNewSound, isTrue);
    expect(vm.instrument, saved, reason: 'opening changes nothing');
    expect(vm.dirty, isFalse);

    vm.setPadPoint(PadPoint(0.5, 0.5));

    expect(vm.startsNewSound, isFalse);
    expect(vm.instrument.id, 'saved-1');
    expect(vm.instrument.harmonics, isNot(saved.harmonics));
    expect(vm.dirty, isTrue);
  });

  test('the library keeps the old recipe until Save', () async {
    final saved = factoryInstruments[2].copyWith(id: 'saved-1');
    await library.save(saved);
    final vm = create(instrument: saved, existing: true);
    addTearDown(vm.dispose);

    vm.setPadPoint(PadPoint(0.9, 0.1));
    expect(library.snapshot.value.instruments.single, saved);

    expect(await vm.save(), isTrue);
    expect(library.snapshot.value.instruments.single, vm.instrument);
    expect(library.snapshot.value.instruments.single, isNot(saved));
  });

  test('startFrom forgets the pad point', () {
    final vm = create();
    addTearDown(vm.dispose);
    vm
      ..setPadPoint(PadPoint(0.2, 0.2))
      ..startFrom(factoryInstruments.first);
    expect(vm.padPoint, isNull);
  });

  test('an invalid name stays in the field and the pad keeps the last valid '
      'one', () {
    final vm = create();
    addTearDown(vm.dispose);
    vm
      ..setName('Good')
      ..setName('')
      ..setPadPoint(PadPoint(0.4, 0.4));
    expect(vm.instrument.name, 'Good');
    expect(vm.name, '');
    expect(vm.canSave, isFalse);
  });
}
