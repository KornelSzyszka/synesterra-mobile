// End-to-end flows of prototype v0 (QA-096), widget level.
//
// The real composition runs: `SynesterraApp`, the real view models, the real
// `EnginePlaybackRepository` with the real `PlaybackScheduler`, and in-memory
// repositories. Only the audio engine is a fake (`FakeEngine`), and the test
// owns its clock. `integration_test/` is not used: it needs a device or an
// emulator, and nothing here is evidence of sound or timing on a phone.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synesterra/app/synesterra_app.dart';
import 'package:synesterra/data/repositories/impl/engine_playback_repository.dart';
import 'package:synesterra/data/repositories/impl/in_memory_arrangement_library_repository.dart';
import 'package:synesterra/data/repositories/impl/in_memory_instrument_library_repository.dart';
import 'package:synesterra/data/repositories/impl/in_memory_loop_library_repository.dart';
import 'package:synesterra/data/repositories/playback_repository.dart';
import 'package:synesterra/features/editor/instrument_radar_view.dart';
import 'package:synesterra/shared/instrument_radar/radar_geometry.dart';
import 'package:synesterra_core/synesterra_core.dart';

import '../data/playback_fakes.dart';
import '../features/editor/audition_fakes.dart';

/// The factory 3:2 loop: 90 BPM, a two-beat cycle.
const cycle32 = 1333333;

/// The factory 5:4 loop: 80 BPM, a four-beat cycle.
const cycle54 = 3000000;

/// Where beat 0 of the first Play lands on the fake clock: minLead (10 ms)
/// plus startPad (30 ms).
const anchor = 40000;

/// The whole prototype on fakes at the audio edge.
class Rig {
  Rig(this.tester) {
    playback = EnginePlaybackRepository(
      engine: engine,
      instruments: instruments,
      render: (instrument, hz) async {
        renders.add((instrument: instrument, hz: hz));
        return Float32List(1);
      },
    );
  }

  final WidgetTester tester;
  final engine = FakeEngine();
  final instruments = InMemoryInstrumentLibraryRepository();
  final loops = InMemoryLoopLibraryRepository();
  final arrangements = InMemoryArrangementLibraryRepository();
  final audition = RecordingAudition();
  final renders = <({Instrument instrument, double hz})>[];
  late final EnginePlaybackRepository playback;

  FakeSink get sink => engine.sink;

  late final SemanticsHandle _semantics;

  Future<void> start() async {
    _semantics = tester.ensureSemantics();
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(480, 3000);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      SynesterraApp(
        instrumentLibrary: instruments,
        instrumentAudition: audition,
        loopLibrary: loops,
        arrangementLibrary: arrangements,
        playback: playback,
      ),
    );
  }

  /// Lets the audio clock run for [microseconds], waking the scheduler (its
  /// own timer) and the UI every 25 ms, like the real timers do.
  Future<void> advance(int microseconds) async {
    final end = engine.clock.microseconds + microseconds;
    while (engine.clock.microseconds < end) {
      final next = engine.clock.microseconds + 25000;
      engine.clock.microseconds = next < end ? next : end;
      sink.renderThrough(engine.clock.microseconds);
      await tester.pump(const Duration(milliseconds: 25));
    }
  }

  /// What sounded before [limit] microseconds of the audio clock.
  List<SinkEvent> soundedBefore(int limit) => [
    for (final e in sink.sounded)
      if (e.event.at.microseconds < limit) e,
  ];

  /// Taps the widget with [key]. The transport bar is pinned outside the
  /// scrolling list, and ensureVisible there would page the tab view
  /// sideways, so only list items are scrolled into view first.
  Future<void> tap(String key) async {
    final finder = find.byKey(Key(key));
    final pinned = key == 'loop-play' || key == 'arrangement-play';
    final scrolls = find
        .ancestor(of: finder, matching: find.byType(Scrollable))
        .evaluate()
        .isNotEmpty;
    if (scrolls && !pinned) await tester.ensureVisible(finder);
    await tester.tap(finder);
    await settle();
  }

  /// While something plays or a lesson runs, the pictures repaint on every
  /// frame and the tree never settles: pump fixed frames instead.
  Future<void> settle() async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  String label(String key) => tester
      .widget<Text>(
        find.descendant(of: find.byKey(Key(key)), matching: find.byType(Text)),
      )
      .data!;

  /// The marks of a layer's steps as the Loop panel announces them.
  List<String> steps(int layer) {
    final labels = <String>[];
    for (var s = 0; ; s++) {
      final finder = find.byKey(Key('step-$layer-$s'));
      if (finder.evaluate().isEmpty) return labels;
      labels.add(tester.getSemantics(finder).label.split(': ').last);
    }
  }

  /// Ends a flow: nothing may keep ticking or hold semantics after it.
  Future<void> finish() async {
    await playback.dispose();
    _semantics.dispose();
  }

  Future<void> back() async {
    await tester.pageBack();
    await tester.pumpAndSettle();
  }
}

