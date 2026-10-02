import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synesterra/app/synesterra_app.dart';
import 'package:synesterra/data/repositories/impl/in_memory_instrument_library_repository.dart';
import 'package:synesterra/data/repositories/impl/noop_instrument_audition_repository.dart';
import 'package:synesterra_core/synesterra_core.dart';

late InMemoryInstrumentLibraryRepository repository;

Future<void> openEditor(WidgetTester tester) async {
  // The panel is a lazy list; a tall screen builds every control.
  tester.view
    ..devicePixelRatio = 1
    ..physicalSize = const Size(800, 3200);
  addTearDown(tester.view.reset);
  repository = InMemoryInstrumentLibraryRepository();
  await tester.pumpWidget(
    SynesterraApp(
      instrumentLibrary: repository,
      instrumentAudition: NoopInstrumentAuditionRepository(),
    ),
  );
  await tester.tap(find.byKey(const Key('home-editor')));
  await tester.pumpAndSettle();
}

Slider sliderOf(WidgetTester tester, String key) => tester.widget<Slider>(
  find.descendant(of: find.byKey(Key(key)), matching: find.byType(Slider)),
);

FilledButton saveButton(WidgetTester tester) => tester.widget<FilledButton>(
  find.descendant(
    of: find.byKey(const Key('instrument-save')),
    matching: find.byType(FilledButton),
  ),
);

void main() {
  testWidgets('the panel offers every control with a visible value', (
    tester,
  ) async {
    await openEditor(tester);

    for (final key in const [
      'instrument-name',
      'instrument-preview',
      'instrument-pitch',
      'instrument-harmonics',
      'instrument-brightness',
      'instrument-attack',
      'instrument-decay',
      'instrument-eq-low',
      'instrument-eq-mid',
      'instrument-eq-high',
      'instrument-save',
    ]) {
      expect(find.byKey(Key(key)), findsOneWidget, reason: key);
    }
    expect(find.text('660 Hz · E5'), findsOneWidget);
    expect(find.text('2 ms'), findsOneWidget);
    expect(find.text('120 ms'), findsOneWidget);
    expect(find.text('+0.0 dB'), findsNWidgets(3));
    expect(find.textContaining('to hear it'), findsOneWidget);
  });

  testWidgets('moving a slider updates its value and the draft', (
    tester,
  ) async {
    await openEditor(tester);

    sliderOf(tester, 'instrument-pitch').onChanged!(0.5);
    sliderOf(tester, 'instrument-eq-high').onChanged!(1);
    sliderOf(tester, 'instrument-decay').onChanged!(1);
    await tester.pump();

    expect(find.text('660 Hz · E5'), findsNothing);
    expect(find.text('+12.0 dB'), findsOneWidget);
    expect(find.text('5000 ms'), findsOneWidget);
    expect(find.text('Unsaved changes'), findsOneWidget);
  });

  testWidgets('the harmonic stepper changes the count', (tester) async {
    await openEditor(tester);

    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('instrument-harmonics')),
        matching: find.byTooltip('Increase harmonics'),
      ),
    );
    await tester.pump();

    expect(
      find.descendant(
        of: find.byKey(const Key('instrument-harmonics')),
        matching: find.text('2'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('tapping the mist plays its pulse without errors', (
    tester,
  ) async {
    await openEditor(tester);

    await tester.tap(find.byKey(const Key('instrument-preview-mist')));
    await tester.pump(const Duration(milliseconds: 30));
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('a start-from chip loads the preset into the form', (
    tester,
  ) async {
    await openEditor(tester);

    await tester.tap(find.byKey(const Key('start-from-factory-bell')));
    await tester.pump();

    expect(
      tester
          .widget<TextField>(find.byKey(const Key('instrument-name')))
          .controller!
          .text,
      'Bell',
    );
    expect(find.text('1046 Hz · C6'), findsOneWidget);
  });

  testWidgets('a blank name disables Save and shows why', (tester) async {
    await openEditor(tester);
    expect(saveButton(tester).onPressed, isNotNull);

    await tester.enterText(find.byKey(const Key('instrument-name')), '');
    await tester.pump();

    expect(saveButton(tester).onPressed, isNull);
    expect(find.text('Give it a name'), findsOneWidget);
  });

  testWidgets('Save stores the instrument and confirms it', (tester) async {
    await openEditor(tester);
    await tester.enterText(find.byKey(const Key('instrument-name')), 'Click');
    await tester.pump();

    await tester.tap(find.byKey(const Key('instrument-save')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(repository.snapshot.value.instruments.single.name, 'Click');
    expect(find.text('Saved "Click"'), findsOneWidget);
    expect(find.text('Saved'), findsOneWidget);
    expect(saveButton(tester).onPressed, isNull);
  });

  testWidgets('panel state survives switching to another panel', (
    tester,
  ) async {
    await openEditor(tester);
    await tester.enterText(find.byKey(const Key('instrument-name')), 'Keep me');
    await tester.pump();

    await tester.tap(find.byKey(const Key('editor-tab-loop')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('editor-tab-instrument')));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<TextField>(find.byKey(const Key('instrument-name')))
          .controller!
          .text,
      'Keep me',
    );
  });

  group('leaving with unsaved changes', () {
    Future<void> change(WidgetTester tester) async {
      await openEditor(tester);
      await tester.enterText(find.byKey(const Key('instrument-name')), 'Draft');
      await tester.pump();
    }

    testWidgets('an unchanged editor leaves without asking', (tester) async {
      await openEditor(tester);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Unsaved changes'), findsNothing);
      expect(find.byKey(const Key('home-editor')), findsOneWidget);
    });

    testWidgets('Cancel stays in the editor with the draft intact', (
      tester,
    ) async {
      await change(tester);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Save this instrument before leaving?'), findsOneWidget);

      await tester.tap(find.byKey(const Key('leave-cancel')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('instrument-name')), findsOneWidget);
      expect(repository.snapshot.value.instruments, isEmpty);
    });

    testWidgets('Discard leaves and stores nothing', (tester) async {
      await change(tester);
      await tester.pageBack();
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('leave-discard')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('home-editor')), findsOneWidget);
      expect(repository.snapshot.value.instruments, isEmpty);
    });

    testWidgets('Save stores the instrument, then leaves', (tester) async {
      await change(tester);
      await tester.pageBack();
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('leave-save')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('home-editor')), findsOneWidget);
      expect(repository.snapshot.value.instruments.single.name, 'Draft');
    });

    testWidgets('Save is not offered while the name is invalid', (
      tester,
    ) async {
      await openEditor(tester);
      await tester.enterText(find.byKey(const Key('instrument-name')), '');
      await tester.pump();
      await tester.pageBack();
      await tester.pumpAndSettle();

      final save = tester.widget<TextButton>(
        find.byKey(const Key('leave-save')),
      );
      expect(save.onPressed, isNull);
    });
  });

  test('the sample instrument used by the panel is valid', () {
    expect(factoryInstruments[1].fundamentalHz, 660);
  });
}
