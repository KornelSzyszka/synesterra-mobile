import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synesterra/shared/loop_view/loop_examples.dart';
import 'package:synesterra/shared/loop_view/loop_geometry.dart';
import 'package:synesterra/shared/loop_view/loop_painters.dart';
import 'package:synesterra/shared/loop_view/loop_view.dart';
import 'package:synesterra/shared/loop_view/loop_view_state.dart';
import 'package:synesterra/shared/loop_view/position_source.dart';
import 'package:synesterra/shared/theme/ground_palette.dart';
import 'package:synesterra/shared/theme/synesterra_theme.dart';

Future<void> pumpView(
  WidgetTester tester, {
  required LoopViewState state,
  required PositionSource source,
  LoopViewMode mode = LoopViewMode.circle,
  SynesterraPalette palette = SynesterraPalette.forest,
}) => tester.pumpWidget(
  MaterialApp(
    theme: synesterraTheme(palette),
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: 320,
          height: 420,
          child: LoopView(state: state, source: source, initialMode: mode),
        ),
      ),
    ),
  ),
);

/// The canvas drew a line from [a] to [b] (anywhere in the display list).
PaintPattern drawsLine(Offset a, Offset b) => paints
  ..something(
    (method, args) => method == #drawLine && args[0] == a && args[1] == b,
  );

