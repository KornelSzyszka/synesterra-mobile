import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synesterra/shared/loop_view/arrangement_ring.dart';
import 'package:synesterra/shared/loop_view/arrangement_ring_geometry.dart';
import 'package:synesterra/shared/loop_view/arrangement_strip.dart';
import 'package:synesterra/shared/loop_view/loop_geometry.dart';
import 'package:synesterra/shared/loop_view/position_source.dart';
import 'package:synesterra/shared/theme/ground_palette.dart';
import 'package:synesterra/shared/theme/synesterra_theme.dart';

final _sections = [
  StripSection(label: 'Verse', repeats: 4, layerSteps: const [3, 2]),
  StripSection(
    label: 'Chorus',
    repeats: 2,
    colorIndex: 1,
    layerSteps: const [5, 4],
  ),
  StripSection(label: 'Missing loop', repeats: 1, missing: true, colorIndex: 2),
];

Future<void> _pump(
  WidgetTester tester,
  PositionSource source, {
  List<StripSection>? sections,
  double width = 412,
  double textScale = 1,
  bool reduceMotion = false,
}) async {
  tester.view
    ..physicalSize = Size(width, 800)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: synesterraTheme(SynesterraPalette.graphite),
      home: MediaQuery(
        data: MediaQueryData(
          size: Size(width, 800),
          textScaler: TextScaler.linear(textScale),
          disableAnimations: reduceMotion,
        ),
        child: Scaffold(
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              ArrangementRing(sections: sections ?? _sections, source: source),
            ],
          ),
        ),
      ),
    ),
  );
}

ArrangementRingPainter _painter(WidgetTester tester) =>
    tester
            .widget<CustomPaint>(
              find.byKey(const ValueKey('arrangement-ring-canvas')),
            )
            .painter!
        as ArrangementRingPainter;

Size _canvasSize(WidgetTester tester) =>
    tester.getSize(find.byKey(const ValueKey('arrangement-ring-canvas')));

