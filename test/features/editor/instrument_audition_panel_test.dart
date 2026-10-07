import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synesterra/app/synesterra_app.dart';
import 'package:synesterra/data/repositories/impl/in_memory_instrument_library_repository.dart';
import 'package:synesterra/features/editor/instrument_editor_view_model.dart';
import 'package:synesterra/features/editor/instrument_panel.dart';

import 'audition_fakes.dart';

late RecordingAudition audition;

Future<void> openEditor(WidgetTester tester) async {
  // The technical controls are hidden in v1; these tests still cover them.
  showTechnicalControls = true;
  addTearDown(() => showTechnicalControls = false);
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

    await tester.tap(find.byKey(const Key('instrument-preview-mist')));
    await tester.pumpAndSettle();

    expect(audition.played, hasLength(1));
  });

  testWidgets('letting go of a slider plays once, after a short pause', (
    tester,
  ) async {
    await openEditor(tester);

    await tester.drag(sliderIn('instrument-decay'), const Offset(60, 0));
    await tester.pump();
    expect(audition.played, isEmpty, reason: 'not while the gesture settles');
    await pastDelay(tester);

    expect(audition.played, hasLength(1));
    expect(audition.played.single.decayMs, isNot(120));
  });

  testWidgets('several quick changes make one sound', (tester) async {
    await openEditor(tester);

    await tester.drag(sliderIn('instrument-brightness'), const Offset(40, 0));
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

  group('test sound', () {
    testWidgets('it starts as A4 and says what it plays', (tester) async {
      await openEditor(tester);
      expect(find.text('Plays A4'), findsOneWidget);
      expect(find.byKey(const Key('test-quality-major')), findsNothing);
    });

    testWidgets('choosing a root note plays it, in the same octave', (
      tester,
    ) async {
      await openEditor(tester);
      await tester.tap(find.byKey(const Key('test-root-0'))); // C
      await pastDelay(tester);

      expect(find.text('Plays C4'), findsOneWidget);
      expect(audition.frequencies.single.single, closeTo(261.6256, 1e-3));
    });

    testWidgets('the octave stepper moves the note', (tester) async {
      await openEditor(tester);
      await tester.tap(
        find.descendant(
          of: find.byKey(const Key('test-octave')),
          matching: find.byTooltip('Increase octave'),
        ),
      );
      await pastDelay(tester);

      expect(find.text('Plays A5'), findsOneWidget);
      expect(audition.frequencies.single.single, closeTo(880, 1e-6));
    });

    testWidgets('the octave stays within C1..B7', (tester) async {
      await openEditor(tester);
      final increase = find.descendant(
        of: find.byKey(const Key('test-octave')),
        matching: find.byTooltip('Increase octave'),
      );
      for (var i = 0; i < 6; i++) {
        await tester.tap(increase);
        await tester.pump();
      }
      await pastDelay(tester);
      expect(find.text('Plays A7'), findsOneWidget);
    });

    testWidgets('switching to Chord plays a chord and offers its qualities', (
      tester,
    ) async {
      await openEditor(tester);
      await tester.tap(find.text('Chord'));
      await pastDelay(tester);

      expect(find.text('Plays A4 Major'), findsOneWidget);
      expect(audition.frequencies.single, hasLength(3));
      for (final name in [
        'major',
        'minor',
        'dominant7',
        'major7',
        'minor7',
        'sus4',
        'power',
      ]) {
        expect(find.byKey(Key('test-quality-$name')), findsOneWidget);
      }
    });

    testWidgets('choosing a quality changes the notes that play', (
      tester,
    ) async {
      await openEditor(tester);
      await tester.tap(find.text('Chord'));
      await pastDelay(tester);
      audition.frequencies.clear();

      await tester.tap(find.byKey(const Key('test-quality-dominant7')));
      await pastDelay(tester);

      expect(find.text('Plays A4 Dom 7'), findsOneWidget);
      expect(audition.frequencies.single, hasLength(4));
    });

    testWidgets('going back to Note keeps the root and drops the chord', (
      tester,
    ) async {
      await openEditor(tester);
      await tester.tap(find.byKey(const Key('test-root-0')));
      await tester.tap(find.text('Chord'));
      await pastDelay(tester);
      await tester.tap(find.text('Note'));
      await pastDelay(tester);

      expect(find.text('Plays C4'), findsOneWidget);
      expect(find.byKey(const Key('test-quality-major')), findsNothing);
    });

    testWidgets('the Play button plays the chosen test sound', (tester) async {
      await openEditor(tester);
      await tester.tap(find.text('Chord'));
      await pastDelay(tester);
      audition.frequencies.clear();

      await tester.tap(find.byKey(const Key('instrument-play')));
      await tester.pump();

      expect(audition.frequencies.single, hasLength(3));
    });

    testWidgets('the Figure and Wave views follow the test root', (
      tester,
    ) async {
      await openEditor(tester);
      await tester.tap(find.text('Figure'));
      await tester.pump();
      await tester.tap(find.byKey(const Key('test-root-5')));
      await tester.pump();
      await tester.tap(find.text('Wave'));
      await tester.pump();
      await pastDelay(tester);

      expect(tester.takeException(), isNull);
    });
  });
}
