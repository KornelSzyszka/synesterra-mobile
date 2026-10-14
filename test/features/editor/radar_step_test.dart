import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synesterra/data/repositories/impl/in_memory_instrument_library_repository.dart';
import 'package:synesterra/features/editor/instrument_editor_view_model.dart';
import 'package:synesterra/features/editor/instrument_panel.dart';
import 'package:synesterra/features/editor/instrument_radar_view.dart';
import 'package:synesterra/shared/instrument_radar/radar_geometry.dart';
import 'package:synesterra/shared/theme/synesterra_theme.dart';
import 'package:synesterra_core/synesterra_core.dart';

import 'audition_fakes.dart';

/// Drags spoke [index] of the wheel found by [wheel] from [from] to [to] in
/// small moves, then lifts.
Future<void> dragSpoke(
  WidgetTester tester,
  Finder wheel,
  int index,
  double from,
  double to,
) async {
  final rect = tester.getRect(wheel);
  final reach = WheelLayout.of(rect.size).reach;
  Offset at(double value) =>
      radarPoint(index, 6, value, rect.size, reach) + rect.topLeft;
  final gesture = await tester.startGesture(at(from));
  for (var i = 1; i <= 24; i++) {
    await gesture.moveTo(at(from + (to - from) * i / 24));
    await tester.pump();
  }
  await gesture.up();
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  testWidgets('the wheel ticks once for each step a vertex snaps to, and '
      'never for a tap', (tester) async {
    var traits = InstrumentTraits.neutral();
    var ticks = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: synesterraTheme(SynesterraPalette.graphite),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => InstrumentRadar(
              traits: traits,
              color: Colors.teal,
              onChanged: (id, value) =>
                  setState(() => traits = traits.withValues({id: value})),
              onRelease: () {},
              onStep: () => ticks++,
            ),
          ),
        ),
      ),
    );
    final wheel = find.byType(InstrumentRadar);
    await dragSpoke(tester, wheel, 2, 0.5, 0.8);
    expect(traits[TraitIds.warmth], 0.8);
    expect(ticks, 3, reason: 'C to C+, B and B+');

    final rect = tester.getRect(wheel);
    await tester.tapAt(
      radarPoint(2, 6, 0.8, rect.size, WheelLayout.of(rect.size).reach) +
          rect.topLeft,
    );
    await tester.pump(const Duration(seconds: 1));
    expect(ticks, 3);
  });

  testWidgets('pointer moves between frames: one tick and one change per '
      'step crossed, none within a step', (tester) async {
    var traits = InstrumentTraits.neutral();
    var ticks = 0;
    final changes = <double>[];
    var releases = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: synesterraTheme(SynesterraPalette.graphite),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => InstrumentRadar(
              traits: traits,
              color: Colors.teal,
              onChanged: (id, value) {
                changes.add(value);
                setState(() => traits = traits.withValues({id: value}));
              },
              onRelease: () => releases++,
              onStep: () => ticks++,
            ),
          ),
        ),
      ),
    );
    final rect = tester.getRect(find.byType(InstrumentRadar));
    final reach = WheelLayout.of(rect.size).reach;
    Offset at(double v) => radarPoint(2, 6, v, rect.size, reach) + rect.topLeft;

    // No frame between the moves: the wheel has not rebuilt yet.
    final gesture = await tester.startGesture(at(0.5));
    for (final v in [0.52, 0.54, 0.6, 0.62, 0.64, 0.7, 0.72, 0.68]) {
      await gesture.moveTo(at(v));
    }
    await gesture.up();
    expect(ticks, 2, reason: 'C to C+, then B');
    expect(changes, [0.6, 0.7]);
    expect(releases, 1);
    await tester.pump(const Duration(seconds: 1));
    expect(traits[TraitIds.warmth], 0.7);

    // Back down within one gesture, still without frames.
    final back = await tester.startGesture(at(0.7));
    for (final v in [0.66, 0.6, 0.58, 0.61]) {
      await back.moveTo(at(v));
    }
    await back.cancel();
    expect(ticks, 3);
    expect(changes, [0.6, 0.7, 0.6]);
    expect(releases, 1, reason: 'a cancelled drag stays silent');
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('two screen-reader steps before a frame move two steps', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    var traits = InstrumentTraits.neutral();
    final changes = <double>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: synesterraTheme(SynesterraPalette.graphite),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => InstrumentRadar(
              traits: traits,
              color: Colors.teal,
              onChanged: (id, value) {
                changes.add(value);
                setState(() => traits = traits.withValues({id: value}));
              },
              onRelease: () {},
            ),
          ),
        ),
      ),
    );
    final air = find.semantics.byLabel('Air');
    tester.semantics.performAction(air, SemanticsAction.increase);
    tester.semantics.performAction(air, SemanticsAction.increase);
    expect(changes, [0.6, 0.7]);
    await tester.pumpAndSettle();
    expect(traits[TraitIds.air], 0.7);
    handle.dispose();
  });

  testWidgets('the panel passes its step feedback to the wheel', (
    tester,
  ) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(412, 900);
    addTearDown(tester.view.reset);
    final vm = InstrumentEditorViewModel(
      repository: InMemoryInstrumentLibraryRepository(),
      audition: RecordingAudition(),
    );
    addTearDown(vm.dispose);
    var ticks = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: synesterraTheme(SynesterraPalette.graphite),
        home: Scaffold(
          body: InstrumentPanel(viewModel: vm, stepFeedback: () => ticks++),
        ),
      ),
    );
    await dragSpoke(tester, find.byType(InstrumentRadar), 5, 0.5, 0.2);
    expect(vm.traits[TraitIds.length], 0.2);
    expect(ticks, 3);
  });
}
