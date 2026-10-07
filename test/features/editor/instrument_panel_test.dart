import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synesterra/app/synesterra_app.dart';
import 'package:synesterra/data/repositories/impl/in_memory_instrument_library_repository.dart';
import 'package:synesterra/data/repositories/impl/noop_instrument_audition_repository.dart';
import 'package:synesterra/features/editor/instrument_panel.dart';

late InMemoryInstrumentLibraryRepository repository;

Future<void> openEditor(WidgetTester tester) async {
  // The technical controls are hidden in v1; these tests still cover them.
  showTechnicalControls = true;
  addTearDown(() => showTechnicalControls = false);
  // The panel is a lazy list; a tall screen builds every control.
  tester.view
    ..devicePixelRatio = 1
    ..physicalSize = const Size(800, 4000);
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
    expect(find.text('2 ms'), findsOneWidget);
    expect(find.text('120 ms'), findsOneWidget);
    expect(find.text('+0.0 dB'), findsNWidgets(3));
    expect(find.textContaining('to hear it'), findsOneWidget);
  });

  testWidgets('moving a slider updates its value and the draft', (
    tester,
  ) async {
    await openEditor(tester);

    sliderOf(tester, 'instrument-brightness').onChanged!(0.2);
    sliderOf(tester, 'instrument-eq-high').onChanged!(1);
    sliderOf(tester, 'instrument-decay').onChanged!(1);
    await tester.pump();

    expect(find.text('20%'), findsOneWidget);
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
  });

  testWidgets(
    'a dirty draft is kept until Start from replacement is confirmed',
    (tester) async {
      await openEditor(tester);
      await tester.enterText(find.byKey(const Key('instrument-name')), 'Draft');
      await tester.pump();

      await tester.tap(find.byKey(const Key('start-from-factory-bell')));
      await tester.pumpAndSettle();

      expect(find.text('Discard unsaved changes?'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('instrument-name')))
            .controller!
            .text,
        'Draft',
      );

      await tester.tap(find.byKey(const Key('start-from-cancel')));
      await tester.pumpAndSettle();
      expect(find.text('Discard unsaved changes?'), findsNothing);

      await tester.tap(find.byKey(const Key('start-from-factory-bell')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('start-from-discard')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('instrument-name')))
            .controller!
            .text,
        'Bell',
      );
    },
  );

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

  group('no pitch in the instrument', () {
    testWidgets('there is no pitch control, only a test sound section', (
      tester,
    ) async {
      await openEditor(tester);
      expect(find.byKey(const Key('instrument-pitch')), findsNothing);
      expect(find.text('Pitch'), findsNothing);
      expect(find.text('TEST SOUND'), findsOneWidget);
      expect(
        find.text('Only for hearing the instrument. It is not saved with it.'),
        findsOneWidget,
      );
    });

    testWidgets('choosing a test note does not mark the instrument changed', (
      tester,
    ) async {
      await openEditor(tester);
      await tester.tap(find.byKey(const Key('test-root-3')));
      await tester.pump();
      expect(find.text('Unsaved changes'), findsNothing);
      expect(find.text('Saved'), findsOneWidget);
    });
  });

  group('tags', () {
    testWidgets('a new instrument has none and says so', (tester) async {
      await openEditor(tester);
      expect(find.text('No tags yet.'), findsOneWidget);
    });

    testWidgets('typing a tag and pressing the add button adds it', (
      tester,
    ) async {
      await openEditor(tester);
      await tester.enterText(
        find.byKey(const Key('instrument-tag-input')),
        '  Dark  Wood ',
      );
      await tester.tap(find.byKey(const Key('instrument-tag-add')));
      await tester.pump();

      expect(find.byKey(const Key('tag-dark wood')), findsOneWidget);
      expect(find.text('No tags yet.'), findsNothing);
      expect(find.text('Unsaved changes'), findsOneWidget);
    });

    testWidgets('submitting from the keyboard adds the tag too', (
      tester,
    ) async {
      await openEditor(tester);
      await tester.enterText(
        find.byKey(const Key('instrument-tag-input')),
        'click',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(find.byKey(const Key('tag-click')), findsOneWidget);
    });

    testWidgets('a suggestion adds a tag and leaves the suggestions', (
      tester,
    ) async {
      await openEditor(tester);
      await tester.tap(find.byKey(const Key('suggest-bell')));
      await tester.pump();

      expect(find.byKey(const Key('tag-bell')), findsOneWidget);
      expect(find.byKey(const Key('suggest-bell')), findsNothing);
      expect(find.byKey(const Key('suggest-click')), findsOneWidget);
    });

    testWidgets('a tag can be removed with its delete button', (tester) async {
      await openEditor(tester);
      await tester.tap(find.byKey(const Key('suggest-wood')));
      await tester.pump();
      await tester.tap(find.byTooltip('Remove tag wood'));
      await tester.pump();

      expect(find.byKey(const Key('tag-wood')), findsNothing);
      expect(find.byKey(const Key('suggest-wood')), findsOneWidget);
    });

    testWidgets('an invalid tag shows why and adds nothing', (tester) async {
      await openEditor(tester);
      await tester.enterText(
        find.byKey(const Key('instrument-tag-input')),
        'no_good!',
      );
      await tester.tap(find.byKey(const Key('instrument-tag-add')));
      await tester.pump();

      expect(find.textContaining('Use letters, digits'), findsOneWidget);
      expect(find.text('No tags yet.'), findsOneWidget);
    });

    testWidgets('a repeated tag is refused with a reason', (tester) async {
      await openEditor(tester);
      for (var i = 0; i < 2; i++) {
        await tester.enterText(
          find.byKey(const Key('instrument-tag-input')),
          'click',
        );
        await tester.tap(find.byKey(const Key('instrument-tag-add')));
        await tester.pump();
      }
      expect(find.text('That tag is already there.'), findsOneWidget);
    });

    testWidgets('at the limit the input goes away and a note explains', (
      tester,
    ) async {
      await openEditor(tester);
      for (final tag in ['click', 'wood', 'metal', 'bell', 'tone', 'drum']) {
        await tester.tap(find.byKey(Key('suggest-$tag')));
        await tester.pump();
      }
      expect(find.byKey(const Key('instrument-tag-input')), findsNothing);
      expect(
        find.text('That is the most tags an instrument can have.'),
        findsOneWidget,
      );
    });

    testWidgets('tags are saved with the instrument', (tester) async {
      await openEditor(tester);
      await tester.tap(find.byKey(const Key('suggest-bell')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('instrument-save')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(repository.snapshot.value.instruments.single.tags, ['bell']);
    });

    testWidgets('a preset arrives with its tags', (tester) async {
      await openEditor(tester);
      await tester.tap(find.byKey(const Key('start-from-factory-bell')));
      await tester.pump();
      expect(find.byKey(const Key('tag-bell')), findsOneWidget);
      expect(find.byKey(const Key('tag-metal')), findsOneWidget);
    });
  });
}
