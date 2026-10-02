import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synesterra/app/synesterra_app.dart';
import 'package:synesterra/data/repositories/impl/in_memory_instrument_library_repository.dart';
import 'package:synesterra/features/editor/instrument_editor_view_model.dart';

import 'audition_fakes.dart';

late RecordingAudition audition;

Future<void> openEditor(WidgetTester tester) async {
  tester.view
    ..devicePixelRatio = 1
    ..physicalSize = const Size(800, 3200);
  addTearDown(tester.view.reset);
  audition = RecordingAudition();
  await tester.pumpWidget(
    SynesterraApp(
      instrumentLibrary: InMemoryInstrumentLibraryRepository(),
      instrumentAudition: audition,
    ),
  );
  await tester.tap(find.byKey(const Key('home-editor')));
  await tester.pumpAndSettle();
}

Future<void> pastDelay(WidgetTester tester) => tester.pump(
  InstrumentEditorViewModel.auditionDelay + const Duration(milliseconds: 50),
);

Finder sliderIn(String key) =>
    find.descendant(of: find.byKey(Key(key)), matching: find.byType(Slider));

void main() {
  testWidgets('opening the editor makes no sound', (tester) async {
    await openEditor(tester);
    await pastDelay(tester);
    expect(audition.played, isEmpty);
  });

  testWidgets('the Play button plays the instrument and pulses the mist', (
    tester,
  ) async {
    await openEditor(tester);

    await tester.tap(find.byKey(const Key('instrument-play')));
    await tester.pump();

    expect(audition.played, hasLength(1));
    expect(audition.played.single.name, 'New instrument');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('the Play button is at least 48 dp tall', (tester) async {
    await openEditor(tester);
    expect(
      tester.getSize(find.byKey(const Key('instrument-play'))).height,
      greaterThanOrEqualTo(48),
    );
  });

  testWidgets('tapping the mist plays the sound', (tester) async {
    await openEditor(tester);

    await tester.tap(find.byKey(const Key('instrument-mist')));
    await tester.pumpAndSettle();

    expect(audition.played, hasLength(1));
  });

  testWidgets('letting go of a slider plays once, after a short pause', (
    tester,
  ) async {
    await openEditor(tester);

    await tester.drag(sliderIn('instrument-pitch'), const Offset(60, 0));
    await tester.pump();
    expect(audition.played, isEmpty, reason: 'not while the gesture settles');
    await pastDelay(tester);

    expect(audition.played, hasLength(1));
    expect(audition.played.single.fundamentalHz, isNot(660));
  });

  testWidgets('several quick changes make one sound', (tester) async {
    await openEditor(tester);

    await tester.drag(sliderIn('instrument-pitch'), const Offset(40, 0));
    await tester.drag(sliderIn('instrument-decay'), const Offset(40, 0));
    await tester.drag(sliderIn('instrument-eq-high'), const Offset(40, 0));
    await pastDelay(tester);

    expect(audition.played, hasLength(1));
  });

  testWidgets('every audible control plays after it is released', (
    tester,
  ) async {
    await openEditor(tester);
    for (final key in const [
      'instrument-brightness',
      'instrument-attack',
      'instrument-decay',
      'instrument-eq-low',
      'instrument-eq-mid',
      'instrument-eq-high',
    ]) {
      audition.played.clear();
      await tester.drag(sliderIn(key), const Offset(30, 0));
      await pastDelay(tester);
      expect(audition.played, hasLength(1), reason: key);
    }
  });

  testWidgets('the harmonic stepper plays after a change', (tester) async {
    await openEditor(tester);

    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('instrument-harmonics')),
        matching: find.byTooltip('Increase harmonics'),
      ),
    );
    await pastDelay(tester);

    expect(audition.played.single.harmonics, hasLength(2));
  });

  testWidgets('choosing a preset plays it', (tester) async {
    await openEditor(tester);

    await tester.tap(find.byKey(const Key('start-from-factory-bell')));
    await tester.pumpAndSettle();

    expect(audition.played.single.name, 'Bell');
  });

  testWidgets('typing a name makes no sound', (tester) async {
    await openEditor(tester);

    await tester.enterText(find.byKey(const Key('instrument-name')), 'Quiet');
    await pastDelay(tester);

    expect(audition.played, isEmpty);
  });

  testWidgets('the note says when sound is not available and recovers', (
    tester,
  ) async {
    await openEditor(tester);
    expect(find.textContaining('to hear it'), findsOneWidget);

    audition.isAvailable = false;
    await tester.pump();
    expect(find.textContaining('Sound is not available'), findsOneWidget);
    expect(find.byKey(const Key('instrument-play')), findsOneWidget);

    audition.isAvailable = true;
    await tester.pump();
    expect(find.textContaining('to hear it'), findsOneWidget);
  });
}
