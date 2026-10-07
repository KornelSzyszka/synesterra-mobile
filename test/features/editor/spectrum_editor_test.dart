import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synesterra/app/synesterra_app.dart';
import 'package:synesterra/data/repositories/impl/in_memory_instrument_library_repository.dart';
import 'package:synesterra/features/editor/instrument_editor_view_model.dart';
import 'package:synesterra/features/editor/spectrum_editor.dart';
import 'package:synesterra/features/editor/instrument_panel.dart';

import 'audition_fakes.dart';

late RecordingAudition audition;

Future<void> openEditor(
  WidgetTester tester, {
  Size size = const Size(800, 3200),
  int harmonics = 8,
  bool prepare = true,
}) async {
  // The technical controls are hidden in v1; these tests still cover them.
  showTechnicalControls = true;
  addTearDown(() => showTechnicalControls = false);
  tester.view
    ..devicePixelRatio = 1
    ..physicalSize = size;
  addTearDown(tester.view.reset);
  audition = RecordingAudition();
  await tester.pumpWidget(
    SynesterraApp(
      instrumentLibrary: InMemoryInstrumentLibraryRepository(),
      instrumentAudition: audition,
    ),
  );
  await tester.tap(find.byKey(const Key('home-editor')));
  await tester.pumpAndSettle();
  if (!prepare) return;
  final increase = find.descendant(
    of: find.byKey(const Key('instrument-harmonics')),
    matching: find.byTooltip('Increase harmonics'),
  );
  for (var i = 1; i < harmonics; i++) {
    await tester.tap(increase);
    await tester.pump();
  }
  // Start from a known, flat shape so the drawn bars are easy to read.
  await tester.tap(find.byKey(const Key('spectrum-shape-saw')));
  await pastDelay(tester);
  audition.played.clear();
  audition.frequencies.clear();
}

Future<void> pastDelay(WidgetTester tester) => tester.pump(
  InstrumentEditorViewModel.auditionDelay + const Duration(milliseconds: 50),
);

Finder get chart => find.byKey(const Key('spectrum-chart'));

/// The vertical scrolling of the panel, not the horizontal tab pages.
Finder pageScrollable() => find
    .descendant(of: find.byType(ListView), matching: find.byType(Scrollable))
    .first;

/// The screen position of bar [index] at height [amplitude] (0..1).
Offset at(WidgetTester tester, int index, double amplitude, {int bars = 8}) {
  final rect = tester.getRect(chart);
  return Offset(
    rect.left + rect.width * (index + 0.5) / bars,
    rect.top + (rect.height - SpectrumEditor.labelHeight) * (1 - amplitude),
  );
}

List<double> last() => audition.played.last.harmonics;

