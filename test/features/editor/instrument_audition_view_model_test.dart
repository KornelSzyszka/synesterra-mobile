import 'package:flutter_test/flutter_test.dart';
import 'package:synesterra/data/repositories/impl/in_memory_instrument_library_repository.dart';
import 'package:synesterra/features/editor/instrument_editor_view_model.dart';

import 'audition_fakes.dart';

Future<void> settle() => Future<void>.delayed(
  InstrumentEditorViewModel.auditionDelay + const Duration(milliseconds: 60),
);

void main() {
  late RecordingAudition audition;
  late InstrumentEditorViewModel vm;

  setUp(() {
    audition = RecordingAudition();
    vm = InstrumentEditorViewModel(
      repository: InMemoryInstrumentLibraryRepository(),
      audition: audition,
    );
  });

  tearDown(() => vm.dispose());

  test('nothing plays when the editor opens or a control changes', () async {
    vm
      ..setPitchHz(300)
      ..setDecayMs(500)
      ..setEq(highDb: 3)
      ..setName('Other');
    await settle();
    expect(audition.played, isEmpty);
    expect(vm.auditionCount, 0);
  });

  test('audition plays the current draft at once and counts the request', () {
    vm
      ..setPitchHz(300)
      ..audition();
    expect(audition.played.single.fundamentalHz, closeTo(300, 1e-9));
    expect(vm.auditionCount, 1);
  });

  test('audition tells listeners so the mist can pulse', () {
    var calls = 0;
    vm.addListener(() => calls++);
    vm.audition();
    expect(calls, 1);
  });

  test(
    'auditionSoon waits, then plays once however often it is called',
    () async {
      vm
        ..auditionSoon()
        ..auditionSoon()
        ..auditionSoon();
      expect(audition.played, isEmpty);
      await settle();
      expect(audition.played, hasLength(1));
      expect(vm.auditionCount, 1);
    },
  );

  test('the sound reflects the last change before the pause', () async {
    vm
      ..setPitchHz(200)
      ..auditionSoon()
      ..setPitchHz(500)
      ..auditionSoon();
    await settle();
    expect(audition.played.single.fundamentalHz, closeTo(500, 1e-9));
  });

  test('an immediate audition cancels a pending delayed one', () async {
    vm
      ..auditionSoon()
      ..audition();
    await settle();
    expect(audition.played, hasLength(1));
  });

  test('disposing cancels a pending audition', () async {
    final other = InstrumentEditorViewModel(
      repository: InMemoryInstrumentLibraryRepository(),
      audition: audition,
    )..auditionSoon();
    other.dispose();
    await settle();
    expect(audition.played, isEmpty);
  });

  test('availability comes from the repository', () {
    expect(vm.soundAvailable.value, isTrue);
    audition.isAvailable = false;
    expect(vm.soundAvailable.value, isFalse);
  });
}