/// The canvas drew a circle centred on [c] (anywhere in the display list).
PaintPattern drawsCircle(Offset c) =>
    paints..something((method, args) => method == #drawCircle && args[0] == c);

RenderCustomPaint canvasRender(WidgetTester tester) => tester
    .renderObject<RenderCustomPaint>(find.byKey(const ValueKey('loop-canvas')));

LoopViewState state32() => LoopViewState.fromDocument(exampleLoop32());

void main() {
  testWidgets('offers Circle, Timeline and Polygons and starts on Circle', (
    tester,
  ) async {
    await pumpView(tester, state: state32(), source: FakePositionSource());

    expect(find.text('Circle'), findsOneWidget);
    expect(find.text('Timeline'), findsOneWidget);
    expect(find.text('Polygons'), findsOneWidget);
    expect(
      tester
          .widget<CustomPaint>(find.byKey(const ValueKey('loop-canvas')))
          .painter,
      isA<CirclePainter>(),
    );
  });

  testWidgets('each painter sits in its own RepaintBoundary', (tester) async {
    await pumpView(tester, state: state32(), source: FakePositionSource());
    final canvas = find.byKey(const ValueKey('loop-canvas'));
    expect(
      find.ancestor(of: canvas, matching: find.byType(RepaintBoundary)),
      findsWidgets,
    );
  });

  testWidgets('switching views swaps the painter and keeps the source', (
    tester,
  ) async {
    final source = FakePositionSource();
    await pumpView(tester, state: state32(), source: source);

    Object? painter() => tester
        .widget<CustomPaint>(find.byKey(const ValueKey('loop-canvas')))
        .painter;

    await tester.tap(find.text('Timeline'));
    await tester.pump();
    expect(painter(), isA<TimelinePainter>());

    await tester.tap(find.text('Polygons'));
    await tester.pump();
    expect(painter(), isA<PolygonsPainter>());

    await tester.tap(find.text('Circle'));
    await tester.pump();
    expect(painter(), isA<CirclePainter>());
  });

  testWidgets('the fake position moves the timeline playhead', (tester) async {
    final source = FakePositionSource();
    await pumpView(
      tester,
      state: state32(),
      source: source,
      mode: LoopViewMode.timeline,
    );
    final layout = TimelineLayout(
      tester.getSize(find.byKey(const ValueKey('loop-canvas'))),
      2,
    );
    PaintPattern playheadAt(double position) {
      final x = timelineX(position, layout.left, layout.width);
      return drawsLine(Offset(x, layout.top), Offset(x, layout.bottom));
    }

    source.set(playing: true, cyclePosition: 0.25);
    await tester.pump();
    expect(canvasRender(tester), playheadAt(0.25));
    expect(canvasRender(tester), isNot(playheadAt(0.75)));

    source.set(playing: true, cyclePosition: 0.75);
    await tester.pump();
    expect(canvasRender(tester), playheadAt(0.75));
    expect(canvasRender(tester), isNot(playheadAt(0.25)));
  });

  testWidgets('the circle draws dots only for enabled steps', (tester) async {
    final state = LoopViewState(
      cycleBeats: 4,
      layers: [
        LoopLayerView(number: 1, colorIndex: 0, steps: [true, false, true]),
        LoopLayerView(number: 2, colorIndex: 1, steps: [true, true]),
      ],
    );
    await pumpView(tester, state: state, source: FakePositionSource());
    final layout = RingLayout(
      tester.getSize(find.byKey(const ValueKey('loop-canvas'))),
    );
    Offset dot(int index) => pointOnCircle(
      layout.center,
      ringRadius(0, 2, layout.outerRadius),
      playheadAngle(stepFraction(index, 3)),
    );

    expect(canvasRender(tester), drawsCircle(dot(0)));
    expect(canvasRender(tester), drawsCircle(dot(2)));
    expect(canvasRender(tester), isNot(drawsCircle(dot(1))));
  });

  testWidgets('the fake position rotates the circle playhead', (tester) async {
    final source = FakePositionSource();
    await pumpView(tester, state: state32(), source: source);
    final layout = RingLayout(
      tester.getSize(find.byKey(const ValueKey('loop-canvas'))),
    );
    PaintPattern playheadAt(double position) => drawsLine(
      layout.center,
      pointOnCircle(layout.center, layout.outerRadius, playheadAngle(position)),
    );

    source.set(playing: true, cyclePosition: 0.5);
    await tester.pump();
    expect(canvasRender(tester), playheadAt(0.5));
    expect(canvasRender(tester), isNot(playheadAt(0)));

    source.set(playing: true, cyclePosition: 0.0);
    await tester.pump();
    expect(canvasRender(tester), playheadAt(0));
  });

  testWidgets('the polygon dot travels with the position', (tester) async {
    final source = FakePositionSource();
    await pumpView(
      tester,
      state: state32(),
      source: source,
      mode: LoopViewMode.polygons,
    );
    final size = tester.getSize(find.byKey(const ValueKey('loop-canvas')));
    final cell = polygonCells(size, 2).first;
    final vertices = polygonVertices(cell.center, polygonRadius(cell), 3);

    source.set(playing: true, cyclePosition: 0);
    await tester.pump();
    final dot0 = polygonDotPoint(vertices, 0);
    expect(canvasRender(tester), drawsCircle(dot0));

    source.set(playing: true, cyclePosition: 0.5);
    await tester.pump();
    final dotHalf = polygonDotPoint(vertices, 0.5);
    expect(canvasRender(tester), drawsCircle(dotHalf));
  });

  testWidgets('semantics describe the loop and the state in words', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final source = FakePositionSource();
    await pumpView(tester, state: state32(), source: source);

    expect(
      find.bySemanticsLabel(RegExp('3 against 2.*circle.*Stopped')),
      findsOneWidget,
    );

    source.set(playing: true, cyclePosition: 0.1);
    await tester.pump();
    expect(
      find.bySemanticsLabel(RegExp('3 against 2.*circle.*Playing')),
      findsOneWidget,
    );

    await tester.tap(find.text('Polygons'));
    await tester.pump();
    expect(
      find.bySemanticsLabel(RegExp('3 against 2.*polygons.*Playing')),
      findsOneWidget,
    );
    handle.dispose();
  });

  testWidgets('layer identity is shown as numbers, not colour alone', (
    tester,
  ) async {
    await pumpView(tester, state: state32(), source: FakePositionSource());
    expect(find.text('01'), findsOneWidget);
    expect(find.text('02'), findsOneWidget);
  });

  testWidgets('works on all palettes and with the 5:4 loop', (tester) async {
    for (final palette in SynesterraPalette.values) {
      for (final mode in LoopViewMode.values) {
        await pumpView(
          tester,
          state: LoopViewState.fromDocument(exampleLoop54()),
          source: FakePositionSource(),
          mode: mode,
          palette: palette,
        );
        expect(tester.takeException(), isNull);
      }
    }
  });

  group('ArrangementStrip', () {
    final sections = [
      StripSection(label: 'Verse', repeats: 4),
      StripSection(label: 'Chorus', repeats: 2),
      StripSection(label: 'Gone', repeats: 1, missing: true),
    ];

    testWidgets('highlights the section index from the source', (tester) async {
      final handle = tester.ensureSemantics();
      final source = FakePositionSource();
      await tester.pumpWidget(
        MaterialApp(
          theme: synesterraTheme(SynesterraPalette.forest),
          home: Scaffold(
            body: ArrangementStrip(sections: sections, source: source),
          ),
        ),
      );
      expect(find.bySemanticsLabel(RegExp('not playing')), findsOneWidget);

      source.set(
        playing: true,
        cyclePosition: 0.5,
        cycleIndex: 1,
        sectionIndex: 1,
      );
      await tester.pump();
      expect(
        find.bySemanticsLabel(RegExp('Section 2 of 3, Chorus.*cycle 2 of 2')),
        findsOneWidget,
      );
      final strip = tester.widget<CustomPaint>(
        find.byKey(const ValueKey('arrangement-strip-canvas')),
      );
      expect(strip.painter, isA<ArrangementStripPainter>());
      handle.dispose();
    });

    test('section labels keep 4.5:1 on their capsules on every palette', () {
      for (final palette in SynesterraPalette.values) {
        final tokens = SynesterraTokens.forPalette(palette);
        List<Color> on({required bool current}) =>
            ArrangementStripPainter.labelGrounds(tokens, current: current);
        for (final (name, color, grounds) in [
          ('label', tokens.text, on(current: false)),
          ('current label', tokens.text, on(current: true)),
          ('missing label', tokens.muted, on(current: false)),
        ]) {
          expect(
            TextContrastPair(name, color, grounds).worstContrast,
            greaterThanOrEqualTo(4.5),
            reason: '${palette.name}: $name',
          );
        }
      }
    });

    test('a section needs 1..32 repeats, checked at runtime', () {
      for (final bad in [0, -1, 33]) {
        expect(
          () => StripSection(label: 'x', repeats: bad),
          throwsArgumentError,
          reason: '$bad',
        );
      }
      expect(StripSection(label: 'x', repeats: 1).repeats, 1);
      expect(StripSection(label: 'x', repeats: 32).repeats, 32);
    });

    test('progress through a section is cycle plus position over repeats', () {
      expect(
        sectionProgress(
          LoopPosition(playing: true, cyclePosition: 0.5, cycleIndex: 1),
          4,
        ),
        0.375,
      );
      expect(sectionProgress(LoopPosition.stopped, 4), 0);
      expect(
        sectionProgress(
          LoopPosition(playing: true, cyclePosition: 0.5, cycleIndex: 9),
          4,
        ),
        closeTo(0.375, 1e-12),
      );
    });
  });
}
