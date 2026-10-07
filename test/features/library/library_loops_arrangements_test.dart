import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synesterra/app/synesterra_app.dart';
import 'package:synesterra/data/repositories/arrangement_library_repository.dart';
import 'package:synesterra/data/repositories/impl/in_memory_arrangement_library_repository.dart';
import 'package:synesterra/data/repositories/impl/in_memory_instrument_library_repository.dart';
import 'package:synesterra/data/repositories/impl/in_memory_loop_library_repository.dart';
import 'package:synesterra/data/repositories/impl/noop_instrument_audition_repository.dart';
import 'package:synesterra/data/repositories/interim_arrangement.dart';
import 'package:synesterra/data/repositories/library_item.dart';
import 'package:synesterra/data/repositories/loop.dart';
import 'package:synesterra/data/repositories/loop_library_repository.dart';
import 'package:synesterra/features/library/library_view.dart';
import 'package:synesterra/shared/theme/synesterra_theme.dart';

Loop myLoop(String id, String name, {List<int> hits = const [3, 2]}) => Loop(
  id: id,
  name: name,
  document: simpleLoopDocument(
    bpm: 120,
    cycleBeats: 4,
    layers: [
      for (final h in hits)
        LoopLayerSpec(instrumentId: 'factory-wood', pitch: 69, hits: h),
    ],
  ),
);

InterimArrangement myArrangement(
  String id,
  String name, {
  List<(String, int)> sections = const [('factory-loop-3-2', 4), ('gone', 2)],
}) => InterimArrangement(
  id: id,
  name: name,
  sections: [
    for (final (loopId, repeats) in sections)
      InterimArrangementSection(loopId: loopId, repeats: repeats),
  ],
);

class UnreadableLoops extends InMemoryLoopLibraryRepository {
  @override
  ValueNotifier<LibrarySnapshot<Loop>> get snapshot =>
      ValueNotifier(LibrarySnapshot(unreadableCount: 1));
}

Future<void> pumpLibrary(
  WidgetTester tester, {
  LoopLibraryRepository? loops,
  ArrangementLibraryRepository? arrangements,
  OpenLoop? onOpenLoop,
  OpenArrangement? onOpenArrangement,
  String tab = 'loops',
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: synesterraTheme(SynesterraPalette.forest),
      home: LibraryView(
        instrumentLibrary: InMemoryInstrumentLibraryRepository(),
        loopLibrary: loops ?? InMemoryLoopLibraryRepository(),
        arrangementLibrary:
            arrangements ?? InMemoryArrangementLibraryRepository(),
        onOpenInstrument: (_, _) {},
        onOpenLoop: onOpenLoop ?? (_, _) {},
        onOpenArrangement: onOpenArrangement ?? (_) {},
      ),
    ),
  );
  await tester.tap(find.byKey(Key('library-tab-$tab')));
  await tester.pumpAndSettle();
}