void main() {
  test('describeArrangement tells the structure', () {
    expect(
      describeArrangement(_sections),
      '3 sections: 1, Verse, 4 times; 2, Chorus, twice; '
      '3, missing loop, skipped.',
    );
    expect(
      describeArrangement([StripSection(label: 'Solo', repeats: 1)]),
      '1 section: 1, Solo, once.',
    );
  });

  testWidgets('announces the structure and the current section', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final source = FakePositionSource();
    await _pump(tester, source);
    expect(
      find.bySemanticsLabel(
        '3 sections: 1, Verse, 4 times; 2, Chorus, twice; '
        '3, missing loop, skipped.',
      ),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel('Arrangement of 3 sections, not playing.'),
      findsOneWidget,
    );
    source.set(cyclePosition: .5, cycleIndex: 1, sectionIndex: 1);
    await tester.pump();
    expect(
      find.bySemanticsLabel('Section 2 of 3, Chorus, cycle 2 of 2.'),
      findsOneWidget,
    );
    handle.dispose();
  });

  testWidgets('the light follows the position source, not a timer', (
    tester,
  ) async {
    final source = FakePositionSource();
    await _pump(tester, source);
    final painter = _painter(tester);
    final size = _canvasSize(tester);
    expect(painter.playheadPoint(size), isNull, reason: 'stopped');
    // Nothing animates on its own: no ticker.
    expect(tester.binding.transientCallbackCount, 0);

    final arcs = ringArcs([4, 2, 1]);
    final center = size.center(Offset.zero);
    final radius = painter.measures(size).radius;
    source.set(cyclePosition: .5, cycleIndex: 1, sectionIndex: 1);
    await tester.pump();
    expect(identical(_painter(tester), painter), isTrue, reason: 'no rebuild');
    final expected = pointOnCircle(
      center,
      radius,
      ringPlayheadAngle(arcs[1], .75),
    );
    expect(painter.playheadPoint(size)!.dx, closeTo(expected.dx, 1e-6));
    expect(painter.playheadPoint(size)!.dy, closeTo(expected.dy, 1e-6));
    await tester.pump(const Duration(seconds: 1));
    expect(painter.playheadPoint(size)!.dx, closeTo(expected.dx, 1e-6));
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('a missing section never holds the light', (tester) async {
    final source = FakePositionSource();
    await _pump(tester, source);
    source.set(sectionIndex: 2);
    await tester.pump();
    expect(_painter(tester).playheadPoint(_canvasSize(tester)), isNull);
    source.set(sectionIndex: 7);
    await tester.pump();
    expect(_painter(tester).playheadPoint(_canvasSize(tester)), isNull);
  });

  testWidgets('reduce motion moves the light once a cycle', (tester) async {
    final source = FakePositionSource();
    await _pump(tester, source, reduceMotion: true);
    final painter = _painter(tester);
    expect(painter.continuous, isFalse);
    final size = _canvasSize(tester);
    source.set(cyclePosition: .1, cycleIndex: 1, sectionIndex: 0);
    final early = painter.playheadPoint(size)!;
    source.set(cyclePosition: .9, cycleIndex: 1, sectionIndex: 0);
    expect(painter.playheadPoint(size), early);
    source.set(cyclePosition: 0, cycleIndex: 2, sectionIndex: 0);
    expect(painter.playheadPoint(size), isNot(early));
  });

  testWidgets('a ring of 1 and of 16 sections of 1..32 repeats paints', (
    tester,
  ) async {
    final source = FakePositionSource();
    for (final sections in [
      [
        StripSection(label: 'Only', repeats: 32, layerSteps: const [4, 3]),
      ],
      [
        for (var i = 0; i < 16; i++)
          StripSection(
            label: 'Loop $i with a rather long name',
            repeats: i == 0 ? 32 : (i % 4) + 1,
            missing: i == 5,
            colorIndex: i % 12,
            layerSteps: [i % 16 + 1, 2, 3, 1],
          ),
      ],
    ]) {
      await _pump(tester, source, sections: sections);
      for (var i = 0; i < sections.length; i++) {
        source.set(
          cyclePosition: .99,
          cycleIndex: sections[i].repeats - 1,
          sectionIndex: i,
        );
        await tester.pump();
      }
      expect(tester.takeException(), isNull);
    }
  });

  for (final textScale in [1.0, 1.5]) {
    testWidgets('fits 320 dp at text scale $textScale', (tester) async {
      final source = FakePositionSource();
      await _pump(tester, source, width: 320, textScale: textScale);
      source.set(cyclePosition: .3, cycleIndex: 0, sectionIndex: 0);
      await tester.pump();
      expect(tester.takeException(), isNull);
      final rect = tester.getRect(
        find.byKey(const ValueKey('arrangement-ring-canvas')),
      );
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(320));
      final m = _painter(tester).measures(rect.size);
      expect(m.innerRadius, greaterThan(0));
      expect(m.figureRadius, lessThan(m.radius));
      expect(m.radius, lessThan(m.labelRadius));
      expect(m.labelRadius, lessThan(rect.width / 2));
    });
  }

  testWidgets('uses no live blur', (tester) async {
    await _pump(tester, FakePositionSource());
    expect(find.byType(BackdropFilter), findsNothing);
  });

  test('numbers and the centre text keep 4.5:1 on every palette', () {
    for (final palette in SynesterraPalette.values) {
      final tokens = SynesterraTokens.forPalette(palette);
      for (final aura in tokens.layerColors) {
        final ground = GroundPalette.of(tokens, GroundTone.dark, aura);
        for (final (name, color, grounds) in [
          (
            'section number',
            ground.text,
            ArrangementRingPainter.numberGrounds(ground),
          ),
          (
            'centre number and loop',
            ground.text,
            ArrangementRingPainter.centreGrounds(ground),
          ),
          (
            'centre cycle',
            ground.muted,
            ArrangementRingPainter.centreGrounds(ground),
          ),
        ]) {
          expect(
            TextContrastPair(name, color, grounds).worstContrast,
            greaterThanOrEqualTo(4.5),
            reason: '${palette.name}: $name',
          );
        }
      }
    }
  });
}
