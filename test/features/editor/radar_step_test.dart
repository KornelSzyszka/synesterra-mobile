import 'package:flutter/material.dart';
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
