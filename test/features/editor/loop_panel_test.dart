import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synesterra/data/repositories/impl/in_memory_instrument_library_repository.dart';
import 'package:synesterra/data/repositories/impl/in_memory_loop_library_repository.dart';
import 'package:synesterra/data/repositories/impl/noop_instrument_audition_repository.dart';
import 'package:synesterra/data/repositories/loop.dart';
import 'package:synesterra/features/editor/editor_view.dart';
import 'package:synesterra/features/editor/loop_edits.dart';
import 'package:synesterra/shared/loop_view/loop_view.dart';
import 'package:synesterra/shared/theme/synesterra_theme.dart';
import 'package:synesterra/shared/widgets/round_components.dart';

import 'loop_fakes.dart';

Loop mine(String id, {String name = 'Mine'}) => Loop(
  id: id,
  name: name,
  document: simpleLoopDocument(
    bpm: 120,
    cycleBeats: 4,
    layers: const [
      LoopLayerSpec(instrumentId: 'factory-wood', pitch: 69, hits: 3),
      LoopLayerSpec(instrumentId: 'gone', pitch: 69, hits: 2),
    ],
  ),
);

late InMemoryLoopLibraryRepository loops;
late RecordingPlayback playback;

Future<void> pumpEditor(
  WidgetTester tester, {
  Loop? loop,
  bool existing = false,
  EditorPanelBuilder? arrangementPanel,
  EditorTab tab = EditorTab.loop,
}) async {
  tester.view
    ..devicePixelRatio = 1
    ..physicalSize = const Size(480, 3000);
  addTearDown(tester.view.reset);
  loops = InMemoryLoopLibraryRepository([if (existing && loop != null) loop]);
  playback = RecordingPlayback();
  await tester.pumpWidget(
    MaterialApp(
      theme: synesterraTheme(SynesterraPalette.forest),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              key: const Key('go'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => EditorView(
                    instrumentLibrary: InMemoryInstrumentLibraryRepository(),
                    instrumentAudition: NoopInstrumentAuditionRepository(),
                    loopLibrary: loops,
                    playback: playback,
                    initialLoop: loop,
                    loopExisting: existing,
                    initialTab: tab,
                    arrangementPanel: arrangementPanel,
                  ),
                ),
              ),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const Key('go')));
  await tester.pumpAndSettle();
}

/// The step marks of layer [layer] as the panel shows them.
List<String> stepLabels(WidgetTester tester, int layer) {
  final labels = <String>[];
  for (var s = 0; ; s++) {
    final finder = find.byKey(Key('step-$layer-$s'));
    if (finder.evaluate().isEmpty) return labels;
    labels.add(tester.getSemantics(finder).label.split(': ').last);
  }
}

Finder inside(String key, IconData icon) =>
    find.descendant(of: find.byKey(Key(key)), matching: find.byIcon(icon));

/// Whether [finder] is in the panel's scrolling list. The transport bar is
/// pinned outside it, and ensureVisible there would page the tab view
/// sideways, so only list items are scrolled into view first.
bool _inList(Finder finder) => find
    .ancestor(of: finder, matching: find.byKey(const Key('loop-panel-list')))
    .evaluate()
    .isNotEmpty;

