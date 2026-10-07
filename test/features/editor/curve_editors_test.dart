import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synesterra/app/synesterra_app.dart';
import 'package:synesterra/data/repositories/impl/in_memory_instrument_library_repository.dart';
import 'package:synesterra/features/editor/curve_geometry.dart';
import 'package:synesterra/features/editor/envelope_editor.dart';
import 'package:synesterra/features/editor/eq_editor.dart';
import 'package:synesterra/features/editor/instrument_editor_view_model.dart';
import 'package:synesterra_core/synesterra_core.dart';

import 'audition_fakes.dart';

late RecordingAudition audition;

Future<void> openEditor(
  WidgetTester tester, {
  Size size = const Size(800, 3200),
}) async {
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
}

Future<void> pastDelay(WidgetTester tester) => tester.pump(
  InstrumentEditorViewModel.auditionDelay + const Duration(milliseconds: 50),
);

Finder get envelope => find.byKey(const Key('envelope-graph'));
Finder get eq => find.byKey(const Key('eq-graph'));

/// The screen position of a point on the envelope graph.
Offset envelopeAt(WidgetTester tester, double seconds, double level) {
  final rect = tester.getRect(envelope);
  return Offset(
    rect.left + envelopeTimeToX(seconds, rect.width),
    rect.top + (rect.height - EnvelopeEditor.labelHeight) * (1 - level),
  );
}

/// The screen position of a gain at a frequency on the EQ graph.
Offset eqAt(WidgetTester tester, double hz, double db) {
  final rect = tester.getRect(eq);
  return Offset(
    rect.left + hzToX(hz, rect.width),
    rect.top + dbToY(db, rect.height - EqEditor.labelHeight),
  );
}

Instrument played() => audition.played.last;

/// Scrolls the panel (without touching any graph) until [target] is built and
/// visible. The list is lazy, so a graph far down does not exist yet.
Future<ScrollableState> scrollTo(WidgetTester tester, Finder target) async {
  final scrollable = find
      .descendant(of: find.byType(ListView), matching: find.byType(Scrollable))
      .first;
  final state = tester.state<ScrollableState>(scrollable);
  for (var i = 0; i < 60 && target.evaluate().isEmpty; i++) {
    state.position.jumpTo(state.position.pixels + 300);
    await tester.pump();
  }
  expect(target, findsOneWidget);
  await tester.ensureVisible(target);
  await tester.pump();
  return state;
}

