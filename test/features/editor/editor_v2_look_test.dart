// Visual language v2 on the Editor shell and the Loop panel (UX-119): the
// round components are in place, every control is 48 dp and labelled, the
// tap flash of the steps goes through the flash gate, the Editor sits in the
// shared still frame, and every text colour
// keeps 4.5:1 on what it is drawn on.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synesterra/data/repositories/impl/in_memory_instrument_library_repository.dart';
import 'package:synesterra/data/repositories/impl/in_memory_loop_library_repository.dart';
import 'package:synesterra/data/repositories/impl/noop_instrument_audition_repository.dart';
import 'package:synesterra/features/editor/editor_style.dart';
import 'package:synesterra/features/editor/editor_view.dart';
import 'package:synesterra/features/editor/step_grid.dart';
import 'package:synesterra/shared/loop_view/loop_view.dart';
import 'package:synesterra/shared/theme/ambient_scope.dart';
import 'package:synesterra/shared/theme/round_shapes.dart';
import 'package:synesterra/shared/theme/surfaces.dart';
import 'package:synesterra/shared/theme/synesterra_theme.dart';
import 'package:synesterra/shared/theme/tap_effect.dart';
import 'package:synesterra/shared/widgets/round_components.dart';
import 'package:synesterra/shared/widgets/round_screen.dart';
import 'package:synesterra/shared/widgets/tap_glitch.dart';

import 'loop_fakes.dart';

/// The test's clock for the flash gate.
Duration _now = Duration.zero;