void main() {
  testWidgets('the panel has a spectrum chart and says how to use it', (
    tester,
  ) async {
    await openEditor(tester);
    expect(chart, findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp(r'^Spectrum of 8 harmonics')),
      findsOneWidget,
    );
    expect(find.textContaining('Drag across the bars'), findsOneWidget);
  });

  testWidgets('a tap sets the bar under the finger', (tester) async {
    await openEditor(tester);

    await tester.tapAt(at(tester, 2, 0.6));
    await pastDelay(tester);

    expect(last()[2], closeTo(0.6, 0.02));
    expect(last()[0], 1, reason: 'other bars are untouched');
    expect(audition.played, hasLength(1));
  });

  testWidgets('a tap at the bottom edge sets the bar to 0', (tester) async {
    await openEditor(tester);

    await tester.tapAt(at(tester, 3, 0.0));
    await pastDelay(tester);

    expect(last()[3], 0);
  });

  testWidgets('dragging across bars draws them, then plays once', (
    tester,
  ) async {
    await openEditor(tester);

    final gesture = await tester.startGesture(at(tester, 1, 0.9));
    await gesture.moveTo(at(tester, 2, 0.7));
    await gesture.moveTo(at(tester, 3, 0.5));
    await gesture.moveTo(at(tester, 4, 0.3));
    expect(audition.played, isEmpty, reason: 'nothing plays while drawing');
    await gesture.up();
    await pastDelay(tester);

    expect(last()[1], closeTo(0.9, 0.02));
    expect(last()[2], closeTo(0.7, 0.02));
    expect(last()[3], closeTo(0.5, 0.02));
    expect(last()[4], closeTo(0.3, 0.02));
    expect(audition.played, hasLength(1));
  });

  testWidgets('a fast drag does not skip the bars in between', (tester) async {
    await openEditor(tester);

    final gesture = await tester.startGesture(at(tester, 0, 0.0));
    await gesture.moveTo(at(tester, 7, 1.0));
    await gesture.up();
    await pastDelay(tester);

    final bars = last();
    for (var i = 1; i < bars.length; i++) {
      expect(bars[i], greaterThan(bars[i - 1]), reason: 'bar $i');
    }
    expect(bars.first, 0);
    expect(bars.last, closeTo(1, 0.02));
  });

  testWidgets('dragging to the left draws leftwards', (tester) async {
    await openEditor(tester);

    final gesture = await tester.startGesture(at(tester, 6, 0.8));
    await gesture.moveTo(at(tester, 3, 0.2));
    await gesture.up();
    await pastDelay(tester);

    expect(last()[6], closeTo(0.8, 0.02));
    expect(last()[3], closeTo(0.2, 0.02));
    expect(last()[4], closeTo(0.4, 0.05));
  });

  testWidgets('the last touched bar is selected and tunable with the slider', (
    tester,
  ) async {
    await openEditor(tester);
    await tester.tapAt(at(tester, 4, 0.5));
    await pastDelay(tester);
    audition.played.clear();

    expect(find.text('Harmonic 5'), findsOneWidget);
    final slider = tester.widget<Slider>(
      find.descendant(
        of: find.byKey(const Key('spectrum-selected')),
        matching: find.byType(Slider),
      ),
    );
    expect(slider.value, closeTo(0.5, 0.02));

    slider.onChanged!(0.25);
    slider.onChangeEnd!(0.25);
    await pastDelay(tester);

    expect(last()[4], closeTo(0.25, 1e-9));
    expect(find.text('25%'), findsWidgets);
  });

  testWidgets('a quick shape redraws all bars and plays', (tester) async {
    await openEditor(tester);

    await tester.tap(find.byKey(const Key('spectrum-shape-square')));
    await pastDelay(tester);

    expect(last()[0], 1);
    expect(last()[1], 0);
    expect(last()[2], closeTo(1 / 3, 1e-9));
    expect(audition.played, hasLength(1));
  });

  testWidgets('every quick shape is offered', (tester) async {
    await openEditor(tester);
    for (final name in ['sine', 'saw', 'square', 'soft']) {
      expect(find.byKey(Key('spectrum-shape-$name')), findsOneWidget);
    }
  });

  testWidgets('the instrument cannot be silenced by drawing', (tester) async {
    await openEditor(tester, harmonics: 1);

    await tester.tapAt(at(tester, 0, 0.0, bars: 1));
    await pastDelay(tester);

    expect(audition.played.last.harmonics, [1]);
  });

  testWidgets('drawing marks the instrument as changed', (tester) async {
    await openEditor(tester);
    await tester.tapAt(at(tester, 2, 0.4));
    await tester.pump();
    expect(find.text('Unsaved changes'), findsOneWidget);
  });

  testWidgets('the Figure view follows the drawn spectrum', (tester) async {
    await openEditor(tester);
    await tester.tap(find.text('Figure'));
    await tester.pump();
    await tester.tapAt(at(tester, 5, 1.0));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('a strong EQ boost keeps the marks inside the chart', (
    tester,
  ) async {
    await openEditor(tester);
    final eq = find.descendant(
      of: find.byKey(const Key('instrument-eq-high')),
      matching: find.byType(Slider),
    );
    tester.widget<Slider>(eq).onChanged!(1);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('touching the chart draws instead of scrolling the page', (
    tester,
  ) async {
    await openEditor(tester, size: const Size(800, 600), prepare: false);
    final scrollable = pageScrollable();
    // The pad fills the middle of the screen and takes the gesture, so scroll
    // by dragging in the page margin, then bring the chart into view.
    while (chart.evaluate().isEmpty) {
      await tester.dragFrom(const Offset(4, 300), const Offset(0, -200));
      await tester.pump();
    }
    await tester.ensureVisible(chart);
    await tester.pump();
    final state = tester.state<ScrollableState>(scrollable);
    final before = state.position.pixels;
    expect(before, greaterThan(0), reason: 'the chart was below the fold');

    final gesture = await tester.startGesture(at(tester, 0, 0.3, bars: 1));
    await gesture.moveBy(const Offset(0, -60));
    await gesture.moveBy(const Offset(0, 90));
    await gesture.moveBy(const Offset(0, -60));
    await gesture.up();
    await pastDelay(tester);

    expect(state.position.pixels, before, reason: 'the page did not scroll');
    expect(audition.played, isNotEmpty, reason: 'it drew');
  });

  testWidgets('dragging elsewhere on the page still scrolls it', (
    tester,
  ) async {
    await openEditor(tester, size: const Size(800, 600), prepare: false);
    final state = tester.state<ScrollableState>(pageScrollable());
    expect(state.position.pixels, 0);

    await tester.drag(
      find.byKey(const Key('instrument-name')),
      const Offset(0, -200),
    );
    await tester.pump();

    expect(state.position.pixels, greaterThan(0));
  });
}