void main() {
  group('envelope graph', () {
    // A new instrument is the sine preset: attack 2 ms, decay 120 ms.
    testWidgets('both graphs are in the panel with a label for TalkBack', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await openEditor(tester);
      expect(envelope, findsOneWidget);
      expect(eq, findsOneWidget);
      expect(
        find.bySemanticsLabel(
          RegExp(r'^Envelope graph. Attack 2 milliseconds'),
        ),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel(RegExp(r'^EQ graph')), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('dragging the peak sets the attack, then plays once', (
      tester,
    ) async {
      await openEditor(tester);
      final gesture = await tester.startGesture(envelopeAt(tester, 0.002, 1));
      await gesture.moveTo(envelopeAt(tester, 0.1, 1));
      await gesture.moveTo(envelopeAt(tester, 0.2, 1));
      expect(audition.played, isEmpty, reason: 'not while dragging');
      await gesture.up();
      await pastDelay(tester);

      expect(played().attackMs, closeTo(200, 2));
      expect(played().decayMs, 120, reason: 'the decay is untouched');
      expect(audition.played, hasLength(1));
    });

    testWidgets('dragging the end sets the decay', (tester) async {
      await openEditor(tester);
      // The end of the decay is at attack + decay = 0.122 s.
      final gesture = await tester.startGesture(
        envelopeAt(tester, 0.122, envelopeFloor),
      );
      await gesture.moveTo(envelopeAt(tester, 1.0, envelopeFloor));
      await gesture.up();
      await pastDelay(tester);

      // 1.0 s from the hit, minus the 2 ms attack.
      expect(played().decayMs, closeTo(998, 10));
      expect(played().attackMs, 2);
    });

    testWidgets('the attack clamps to 0..500 ms', (tester) async {
      await openEditor(tester);
      var gesture = await tester.startGesture(envelopeAt(tester, 0.002, 1));
      await gesture.moveBy(const Offset(2000, 0));
      await gesture.up();
      await pastDelay(tester);
      expect(played().attackMs, Instrument.maxAttackMs);
    });

    testWidgets('the attack can be dragged back to 0', (tester) async {
      await openEditor(tester);
      final gesture = await tester.startGesture(envelopeAt(tester, 0.002, 1));
      await gesture.moveBy(const Offset(-500, 0));
      await gesture.up();
      await pastDelay(tester);
      expect(played().attackMs, 0);
    });

    testWidgets('the decay clamps to 20..5000 ms', (tester) async {
      await openEditor(tester);
      var gesture = await tester.startGesture(
        envelopeAt(tester, 0.122, envelopeFloor),
      );
      await gesture.moveBy(const Offset(2000, 0));
      await gesture.up();
      await pastDelay(tester);
      expect(played().decayMs, Instrument.maxDecayMs);

      audition.played.clear();
      final rect = tester.getRect(envelope);
      gesture = await tester.startGesture(
        Offset(
          rect.left + envelopeTimeToX(5.002, rect.width),
          rect.top +
              (rect.height - EnvelopeEditor.labelHeight) * (1 - envelopeFloor),
        ),
      );
      await gesture.moveBy(const Offset(-4000, 0));
      await gesture.up();
      await pastDelay(tester);
      expect(played().decayMs, Instrument.minDecayMs);
    });

    testWidgets('a touch far from both handles changes nothing', (
      tester,
    ) async {
      await openEditor(tester);
      final gesture = await tester.startGesture(envelopeAt(tester, 2.5, 0.5));
      await gesture.moveBy(const Offset(40, 0));
      await gesture.up();
      await pastDelay(tester);

      expect(audition.played, isEmpty);
      expect(find.text('Unsaved changes'), findsNothing);
    });

    testWidgets('the sliders follow the graph', (tester) async {
      await openEditor(tester);
      final gesture = await tester.startGesture(envelopeAt(tester, 0.002, 1));
      await gesture.moveTo(envelopeAt(tester, 0.3, 1));
      await gesture.up();
      await pastDelay(tester);

      expect(find.textContaining(RegExp(r'^\d+ ms$')), findsWidgets);
      expect(find.text('${played().attackMs} ms'), findsOneWidget);
    });

    testWidgets('dragging marks the instrument as changed', (tester) async {
      await openEditor(tester);
      final gesture = await tester.startGesture(envelopeAt(tester, 0.002, 1));
      await gesture.moveBy(const Offset(40, 0));
      await tester.pump();
      await gesture.up();
      await pastDelay(tester);
      expect(find.text('Unsaved changes'), findsOneWidget);
    });
  });

  group('EQ graph', () {
    testWidgets('dragging the mid handle sets the mid gain only', (
      tester,
    ) async {
      await openEditor(tester);
      final gesture = await tester.startGesture(eqAt(tester, 1000, 0));
      await gesture.moveTo(eqAt(tester, 1000, 6));
      expect(audition.played, isEmpty, reason: 'not while dragging');
      await gesture.up();
      await pastDelay(tester);

      expect(played().eq.midDb, closeTo(6, 0.5));
      expect(played().eq.lowDb, 0);
      expect(played().eq.highDb, 0);
      expect(audition.played, hasLength(1));
    });

    testWidgets('the low and high handles set their own bands', (tester) async {
      await openEditor(tester);
      var gesture = await tester.startGesture(eqAt(tester, 200, 0));
      await gesture.moveTo(eqAt(tester, 200, -8));
      await gesture.up();
      await pastDelay(tester);
      expect(played().eq.lowDb, closeTo(-8, 0.5));

      gesture = await tester.startGesture(eqAt(tester, 4000, 0));
      await gesture.moveTo(eqAt(tester, 4000, 9));
      await gesture.up();
      await pastDelay(tester);
      expect(played().eq.highDb, closeTo(9, 0.5));
      expect(played().eq.lowDb, closeTo(-8, 0.5), reason: 'kept');
    });

    testWidgets('the gain clamps to ±12 dB and moves in half decibels', (
      tester,
    ) async {
      await openEditor(tester);
      var gesture = await tester.startGesture(eqAt(tester, 1000, 0));
      await gesture.moveBy(const Offset(0, -900));
      await gesture.up();
      await pastDelay(tester);
      expect(played().eq.midDb, 12);

      audition.played.clear();
      gesture = await tester.startGesture(eqAt(tester, 1000, 12));
      await gesture.moveBy(const Offset(0, 900));
      await gesture.up();
      await pastDelay(tester);
      expect(played().eq.midDb, -12);
      expect((played().eq.midDb * 2) % 1, 0);
    });

    testWidgets('the handle keeps its frequency while it is dragged sideways', (
      tester,
    ) async {
      await openEditor(tester);
      final gesture = await tester.startGesture(eqAt(tester, 1000, 0));
      await gesture.moveBy(const Offset(120, -20));
      await gesture.up();
      await pastDelay(tester);
      // Only the gain changed; there is no frequency in the model.
      expect(played().eq.midDb, isNot(0));
    });

    testWidgets('a touch far from every handle changes nothing', (
      tester,
    ) async {
      await openEditor(tester);
      final gesture = await tester.startGesture(eqAt(tester, 90, 10));
      await gesture.moveBy(const Offset(0, 30));
      await gesture.up();
      await pastDelay(tester);

      expect(audition.played, isEmpty);
      expect(find.text('Unsaved changes'), findsNothing);
    });

    testWidgets('the sliders follow the graph', (tester) async {
      await openEditor(tester);
      final gesture = await tester.startGesture(eqAt(tester, 1000, 0));
      await gesture.moveTo(eqAt(tester, 1000, 6));
      await gesture.up();
      await pastDelay(tester);

      expect(
        find.text('+${played().eq.midDb.toStringAsFixed(1)} dB'),
        findsOneWidget,
      );
    });

    testWidgets('changing the test note redraws the harmonic ticks', (
      tester,
    ) async {
      await openEditor(tester);
      await tester.tap(find.byKey(const Key('test-root-0')));
      await pastDelay(tester);
      await tester.tap(find.text('Chord'));
      await pastDelay(tester);
      expect(tester.takeException(), isNull);
      expect(eq, findsOneWidget);
    });
  });

  group('both graphs', () {
    testWidgets('touching a graph does not scroll the page', (tester) async {
      await openEditor(tester, size: const Size(800, 600));
      final state = await scrollTo(tester, envelope);
      final before = state.position.pixels;

      final gesture = await tester.startGesture(envelopeAt(tester, 0.002, 1));
      await gesture.moveBy(const Offset(30, 60));
      await gesture.moveBy(const Offset(0, -80));
      await gesture.up();
      await pastDelay(tester);

      expect(state.position.pixels, before);
    });

    testWidgets('an EQ handle drag does not scroll the page either', (
      tester,
    ) async {
      await openEditor(tester, size: const Size(800, 600));
      final state = await scrollTo(tester, eq);
      final before = state.position.pixels;

      final gesture = await tester.startGesture(eqAt(tester, 1000, 0));
      await gesture.moveBy(const Offset(0, -50));
      await gesture.moveBy(const Offset(0, 90));
      await gesture.up();
      await pastDelay(tester);

      expect(state.position.pixels, before);
      expect(audition.played, isNotEmpty);
    });
  });
}
