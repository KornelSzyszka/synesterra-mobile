import 'package:flutter_test/flutter_test.dart';
import 'package:synesterra/data/repositories/impl/in_memory_instrument_library_repository.dart';
import 'package:synesterra/features/editor/instrument_editor_view_model.dart';
import 'package:synesterra/features/editor/test_sound.dart';

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
      ..setDecayMs(300)
      ..setDecayMs(500)
      ..setEq(highDb: 3)
      ..addTag('click')
      ..setName('Other');
    await settle();
    expect(audition.played, isEmpty);
    expect(vm.auditionCount, 0);
  });

  test('audition plays the current draft at the test note, at once', () {
    vm
      ..setDecayMs(300)
      ..audition();
    expect(audition.played.single.decayMs, 300);
    expect(audition.frequencies.single, hasLength(1));
    expect(audition.frequencies.single.single, closeTo(440, 1e-9));
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
      ..setDecayMs(200)
      ..auditionSoon()
      ..setDecayMs(500)
      ..auditionSoon();
    await settle();
    expect(audition.played.single.decayMs, 500);
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

  group('the test sound decides the pitch', () {
    test('a chosen note is what plays', () {
      vm
        ..setTestSound(const TestNote(60))
        ..audition();
      expect(audition.frequencies.last.single, closeTo(261.6256, 1e-3));
    });

    test('a chord plays all its notes together, root first', () {
      vm
        ..setTestSound(const TestChord(60, ChordQuality.major))
        ..audition();
      final notes = audition.frequencies.last;
      expect(notes, hasLength(3));
      expect(notes[0], closeTo(261.6256, 1e-3)); // C4
      expect(notes[1], closeTo(329.6276, 1e-3)); // E4
      expect(notes[2], closeTo(391.9954, 1e-3)); // G4
    });

    test('choosing a test sound plays it after a short pause, once', () async {
      vm
        ..setTestSound(const TestNote(57))
        ..setTestSound(const TestNote(62))
        ..setTestSound(const TestNote(64));
      expect(audition.played, isEmpty);
      await settle();
      expect(audition.played, hasLength(1));
      expect(audition.frequencies.single.single, closeTo(329.6276, 1e-3));
    });

    test('the same instrument is played, whatever the test sound', () {
      vm
        ..setTestSound(const TestChord(48, ChordQuality.minor7))
        ..audition();
      expect(audition.played.last, vm.instrument);
    });
  });
}