Future<void> tapAndSettle(WidgetTester tester, Finder finder) async {
  if (_inList(finder)) await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// While playing, the picture reads the clock every frame, so the tree never
/// settles; pump a few frames instead.
Future<void> tapAndPump(WidgetTester tester, Finder finder) async {
  if (_inList(finder)) await tester.ensureVisible(finder);
  await tester.tap(finder);
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

void main() {
  testWidgets('shows layers, a missing sound and the loop picture', (
    tester,
  ) async {
    await pumpEditor(tester, loop: mine('m1'), existing: true);
    expect(find.byKey(const Key('layer-0')), findsOneWidget);
    expect(find.byKey(const Key('layer-1')), findsOneWidget);
    expect(find.text('missing sound'), findsOneWidget);
    expect(find.text('Layer 2: missing sound, plays silence.'), findsOneWidget);
    expect(find.byType(LoopView), findsOneWidget);
    expect(stepLabels(tester, 0), ['strong', 'on', 'on']);
    // The view switch is UI state and changes nothing in the loop.
    await tapAndSettle(tester, find.text('Polygons'));
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('go')), findsOneWidget, reason: 'not dirty');
  });

  testWidgets('editing steps, hits, on/off, volume, cycle and tempo', (
    tester,
  ) async {
    await pumpEditor(tester);
    await tapAndSettle(tester, find.byKey(const Key('step-0-1')));
    expect(stepLabels(tester, 0), ['strong', 'strong', 'on']);
    await tapAndSettle(tester, find.byKey(const Key('step-0-1')));
    expect(stepLabels(tester, 0), ['strong', 'off', 'on']);

    await tapAndSettle(tester, inside('layer-hits-1', Icons.add));
    expect(stepLabels(tester, 1), ['strong', 'on', 'on']);

    await tapAndSettle(tester, find.byKey(const Key('layer-on-1')));
    expect(
      tester
          .widget<Switch>(
            find.descendant(
              of: find.byKey(const Key('layer-on-1')),
              matching: find.byType(Switch),
            ),
          )
          .value,
      isFalse,
    );

    final slider = find.byKey(const Key('layer-volume-0'));
    await tester.ensureVisible(slider);
    await tester.tapAt(tester.getTopLeft(slider) + const Offset(30, 24));
    await tester.pumpAndSettle();
    expect(tester.widget<RoundSlider>(slider).value, lessThan(0.5));

    await tapAndSettle(tester, inside('loop-cycle', Icons.add));
    expect(
      find.descendant(
        of: find.byKey(const Key('loop-cycle')),
        matching: find.text('3'),
      ),
      findsOneWidget,
    );

    await tapAndSettle(tester, inside('loop-tempo', Icons.add));
    expect(find.text('91'), findsOneWidget);
    expect(find.text('Changed, not saved yet'), findsNothing);
    expect(find.text('Not in your library yet'), findsOneWidget);
  });

  testWidgets('choosing a sound and a note', (tester) async {
    await pumpEditor(tester, loop: mine('m1'), existing: true);
    await tapAndSettle(tester, find.byKey(const Key('layer-sound-1')));
    await tapAndSettle(
      tester,
      find.byKey(const Key('pick-sound-factory-bell')),
    );
    expect(find.text('missing sound'), findsNothing);
    expect(
      find.bySemanticsLabel(
        RegExp('Layer 2 sound: .*Bell', caseSensitive: false),
      ),
      findsOneWidget,
    );

    await tapAndSettle(tester, find.byKey(const Key('layer-note-0')));
    await tester.tap(find.byKey(const Key('note-name-0'))); // C
    await tester.pump();
    await tester.tap(inside('note-octave', Icons.remove));
    await tester.pump();
    expect(find.text('Note C3'), findsOneWidget);
    await tapAndSettle(tester, find.byKey(const Key('note-ok')));
    expect(
      find.descendant(
        of: find.byKey(const Key('layer-note-0')),
        matching: find.text('C3'),
      ),
      findsOneWidget,
    );
    expect(find.text('Changed, not saved yet'), findsOneWidget);
  });

  testWidgets('add and remove layers within 2..4', (tester) async {
    await pumpEditor(tester);
    expect(find.byKey(const Key('layer-remove-0')), findsNothing);
    await tapAndSettle(tester, find.byKey(const Key('loop-add-layer')));
    await tapAndSettle(tester, find.byKey(const Key('loop-add-layer')));
    expect(find.byKey(const Key('layer-3')), findsOneWidget);
    expect(find.byKey(const Key('loop-add-layer')), findsNothing);
    expect(find.text('A loop has at most 4 layers.'), findsOneWidget);
    // A new layer plays A4.
    expect(
      find.descendant(
        of: find.byKey(const Key('layer-note-3')),
        matching: find.text('A4'),
      ),
      findsOneWidget,
    );
    await tapAndSettle(tester, find.byKey(const Key('layer-remove-0')));
    await tapAndSettle(tester, find.byKey(const Key('layer-remove-0')));
    expect(find.byKey(const Key('layer-2')), findsNothing);
    expect(find.byKey(const Key('layer-remove-0')), findsNothing);
  });

  testWidgets('Play sends the loop, edits while playing are sent, Stop', (
    tester,
  ) async {
    await pumpEditor(tester);
    final play = find.byKey(const Key('loop-play'));
    expect(find.descendant(of: play, matching: find.text('Play')), findsOne);
    await tapAndPump(tester, play);
    expect(playback.played, hasLength(1));
    expect(find.descendant(of: play, matching: find.text('Stop')), findsOne);

    await tapAndPump(tester, find.byKey(const Key('step-0-2')));
    expect(playback.played, hasLength(2));
    expect(
      stepMark(loopLayer(playback.played.last, 0).pattern.steps[2]),
      StepMark.accent,
    );
    expect(
      playback.played.last.scenes[1].layers,
      playback.played.last.scenes[0].layers,
    );

    await tapAndSettle(tester, play);
    expect(playback.commands.last, 'stop');
    expect(find.descendant(of: play, matching: find.text('Play')), findsOne);
  });

  testWidgets('the app going to the background stops the loop', (tester) async {
    await pumpEditor(tester);
    await tapAndPump(tester, find.byKey(const Key('loop-play')));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await tester.pump();
    expect(playback.commands.last, 'stop');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });

  testWidgets('save a copy, then open a factory loop as a new copy', (
    tester,
  ) async {
    await pumpEditor(tester);
    await tester.enterText(find.byKey(const Key('loop-name')), 'Groove');
    await tapAndSettle(tester, find.byKey(const Key('loop-save')));
    expect(loops.snapshot.value.items.single.name, 'Groove');
    expect(find.text('Saved'), findsOneWidget);

    await tapAndSettle(tester, find.byKey(const Key('step-0-0')));
    await tapAndSettle(tester, find.byKey(const Key('loop-open')));
    expect(
      find.byKey(Key('open-mine-${loops.snapshot.value.items.single.id}')),
      findsOneWidget,
    );
    await tapAndSettle(
      tester,
      find.byKey(const Key('open-factory-factory-loop-5-4')),
    );
    // Unsaved changes: Cancel keeps them.
    await tapAndSettle(tester, find.byKey(const Key('discard-cancel')));
    expect(find.text('Groove'), findsWidgets);
    await tapAndSettle(tester, find.byKey(const Key('loop-open')));
    await tapAndSettle(
      tester,
      find.byKey(const Key('open-factory-factory-loop-5-4')),
    );
    await tapAndSettle(tester, find.byKey(const Key('discard-confirm')));
    expect(find.text('Five against four copy'), findsOneWidget);
    expect(stepLabels(tester, 0), hasLength(5));
  });

  testWidgets('a saved loop opened again edits in place', (tester) async {
    await pumpEditor(tester, loop: mine('m1'), existing: true);
    expect(find.text('Saved'), findsOneWidget);
    await tapAndSettle(tester, find.byKey(const Key('step-0-0')));
    await tapAndSettle(tester, find.byKey(const Key('loop-save')));
    expect(loops.snapshot.value.items.single.id, 'm1');
    expect(
      stepMark(
        loopLayer(
          loops.snapshot.value.items.single.document,
          0,
        ).pattern.steps[0],
      ),
      StepMark.off,
    );
  });

  testWidgets('leaving with an unsaved loop asks first', (tester) async {
    await pumpEditor(tester, loop: mine('m1'), existing: true);
    await tapAndSettle(tester, find.byKey(const Key('step-0-0')));
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Save this loop before leaving?'), findsOneWidget);
    await tapAndSettle(tester, find.byKey(const Key('leave-save')));
    expect(find.byKey(const Key('go')), findsOneWidget);
    expect(
      loops.snapshot.value.items.single.document,
      isNot(mine('m1').document),
    );
  });

  testWidgets('the Arrangement tab shows a placeholder by default', (
    tester,
  ) async {
    await pumpEditor(tester, tab: EditorTab.arrangement);
    expect(
      find.text('Chain loops into a backing track. Planned.'),
      findsOneWidget,
    );
  });

  testWidgets('a panel built outside gets the shell: position and openLoop', (
    tester,
  ) async {
    EditorShell? shell;
    await pumpEditor(
      tester,
      tab: EditorTab.arrangement,
      arrangementPanel: (context, s) {
        shell = s;
        return const Text('my arrangement panel');
      },
    );
    expect(find.text('my arrangement panel'), findsOneWidget);
    expect(shell!.position.value.playing, isFalse);
    await shell!.openLoop(factoryLoops[2], existing: false);
    await tester.pumpAndSettle();
    expect(find.text('Three layers copy'), findsOneWidget);
    expect(find.byKey(const Key('layer-2')), findsOneWidget);
  });
}
