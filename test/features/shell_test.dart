import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synesterra/app/synesterra_app.dart';
import 'package:synesterra/data/repositories/impl/in_memory_instrument_library_repository.dart';
import 'package:synesterra/data/repositories/impl/noop_instrument_audition_repository.dart';

Future<void> _pumpApp(WidgetTester tester) async {
  await tester.pumpWidget(
    SynesterraApp(
      instrumentLibrary: InMemoryInstrumentLibraryRepository(),
      instrumentAudition: NoopInstrumentAuditionRepository(),
    ),
  );
}

void main() {
  testWidgets('start screen offers the Editor, Library and Learn entries', (
    tester,
  ) async {
    await _pumpApp(tester);

    expect(find.byKey(const Key('home-editor')), findsOneWidget);
    expect(find.byKey(const Key('home-library')), findsOneWidget);
    expect(find.text('Editor'), findsOneWidget);
    expect(find.text('Library'), findsOneWidget);
    expect(find.byKey(const Key('home-learn')), findsOneWidget);
    expect(find.text('Learn'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(ListView),
        matching: find.byType(InkWell),
      ),
      findsNWidgets(3),
    );
  });

  testWidgets('entries are at least 48 dp tall and labelled for TalkBack', (
    tester,
  ) async {
    await _pumpApp(tester);

    for (final key in const ['home-editor', 'home-library', 'home-learn']) {
      expect(
        tester.getSize(find.byKey(Key(key))).height,
        greaterThanOrEqualTo(48),
      );
    }
    expect(find.bySemanticsLabel(RegExp('^Editor\\.')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('^Library\\.')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('^Learn\\.')), findsOneWidget);
  });

  testWidgets('Learn Try it opens the Loop panel on an unsaved copy', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await _pumpApp(tester);
    await tester.tap(find.byKey(const Key('home-learn')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('lesson-two-against-three')));
    // The tutorial clock ticks while a lesson is open, so nothing settles.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.byKey(const Key('lesson-try-it')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byKey(const Key('loop-play')), findsOneWidget);
    expect(find.text('Three against two copy'), findsOneWidget);
  });

  testWidgets('Editor has Instrument, Loop and Arrangement panels', (
    tester,
  ) async {
    await _pumpApp(tester);
    await tester.tap(find.byKey(const Key('home-editor')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('editor-tab-instrument')), findsOneWidget);
    expect(find.byKey(const Key('editor-tab-loop')), findsOneWidget);
    expect(find.byKey(const Key('editor-tab-arrangement')), findsOneWidget);

    await tester.tap(find.byKey(const Key('editor-tab-loop')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('loop-play')), findsOneWidget);
    expect(find.text('Three against two copy'), findsOneWidget);

    await tester.tap(find.byKey(const Key('editor-tab-arrangement')));
    await tester.pumpAndSettle();
    expect(
      find.text('Chain loops into a backing track. Planned.'),
      findsOneWidget,
    );
  });

  testWidgets('Library has a tab per editor with an empty state', (
    tester,
  ) async {
    await _pumpApp(tester);
    await tester.tap(find.byKey(const Key('home-library')));
    await tester.pumpAndSettle();

    expect(
      find.text('No instruments yet. Save one from the Editor.'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('library-tab-loops')));
    await tester.pumpAndSettle();
    expect(
      find.text('No loops of your own yet. Copy a factory loop to start one.'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('library-tab-arrangements')));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'No arrangements yet. An arrangement plays loops one after another.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('back from the Editor returns to the start screen', (
    tester,
  ) async {
    await _pumpApp(tester);
    await tester.tap(find.byKey(const Key('home-editor')));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('home-editor')), findsOneWidget);
    expect(find.byKey(const Key('home-library')), findsOneWidget);
  });
}
