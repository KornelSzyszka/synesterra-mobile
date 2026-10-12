import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synesterra/data/repositories/impl/in_memory_loop_library_repository.dart';
import 'package:synesterra/data/repositories/impl/noop_playback_repository.dart';
import 'package:synesterra/data/repositories/impl/in_memory_instrument_library_repository.dart';
import 'package:synesterra/features/editor/editor_view.dart';
import 'package:synesterra/features/editor/envelope_editor.dart';
import 'package:synesterra/features/editor/eq_editor.dart';
import 'package:synesterra/features/editor/instrument_pad_view.dart';
import 'package:synesterra/features/editor/pad_geometry.dart';
import 'package:synesterra/features/editor/spectrum_editor.dart';
import 'package:synesterra/shared/instrument_figure/instrument_sound_view.dart';
import 'package:synesterra/shared/theme/synesterra_theme.dart';
import 'package:synesterra_core/synesterra_core.dart';

import 'audition_fakes.dart';

const padKey = Key('instrument-pad');
const characterLabel = InstrumentPad.characterLabel;
const strengthLabel = InstrumentPad.strengthLabel;

late RecordingAudition audition;
late InMemoryInstrumentLibraryRepository library;

Future<void> open(
  WidgetTester tester, {
  Instrument? instrument,
  bool existing = false,
}) async {
  tester.view
    ..devicePixelRatio = 1
    ..physicalSize = const Size(400, 900);
  addTearDown(tester.view.reset);
  audition = RecordingAudition();
  library = InMemoryInstrumentLibraryRepository();
  if (existing && instrument != null) await library.save(instrument);
  await tester.pumpWidget(
    MaterialApp(
      theme: synesterraTheme(SynesterraPalette.values.first),
      home: EditorView(
        instrumentLibrary: library,
        instrumentAudition: audition,
        loopLibrary: InMemoryLoopLibraryRepository(),
        playback: NoopPlaybackRepository(),
        initialInstrument: instrument,
        editsExisting: existing,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

InstrumentPadPainter painter(WidgetTester tester) =>
    tester
            .widget<CustomPaint>(
              find.byWidgetPredicate(
                (w) => w is CustomPaint && w.painter is InstrumentPadPainter,
              ),
            )
            .painter!
        as InstrumentPadPainter;

/// The screen position of the pad point `(x, y)` in the unit disc.
Offset at(WidgetTester tester, double x, double y) {
  final rect = tester.getRect(find.byKey(padKey));
  return padOffsetOf(PadPoint(x, y), rect.size) + rect.topLeft;
}

Instrument shownInMist(WidgetTester tester) => tester
    .widget<InstrumentSoundView>(find.byType(InstrumentSoundView))
    .instrument;

List<double> padHarmonics(PadPoint point) =>
    instrumentForPad(point, id: 'x', name: 'x').harmonics;

void adjust(WidgetTester tester, String label, SemanticsAction action) =>
    tester.semantics.performAction(find.semantics.byLabel(label), action);

SemanticsNode nodeLabelled(String label) =>
    find.semantics.byLabel(label).evaluate().single;

void main() {
  testWidgets('the screen shows the pad, the mist, the name and Save', (
    tester,
  ) async {
    await open(tester);
    expect(find.byKey(padKey), findsOneWidget);
    expect(find.byKey(const Key('instrument-preview-mist')), findsOneWidget);
    expect(find.byKey(const Key('instrument-name')), findsOneWidget);
    expect(find.byKey(const Key('instrument-save')), findsOneWidget);
  });

  testWidgets('the pad is at least 48 dp in both directions', (tester) async {
    await open(tester);
    final size = tester.getSize(find.byKey(padKey));
    expect(size.width, greaterThanOrEqualTo(48));
    expect(size.height, greaterThanOrEqualTo(48));
  });

  testWidgets('the pad is drawn as a disc with hint rings, not a square', (
    tester,
  ) async {
    await open(tester);
    final box = tester.renderObject(
      find.byWidgetPredicate(
        (w) => w is CustomPaint && w.painter is InstrumentPadPainter,
      ),
    );
    // The disc, its border and at least one concentric ring are circles;
    // nothing is drawn as a rounded square.
    expect(
      box,
      paints
        ..circle()
        ..circle()
        ..circle(),
    );
    expect(box, isNot(paints..rrect()));
    expect(InstrumentPadPainter.ringFractions, isNotEmpty);
    for (final fraction in InstrumentPadPainter.ringFractions) {
      expect(fraction, inExclusiveRange(0, 1));
    }
  });

  testWidgets('the five anchor names are painted as labels', (tester) async {
    await open(tester);
    final box = tester.renderObject(
      find.byWidgetPredicate(
        (w) => w is CustomPaint && w.painter is InstrumentPadPainter,
      ),
    );
    expect(
      box,
      paints
        ..paragraph()
        ..paragraph()
        ..paragraph()
        ..paragraph()
        ..paragraph(),
    );
  });

  testWidgets('touching the pad sets the point and updates the instrument', (
    tester,
  ) async {
    await open(tester);
    final gesture = await tester.startGesture(at(tester, -0.25, 0.5));
    await tester.pump();

    final point = painter(tester).point!;
    expect(point.x, closeTo(-0.25, 1e-6));
    expect(point.y, closeTo(0.5, 1e-6));
    expect(shownInMist(tester).name, 'New instrument');
    expect(shownInMist(tester).harmonics, padHarmonics(point));
    expect(audition.played, isEmpty, reason: 'nothing plays under the finger');
    await gesture.up();
  });

  testWidgets('dragging updates the mist live and plays nothing until the '
      'lift', (tester) async {
    await open(tester);
    final gesture = await tester.startGesture(at(tester, -0.5, -0.5));
    await gesture.moveTo(at(tester, 0, 0));
    await tester.pump();
    final mid = shownInMist(tester);
    await gesture.moveTo(at(tester, 0.6, 0.6));
    await tester.pump();
    final end = shownInMist(tester);

    expect(mid.harmonics, isNot(end.harmonics));
    expect(audition.played, isEmpty);
    await gesture.up();
  });

  testWidgets('lifting the finger plays exactly once', (tester) async {
    await open(tester);
    final gesture = await tester.startGesture(at(tester, -0.2, -0.2));
    await gesture.moveTo(at(tester, 0.5, 0.3));
    await gesture.moveTo(at(tester, 0.5, 0.7));
    await tester.pump();
    expect(audition.played, isEmpty);

    await gesture.up();
    await tester.pump(const Duration(seconds: 1));

    expect(audition.played, hasLength(1));
    expect(audition.frequencies.single.single, closeTo(440, 1e-9));
    expect(
      audition.played.single.harmonics,
      padHarmonics(painter(tester).point!),
    );
  });

  testWidgets('a tap plays once too', (tester) async {
    await open(tester);
    await tester.tapAt(at(tester, 0.3, 0.3));
    await tester.pump(const Duration(seconds: 1));
    expect(audition.played, hasLength(1));
  });

  testWidgets('the dot clamps inside the disc', (tester) async {
    await open(tester);
    final rect = tester.getRect(find.byKey(padKey));
    final gesture = await tester.startGesture(rect.center);
    // Far beyond the bottom right corner of the field: the dot sits on the
    // rim in that direction.
    await gesture.moveTo(rect.bottomRight + const Offset(300, 300));
    await tester.pump();
    var point = painter(tester).point!;
    expect(point.radius, closeTo(1, 1e-9));
    expect(point.angle, closeTo(pi / 4, 1e-9));

    await gesture.moveTo(rect.topLeft - const Offset(300, 300));
    await tester.pump();
    point = painter(tester).point!;
    expect(point.radius, closeTo(1, 1e-9));
    expect(point.angle, closeTo(-3 * pi / 4, 1e-9));

    final dot = padOffsetOf(point, rect.size);
    final from = rect.size.center(Offset.zero);
    expect(
      (dot - from).distance,
      lessThanOrEqualTo(padDiscRadius(rect.size) + 1e-9),
    );
    expect(dot.dx, greaterThan(0));
    expect(dot.dy, greaterThan(0));
    await gesture.up();
  });

  testWidgets('a touch in the corner of the square lands on the rim', (
    tester,
  ) async {
    await open(tester);
    final rect = tester.getRect(find.byKey(padKey));
    await tester.tapAt(rect.topRight + const Offset(-2, 2));
    await tester.pump(const Duration(seconds: 1));
    final point = painter(tester).point!;
    expect(point.radius, closeTo(1, 1e-9));
    expect(point.angle, closeTo(-pi / 4, 0.1));
  });

  testWidgets('the anchor names are drawn as labels', (tester) async {
    await open(tester);
    expect(painter(tester).anchors.map((a) => a.name), [
      'warm drone',
      'airy pad',
      'bass',
      'guitar',
      'click',
    ]);
  });

  testWidgets('touching the pad does not scroll the page', (tester) async {
    await open(tester);
    final scrollable = tester.state<ScrollableState>(
      find.byType(Scrollable).first,
    );
    await tester.dragFrom(at(tester, 0, 0.9), const Offset(0, -200));
    await tester.pump();
    expect(scrollable.position.pixels, 0);
  });

  group('semantics', () {
    testWidgets('angle and distance have plain labels and adjust actions', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await open(tester);
      expect(characterLabel, 'Character, turn around the circle');
      expect(strengthLabel, 'Strength, centre to rim');
      for (final label in [characterLabel, strengthLabel]) {
        final node = nodeLabelled(label);
        expect(
          node,
          isSemantics(hasIncreaseAction: true, hasDecreaseAction: true),
        );
      }
      handle.dispose();
    });

    testWidgets('strength moves the dot along its direction and plays once', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await open(tester);

      adjust(tester, strengthLabel, SemanticsAction.increase);
      await tester.pump(const Duration(seconds: 1));
      var point = painter(tester).point!;
      expect(point.radius, closeTo(padStepRadius, 1e-9));
      expect(point.angle, closeTo(-pi / 2, 1e-9));
      expect(audition.played, hasLength(1));

      adjust(tester, strengthLabel, SemanticsAction.increase);
      await tester.pump(const Duration(seconds: 1));
      point = painter(tester).point!;
      expect(point.radius, closeTo(2 * padStepRadius, 1e-9));
      expect(point.angle, closeTo(-pi / 2, 1e-9));
      expect(audition.played, hasLength(2));
      handle.dispose();
    });

    testWidgets('character turns the dot around the circle and plays once', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await open(tester);

      adjust(tester, characterLabel, SemanticsAction.increase);
      await tester.pump(const Duration(seconds: 1));
      var point = painter(tester).point!;
      expect(point.radius, closeTo(0.5, 1e-9));
      expect(point.angle, closeTo(-pi / 2 + padStepAngle, 1e-9));
      expect(audition.played, hasLength(1));

      adjust(tester, characterLabel, SemanticsAction.decrease);
      await tester.pump(const Duration(seconds: 1));
      point = painter(tester).point!;
      expect(point.radius, closeTo(0.5, 1e-9));
      expect(point.angle, closeTo(-pi / 2, 1e-9));
      expect(audition.played, hasLength(2));
      handle.dispose();
    });

    testWidgets('values are spoken in plain words', (tester) async {
      final handle = tester.ensureSemantics();
      await open(tester);
      expect(nodeLabelled(characterLabel).value, 'Not set');
      expect(nodeLabelled(strengthLabel).value, 'Not set');

      adjust(tester, strengthLabel, SemanticsAction.increase);
      await tester.pump(const Duration(seconds: 1));
      expect(nodeLabelled(strengthLabel).value, '10 percent');
      expect(nodeLabelled(characterLabel).value, startsWith('Closest to '));

      await tester.tapAt(at(tester, 0, 0.9));
      await tester.pump(const Duration(seconds: 1));
      expect(nodeLabelled(characterLabel).value, 'Closest to click');
      expect(nodeLabelled(strengthLabel).value, '90 percent');
      handle.dispose();
    });

    testWidgets('adjusting at the rim stays in range', (tester) async {
      final handle = tester.ensureSemantics();
      await open(tester);
      for (var i = 0; i < 30; i++) {
        adjust(tester, strengthLabel, SemanticsAction.increase);
        await tester.pump();
      }
      await tester.pump(const Duration(seconds: 1));
      expect(painter(tester).point!.radius, closeTo(1, 1e-9));
      for (var i = 0; i < 60; i++) {
        adjust(tester, characterLabel, SemanticsAction.increase);
        await tester.pump();
      }
      await tester.pump(const Duration(seconds: 1));
      expect(painter(tester).point!.radius, closeTo(1, 1e-9));
      expect(tester.takeException(), isNull);
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
      await open(tester);
      final banned = RegExp(
        r'harmonic|attack|decay|envelope|spectrum|\bEQ\b|\bdB\b|\bHz\b',
        caseSensitive: false,
      );
      for (final text in tester.widgetList<Text>(find.byType(Text))) {
        expect(text.data ?? '', isNot(matches(banned)));
      }
      final labels = [
        for (final node
            in tester.semantics.simulatedAccessibilityTraversal()) ...[
          node.label,
          node.value,
          node.hint,
        ],
      ];
      for (final label in labels) {
        expect(label, isNot(matches(banned)));
      }
      handle.dispose();
    });
  });

  group('opening a saved instrument', () {
    final saved = factoryInstruments[2].copyWith(id: 'saved-1', name: 'Bell');

    testWidgets('hides the dot and says touching starts a new sound', (
      tester,
    ) async {
      await open(tester, instrument: saved, existing: true);
      expect(painter(tester).point, isNull);
      expect(find.textContaining('starts a new sound'), findsOneWidget);
      expect(find.text('Saved'), findsOneWidget);
    });

    testWidgets('the first touch shows the dot and replaces the draft, but '
        'the library only after Save', (tester) async {
      await open(tester, instrument: saved, existing: true);
      await tester.tapAt(at(tester, 0.6, -0.4));
      await tester.pump(const Duration(seconds: 1));

      expect(painter(tester).point, isNotNull);
      expect(find.textContaining('starts a new sound'), findsNothing);
      expect(find.text('Unsaved changes'), findsOneWidget);
      expect(library.snapshot.value.instruments.single, saved);

      await tester.tap(find.byKey(const Key('instrument-save')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final stored = library.snapshot.value.instruments.single;
      expect(stored.id, 'saved-1');
      expect(stored.name, 'Bell');
      expect(stored.harmonics, isNot(saved.harmonics));
    });
  });

  testWidgets('a new instrument can be named and saved from the pad', (
    tester,
  ) async {
    await open(tester);
    await tester.enterText(find.byKey(const Key('instrument-name')), 'Glow');
    await tester.tapAt(at(tester, -0.6, -0.6));
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.byKey(const Key('instrument-save')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final stored = library.snapshot.value.instruments.single;
    expect(stored.name, 'Glow');
    expect(stored.harmonics, padHarmonics(painter(tester).point!));
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
}
