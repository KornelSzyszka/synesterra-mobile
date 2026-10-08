import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synesterra/data/repositories/impl/in_memory_arrangement_library_repository.dart';
import 'package:synesterra/data/repositories/impl/in_memory_loop_library_repository.dart';
import 'package:synesterra/data/repositories/playback_repository.dart';
import 'package:synesterra/features/arrangement/arrangement_panel.dart';
import 'package:synesterra/shared/theme/synesterra_theme.dart';
import 'package:synesterra_core/synesterra_core.dart';

import 'arrangement_fakes.dart';

void main() {
  late InMemoryLoopLibraryRepository loops;
  late InMemoryArrangementLibraryRepository arrangements;
  late RecordingPlayback playback;
  late List<Arrangement> saved;

  setUp(() {
    loops = InMemoryLoopLibraryRepository([userLoop('mine', 'My loop')]);
    arrangements = InMemoryArrangementLibraryRepository();
    playback = RecordingPlayback();
    saved = [];
  });

  Future<void> pumpPanel(WidgetTester tester, {Arrangement? initial}) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: synesterraTheme(SynesterraPalette.forest),
        home: Scaffold(
          body: ArrangementPanel(
            loops: loops,
            arrangements: arrangements,
            playback: playback,
            initial: initial,
            onSaved: saved.add,
          ),
        ),
      ),
    );
    await tester.pump();
  }

  FilledButton playButton(WidgetTester tester) => tester.widget<FilledButton>(
    find.descendant(
      of: find.byKey(const Key('arrangement-play')),
      matching: find.byType(FilledButton),
    ),
  );

  Future<void> addSection(WidgetTester tester, String loopId) async {
    await tester.ensureVisible(
      find.byKey(const Key('arrangement-add-section')),
    );
    await tester.tap(find.byKey(const Key('arrangement-add-section')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('loop-option-$loopId')));
    await tester.pumpAndSettle();
  }

  /// While playing, the strip reads the position on every frame, so the tree
  /// never settles; then a few fixed frames are pumped instead.
  Future<void> tapKey(WidgetTester tester, String key) async {
    await tester.ensureVisible(find.byKey(Key(key)));
    await tester.tap(find.byKey(Key(key)));
    if (playback.positionNotifier.value.playing) {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    } else {
      await tester.pumpAndSettle();
    }
  }

  testWidgets('an empty arrangement cannot play and says why', (tester) async {
    await pumpPanel(tester);
    expect(playButton(tester).onPressed, isNull);
    expect(find.text('Add a loop to play.'), findsOneWidget);
  });

  testWidgets('add sections from the loop picker, factory loops included', (
    tester,
  ) async {
    await pumpPanel(tester);
    await tester.tap(find.byKey(const Key('arrangement-add-section')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('loop-option-factory-loop-3-2')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('loop-option-mine')), findsOneWidget);
    await tester.tap(find.byKey(const Key('loop-option-factory-loop-5-4')));
    await tester.pumpAndSettle();
    await addSection(tester, 'mine');

    expect(
      find.descendant(
        of: find.byKey(const Key('section-0')),
        matching: find.text('Five against four'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('section-1')),
        matching: find.text('My loop'),
      ),
      findsOneWidget,
    );
    expect(playButton(tester).onPressed, isNotNull);
  });

  testWidgets('repeats, reorder and remove', (tester) async {
    await pumpPanel(
      tester,
      initial: arrangementOf('a1', 'Song', [
        ('factory-loop-3-2', 2),
        ('mine', 4),
      ]),
    );
    final increase = find.descendant(
      of: find.byKey(const Key('section-repeats-0')),
      matching: find.byTooltip('Increase repeats'),
    );
    await tester.ensureVisible(increase);
    await tester.tap(increase);
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const Key('section-repeats-0')),
        matching: find.text('3'),
      ),
      findsOneWidget,
    );

    await tapKey(tester, 'section-down-0');
    expect(
      find.descendant(
        of: find.byKey(const Key('section-0')),
        matching: find.text('My loop'),
      ),
      findsOneWidget,
    );
    expect(
      tester
          .widget<IconButton>(find.byKey(const Key('section-up-0')))
          .onPressed,
      isNull,
    );

    await tapKey(tester, 'section-remove-0');
    expect(find.byKey(const Key('section-1')), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const Key('section-0')),
        matching: find.text('Three against two'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('change the loop of a section', (tester) async {
    await pumpPanel(
      tester,
      initial: arrangementOf('a1', 'Song', [('gone', 2)]),
    );
    await tapKey(tester, 'section-loop-0');
    await tester.tap(find.byKey(const Key('loop-option-mine')));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const Key('section-0')),
        matching: find.text('My loop'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('a missing loop is shown as missing and skipped', (tester) async {
    await pumpPanel(
      tester,
      initial: arrangementOf('a1', 'Song', [
        ('gone', 1),
        ('factory-loop-3-2', 2),
      ]),
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('section-0')),
        matching: find.text('Missing loop'),
      ),
      findsOneWidget,
    );
    expect(
      find.text('Skipped when playing. Pick another loop.'),
      findsOneWidget,
    );

    await tapKey(tester, 'arrangement-play');
    final (sections, _) = playback.sequences.single;
    expect(sections.single.originalIndex, 1);
  });

  testWidgets('nothing playable disables Play with a plain reason', (
    tester,
  ) async {
    await pumpPanel(
      tester,
      initial: arrangementOf('a1', 'Song', [('gone', 1), ('gone-too', 2)]),
    );
    expect(playButton(tester).onPressed, isNull);
    expect(
      find.text(
        'Nothing to play: the loops of every section are missing. '
        'Pick a loop for a section.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('Play, Stop and repeat all', (tester) async {
    await pumpPanel(
      tester,
      initial: arrangementOf('a1', 'Song', [('factory-loop-3-2', 2)]),
    );
    await tapKey(tester, 'arrangement-repeat-all');
    await tapKey(tester, 'arrangement-play');
    expect(playback.sequences.single.$2, isTrue);
    expect(
      find.descendant(
        of: find.byKey(const Key('arrangement-play')),
        matching: find.text('Stop'),
      ),
      findsOneWidget,
    );
    await tapKey(tester, 'arrangement-play');
    expect(playback.stops, 1);
    expect(
      find.descendant(
        of: find.byKey(const Key('arrangement-play')),
        matching: find.text('Play'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('the strip follows the playing section by its original index', (
    tester,
  ) async {
    await pumpPanel(
      tester,
      initial: arrangementOf('a1', 'Song', [
        ('gone', 1),
        ('factory-loop-3-2', 2),
      ]),
    );
    await tapKey(tester, 'arrangement-play');
    playback.positionNotifier.value = PlaybackPosition(
      playing: true,
      cyclePosition: .5,
      cycleIndex: 1,
      generation: 9,
      sectionIndex: 1,
    );
    await tester.pump();
    await tester.pump();
    expect(
      find.bySemanticsLabel('Section 2 of 2, Three against two, cycle 2 of 2.'),
      findsOneWidget,
    );
    await tapKey(tester, 'arrangement-play');
  });

  testWidgets('save names the arrangement and stores it', (tester) async {
    await pumpPanel(tester);
    await addSection(tester, 'mine');
    await tester.enterText(find.byKey(const Key('arrangement-name')), 'Song');
    await tapKey(tester, 'arrangement-save');
    expect(arrangements.snapshot.value.items.single.name, 'Song');
    expect(saved.single.name, 'Song');
    expect(find.text('Saved.'), findsOneWidget);
  });

  testWidgets('open an arrangement from the library', (tester) async {
    await arrangements.save(arrangementOf('a2', 'Older song', [('mine', 5)]));
    await pumpPanel(tester);
    await tapKey(tester, 'arrangement-open');
    await tester.tap(find.byKey(const Key('arrangement-option-a2')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('arrangement-name')))
          .controller!
          .text,
      'Older song',
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('section-repeats-0')),
        matching: find.text('5'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('opening over unsaved changes asks first', (tester) async {
    await arrangements.save(arrangementOf('a2', 'Older song', [('mine', 5)]));
    await pumpPanel(tester);
    await addSection(tester, 'factory-loop-3-2');
    await tapKey(tester, 'arrangement-open');
    await tester.tap(find.byKey(const Key('arrangement-option-a2')));
    await tester.pumpAndSettle();
    expect(find.text('Discard unsaved changes?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('arrangement-discard-cancel')));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const Key('section-0')),
        matching: find.text('Three against two'),
      ),
      findsOneWidget,
    );
  });
}
