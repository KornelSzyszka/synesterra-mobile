import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synesterra/app/synesterra_app.dart';
import 'package:synesterra/data/repositories/impl/in_memory_arrangement_library_repository.dart';
import 'package:synesterra/data/repositories/impl/in_memory_instrument_library_repository.dart';
import 'package:synesterra/data/repositories/impl/noop_instrument_audition_repository.dart';
import 'package:synesterra/data/repositories/impl/noop_playback_repository.dart';
import 'package:synesterra/data/repositories/playback_repository.dart';
import 'package:synesterra/features/home/home_view.dart';
import 'package:synesterra/shared/widgets/tap_glitch.dart';

Future<void> _pumpApp(WidgetTester tester) async {
  await tester.pumpWidget(
    SynesterraApp(
      showArrangement: true,
      instrumentLibrary: InMemoryInstrumentLibraryRepository(),
      instrumentAudition: NoopInstrumentAuditionRepository(),
    ),
  );
}

void main() {
  sharedPlaybackTests();
  arrangementLeaveTests();
  arrangementNameLeaveTests();

  testWidgets('the shipped app hides the shelved Arrangement tabs', (
    tester,
  ) async {
    await tester.pumpWidget(
      SynesterraApp(
        instrumentLibrary: InMemoryInstrumentLibraryRepository(),
        instrumentAudition: NoopInstrumentAuditionRepository(),
      ),
    );
    await tester.tap(find.byKey(const Key('home-editor')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('editor-tab-loop')), findsOneWidget);
    expect(find.byKey(const Key('editor-tab-arrangement')), findsNothing);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('home-library')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('library-tab-loops')), findsOneWidget);
    expect(find.byKey(const Key('library-tab-arrangements')), findsNothing);
  });

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
        of: find.byType(HomeView),
        matching: find.byType(TapGlitch),
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
    expect(find.byKey(const Key('arrangement-panel')), findsOneWidget);
    expect(find.text('Add a loop to play.'), findsOneWidget);
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

Future<void> _tap(WidgetTester tester, String key) async {
  await tester.ensureVisible(find.byKey(Key(key)));
  await tester.tap(find.byKey(Key(key)));
  // While something plays, views read the position every frame, so the tree
  // never settles; pump fixed frames instead.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

String _label(WidgetTester tester, String key) => tester
    .widget<Text>(
      find.descendant(of: find.byKey(Key(key)), matching: find.byType(Text)),
    )
    .data!;

void sharedPlaybackTests() {
  testWidgets('the Loop and Arrangement panels share one playback', (
    tester,
  ) async {
    final playback = NoopPlaybackRepository();
    await tester.pumpWidget(
      SynesterraApp(
        showArrangement: true,
        instrumentLibrary: InMemoryInstrumentLibraryRepository(),
        instrumentAudition: NoopInstrumentAuditionRepository(),
        playback: playback,
      ),
    );
    await _tap(tester, 'home-editor');
    await _tap(tester, 'editor-tab-loop');
    await _tap(tester, 'loop-play');
    expect(_label(tester, 'loop-play'), 'Stop');
    final loopOwner = playback.status.value.owner;
    expect(loopOwner, isNotNull);

    // The Arrangement panel takes the transport over.
    await _tap(tester, 'editor-tab-arrangement');
    await _tap(tester, 'arrangement-add-section');
    await _tap(tester, 'loop-option-factory-loop-3-2');
    expect(_label(tester, 'arrangement-play'), 'Play');
    await _tap(tester, 'arrangement-play');
    expect(_label(tester, 'arrangement-play'), 'Stop');
    expect(playback.status.value.owner, isNot(same(loopOwner)));
    await _tap(tester, 'editor-tab-loop');
    expect(_label(tester, 'loop-play'), 'Play');

    // The loop takes it back; an arrangement edit leaves the loop playing.
    await _tap(tester, 'loop-play');
    expect(playback.status.value.owner, same(loopOwner));
    await _tap(tester, 'editor-tab-arrangement');
    expect(_label(tester, 'arrangement-play'), 'Play');
    await _tap(tester, 'section-remove-0');
    expect(playback.status.value.state, PlaybackState.playing);
    expect(playback.status.value.owner, same(loopOwner));

    await _tap(tester, 'editor-tab-loop');
    await _tap(tester, 'loop-play');
    expect(playback.status.value.state, PlaybackState.stopped);
  });
}

void arrangementLeaveTests() {
  Future<InMemoryArrangementLibraryRepository> openWithDraft(
    WidgetTester tester,
  ) async {
    final arrangements = InMemoryArrangementLibraryRepository();
    await tester.pumpWidget(
      SynesterraApp(
        showArrangement: true,
        instrumentLibrary: InMemoryInstrumentLibraryRepository(),
        instrumentAudition: NoopInstrumentAuditionRepository(),
        arrangementLibrary: arrangements,
      ),
    );
    await tester.tap(find.byKey(const Key('home-editor')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('editor-tab-arrangement')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('arrangement-add-section')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('loop-option-factory-loop-3-2')));
    await tester.pumpAndSettle();
    return arrangements;
  }

  testWidgets('leaving the Editor with an unsaved arrangement asks first', (
    tester,
  ) async {
    await openWithDraft(tester);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Save this arrangement before leaving?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('leave-cancel')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('arrangement-panel')), findsOneWidget);
    expect(find.byKey(const Key('section-0')), findsOneWidget);
  });

  testWidgets('Save in the leave dialog stores the arrangement and leaves', (
    tester,
  ) async {
    final arrangements = await openWithDraft(tester);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('leave-save')));
    await tester.pumpAndSettle();
    expect(arrangements.snapshot.value.items.single.sections, hasLength(1));
    expect(find.byKey(const Key('home-editor')), findsOneWidget);
  });

  testWidgets('a saved arrangement leaves without asking', (tester) async {
    await openWithDraft(tester);
    await tester.tap(find.byKey(const Key('arrangement-save')));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Unsaved changes'), findsNothing);
    expect(find.byKey(const Key('home-editor')), findsOneWidget);
  });
}

void arrangementNameLeaveTests() {
  testWidgets('a renamed new arrangement without sections still asks', (
    tester,
  ) async {
    await tester.pumpWidget(
      SynesterraApp(
        showArrangement: true,
        instrumentLibrary: InMemoryInstrumentLibraryRepository(),
        instrumentAudition: NoopInstrumentAuditionRepository(),
      ),
    );
    await tester.tap(find.byKey(const Key('home-editor')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('editor-tab-arrangement')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('arrangement-name')), 'Song');
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Save this arrangement before leaving?'), findsOneWidget);
    // Nothing to save yet (no section), so Save is off; Discard leaves.
    expect(
      tester.widget<TextButton>(find.byKey(const Key('leave-save'))).onPressed,
      isNull,
    );
    await tester.tap(find.byKey(const Key('leave-discard')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('home-editor')), findsOneWidget);
  });
}