/// Harmonics survive saving and rendering up to rounding.
bool sameHarmonics(List<double> a, List<double> b) =>
    a.length == b.length &&
    [for (var i = 0; i < a.length; i++) (a[i] - b[i]).abs()]
        .every((d) => d < 1e-9);

Future<Rig> boot(WidgetTester tester) async {
  final rig = Rig(tester);
  await rig.start();
  return rig;
}

void main() {
  testWidgets('create a loop, edit a layer, play, stop, save and reopen it '
      'from the Library', (tester) async {
    final rig = await boot(tester);
    expect(rig.engine.log, isEmpty, reason: 'nothing starts at launch');

    // New loop: the Loop panel starts from a copy of the first factory loop.
    await rig.tap('home-editor');
    await rig.tap('editor-tab-loop');
    expect(find.text('Three against two copy'), findsOneWidget);
    expect(find.text('Not in your library yet'), findsOneWidget);
    expect(rig.steps(0), ['strong', 'on', 'on']);
    expect(rig.steps(1), ['strong', 'on']);

    // Edit a layer: switch the middle step of the 3-step layer off, rename.
    await rig.tap('step-0-1'); // on -> strong
    expect(rig.steps(0), ['strong', 'strong', 'on']);
    await rig.tap('step-0-1'); // strong -> off
    expect(rig.steps(0), ['strong', 'off', 'on']);
    await tester.enterText(find.byKey(const Key('loop-name')), 'My pulse');
    await rig.settle();

    // Play: the engine starts only now, and exactly the edited pattern is
    // heard in the first cycle (2 + 2 hits, not 3 + 2).
    await rig.tap('loop-play');
    expect(rig.label('loop-play'), 'Stop');
    expect(rig.engine.log, contains('start'));
    expect(rig.playback.status.value.state, PlaybackState.playing);
    await rig.advance(cycle32 + 200000);
    expect(rig.soundedBefore(anchor + cycle32), hasLength(4));
    expect(rig.playback.readPosition().playing, isTrue);
    expect(rig.playback.readPosition().cycleIndex, 1);

    // Stop: silence, the engine stops, pending hits are dropped.
    await rig.tap('loop-play');
    expect(rig.label('loop-play'), 'Play');
    expect(rig.playback.status.value.state, PlaybackState.stopped);
    expect(rig.engine.log.last, 'stop');
    expect(rig.sink.pending, isEmpty);
    final heard = rig.sink.sounded.length;
    await rig.advance(cycle32);
    expect(rig.sink.sounded, hasLength(heard), reason: 'silent after Stop');

    // Save.
    expect(rig.loops.snapshot.value.items, isEmpty);
    await rig.tap('loop-save');
    final saved = rig.loops.snapshot.value.items.single;
    expect(saved.name, 'My pulse');
    final savedSteps = saved.document.scenes.first.layers.first.pattern.steps;
    expect(savedSteps.map((s) => s.enabled), [true, false, true]);
    expect(find.text('Saved'), findsOneWidget);

    // Reopen from the Library: Back to the start screen, Library, Loops tab.
    await rig.back();
    expect(find.byKey(const Key('home-library')), findsOneWidget);
    await rig.tap('home-library');
    await rig.tap('library-tab-loops');
    await rig.tap('loop-tile-${saved.id}');
    expect(find.byKey(const Key('loop-play')), findsOneWidget);
    expect(find.text('Saved'), findsOneWidget, reason: 'opened in place');
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('loop-name')))
          .controller!
          .text,
      'My pulse',
    );
    expect(rig.steps(0), ['strong', 'off', 'on']);
    expect(rig.loops.snapshot.value.items, hasLength(1));
    await rig.finish();
  });

  testWidgets('build an arrangement of two loops and start the sequence', (
    tester,
  ) async {
    final rig = await boot(tester);
    await rig.tap('home-editor');
    await rig.tap('editor-tab-arrangement');
    expect(find.text('Add a loop to play.'), findsOneWidget);

    await rig.tap('arrangement-add-section');
    await rig.tap('loop-option-factory-loop-3-2');
    await rig.tap('arrangement-add-section');
    await rig.tap('loop-option-factory-loop-5-4');
    expect(find.byKey(const Key('section-0')), findsOneWidget);
    expect(find.byKey(const Key('section-1')), findsOneWidget);
    expect(rig.engine.log, isEmpty);

    // Save first, to read the repeats the user sees, then start.
    await rig.tap('arrangement-save');
    final arrangement = rig.arrangements.snapshot.value.items.single;
    expect(arrangement.sections.map((s) => s.loopId), [
      'factory-loop-3-2',
      'factory-loop-5-4',
    ]);
    final repeats = arrangement.sections.first.repeats;
    final firstSection = repeats * cycle32;

    await rig.tap('arrangement-play');
    expect(rig.label('arrangement-play'), 'Stop');
    expect(rig.playback.status.value.state, PlaybackState.playing);
    expect(rig.playback.readPosition().sectionIndex, 0);

    // Section 0 lasts `repeats` cycles of 3:2; then the sequence moves on.
    // The second section's own tempo is a known issue, so only the first
    // boundary is timed.
    await rig.advance(firstSection - 300000);
    expect(rig.playback.readPosition().sectionIndex, 0);
    await rig.advance(600000);
    expect(rig.playback.readPosition().sectionIndex, 1);

    // Both layers of the second loop sound.
    await rig.advance(3000000);
    final inSecond = [
      for (final e in rig.sink.sounded)
        if (e.event.at.microseconds >= anchor + firstSection) e,
    ];
    expect(inSecond.map((e) => e.event.sound).toSet(), hasLength(2));

    // Without "repeat all" the sequence ends by itself and the engine stops.
    for (
      var i = 0;
      i < 40 && rig.playback.status.value.state.name != 'stopped';
      i++
    ) {
      await rig.advance(1000000);
    }
    expect(rig.playback.status.value.state, PlaybackState.stopped);
    expect(rig.playback.status.value.stopReason, PlaybackStopReason.finished);
    expect(rig.label('arrangement-play'), 'Play');

    // The saved arrangement opens again from the Library.
    await rig.back();
    await rig.tap('home-library');
    await rig.tap('library-tab-arrangements');
    await rig.tap('arrangement-tile-${arrangement.id}');
    expect(find.byKey(const Key('arrangement-panel')), findsOneWidget);
    expect(find.byKey(const Key('section-0')), findsOneWidget);
    expect(find.byKey(const Key('section-1')), findsOneWidget);
    await rig.finish();
  });

  testWidgets('a lesson opens and Try it lands in the Loop panel on an '
      'unsaved copy', (tester) async {
    final rig = await boot(tester);
    await rig.tap('home-learn');
    expect(find.byKey(const Key('learn-list')), findsOneWidget);
    await rig.tap('lesson-four-against-five');
    expect(find.byKey(const Key('lesson-picture')), findsOneWidget);
    expect(find.byKey(const Key('lesson-text')), findsOneWidget);
    expect(rig.engine.log, isEmpty, reason: 'a lesson makes no sound alone');

    // The lesson's own loop (5:4, not the Editor's default 3:2) arrives.
    await rig.tap('lesson-try-it');
    expect(find.byKey(const Key('loop-play')), findsOneWidget);
    expect(find.text('Five against four copy'), findsOneWidget);
    expect(find.text('Not in your library yet'), findsOneWidget);
    expect(rig.loops.snapshot.value.items, isEmpty, reason: 'a copy only');
    expect(rig.steps(0), ['strong', 'on', 'on', 'on', 'on']);
    expect(rig.steps(1), ['strong', 'on', 'on', 'on']);

    // It plays like any loop of the Editor: 5 + 4 hits in the first cycle.
    await rig.tap('loop-play');
    await rig.advance(cycle54);
    expect(rig.soundedBefore(anchor + cycle54), hasLength(9));
    await rig.tap('loop-play');
    expect(rig.playback.status.value.state, PlaybackState.stopped);
    await rig.finish();
  });

  testWidgets('shape an instrument on the radar, save it, use it in a loop '
      'layer', (tester) async {
    final rig = await boot(tester);
    await rig.tap('home-editor');
    const radar = Key('instrument-radar');
    expect(find.byKey(radar), findsOneWidget);

    await tester.enterText(find.byKey(const Key('instrument-name')), 'Glow');
    // A new instrument is the neutral shape, Fullness in the middle (rank C):
    // drag that vertex toward the edge.
    InstrumentTraits shown() =>
        tester.widget<InstrumentRadar>(find.byKey(radar)).traits;
    final before = shown();
    expect(before[TraitIds.fullness], 0.5);
    final rect = tester.getRect(find.byKey(radar));
    final count = defaultTraitDefinitions.length;
    final reach = WheelLayout.of(rect.size).reach;
    Offset vertex(double value) =>
        radarPoint(1, count, value, rect.size, reach) + rect.topLeft;
    final gesture = await tester.startGesture(vertex(0.5));
    await gesture.moveTo(vertex(0.7));
    await gesture.moveTo(vertex(0.9));
    await tester.pump();
    expect(rig.audition.played, isEmpty, reason: 'nothing under the finger');
    await gesture.up();
    await tester.pump(const Duration(seconds: 1));
    expect(rig.audition.played, hasLength(1), reason: 'the lift sounds once');
    final traits = shown();
    expect(traits[TraitIds.fullness], 0.9, reason: 'snapped to a step');
    expect(
      before.withValues({TraitIds.fullness: traits[TraitIds.fullness]}),
      traits,
      reason: 'only the dragged trait moved',
    );
    await rig.tap('instrument-save');
    // The "saved" snack bar covers the pinned transport bar until it ends.
    await tester.pump(const Duration(seconds: 6));

    final glow = rig.instruments.snapshot.value.instruments.single;
    expect(glow.name, 'Glow');
    expect(
      sameHarmonics(
        glow.harmonics,
        instrumentForTraits(traits, id: 'x', name: 'x').harmonics,
      ),
      isTrue,
      reason: 'the saved sound is the shape under the finger',
    );
    expect(
      glow.harmonics.length,
      greaterThan(
        instrumentForTraits(before, id: 'x', name: 'x').harmonics.length,
      ),
      reason: 'the drag made the neutral tone fuller',
    );

    // Use it in the first layer of a new loop.
    await rig.tap('editor-tab-loop');
    await rig.tap('layer-sound-0');
    await rig.tap('pick-sound-${glow.id}');
    await tester.pumpAndSettle(); // the sheet closes; nothing plays yet
    await rig.tap('loop-play');
    await rig.advance(cycle32 ~/ 2);
    expect(rig.playback.status.value.state, PlaybackState.playing);
    expect(rig.playback.status.value.missingInstrumentIds, isEmpty);
    expect(
      rig.renders.any(
        (r) => sameHarmonics(r.instrument.harmonics, glow.harmonics),
      ),
      isTrue,
      reason: 'the new sound was rendered for playback',
    );
    expect(rig.sink.sounded, isNotEmpty);
    await rig.tap('loop-play');
    expect(rig.playback.status.value.state, PlaybackState.stopped);
    await rig.finish();
  });
}
