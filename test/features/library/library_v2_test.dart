import 'package:flutter/material.dart';

import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:synesterra/data/repositories/impl/in_memory_arrangement_library_repository.dart';
import 'package:synesterra/data/repositories/impl/in_memory_instrument_library_repository.dart';
import 'package:synesterra/data/repositories/impl/in_memory_loop_library_repository.dart';
import 'package:synesterra/data/repositories/loop.dart';
import 'package:synesterra/features/library/library_view.dart';
import 'package:synesterra/shared/theme/synesterra_theme.dart';
import 'package:synesterra/shared/widgets/round_components.dart';
import 'package:synesterra_core/synesterra_core.dart';

Future<void> _pump(WidgetTester tester, {bool reduceMotion = false}) async {
  tester.view
    ..physicalSize = const Size(412, 892)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  if (reduceMotion) {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  }
  final loop = Loop(
    id: 'l1',
    name: 'Evening walk',
    document: simpleLoopDocument(
      bpm: 96,
      cycleBeats: 4,
      layers: [
        for (final hits in [3, 2])
          LoopLayerSpec(instrumentId: 'factory-wood', pitch: 69, hits: hits),
      ],
    ),
  );
  await tester.pumpWidget(
    MaterialApp(
      theme: synesterraTheme(SynesterraPalette.graphite),
      home: LibraryView(
        instrumentLibrary: InMemoryInstrumentLibraryRepository([
          Instrument(
            id: 'i1',
            name: 'Glass drop',
            tags: const ['bell'],
            harmonics: const [1, .4],
            attackMs: 3,
            decayMs: 150,
          ),
        ]),
        loopLibrary: InMemoryLoopLibraryRepository([loop]),
        arrangementLibrary: InMemoryArrangementLibraryRepository([
          Arrangement(
            id: 'a1',
            name: 'Suite',
            sections: [ArrangementSection(loopId: 'l1', repeats: 2)],
          ),
        ]),
        onOpenInstrument: (_, _) {},
        onOpenLoop: (_, _) {},
        onOpenArrangement: (_) {},
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  for (final tab in ['instruments', 'loops', 'arrangements']) {
    testWidgets('$tab tab: 48 dp targets, labels, no blur', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester);
      await tester.tap(find.byKey(Key('library-tab-$tab')));
      await tester.pumpAndSettle();

      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      expect(find.byType(BackdropFilter), findsNothing);
      // The items are organic cards, not Material cards or list tiles.
      expect(find.byType(OrganicCard), findsWidgets);
      expect(find.byType(Card), findsNothing);
      expect(find.byType(ListTile), findsNothing);
      handle.dispose();
    });
  }

  testWidgets('the tab strip announces the chosen tab and follows swipes', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _pump(tester);
    bool selected(String key) {
      final data = tester
          .getSemantics(find.byKey(Key('library-tab-$key')))
          .getSemanticsData();
      return data.flagsCollection.isSelected == ui.Tristate.isTrue;
    }

    expect(selected('instruments'), isTrue);
    expect(selected('loops'), isFalse);

    await tester.fling(find.byType(TabBarView), const Offset(-300, 0), 1000);
    await tester.pumpAndSettle();
    expect(selected('loops'), isTrue);
    expect(selected('instruments'), isFalse);
    handle.dispose();
  });

  testWidgets('the library is still: no animation runs on its own', (
    tester,
  ) async {
    await _pump(tester);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('under reduce motion a tap on a tab still switches it', (
    tester,
  ) async {
    await _pump(tester, reduceMotion: true);
    await tester.tap(find.byKey(const Key('library-tab-loops')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('loop-tile-l1')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