Future<void> showSnackBar(WidgetTester tester) async {
  await tester.pump();
  // The floating snack bar has to finish sliding in before Undo is hittable.
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  testWidgets('the tabs are Instruments, Loops, Arrangements in that order', (
    tester,
  ) async {
    await pumpLibrary(tester, tab: 'instruments');
    final x = [
      'instruments',
      'loops',
      'arrangements',
    ].map((t) => tester.getCenter(find.byKey(Key('library-tab-$t'))).dx);
    expect(x.toList(), orderedEquals(x.toList()..sort()));
    expect(find.text('Instruments'), findsOneWidget);
    expect(find.text('Loops'), findsOneWidget);
    expect(find.text('Arrangements'), findsOneWidget);
  });

  group('Loops tab', () {
    testWidgets('empty: plain wording and the three factory loops', (
      tester,
    ) async {
      await pumpLibrary(tester);

      expect(
        find.text(
          'No loops of your own yet. Copy a factory loop to start one.',
        ),
        findsOneWidget,
      );
      for (final loop in factoryLoops) {
        expect(find.byKey(Key('loop-tile-${loop.id}')), findsOneWidget);
      }
      expect(find.text('3:2 · 2 layers · 90 BPM'), findsOneWidget);
      expect(find.text('5:4 · 2 layers · 80 BPM'), findsOneWidget);
      expect(find.text('4:3:2 · 3 layers · 90 BPM'), findsOneWidget);
    });

    testWidgets('factory loops are read-only: no rename, no delete', (
      tester,
    ) async {
      await pumpLibrary(tester);
      for (final loop in factoryLoops) {
        expect(find.byKey(Key('loop-rename-${loop.id}')), findsNothing);
        expect(find.byKey(Key('loop-delete-${loop.id}')), findsNothing);
        expect(find.byKey(Key('loop-copy-${loop.id}')), findsOneWidget);
      }
    });

    testWidgets('copying a factory loop adds an editable copy', (tester) async {
      final repository = InMemoryLoopLibraryRepository();
      await pumpLibrary(tester, loops: repository);

      await tester.tap(find.byKey(const Key('loop-copy-factory-loop-3-2')));
      await tester.pump();

      final copy = repository.snapshot.value.items.single;
      expect(copy.name, 'Three against two copy');
      expect(isFactoryId(copy.id), isFalse);
      expect(copy.document, factoryLoops.first.document);
      expect(find.byKey(Key('loop-tile-${copy.id}')), findsOneWidget);
      expect(find.byKey(Key('loop-rename-${copy.id}')), findsOneWidget);
    });

    testWidgets('own loops are listed by name with a summary', (tester) async {
      await pumpLibrary(
        tester,
        loops: InMemoryLoopLibraryRepository([
          myLoop('b', 'beta', hits: [5, 4, 3]),
          myLoop('a', 'Alpha'),
        ]),
      );

      expect(
        find.text(
          'No loops of your own yet. Copy a factory loop to start one.',
        ),
        findsNothing,
      );
      expect(
        tester.getTopLeft(find.byKey(const Key('loop-tile-a'))).dy,
        lessThan(tester.getTopLeft(find.byKey(const Key('loop-tile-b'))).dy),
      );
      expect(find.text('3:2 · 2 layers · 120 BPM'), findsOneWidget);
      expect(find.text('5:4:3 · 3 layers · 120 BPM'), findsOneWidget);
    });

    testWidgets('tapping opens: own in place, factory as a copy', (
      tester,
    ) async {
      final opened = <(String, bool)>[];
      await pumpLibrary(
        tester,
        loops: InMemoryLoopLibraryRepository([myLoop('a', 'Alpha')]),
        onOpenLoop: (loop, existing) => opened.add((loop.id, existing)),
      );

      await tester.tap(find.byKey(const Key('loop-tile-a')));
      await tester.tap(find.byKey(const Key('loop-tile-factory-loop-5-4')));
      expect(opened, [('a', true), ('factory-loop-5-4', false)]);
    });

    testWidgets('rename saves the new name; a blank name cannot be saved', (
      tester,
    ) async {
      final repository = InMemoryLoopLibraryRepository([myLoop('a', 'Alpha')]);
      await pumpLibrary(tester, loops: repository);

      await tester.tap(find.byKey(const Key('loop-rename-a')));
      await tester.pumpAndSettle();
      expect(find.text('Rename loop'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('rename-field')), '   ');
      await tester.pump();
      expect(
        tester.widget<TextButton>(find.byKey(const Key('rename-save'))).enabled,
        isFalse,
      );

      await tester.enterText(find.byKey(const Key('rename-field')), 'Groove');
      await tester.pump();
      await tester.tap(find.byKey(const Key('rename-save')));
      await tester.pumpAndSettle();

      final renamed = repository.snapshot.value.items.single;
      expect(renamed.id, 'a');
      expect(renamed.name, 'Groove');
      expect(find.text('Groove'), findsOneWidget);
    });

    testWidgets('cancel leaves the name as it was', (tester) async {
      final repository = InMemoryLoopLibraryRepository([myLoop('a', 'Alpha')]);
      await pumpLibrary(tester, loops: repository);

      await tester.tap(find.byKey(const Key('loop-rename-a')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('rename-field')), 'Other');
      await tester.tap(find.byKey(const Key('rename-cancel')));
      await tester.pumpAndSettle();

      expect(repository.snapshot.value.items.single.name, 'Alpha');
    });

    testWidgets('delete removes the loop and Undo brings it back', (
      tester,
    ) async {
      final original = myLoop('a', 'Alpha');
      final repository = InMemoryLoopLibraryRepository([original]);
      await pumpLibrary(tester, loops: repository);

      await tester.tap(find.byKey(const Key('loop-delete-a')));
      await showSnackBar(tester);
      expect(repository.snapshot.value.items, isEmpty);
      expect(find.text('Deleted "Alpha"'), findsOneWidget);

      await tester.tap(find.text('Undo'));
      await tester.pump();
      expect(repository.snapshot.value.items, [original]);
      expect(find.byKey(const Key('loop-tile-a')), findsOneWidget);
    });

    testWidgets('unreadable files are announced, not hidden', (tester) async {
      await pumpLibrary(tester, loops: UnreadableLoops());
      expect(
        find.text('1 stored file could not be read. It was left untouched.'),
        findsOneWidget,
      );
    });
  });

  group('Arrangements tab', () {
    testWidgets('empty: plain wording', (tester) async {
      await pumpLibrary(tester, tab: 'arrangements');
      expect(
        find.text(
          'No arrangements yet. An arrangement plays loops one after '
          'another.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('a card shows sections, repeats and missing loops', (
      tester,
    ) async {
      await pumpLibrary(
        tester,
        tab: 'arrangements',
        loops: InMemoryLoopLibraryRepository([myLoop('mine', 'Mine')]),
        arrangements: InMemoryArrangementLibraryRepository([
          myArrangement('x', 'Song'),
          myArrangement('y', 'Fine', sections: [('mine', 3)]),
        ]),
      );

      expect(find.text('Song'), findsOneWidget);
      expect(find.text('2 sections · 6 repeats'), findsOneWidget);
      expect(
        find.text('Three against two ×4 → missing loop ×2'),
        findsOneWidget,
      );
      expect(find.text('1 missing loop'), findsOneWidget);
      expect(find.text('1 section · 3 repeats'), findsOneWidget);
      expect(find.text('Mine ×3'), findsOneWidget);
    });

    testWidgets('a loop deleted elsewhere shows as missing at once', (
      tester,
    ) async {
      final loops = InMemoryLoopLibraryRepository([myLoop('mine', 'Mine')]);
      await pumpLibrary(
        tester,
        tab: 'arrangements',
        loops: loops,
        arrangements: InMemoryArrangementLibraryRepository([
          myArrangement('y', 'Fine', sections: [('mine', 3)]),
        ]),
      );
      expect(find.text('1 missing loop'), findsNothing);

      await loops.delete('mine');
      await tester.pump();
      expect(find.text('1 missing loop'), findsOneWidget);
    });

    testWidgets('tap opens, rename saves, delete has Undo', (tester) async {
      final opened = <String>[];
      final original = myArrangement('x', 'Song');
      final repository = InMemoryArrangementLibraryRepository([original]);
      await pumpLibrary(
        tester,
        tab: 'arrangements',
        arrangements: repository,
        onOpenArrangement: (a) => opened.add(a.id),
      );

      await tester.tap(find.byKey(const Key('arrangement-tile-x')));
      expect(opened, ['x']);

      await tester.tap(find.byKey(const Key('arrangement-rename-x')));
      await tester.pumpAndSettle();
      expect(find.text('Rename arrangement'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('rename-field')), 'Tune');
      await tester.pump();
      await tester.tap(find.byKey(const Key('rename-save')));
      await tester.pumpAndSettle();
      expect(repository.snapshot.value.items.single.name, 'Tune');

      await tester.tap(find.byKey(const Key('arrangement-delete-x')));
      await showSnackBar(tester);
      expect(repository.snapshot.value.items, isEmpty);
      expect(find.text('Deleted "Tune"'), findsOneWidget);
      await tester.tap(find.text('Undo'));
      await tester.pump();
      expect(repository.snapshot.value.items.single.name, 'Tune');
    });
  });

  group('app shell', () {
    testWidgets('opening a loop or an arrangement shows a placeholder', (
      tester,
    ) async {
      await tester.pumpWidget(
        SynesterraApp(
          instrumentLibrary: InMemoryInstrumentLibraryRepository(),
          instrumentAudition: NoopInstrumentAuditionRepository(),
          loopLibrary: InMemoryLoopLibraryRepository(),
          arrangementLibrary: InMemoryArrangementLibraryRepository([
            myArrangement('x', 'Song'),
          ]),
        ),
      );
      await tester.tap(find.byKey(const Key('home-library')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('library-tab-loops')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('loop-tile-factory-loop-3-2')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('library-item-placeholder')), findsOneWidget);
      expect(find.text('Three against two'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('library-tab-arrangements')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('arrangement-tile-x')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('library-item-placeholder')), findsOneWidget);
      expect(find.text('Song'), findsOneWidget);
    });
  });
}
