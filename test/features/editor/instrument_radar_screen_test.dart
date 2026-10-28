import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synesterra/data/repositories/impl/in_memory_instrument_library_repository.dart';
import 'package:synesterra/data/repositories/impl/in_memory_loop_library_repository.dart';
import 'package:synesterra/data/repositories/impl/noop_playback_repository.dart';
import 'package:synesterra/features/editor/editor_view.dart';
import 'package:synesterra/features/editor/envelope_editor.dart';
import 'package:synesterra/features/editor/eq_editor.dart';
import 'package:synesterra/features/editor/instrument_panel.dart';
import 'package:synesterra/features/editor/instrument_radar_view.dart';
import 'package:synesterra/features/editor/spectrum_editor.dart';
import 'package:synesterra/shared/instrument_figure/instrument_sound_view.dart';
import 'package:synesterra/shared/instrument_mist/mist_spec.dart';
import 'package:synesterra/shared/instrument_radar/radar_geometry.dart';
import 'package:synesterra/shared/instrument_radar/radar_painter.dart';
import 'package:synesterra/shared/theme/ambient_scope.dart';
import 'package:synesterra/shared/theme/ground_palette.dart';
import 'package:synesterra/shared/theme/synesterra_theme.dart';
import 'package:synesterra/shared/theme/tap_effect.dart';
import 'package:synesterra/shared/widgets/round_components.dart';
import 'package:synesterra/shared/widgets/tap_glitch.dart';
import 'package:synesterra_core/synesterra_core.dart';

import 'audition_fakes.dart';

const radarKey = Key('instrument-radar');
const saveKey = Key('instrument-save');
const nameKey = Key('instrument-name');
final ids = [for (final d in defaultTraitDefinitions) d.id];
final labels = [for (final d in defaultTraitDefinitions) d.label];

late RecordingAudition audition;
late InMemoryInstrumentLibraryRepository library;

/// A flash gate whose clock never moves: after one flash it refuses all.
late FlashGate gate;

