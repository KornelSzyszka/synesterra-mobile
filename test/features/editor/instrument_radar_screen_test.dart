import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synesterra/data/repositories/impl/in_memory_instrument_library_repository.dart';
import 'package:synesterra/data/repositories/impl/in_memory_loop_library_repository.dart';
import 'package:synesterra/data/repositories/impl/noop_playback_repository.dart';
import 'package:synesterra/features/editor/editor_view.dart';
import 'package:synesterra/features/editor/envelope_editor.dart';
import 'package:synesterra/features/editor/eq_editor.dart';
import 'package:synesterra/features/editor/instrument_radar_view.dart';
import 'package:synesterra/features/editor/spectrum_editor.dart';
import 'package:synesterra/shared/instrument_figure/instrument_sound_view.dart';
import 'package:synesterra/shared/instrument_radar/radar_geometry.dart';
import 'package:synesterra/shared/instrument_radar/radar_painter.dart';
import 'package:synesterra/shared/theme/ambient_scope.dart';
import 'package:synesterra/shared/theme/ground_palette.dart';
import 'package:synesterra/shared/theme/synesterra_theme.dart';
import 'package:synesterra/shared/theme/tap_effect.dart';
import 'package:synesterra/shared/widgets/tap_glitch.dart';
import 'package:synesterra_core/synesterra_core.dart';

import 'audition_fakes.dart';

const radarKey = Key('instrument-radar');
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

InstrumentTraits shownTraits(WidgetTester tester) =>
    tester.widget<InstrumentRadar>(find.byKey(radarKey)).traits;

List<double> painted(WidgetTester tester) => tester
    .widgetList<CustomPaint>(
      find.descendant(
        of: find.byKey(radarKey),
        matching: find.byType(CustomPaint),
      ),
    )
    .map((w) => w.painter)
    .whereType<RadarShapePainter>()
    .single
    .values;

Rect radarRect(WidgetTester tester) => tester.getRect(find.byKey(radarKey));

/// The screen position of [value] on axis [index].
Offset at(WidgetTester tester, int index, double value) {
  final rect = radarRect(tester);
  final reach = radarReach(rect.size, ids.length);
  return radarPoint(index, ids.length, value, rect.size, reach) + rect.topLeft;
}

Instrument shownInMist(WidgetTester tester) => tester
    .widget<InstrumentSoundView>(find.byType(InstrumentSoundView))
    .instrument;

TraitPreset preset(String name) =>
    traitPresets.singleWhere((p) => p.name == name);

Finder chip(String name) =>
    find.byKey(Key('radar-preset-${name.replaceAll(' ', '-')}'));

SemanticsNode axisNode(String label) =>
    find.semantics.byLabel(label).evaluate().single;

void adjust(WidgetTester tester, String label, SemanticsAction action) =>
    tester.semantics.performAction(find.semantics.byLabel(label), action);

bool flashing(WidgetTester tester) => tester
    .widgetList<CustomPaint>(find.byType(CustomPaint))
    .any((w) => w.painter is TapGlitchPainter);

