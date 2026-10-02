import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synesterra/app/synesterra_app.dart';

Future<void> _pumpApp(WidgetTester tester) async {
  await tester.pumpWidget(const SynesterraApp());
}

void main() {
  testWidgets('start screen offers exactly the Editor and Library entries', (
    tester,
  ) async {
    await _pumpApp(tester);

    expect(find.byKey(const Key('home-editor')), findsOneWidget);
    expect(find.byKey(const Key('home-library')), findsOneWidget);
    expect(find.text('Editor'), findsOneWidget);
    expect(find.text('Library'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(ListView),
        matching: find.byType(InkWell),
      ),
      findsNWidgets(2),
    );
  });

  testWidgets('entries are at least 48 dp tall and labelled for TalkBack', (
    tester,
  ) async {
    await _pumpApp(tester);

    for (final key in const ['home-editor', 'home-library']) {
      expect(
        tester.getSize(find.byKey(Key(key))).height,
        greaterThanOrEqualTo(48),
      );
    }
    expect(find.bySemanticsLabel(RegExp('^Editor\\.')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('^Library\\.')), findsOneWidget);
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
    expect(
      find.text('Layers with an instrument each. Planned.'),
      findsOneWidget,
    );

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
    expect(find.text('No loops yet.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('library-tab-arrangements')));
    await tester.pumpAndSettle();
    expect(find.text('No arrangements yet.'), findsOneWidget);
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