Future<void> open(
  WidgetTester tester, {
  Instrument? instrument,
  bool existing = false,
  bool reduceMotion = false,
  GlitchStrength strength = GlitchStrength.strong,
}) async {
  tester.view
    ..devicePixelRatio = 1
    ..physicalSize = const Size(412, 1000);
  addTearDown(tester.view.reset);
  if (reduceMotion) {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  }
  audition = RecordingAudition();
  library = InMemoryInstrumentLibraryRepository();
  gate = FlashGate(clock: () => Duration.zero);
  if (existing && instrument != null) await library.save(instrument);
  final tokens = SynesterraTokens.forPalette(SynesterraPalette.graphite);
  await tester.pumpWidget(
    MaterialApp(
      theme: synesterraTheme(SynesterraPalette.graphite),
      home: AmbientScope(
        palette: GroundPalette.of(
          tokens,
          GroundTone.dark,
          tokens.layerColors.first,
        ),
        tapStrength: strength,
        gate: gate,
        child: EditorView(
          instrumentLibrary: library,
          instrumentAudition: audition,
          loopLibrary: InMemoryLoopLibraryRepository(),
          playback: NoopPlaybackRepository(),
          initialInstrument: instrument,
          editsExisting: existing,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// The traits the panel holds (continuous; the wheel shows them snapped).
InstrumentTraits shownTraits(WidgetTester tester) =>
    tester.widget<InstrumentRadar>(find.byKey(radarKey)).traits;

List<double> values(InstrumentTraits traits) => [
  for (final id in ids) traits[id],
];

T painter<T>(WidgetTester tester) => tester
    .widgetList<CustomPaint>(
      find.descendant(
        of: find.byKey(radarKey),
        matching: find.byType(CustomPaint),
      ),
    )
    .map((w) => w.painter)
    .whereType<T>()
    .single;

List<double> painted(WidgetTester tester) =>
    painter<RadarShapePainter>(tester).values;

Rect radarRect(WidgetTester tester) => tester.getRect(find.byKey(radarKey));

double reachOf(WidgetTester tester) =>
    WheelLayout.of(radarRect(tester).size).reach;

/// The screen position of [value] on spoke [index].
Offset at(WidgetTester tester, int index, double value) {
  final rect = radarRect(tester);
  return radarPoint(index, ids.length, value, rect.size, reachOf(tester)) +
      rect.topLeft;
}

Instrument draft(WidgetTester tester) => tester
    .widget<InstrumentPanel>(find.byType(InstrumentPanel))
    .viewModel
    .instrument;

SemanticsNode axisNode(String label) =>
    find.semantics.byLabel(label).evaluate().single;

void adjust(WidgetTester tester, String label, SemanticsAction action) =>
    tester.semantics.performAction(find.semantics.byLabel(label), action);

bool flashing(WidgetTester tester) => tester
    .widgetList<CustomPaint>(find.byType(CustomPaint))
    .any((w) => w.painter is TapGlitchPainter);

bool onSteps(Iterable<double> values) =>
    values.every((v) => (v * rankSteps - (v * rankSteps).round()).abs() < 1e-9);

void main() {
  group('only the wheel', () {
    testWidgets('the panel is the name, the wheel and one round Save: no '
        'sliders, chips, hints or notes', (tester) async {
      await open(
        tester,
        instrument: factoryInstruments[2].copyWith(id: 'b', name: 'Bell'),
        existing: true,
      );
      final panel = find.byType(InstrumentPanel);
      Finder inPanel(Finder f) => find.descendant(of: panel, matching: f);

      expect(find.byKey(radarKey), findsOneWidget);
      expect(find.byKey(nameKey), findsOneWidget);
      expect(
        inPanel(find.byType(RoundActionButton)),
        findsOneWidget,
        reason: 'one round Save button',
      );
      expect(find.byKey(saveKey), findsOneWidget);
      for (final type in [
        Slider,
        RoundSlider,
        TactileChip,
        ActionChip,
        ChoiceChip,
        FilterChip,
        InputChip,
        RoundSegmented<bool>,
        InstrumentSoundView,
      ]) {
        expect(inPanel(find.byType(type)), findsNothing, reason: '$type');
      }
      // No line of text at all: no hint, no preset name, no note (the Bell
      // is approximated; that is said to screen readers only).
      expect(inPanel(find.byType(Text)), findsNothing);
      for (final key in const [
        'instrument-radar-hint',
        'instrument-radar-presets',
        'instrument-radar-approximate',
        'instrument-status',
        'instrument-preview',
      ]) {
        expect(find.byKey(Key(key)), findsNothing, reason: key);
      }
    });

    testWidgets('the wheel: names on the ring, rank letters, the mist as a '
        'glow behind it', (tester) async {
      await open(tester);
      final field = painter<RadarFieldPainter>(tester);
      expect(field.labels, labels);
      expect(field.count, 6);
      expect(field.bare, isFalse);
      expect(painter<RadarRankPainter>(tester).count, 6);
      expect(
        painter<RadarGlowPainter>(tester).spec,
        buildMistSpec(draft(tester)),
      );
    });

    testWidgets('the painters sit behind their own repaint boundaries and '
        'nothing blurs the backdrop', (tester) async {
      await open(tester);
      for (final type in [
        RadarGlowPainter,
        RadarFieldPainter,
        RadarShapePainter,
        RadarRankPainter,
      ]) {
        final paint = find.byWidgetPredicate(
          (w) => w is CustomPaint && w.painter.runtimeType == type,
        );
        expect(paint, findsOneWidget, reason: '$type');
        expect(
          find.ancestor(of: paint, matching: find.byType(RepaintBoundary)),
          findsWidgets,
          reason: '$type',
        );
      }
      expect(find.byType(BackdropFilter), findsNothing);
    });
  });

  testWidgets('larger system text scales the names and letters; the chart '
      'makes room and still follows the finger', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await open(tester);
    expect(painter<RadarFieldPainter>(tester).textScale, 1.5);
    expect(painter<RadarRankPainter>(tester).textScale, 1.5);
    expect(painter<RadarShapePainter>(tester).textScale, 1.5);
    expect(painter<RadarGlowPainter>(tester).textScale, 1.5);

    final rect = radarRect(tester);
    final big = WheelLayout.of(rect.size, textScale: 1.5);
    expect(big.reach, lessThan(reachOf(tester)));
    Offset bigAt(double v) =>
        radarPoint(2, 6, v, rect.size, big.reach) + rect.topLeft;
    final gesture = await tester.startGesture(bigAt(0.5));
    await gesture.moveTo(bigAt(0.65));
    await gesture.moveTo(bigAt(0.8));
    await gesture.up();
    await tester.pump(const Duration(seconds: 1));
    expect(shownTraits(tester)[TraitIds.warmth], 0.8);
  });

  testWidgets('a new instrument starts on the neutral shape', (tester) async {
    await open(tester);
    final neutral = traitPresets.singleWhere((p) => p.name == 'neutral');
    expect(shownTraits(tester), neutral.traits);
    expect(painted(tester), values(neutral.traits));
    expect(
      draft(tester),
      instrumentForTraits(
        neutral.traits,
        id: draft(tester).id,
        name: 'New instrument',
      ),
    );
  });

  group('dragging a vertex', () {
    testWidgets('changes that trait only, along its spoke, snapped to a step', (
      tester,
    ) async {
      await open(tester);
      final before = shownTraits(tester);
      // Warmth is spoke 2 (lower right). Push it out, wandering across the
      // spoke too: only the part along it counts.
      final direction = radarAxisDirection(2, ids.length);
      final across = Offset(-direction.dy, direction.dx) * 14;
      final gesture = await tester.startGesture(at(tester, 2, 0.5));
      await gesture.moveTo(at(tester, 2, 0.7) + across);
      await gesture.moveTo(at(tester, 2, 0.87) - across);
      await tester.pump();

      final traits = shownTraits(tester);
      expect(traits[TraitIds.warmth], 0.9, reason: 'snapped to the step');
      for (final id in ids) {
        if (id == TraitIds.warmth) continue;
        expect(traits[id], before[id], reason: id);
      }
      await gesture.up();
      await tester.pump(const Duration(seconds: 1));
      expect(painted(tester)[2], 0.9);
    });

    testWidgets('every value it sends is on a step', (tester) async {
      await open(tester);
      final seen = <double>[];
      final gesture = await tester.startGesture(at(tester, 4, 0.5));
      for (var i = 1; i <= 30; i++) {
        await gesture.moveTo(at(tester, 4, 0.5 + 0.3 * i / 30));
        await tester.pump();
        seen.add(shownTraits(tester)[TraitIds.softness]);
      }
      expect(onSteps(seen), isTrue, reason: '$seen');
      expect(seen.toSet(), {0.5, 0.6, 0.7, 0.8});
      await gesture.up();
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('past the edge or the centre it stays in 0..1', (tester) async {
      await open(tester);
      final gesture = await tester.startGesture(at(tester, 0, 0.5));
      await gesture.moveTo(at(tester, 0, 0.5) + const Offset(0, -900));
      await tester.pump();
      expect(shownTraits(tester)[TraitIds.brightness], 1);
      await gesture.moveTo(at(tester, 0, 0.5) + const Offset(0, 900));
      await tester.pump();
      expect(shownTraits(tester)[TraitIds.brightness], 0);
      await gesture.up();
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('the glow follows the drag live; nothing plays until the '
        'lift, then once', (tester) async {
      await open(tester);
      final gesture = await tester.startGesture(at(tester, 1, 0.5));
      await gesture.moveTo(at(tester, 1, 0.8));
      await tester.pump();
      final mid = painter<RadarGlowPainter>(tester).spec;
      await gesture.moveTo(at(tester, 1, 0.2));
      await tester.pump();
      final end = draft(tester);
      expect(painter<RadarGlowPainter>(tester).spec, buildMistSpec(end));
      expect(mid, isNot(buildMistSpec(end)));
      expect(
        end,
        instrumentForTraits(
          shownTraits(tester),
          id: end.id,
          name: 'New instrument',
        ),
      );
      expect(
        audition.played,
        isEmpty,
        reason: 'nothing plays under the finger',
      );

      await gesture.up();
      await tester.pump(const Duration(seconds: 1));
      expect(audition.played, hasLength(1));
      expect(audition.played.single, end);
    });

    testWidgets('a tap on a handle plays once and moves nothing', (
      tester,
    ) async {
      await open(tester);
      final before = shownTraits(tester);
      await tester.tapAt(at(tester, 2, before[TraitIds.warmth]));
      await tester.pump(const Duration(seconds: 1));
      expect(audition.played, hasLength(1));
      expect(shownTraits(tester), before);
    });

    testWidgets('a touch away from every spoke does nothing', (tester) async {
      await open(tester);
      final before = shownTraits(tester);
      final rect = radarRect(tester);
      final between = radarAxisDirection(0, 6) + radarAxisDirection(1, 6);
      await tester.tapAt(
        rect.center + between / between.distance * (reachOf(tester) + 20),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(audition.played, isEmpty);
      expect(shownTraits(tester), before);
    });

    testWidgets('handles stacked at the centre: the first move picks the '
        'spoke it points along', (tester) async {
      // Everything at the centre but Brightness (which the core reads as
      // the middle once Fullness is this low).
      final flat = instrumentForTraits(
        InstrumentTraits({for (final id in ids) id: 0.0}),
        id: 'flat',
        name: 'Flat',
      );
      await open(tester, instrument: flat, existing: true);
      expect(painted(tester), [0.5, 0.0, 0.0, 0.0, 0.0, 0.0]);
      final centre = radarRect(tester).center;
      final gesture = await tester.startGesture(centre);
      final direction = radarAxisDirection(3, 6);
      for (final share in [0.05, 0.2, 0.4]) {
        await gesture.moveTo(centre + direction * reachOf(tester) * share);
        await tester.pump();
      }
      final traits = shownTraits(tester);
      expect(traits[TraitIds.air], 0.4, reason: 'Air points straight down');
      for (final id in ids.skip(1)) {
        if (id == TraitIds.air) continue;
        expect(traits[id], closeTo(0, 1e-9), reason: id);
      }
      await gesture.up();
      await tester.pump(const Duration(seconds: 1));
      expect(audition.played, hasLength(1));
    });

    testWidgets('touching the wheel does not scroll the page', (tester) async {
      await open(tester);
      final scrollable = tester.state<ScrollableState>(
        find
            .descendant(
              of: find.byType(InstrumentPanel),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.dragFrom(at(tester, 3, 0.5), const Offset(0, -200));
      await tester.pump(const Duration(seconds: 1));
      expect(scrollable.position.pixels, 0);
    });
  });

  group('the accent on release', () {
    testWidgets('letting go of a handle flashes it through the shared gate', (
      tester,
    ) async {
      await open(tester);
      final gesture = await tester.startGesture(at(tester, 0, 0.5));
      await gesture.moveTo(at(tester, 0, 0.8));
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 40));
      expect(flashing(tester), isTrue);
      expect(
        gate.tryFlash(Duration.zero),
        isFalse,
        reason: 'the wheel used the gate in scope',
      );
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('a second release inside the gate interval does not flash '
        'again', (tester) async {
      await open(tester);
      expect(gate.tryFlash(Duration.zero), isTrue);
      await tester.tapAt(at(tester, 0, 0.5));
      await tester.pump(const Duration(milliseconds: 40));
      expect(flashing(tester), isFalse);
      expect(audition.played, hasLength(1), reason: 'the sound still plays');
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('with the effect off nothing flashes', (tester) async {
      await open(tester, strength: GlitchStrength.off);
      await tester.tapAt(at(tester, 0, 0.5));
      await tester.pump(const Duration(milliseconds: 40));
      expect(flashing(tester), isFalse);
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('the glow swells after a release, but never under reduce '
        'motion', (tester) async {
      await open(tester);
      final swell = painter<RadarGlowPainter>(tester).swell!;
      await tester.tapAt(at(tester, 0, 0.5));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(swell.value, inExclusiveRange(0, 1));
      await tester.pump(const Duration(seconds: 1));

      await open(tester, reduceMotion: true);
      expect(painter<RadarGlowPainter>(tester).swell, isNull);
      expect(painter<RadarShapePainter>(tester).breath, isNull);
    });
  });

  group('changes from outside', () {
    testWidgets('a screen-reader step glides the shape there with a short '
        'ease', (tester) async {
      final handle = tester.ensureSemantics();
      await open(tester);
      adjust(tester, 'Fullness', SemanticsAction.increase);
      await tester.pump();
      await tester.pump(InstrumentRadar.glide ~/ 3);
      expect(painted(tester)[1], inExclusiveRange(0.5, 0.6));
      await tester.pump(InstrumentRadar.glide);
      expect(painted(tester)[1], 0.6);
      expect(InstrumentRadar.glide, lessThan(const Duration(seconds: 1)));
      handle.dispose();
    });

    testWidgets('under reduce motion it jumps there, without the glide', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await open(tester, reduceMotion: true);
      adjust(tester, 'Fullness', SemanticsAction.increase);
      await tester.pump();
      expect(painted(tester)[1], 0.6);
      handle.dispose();
    });
  });

  group('semantics', () {
    testWidgets('every spoke is an adjustable control with its plain name '
        'and rank, at least 48 dp', (tester) async {
      final handle = tester.ensureSemantics();
      await open(tester);
      for (final label in labels) {
        final node = axisNode(label);
        expect(
          node,
          isSemantics(
            isSlider: true,
            hasIncreaseAction: true,
            hasDecreaseAction: true,
            value: 'C',
            increasedValue: 'C plus',
            decreasedValue: 'D plus',
          ),
          reason: label,
        );
        expect(node.rect.width, greaterThanOrEqualTo(48), reason: label);
        expect(node.rect.height, greaterThanOrEqualTo(48), reason: label);
      }
      handle.dispose();
    });

    testWidgets('increase and decrease move one step of one trait, speak the '
        'rank and play once each', (tester) async {
      final handle = tester.ensureSemantics();
      await open(tester);
      final before = shownTraits(tester);

      adjust(tester, 'Air', SemanticsAction.increase);
      await tester.pumpAndSettle();
      expect(shownTraits(tester)[TraitIds.air], 0.6);
      expect(axisNode('Air').value, 'C plus');
      expect(axisNode('Air').label, 'Air');
      expect(audition.played, hasLength(1));

      adjust(tester, 'Length', SemanticsAction.decrease);
      await tester.pumpAndSettle();
      expect(axisNode('Length').value, 'D plus');
      expect(
        shownTraits(tester),
        before.withValues({TraitIds.air: 0.6, TraitIds.length: 0.4}),
        reason: 'each step moved its own trait only',
      );
      expect(audition.played, hasLength(2));
      handle.dispose();
    });

    testWidgets('stepping at the ends stays in range', (tester) async {
      final handle = tester.ensureSemantics();
      await open(tester);
      for (var i = 0; i < 12; i++) {
        adjust(tester, 'Fullness', SemanticsAction.increase);
        await tester.pump();
      }
      await tester.pumpAndSettle();
      expect(shownTraits(tester)[TraitIds.fullness], 1);
      expect(axisNode('Fullness').value, 'A plus');
      for (var i = 0; i < 12; i++) {
        adjust(tester, 'Fullness', SemanticsAction.decrease);
        await tester.pump();
      }
      await tester.pumpAndSettle();
      expect(shownTraits(tester)[TraitIds.fullness], 0);
      expect(axisNode('Fullness').value, 'none');
      expect(tester.takeException(), isNull);
      handle.dispose();
    });

    testWidgets('the shape is described in plain words', (tester) async {
      final handle = tester.ensureSemantics();
      await open(tester);
      expect(
        find.semantics.byLabel(
          'Sound shape, neutral: everything in the middle',
        ),
        findsOne,
      );
      handle.dispose();
    });

    testWidgets('an approximated sound is said to screen readers, not shown', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final bell = factoryInstruments[2].copyWith(id: 'b', name: 'Bell');
      await open(tester, instrument: bell, existing: true);
      final shown = [for (final v in values(traitsForInstrument(bell))) v];
      expect(
        find.semantics.byLabel(
          describeRadar(labels, [
            for (final v in shown) snapToRank(v),
          ], approximate: true),
        ),
        findsOne,
      );
      expect(find.text(radarApproximateNote), findsNothing);
      handle.dispose();
    });

    testWidgets('the name and Save are labelled', (tester) async {
      final handle = tester.ensureSemantics();
      await open(tester);
      expect(
        tester.getSemantics(find.byKey(saveKey)),
        isSemantics(label: 'Save', isButton: true, isEnabled: true),
      );
      expect(find.semantics.byLabel('Name'), findsWidgets);
      handle.dispose();
    });
  });

  group('technical controls are hidden', () {
    testWidgets('none of them is in the widget tree', (tester) async {
      await open(tester);
      expect(find.byType(SpectrumEditor), findsNothing);
      expect(find.byType(EnvelopeEditor), findsNothing);
      expect(find.byType(EqEditor), findsNothing);
      expect(find.byType(Slider), findsNothing);
      for (final key in const [
        'instrument-play',
        'instrument-harmonics',
        'instrument-brightness',
        'instrument-attack',
        'instrument-decay',
        'instrument-eq-low',
        'instrument-tag-input',
        'test-mode',
        'start-from-factory-bell',
        'instrument-view-switch',
      ]) {
        expect(find.byKey(Key(key)), findsNothing, reason: key);
      }
    });

    testWidgets('no visible text or label uses technical words', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await open(
        tester,
        instrument: factoryInstruments[2].copyWith(id: 'saved-bell'),
        existing: true,
      );
      final banned = RegExp(
        r'harmonic|attack|decay|envelope|spectrum|\bEQ\b|\bdB\b|\bHz\b|'
        r'\bms\b|shelf|trait',
        caseSensitive: false,
      );
      for (final text in tester.widgetList<Text>(find.byType(Text))) {
        expect(text.data ?? '', isNot(matches(banned)));
      }
      final spoken = [
        for (final node
            in tester.semantics.simulatedAccessibilityTraversal()) ...[
          node.label,
          node.value,
          node.hint,
        ],
      ];
      expect(spoken, isNotEmpty);
      for (final label in spoken) {
        expect(label, isNot(matches(banned)));
      }
      handle.dispose();
    });
  });

  group('opening a saved instrument', () {
    final saved = factoryInstruments[2].copyWith(id: 'saved-1', name: 'Bell');

    testWidgets('shows its shape snapped to the steps and changes nothing', (
      tester,
    ) async {
      await open(tester, instrument: saved, existing: true);
      final read = traitsForInstrument(saved);
      expect(shownTraits(tester), read, reason: 'the model stays continuous');
      expect(painted(tester), [for (final v in values(read)) snapToRank(v)]);
      expect(draft(tester), saved, reason: 'the recipe is untouched');
      expect(
        tester.widget<RoundActionButton>(find.byKey(saveKey)).onPressed,
        isNull,
        reason: 'nothing to save yet',
      );
      expect(library.snapshot.value.instruments.single, saved);
    });

    testWidgets('the first move replaces the draft; the library changes only '
        'on Save', (tester) async {
      await open(tester, instrument: saved, existing: true);
      final length = snapToRank(traitsForInstrument(saved)[TraitIds.length]);
      final gesture = await tester.startGesture(at(tester, 5, length));
      await gesture.moveTo(at(tester, 5, 0.2));
      await gesture.up();
      await tester.pump(const Duration(seconds: 1));

      expect(shownTraits(tester)[TraitIds.length], 0.2);
      expect(library.snapshot.value.instruments.single, saved);

      await tester.tap(find.byKey(saveKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final stored = library.snapshot.value.instruments.single;
      expect(stored.id, 'saved-1');
      expect(stored.name, 'Bell');
      expect(
        stored,
        instrumentForTraits(
          shownTraits(tester),
          id: 'saved-1',
          name: 'Bell',
          tags: saved.tags,
        ),
      );
    });

    testWidgets('an instrument made on the wheel opens on its steps', (
      tester,
    ) async {
      final airy = traitPresets.singleWhere((p) => p.name == 'airy pad');
      final made = instrumentForTraits(
        airy.traits,
        id: 'saved-2',
        name: 'Haze',
      );
      await open(tester, instrument: made, existing: true);
      expect(shownTraits(tester), airy.traits);
      expect(painted(tester), [
        for (final v in values(airy.traits)) snapToRank(v),
      ]);
    });
  });

  group('name and Save', () {
    testWidgets('tapping the name renames it in place; Save stores it', (
      tester,
    ) async {
      await open(tester);
      final field = tester.widget<TextField>(find.byKey(nameKey));
      expect(field.controller!.text, 'New instrument');
      expect(field.decoration!.labelText, isNull, reason: 'a title, no label');

      await tester.tap(find.byKey(nameKey));
      await tester.pump();
      expect(tester.testTextInput.isVisible, isTrue);
      await tester.enterText(find.byKey(nameKey), 'Glow');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      final gesture = await tester.startGesture(at(tester, 0, 0.5));
      await gesture.moveTo(at(tester, 0, 0.8));
      await gesture.up();
      await tester.pump(const Duration(seconds: 1));

      await tester.tap(find.byKey(saveKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final stored = library.snapshot.value.instruments.single;
      expect(stored.name, 'Glow');
      expect(
        stored,
        instrumentForTraits(shownTraits(tester), id: stored.id, name: 'Glow'),
      );
      expect(find.text('Saved "Glow"'), findsOneWidget);
      expect(
        tester.widget<RoundActionButton>(find.byKey(saveKey)).onPressed,
        isNull,
        reason: 'saved: nothing more to save',
      );
    });

    testWidgets('an empty name asks for one and Save waits', (tester) async {
      await open(tester);
      await tester.enterText(find.byKey(nameKey), '');
      await tester.pump();
      expect(find.text('Give it a name'), findsOneWidget);
      expect(
        tester.widget<RoundActionButton>(find.byKey(saveKey)).onPressed,
        isNull,
      );
    });
  });

  testWidgets('when sound is unavailable the screen says so', (tester) async {
    await open(tester);
    audition.isAvailable = false;
    await tester.pump();
    expect(find.textContaining('Sound is not available'), findsOneWidget);
    expect(find.textContaining('Play'), findsNothing);
  });

  test('the description lists high and low traits in plain words', () {
    expect(
      describeRadar(['A', 'B', 'C'], [0.9, 0.1, 0.5]),
      'Sound shape: high A, low B, the rest in the middle',
    );
    expect(
      describeRadar(['A', 'B', 'C'], [0.9, 0.8, 0.7], preset: 'x'),
      'Sound shape, x: high A, B and C',
    );
    expect(
      describeRadar(['A', 'B', 'C'], [0.5, 0.4, 0.6], approximate: true),
      'Sound shape: everything in the middle. $radarApproximateNote',
    );
  });

  group('instrument dice', () {
    testWidgets('rolls the traits, plays the sound, and undo steps back', (
      tester,
    ) async {
      await open(tester);
      const dice = Key('instrument-randomize');
      const undo = Key('instrument-randomize-undo');
      expect(tester.getSize(find.byKey(dice)), const Size(48, 48));
      expect(find.byKey(undo), findsNothing);
      final before = shownTraits(tester);
      final plays = audition.played.length;

      await tester.tap(find.byKey(dice));
      await tester.pumpAndSettle();
      expect(shownTraits(tester), isNot(before));
      expect(audition.played.length, plays + 1);
      expect(find.byKey(undo), findsOneWidget);
      expect(tester.getSize(find.byKey(undo)), const Size(48, 48));
      expect(
        tester.widget<RoundActionButton>(find.byKey(saveKey)).onPressed,
        isNotNull,
        reason: 'a roll is an unsaved change',
      );

      await tester.tap(find.byKey(undo));
      await tester.pumpAndSettle();
      expect(shownTraits(tester), before);
      expect(find.byKey(undo), findsNothing);
    });

    testWidgets('both buttons are labelled for screen readers', (tester) async {
      final semantics = tester.ensureSemantics();
      await open(tester);
      await tester.tap(find.byKey(const Key('instrument-randomize')));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Randomize instrument'), findsOneWidget);
      expect(find.bySemanticsLabel('Undo randomize'), findsOneWidget);
      semantics.dispose();
    });
  });
}
