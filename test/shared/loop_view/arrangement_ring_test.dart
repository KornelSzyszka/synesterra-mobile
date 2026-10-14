import 'dart:math' as math;

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

  group('what the painter draws', () {
    final tokens = SynesterraTokens.forPalette(SynesterraPalette.graphite);
    final colors = ArrangementRingColors.of(
      GroundPalette.of(tokens, GroundTone.dark, tokens.layerColors[0]),
      tokens,
    );
    const size = Size.square(300);
    final sixteen = [
      for (var i = 0; i < 16; i++)
        StripSection(
          label: 'Loop $i',
          repeats: i == 0 ? 32 : (i % 4) + 1,
          missing: i == 5,
          colorIndex: i % 12,
          layerSteps: const [3, 2],
        ),
    ];

    ArrangementRingPainter painterFor(
      List<StripSection> sections, [
      LoopPosition? position,
    ]) => ArrangementRingPainter(
      sections: sections,
      source: FakePositionSource(position),
      colors: colors,
      labelStyle: const TextStyle(fontSize: 12.5),
      numberStyle: const TextStyle(fontSize: 26),
      captionStyle: const TextStyle(fontSize: 12.5),
    );

    List<_Arc> paintRing(List<StripSection> sections, LoopPosition position) {
      final canvas = _ArcRecorder();
      painterFor(sections, position).paint(canvas, size);
      return canvas.arcs;
    }

    final m = painterFor(sixteen).measures(size);
    final cap = (m.band / 2) / m.radius;

    /// The section bands: full band width, no blur, translucent, not grey.
    List<_Arc> bands(List<_Arc> arcs) => [
      for (final arc in arcs)
        if (arc.strokeWidth == m.band &&
            !arc.blurred &&
            arc.color.a < .5 &&
            !_same(arc.color.withValues(alpha: 1), colors.muted))
          arc,
    ];

    test('one band per loaded section, with the sweep from its repeats', () {
      final found = bands(paintRing(sixteen, LoopPosition.stopped));
      final expected = ringArcs([for (final s in sixteen) s.repeats]);
      expect(found, hasLength(15), reason: '16 sections, one missing');
      var k = 0;
      for (var i = 0; i < 16; i++) {
        if (i == 5) continue;
        expect(found[k].start, closeTo(expected[i].start + cap, 1e-9));
        expect(found[k].sweep, closeTo(expected[i].sweep - 2 * cap, 1e-9));
        expect(
          _same(
            found[k].color.withValues(alpha: 1),
            colors.layerColors[sixteen[i].colorIndex],
          ),
          isTrue,
          reason: 'section $i in its loop colour',
        );
        k++;
      }
    });

    test('one section is a single band almost around the ring', () {
      final found = bands(
        paintRing([
          StripSection(label: 'Only', repeats: 32),
        ], LoopPosition.stopped),
      );
      expect(found, hasLength(1));
      expect(found.single.sweep, greaterThan(6));
    });

    test('a missing loop is dashed in grey, stopped and while playing', () {
      List<_Arc>? whenStopped;
      // Stopped, then two moments in section 4 (before the missing one)
      // and two in section 10 (after it).
      for (final position in [
        LoopPosition.stopped,
        for (final (section, cycleIndex, cyclePosition) in [
          (3, 1, .5),
          (3, 3, .5),
          (9, 0, .25),
          (9, 1, .75),
        ])
          LoopPosition(
            playing: true,
            cyclePosition: cyclePosition,
            cycleIndex: cycleIndex,
            sectionIndex: section,
          ),
      ]) {
        final arcs = paintRing(sixteen, position);
        final missing = ringArcs([for (final s in sixteen) s.repeats])[5];
        final inside = [
          for (final arc in arcs)
            if (arc.start >= missing.start - 1e-9 &&
                arc.end <= missing.end + 1e-9)
              arc,
        ];
        expect(inside.length, greaterThan(1), reason: 'several dashes');
        for (final dash in inside) {
          expect(_same(dash.color.withValues(alpha: 1), colors.muted), isTrue);
          expect(dash.strokeWidth, lessThan(m.band));
          expect(dash.sweep, lessThan(missing.sweep / 3));
        }
        // The dashes run along the whole arc, evenly: from its start (inside
        // the round cap) to its end, one dash every two dash lengths, so
        // together they cover about half of it.
        final dashCap = (inside.first.strokeWidth / 2) / m.radius;
        final dash = 4 / m.radius;
        final from = missing.start + dashCap;
        final to = missing.end - dashCap;
        expect(inside.first.start, closeTo(from, 1e-9));
        for (var i = 1; i < inside.length; i++) {
          expect(
            inside[i].start - inside[i - 1].start,
            closeTo(2 * dash, 1e-9),
          );
        }
        expect(inside.last.end, lessThanOrEqualTo(to + 1e-9));
        expect(to - inside.last.start, lessThan(2 * dash));
        final covered = inside.fold<double>(0, (sum, d) => sum + d.sweep);
        final expectedCount = ((to - from) / (2 * dash)).ceil();
        expect(inside, hasLength(expectedCount));
        expect(covered / (to - from), inInclusiveRange(.3, .7));
        // While playing, the missing arc is drawn exactly as when stopped.
        whenStopped ??= inside;
        expect(inside, hasLength(whenStopped.length), reason: '$position');
        for (var i = 0; i < inside.length; i++) {
          expect(inside[i].start, closeTo(whenStopped[i].start, 1e-9));
          expect(inside[i].sweep, closeTo(whenStopped[i].sweep, 1e-9));
        }
      }
    });

    test('the current section glows, fills and has a gold rim', () {
      final expected = ringArcs([for (final s in sixteen) s.repeats]);
      final current = expected[3];
      final from = current.start + cap;
      final sweep = current.sweep - 2 * cap;
      // Section 4 plays 4 cycles; two moments in it.
      for (final (cycleIndex, cyclePosition) in [(1, .5), (3, .5)]) {
        final arcs = paintRing(
          sixteen,
          LoopPosition(
            playing: true,
            cyclePosition: cyclePosition,
            cycleIndex: cycleIndex,
            sectionIndex: 3,
          ),
        );
        final glows = [
          for (final a in arcs)
            if (a.blurred) a,
        ];
        expect(glows, hasLength(1));
        expect(glows.single.start, closeTo(from, 1e-9));
        expect(glows.single.sweep, closeTo(sweep, 1e-9));
        final gold = [
          for (final a in arcs)
            if (_same(a.color, colors.accent)) a,
        ];
        expect(gold, hasLength(1), reason: 'the rim');
        expect(gold.single.start, closeTo(from, 1e-9));
        expect(gold.single.sweep, closeTo(sweep, 1e-9));
        final fill = [
          for (final a in arcs)
            if (a.color.a > .9 && !_same(a.color, colors.accent)) a,
        ];
        expect(fill, hasLength(1), reason: 'the fill');
        // The fill ends at the light (the section start plus its
        // progress), held inside the band's round caps.
        final progress = (cycleIndex + cyclePosition) / 4;
        expect(fill.single.start, closeTo(from, 1e-9));
        expect(
          fill.single.sweep,
          closeTo(math.min(current.sweep * progress - cap, sweep), 1e-9),
          reason: 'cycle ${cycleIndex + 1} at $cyclePosition',
        );
        expect(
          _same(
            fill.single.color.withValues(alpha: 1),
            colors.layerColors[sixteen[3].colorIndex],
          ),
          isTrue,
        );
        // Played sections are dimmer than the ones to come, the current one
        // brighter.
        final found = bands(arcs);
        expect(found[0].color.a, lessThan(found[10].color.a));
        expect(found[3].color.a, greaterThan(found[10].color.a));
      }
    });
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

/// Paint keeps 8 bits per channel, so colours are compared at that depth.
bool _same(Color a, Color b) => a.toARGB32() == b.toARGB32();

class _Arc {
  _Arc(this.start, this.sweep, Paint paint)
    : color = paint.color,
      strokeWidth = paint.strokeWidth,
      blurred = paint.maskFilter != null;

  final double start;
  final double sweep;
  final Color color;
  final double strokeWidth;
  final bool blurred;

  double get end => start + sweep;
}

/// A canvas that records `drawArc` and ignores everything else.
class _ArcRecorder implements Canvas {
  final arcs = <_Arc>[];

  @override
  void drawArc(
    Rect rect,
    double startAngle,
    double sweepAngle,
    bool useCenter,
    Paint paint,
  ) => arcs.add(_Arc(startAngle, sweepAngle, paint));

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