Future<void> _pumpEditor(
  WidgetTester tester, {
  bool reduceMotion = false,
  EditorTab tab = EditorTab.loop,
  Size size = const Size(480, 3000),
  double textScale = 1,
}) async {
  _now = const Duration(seconds: 10);
  if (reduceMotion) {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  }
  tester.view
    ..devicePixelRatio = 1
    ..physicalSize = size;
  addTearDown(tester.view.reset);
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  await tester.pumpWidget(
    MaterialApp(
      theme: synesterraTheme(SynesterraPalette.graphite),
      home: AmbientScope(
        palette: editorPalette(SynesterraTokens.graphite),
        tapStrength: GlitchStrength.strong,
        gate: FlashGate(clock: () => _now),
        child: EditorView(
          instrumentLibrary: InMemoryInstrumentLibraryRepository(),
          instrumentAudition: NoopInstrumentAuditionRepository(),
          loopLibrary: InMemoryLoopLibraryRepository(),
          playback: RecordingPlayback(),
          initialTab: tab,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

StepPainter _step(WidgetTester tester, String key) =>
    tester
            .widget<CustomPaint>(
              find.descendant(
                of: find.byKey(Key(key)),
                matching: find.byType(CustomPaint),
              ),
            )
            .painter!
        as StepPainter;

Future<void> _frames(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

void main() {
  testWidgets('the Loop panel is built from the round components', (
    tester,
  ) async {
    await _pumpEditor(tester);
    final list = find.byKey(const Key('loop-panel-list'));

    // Play/Stop: the gold disc on a glass capsule.
    final play = find.byKey(const Key('loop-play'));
    expect(
      find.descendant(of: play, matching: find.byType(RoundActionButton)),
      findsOneWidget,
    );
    expect(
      find.ancestor(of: play, matching: find.byType(GlassPanel)),
      findsOne,
    );
    // Actions are capsule chips.
    for (final key in ['loop-open', 'loop-save', 'loop-add-layer']) {
      expect(
        tester.widget(find.byKey(Key(key))),
        isA<TactileChip>(),
        reason: key,
      );
    }
    // Layers are organic pebbles, not boxes.
    final card = tester.widget<RoundSurface>(find.byKey(const Key('layer-0')));
    expect(card.style, SurfaceStyle.organic);
    expect(card.shape, isA<PebbleShape>());
    // Steps are round painted buttons, without Material ink.
    expect(_step(tester, 'step-0-0'), isA<StepPainter>());
    expect(
      find.descendant(
        of: find.byKey(const Key('step-0-0')),
        matching: find.byType(InkWell),
      ),
      findsNothing,
    );
    // No rectangular Material buttons are left in the panel.
    for (final type in [
      FilledButton,
      OutlinedButton,
      IconButton,
      ChoiceChip,
      Slider,
    ]) {
      expect(
        find.descendant(of: list, matching: find.byType(type)),
        findsNothing,
        reason: '$type',
      );
    }
    // The view switch is the shared tray with the choice raised.
    expect(
      find.descendant(
        of: find.byKey(const Key('loop-view')),
        matching: find.byType(RoundSegmented<LoopViewMode>),
      ),
      findsOneWidget,
    );
    // Glass is painted, never a live blur.
    expect(find.byType(BackdropFilter), findsNothing);
  });

  for (final textScale in [1.0, 1.5]) {
    testWidgets('the Loop panel fits a 320 dp screen at text scale '
        '$textScale', (tester) async {
      await _pumpEditor(
        tester,
        size: const Size(320, 4000),
        textScale: textScale,
      );
      expect(tester.takeException(), isNull);
      // Up to the longest pattern: 16 steps wrap inside the card.
      for (var i = 0; i < 14; i++) {
        await tester.tap(find.byKey(const Key('layer-hits-0')).last);
        await tester.tap(
          find.descendant(
            of: find.byKey(const Key('layer-hits-0')),
            matching: find.byIcon(Icons.add),
          ),
          warnIfMissed: false,
        );
        await tester.pump();
      }
      await tester.tap(find.byKey(const Key('loop-add-layer')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      for (final key in [
        'layer-remove-0',
        'layer-note-0',
        'layer-sound-0',
        'loop-play',
        'loop-save',
      ]) {
        expect(
          tester.getRect(find.byKey(Key(key))).right,
          lessThanOrEqualTo(320),
          reason: key,
        );
      }
      // Rolled loops (up to four layers of up to 16 hits) still fit, and so
      // do the dice and undo. The seeds are random, so roll several.
      for (var roll = 0; roll < 10; roll++) {
        await tester.tap(find.byKey(const Key('loop-randomize')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'roll $roll');
      }
      for (final key in ['loop-randomize', 'loop-randomize-undo']) {
        expect(
          tester.getRect(find.byKey(Key(key))).right,
          lessThanOrEqualTo(320),
          reason: key,
        );
      }
    });
  }

  testWidgets('the dice is a round button labelled for screen readers whose '
      'flash goes through the shared gate', (tester) async {
    final semantics = tester.ensureSemantics();
    await _pumpEditor(tester);
    final dice = find.byKey(const Key('loop-randomize'));
    expect(tester.widget(dice), isA<RoundIconButton>());
    expect(tester.getSemantics(dice).label, 'Randomize loop');
    expect(find.byKey(const Key('loop-randomize-undo')), findsNothing);

    await tester.tap(dice);
    await tester.pump(const Duration(milliseconds: 16));
    final glitch =
        tester
                .widget<CustomPaint>(
                  find
                      .descendant(
                        of: find.descendant(
                          of: dice,
                          matching: find.byType(TapGlitch),
                        ),
                        matching: find.byType(CustomPaint),
                      )
                      .first,
                )
                .foregroundPainter!
            as TapGlitchPainter;
    expect(glitch.flash.isAnimating, isTrue);
    final undo = find.byKey(const Key('loop-randomize-undo'));
    expect(tester.widget(undo), isA<RoundIconButton>());
    expect(tester.getSemantics(undo).label, 'Undo randomize');

    // The same gate: a step tapped within a third of a second edits
    // without a flash of its own.
    _now += const Duration(milliseconds: 100);
    await tester.tap(find.byKey(const Key('step-0-0')));
    await tester.pump(const Duration(milliseconds: 16));
    expect(_step(tester, 'step-0-0').glitch, isNull);
    await tester.pumpAndSettle();
    semantics.dispose();
  });

  testWidgets('every control of the shell and the Loop panel is 48 dp and '
      'labelled', (tester) async {
    final semantics = tester.ensureSemantics();
    await _pumpEditor(tester);
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    expect(
      tester.getSize(find.byKey(const Key('step-0-0'))),
      const Size(48, 48),
    );
    for (final key in [
      'editor-tab-instrument',
      'editor-tab-loop',
      'editor-tab-arrangement',
    ]) {
      expect(
        tester.getSize(find.byKey(Key(key))).height,
        greaterThanOrEqualTo(48),
        reason: key,
      );
    }
    semantics.dispose();
  });

  testWidgets('a step keeps its label and answers a tap with a flash that '
      'the gate limits to three a second', (tester) async {
    final semantics = tester.ensureSemantics();
    await _pumpEditor(tester);
    expect(
      tester.getSemantics(find.byKey(const Key('step-0-1'))).label,
      'Layer 1, hit 2: on',
    );

    await tester.tap(find.byKey(const Key('step-0-1')));
    await tester.pump(const Duration(milliseconds: 16));
    expect(
      tester.getSemantics(find.byKey(const Key('step-0-1'))).label,
      'Layer 1, hit 2: strong',
    );
    final first = _step(tester, 'step-0-1').glitch;
    expect(first, isNotNull);
    expect(first!.mode, GlitchMode.full);
    expect(first.flash.isAnimating, isTrue);

    // A second tap within a third of a second still edits, without a flash.
    _now += const Duration(milliseconds: 100);
    await tester.tap(find.byKey(const Key('step-0-2')));
    await tester.pump(const Duration(milliseconds: 16));
    expect(
      tester.getSemantics(find.byKey(const Key('step-0-2'))).label,
      'Layer 1, hit 3: strong',
    );
    expect(_step(tester, 'step-0-2').glitch, isNull);

    // Later, it flashes again; the flash is over within a quarter second.
    _now += const Duration(milliseconds: 400);
    await tester.tap(find.byKey(const Key('step-0-0')));
    await tester.pump(const Duration(milliseconds: 16));
    expect(_step(tester, 'step-0-0').glitch, isNotNull);
    await tester.pump(glitchDuration + const Duration(milliseconds: 20));
    expect(_step(tester, 'step-0-0').glitch!.flash.isAnimating, isFalse);
    semantics.dispose();
  });

  testWidgets('under reduce motion a step flash is a plain fade', (
    tester,
  ) async {
    await _pumpEditor(tester, reduceMotion: true);
    await tester.tap(find.byKey(const Key('step-1-0')));
    await tester.pump(const Duration(milliseconds: 16));
    expect(_step(tester, 'step-1-0').glitch!.mode, GlitchMode.fade);
  });

  testWidgets('the Editor sits in the shared still frame', (tester) async {
    await _pumpEditor(tester);
    expect(find.byType(RoundScreen), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(RoundScreen),
        matching: find.text('Editor'),
      ),
      findsOneWidget,
    );
    // A silent Editor schedules no frames: nothing drifts, nothing ticks.
    expect(tester.binding.hasScheduledFrame, isFalse);

    // Playing moves only the picture; stopping brings everything to rest,
    // and the frame goes away cleanly with the Editor.
    await tester.tap(find.byKey(const Key('loop-play')));
    await _frames(tester);
    await tester.tap(find.byKey(const Key('loop-play')));
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });

  testWidgets('dialogs are pebbles and sheets are glass lenses', (
    tester,
  ) async {
    await _pumpEditor(tester);
    await tester.tap(find.byKey(const Key('layer-note-0')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<Material>(
            find
                .descendant(
                  of: find.byType(AlertDialog),
                  matching: find.byType(Material),
                )
                .first,
          )
          .shape,
      isA<PebbleBorder>(),
    );
    await tester.tap(find.byKey(const Key('note-cancel')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('layer-sound-0')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<Material>(
            find
                .descendant(
                  of: find.byType(BottomSheet),
                  matching: find.byType(Material),
                )
                .first,
          )
          .shape,
      isA<GlassLensBorder>(),
    );
  });

  test('every text colour of the shell and the Loop panel keeps its '
      'contrast on every palette and layer colour', () {
    for (final palette in SynesterraPalette.values) {
      final theme = synesterraTheme(palette);
      final tokens = theme.extension<SynesterraTokens>()!;
      for (final rule in editorTextRules(tokens, theme.colorScheme.error)) {
        expect(
          rule.pair.worstContrast,
          greaterThanOrEqualTo(rule.minimum),
          reason: '${palette.name}: ${rule.pair.name}',
        );
      }
    }
  });
}