void main() {
  testWidgets('the screen shows the radar, the presets, the mist, the name '
      'and Save', (tester) async {
    await open(tester);
    expect(find.byKey(radarKey), findsOneWidget);
    for (final p in traitPresets) {
      expect(chip(p.name), findsOneWidget, reason: p.name);
    }
    expect(find.byKey(const Key('instrument-preview-mist')), findsOneWidget);
    expect(find.byKey(const Key('instrument-name')), findsOneWidget);
    expect(find.byKey(const Key('instrument-save')), findsOneWidget);
    expect(find.byKey(const Key('instrument-radar-hint')), findsOneWidget);
    expect(find.byKey(const Key('instrument-radar-approximate')), findsNothing);
  });

  testWidgets('a new instrument starts on the shape of the plain Sine', (
    tester,
  ) async {
    await open(tester);
    final sine = traitsForInstrument(factoryInstruments[1]);
    expect(shownTraits(tester), sine);
    expect(painted(tester), [for (final id in ids) sine[id]]);
  });

  testWidgets('the axes are labelled with the plain trait names', (
    tester,
  ) async {
    await open(tester);
    final field = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((w) => w.painter)
        .whereType<RadarFieldPainter>()
        .single;
    expect(field.labels, labels);
    expect(field.count, 6);
  });

  testWidgets('the painters sit behind their own repaint boundaries and '
      'nothing blurs the backdrop', (tester) async {
    await open(tester);
    for (final painter in [RadarFieldPainter, RadarShapePainter]) {
      final paint = find.byWidgetPredicate(
        (w) => w is CustomPaint && w.painter.runtimeType == painter,
      );
      expect(
        find.ancestor(of: paint, matching: find.byType(RepaintBoundary)),
        findsWidgets,
      );
    }
    expect(find.byType(BackdropFilter), findsNothing);
  });

  testWidgets('dragging a handle changes that trait only, along its axis', (
    tester,
  ) async {
    await open(tester);
    final before = shownTraits(tester);
    // Warmth is axis 2 (lower right). Push it out, wandering across the
    // axis too: only the part along the axis counts.
    final direction = radarAxisDirection(2, ids.length);
    final across = Offset(-direction.dy, direction.dx) * 14;
    final gesture = await tester.startGesture(at(tester, 2, 0.5));
    await gesture.moveTo(at(tester, 2, 0.7) + across);
    await gesture.moveTo(at(tester, 2, 0.9) - across);
    await tester.pump();

    final traits = shownTraits(tester);
    expect(traits[TraitIds.warmth], closeTo(0.9, 0.01));
    for (final id in ids) {
      if (id == TraitIds.warmth) continue;
      expect(traits[id], before[id], reason: id);
    }
    await gesture.up();
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('a handle drag past the edge or the centre stays in 0..1', (
    tester,
  ) async {
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

  testWidgets('the mist follows the drag live and nothing plays until the '
      'lift, then once', (tester) async {
    await open(tester);
    final gesture = await tester.startGesture(at(tester, 1, 0.5));
    await gesture.moveTo(at(tester, 1, 0.8));
    await tester.pump();
    final mid = shownInMist(tester);
    await gesture.moveTo(at(tester, 1, 0.2));
    await tester.pump();
    final end = shownInMist(tester);
    expect(mid.harmonics, isNot(end.harmonics));
    expect(
      end,
      instrumentForTraits(
        shownTraits(tester),
        id: end.id,
        name: 'New instrument',
      ),
    );
    expect(audition.played, isEmpty, reason: 'nothing plays under the finger');

    await gesture.up();
    await tester.pump(const Duration(seconds: 1));
    expect(audition.played, hasLength(1));
    expect(audition.played.single, end);
  });

  testWidgets('a tap on a handle plays once and moves nothing', (tester) async {
    await open(tester);
    final before = shownTraits(tester);
    await tester.tapAt(at(tester, 2, before[TraitIds.warmth]));
    await tester.pump(const Duration(seconds: 1));
    expect(audition.played, hasLength(1));
    expect(shownTraits(tester), before);
  });

  testWidgets('a touch away from every axis does nothing', (tester) async {
    await open(tester);
    final before = shownTraits(tester);
    final rect = radarRect(tester);
    // Between the first two axes, outside the shape's reach.
    final reach = radarReach(rect.size, 6);
    final between = radarAxisDirection(0, 6) + radarAxisDirection(1, 6);
    await tester.tapAt(rect.center + between / between.distance * (reach + 20));
    await tester.pump(const Duration(seconds: 1));
    expect(audition.played, isEmpty);
    expect(shownTraits(tester), before);
  });

  testWidgets('touching the radar does not scroll the page', (tester) async {
    await open(tester);
    final scrollable = tester.state<ScrollableState>(
      find.byType(Scrollable).first,
    );
    await tester.dragFrom(at(tester, 3, 0.5), const Offset(0, -200));
    await tester.pump(const Duration(seconds: 1));
    expect(scrollable.position.pixels, 0);
  });

  group('presets', () {
    testWidgets('each chip sets its traits, is selected and plays once', (
      tester,
    ) async {
      await open(tester);
      for (final (i, p) in traitPresets.reversed.indexed) {
        await tester.ensureVisible(chip(p.name));
        await tester.tap(chip(p.name));
        await tester.pumpAndSettle();
        expect(shownTraits(tester), p.traits, reason: p.name);
        expect(audition.played, hasLength(i + 1));
        expect(
          tester.getSemantics(chip(p.name)),
          isSemantics(isSelected: true, isButton: true),
        );
      }
    });

    testWidgets('choosing one glides the shape there with a short ease', (
      tester,
    ) async {
      await open(tester);
      final from = painted(tester);
      final bass = preset('bass');
      await tester.ensureVisible(chip('bass'));
      await tester.tap(chip('bass'));
      await tester.pump();
      await tester.pump(InstrumentRadar.glide ~/ 3);

      final mid = painted(tester);
      final target = [for (final id in ids) bass.traits[id]];
      var between = 0;
      for (var i = 0; i < ids.length; i++) {
        if (target[i] == from[i]) continue;
        final lo = target[i] < from[i] ? target[i] : from[i];
        final hi = target[i] < from[i] ? from[i] : target[i];
        expect(mid[i], inInclusiveRange(lo, hi), reason: ids[i]);
        if (mid[i] > lo && mid[i] < hi) between++;
      }
      expect(between, greaterThan(0), reason: 'it is on its way');

      await tester.pump(InstrumentRadar.glide);
      expect(painted(tester), target);
      expect(InstrumentRadar.glide, lessThan(const Duration(seconds: 1)));
    });

    testWidgets('under reduce motion it jumps there, without the glide', (
      tester,
    ) async {
      await open(tester, reduceMotion: true);
      await tester.ensureVisible(chip('click'));
      await tester.tap(chip('click'));
      await tester.pump();
      expect(painted(tester), [
        for (final id in ids) preset('click').traits[id],
      ]);
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
        reason: 'the radar used the gate in scope',
      );
    });

    testWidgets('a second release inside the gate interval does not flash '
        'again', (tester) async {
      await open(tester);
      // The gate's clock never moves, so after this nothing may flash.
      expect(gate.tryFlash(Duration.zero), isTrue);
      await tester.tapAt(at(tester, 0, 0.5));
      await tester.pump(const Duration(milliseconds: 40));
      expect(flashing(tester), isFalse);
      expect(audition.played, hasLength(1), reason: 'the sound still plays');
    });

    testWidgets('with the effect off nothing flashes', (tester) async {
      await open(tester, strength: GlitchStrength.off);
      await tester.tapAt(at(tester, 0, 0.5));
      await tester.pump(const Duration(milliseconds: 40));
      expect(flashing(tester), isFalse);
    });
  });

  group('semantics', () {
    testWidgets('every axis is an adjustable control with its plain name and '
        'level, at least 48 dp', (tester) async {
      final handle = tester.ensureSemantics();
      await open(tester, instrument: factoryInstruments[2], existing: true);
      final traits = shownTraits(tester);
      String level(double v) => '${radarPercent(v)} percent';
      for (final (i, label) in labels.indexed) {
        final value = traits[ids[i]];
        final node = axisNode(label);
        expect(
          node,
          isSemantics(
            isSlider: true,
            hasIncreaseAction: true,
            hasDecreaseAction: true,
            value: level(value),
            increasedValue: level(radarStep(value, 1)),
            decreasedValue: level(radarStep(value, -1)),
          ),
          reason: label,
        );
        expect(node.rect.width, greaterThanOrEqualTo(48), reason: label);
        expect(node.rect.height, greaterThanOrEqualTo(48), reason: label);
      }
      handle.dispose();
    });

    testWidgets('increase and decrease step one trait and play once each', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await open(tester);
      final before = shownTraits(tester);

      adjust(tester, 'Air', SemanticsAction.increase);
      await tester.pumpAndSettle();
      final air = radarStep(before[TraitIds.air], 1);
      expect(shownTraits(tester)[TraitIds.air], air);
      expect(axisNode('Air').value, '${radarPercent(air)} percent');
      expect(audition.played, hasLength(1));

      adjust(tester, 'Length', SemanticsAction.decrease);
      await tester.pumpAndSettle();
      expect(
        shownTraits(tester),
        before.withValues({
          TraitIds.air: air,
          TraitIds.length: radarStep(before[TraitIds.length], -1),
        }),
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
      expect(tester.takeException(), isNull);
      handle.dispose();
    });

    testWidgets('the shape is described in plain words', (tester) async {
      final handle = tester.ensureSemantics();
      await open(tester);
      final traits = shownTraits(tester);
      expect(
        find.semantics.byLabel(
          describeRadar(labels, [for (final id in ids) traits[id]]),
        ),
        findsOne,
      );
      await tester.ensureVisible(chip('neutral'));
      await tester.tap(chip('neutral'));
      await tester.pumpAndSettle();
      expect(
        find.semantics.byLabel(
          'Sound shape, neutral: everything in the middle',
        ),
        findsOne,
      );
      await tester.ensureVisible(chip('warm drone'));
      await tester.tap(chip('warm drone'));
      await tester.pumpAndSettle();
      expect(
        find.semantics.byLabel(
          'Sound shape, warm drone: high Softness and Length, '
          'low Brightness, Fullness and Air, the rest in the middle',
        ),
        findsOne,
      );
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
      await open(tester, instrument: factoryInstruments[2], existing: true);
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

    testWidgets('shows its approximate shape with a plain note and changes '
        'nothing', (tester) async {
      await open(tester, instrument: saved, existing: true);
      expect(shownTraits(tester), traitsForInstrument(saved));
      expect(
        find.byKey(const Key('instrument-radar-approximate')),
        findsOneWidget,
      );
      expect(find.text('Saved'), findsOneWidget);
      expect(shownInMist(tester), saved);
    });

    testWidgets('the first move replaces the draft and clears the note, the '
        'library changes only on Save', (tester) async {
      await open(tester, instrument: saved, existing: true);
      final gesture = await tester.startGesture(
        at(tester, 5, traitsForInstrument(saved)[TraitIds.length]),
      );
      await gesture.moveTo(at(tester, 5, 0.2));
      await gesture.up();
      await tester.pump(const Duration(seconds: 1));

      expect(
        find.byKey(const Key('instrument-radar-approximate')),
        findsNothing,
      );
      expect(find.text('Unsaved changes'), findsOneWidget);
      expect(library.snapshot.value.instruments.single, saved);

      await tester.tap(find.byKey(const Key('instrument-save')));
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

    testWidgets('an instrument made on the radar opens without the note', (
      tester,
    ) async {
      final made = instrumentForTraits(
        preset('airy pad').traits,
        id: 'saved-2',
        name: 'Haze',
      );
      await open(tester, instrument: made, existing: true);
      expect(
        find.byKey(const Key('instrument-radar-approximate')),
        findsNothing,
      );
      expect(shownTraits(tester), preset('airy pad').traits);
    });
  });

  testWidgets('a new instrument can be named and saved from the radar', (
    tester,
  ) async {
    await open(tester);
    await tester.enterText(find.byKey(const Key('instrument-name')), 'Glow');
    await tester.ensureVisible(chip('guitar'));
    await tester.tap(chip('guitar'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('instrument-save')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final stored = library.snapshot.value.instruments.single;
    expect(stored.name, 'Glow');
    expect(
      stored.harmonics,
      instrumentForTraits(
        preset('guitar').traits,
        id: 'x',
        name: 'x',
      ).harmonics,
    );
  });

  testWidgets('when sound is unavailable the screen says so without Play', (
    tester,
  ) async {
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
      describeRadar(['A', 'B', 'C'], [0.5, 0.4, 0.6]),
      'Sound shape: everything in the middle',
    );
  });
}
