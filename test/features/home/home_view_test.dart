import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synesterra/features/home/home_view.dart';
import 'package:synesterra/shared/theme/ground_palette.dart';
import 'package:synesterra/shared/theme/surfaces.dart';
import 'package:synesterra/shared/theme/synesterra_theme.dart';
import 'package:synesterra/shared/theme/tap_effect.dart';
import 'package:synesterra/shared/widgets/round_screen.dart';
import 'package:synesterra/shared/widgets/tap_glitch.dart';

var _opened = <String>[];

Future<void> _pumpHome(
  WidgetTester tester, {
  bool reduceMotion = false,
  bool withMenu = true,
}) async {
  _opened = [];
  tester.view
    ..physicalSize = const Size(412, 892)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  if (reduceMotion) {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  }
  await tester.pumpWidget(
    MaterialApp(
      theme: synesterraTheme(SynesterraPalette.graphite),
      home: HomeView(
        onOpenEditor: () => _opened.add('editor'),
        onOpenLibrary: () => _opened.add('library'),
        onOpenTraining: () => _opened.add('training'),
        onPaletteChanged: withMenu ? (_) {} : null,
      ),
    ),
  );
}

Iterable<TapGlitchPainter> _glitches(WidgetTester tester) => tester
    .widgetList<CustomPaint>(find.byType(CustomPaint))
    .map((paint) => paint.foregroundPainter)
    .whereType<TapGlitchPainter>();

void main() {
  test('the start screen follows the app default palette, Graphite', () {
    final home = HomeView(
      onOpenEditor: () {},
      onOpenLibrary: () {},
      onOpenTraining: () {},
    );
    expect(home.palette, SynesterraPalette.graphite);
  });

  testWidgets('three round entries open their places', (tester) async {
    await _pumpHome(tester, withMenu: false);
    for (final key in ['home-editor', 'home-library', 'home-training']) {
      await tester.tap(find.byKey(Key(key)));
    }
    expect(_opened, ['editor', 'library', 'training']);
    expect(find.byKey(const Key('home-audio-spike')), findsNothing);
    // Each entry has the tap effect and sits in a round shape, never in a
    // rounded rectangle or an ink well.
    expect(
      find.descendant(
        of: find.byType(HomeView),
        matching: find.byType(InkWell),
      ),
      findsNothing,
    );
    expect(find.byType(BackdropFilter), findsNothing);
    await tester.pump(glitchDuration);
  });

  testWidgets('entries and the menu are 48 dp and labelled', (tester) async {
    final handle = tester.ensureSemantics();
    await _pumpHome(tester);
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    for (final key in ['home-editor', 'home-library', 'home-training']) {
      final size = tester.getSize(find.byKey(Key(key)));
      expect(size.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));
    }
    expect(find.bySemanticsLabel(RegExp(r'^Editor\. Shape')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp(r'^Library\. Your')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp(r'^Training\. Tap')), findsOneWidget);
    handle.dispose();
  });

  testWidgets('the drift is one breath and then the screen is at rest', (
    tester,
  ) async {
    await _pumpHome(tester);
    expect(tester.binding.transientCallbackCount, greaterThan(0));
    await tester.pump(driftPeriod + const Duration(seconds: 1));
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.binding.hasScheduledFrame, isFalse);

    // A touch wakes it for one more breath.
    final gesture = await tester.startGesture(const Offset(200, 20));
    await tester.pump();
    expect(tester.binding.transientCallbackCount, greaterThan(0));
    await gesture.up();
    await tester.pump(driftPeriod + const Duration(seconds: 1));
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('under reduce motion nothing drifts and a tap only fades', (
    tester,
  ) async {
    await _pumpHome(tester, reduceMotion: true);
    expect(tester.binding.transientCallbackCount, 0);
    await tester.tap(find.byKey(const Key('home-editor')));
    await tester.pump();
    expect(_glitches(tester), isNotEmpty);
    expect(_glitches(tester).every((g) => g.mode == GlitchMode.fade), isTrue);
    await tester.pump(glitchDuration);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('the drift controller is disposed with the screen', (
    tester,
  ) async {
    await _pumpHome(tester);
    expect(tester.binding.transientCallbackCount, greaterThan(0));
    await tester.pumpWidget(const SizedBox());
    // A ticker that outlived its State would fail the test on teardown.
    expect(tester.binding.transientCallbackCount, 0);
  });

  test('text on the mist keeps 4.5:1 in every palette', () {
    for (final palette in SynesterraPalette.values) {
      final tokens = SynesterraTokens.forPalette(palette);
      final ground = GroundPalette.of(
        tokens,
        GroundTone.dark,
        tokens.layerColors.first,
      );
      // The brightest place of the mist: both lights over the ground.
      final gold = Color.alphaBlend(
        ground.accent.withValues(alpha: MistGroundPainter.goldAlpha),
        ground.ground,
      );
      final both = Color.alphaBlend(
        ground.text.withValues(alpha: MistGroundPainter.coolAlpha),
        gold,
      );
      for (final under in [ground.ground, gold, both]) {
        expect(
          contrastRatio(ground.text, under),
          greaterThanOrEqualTo(4.5),
          reason: '${palette.name} text',
        );
        expect(
          contrastRatio(ground.muted, under),
          greaterThanOrEqualTo(4.5),
          reason: '${palette.name} muted',
        );
      }
      // Glass (the Library's empty states) is tested over the brightest
      // ground the surfaces tests already know; the mist must not be
      // brighter than that.
      final brightest = ground.groundSamples
          .map((c) => c.computeLuminance())
          .reduce((a, b) => a > b ? a : b);
      expect(both.computeLuminance(), lessThanOrEqualTo(brightest));
      expect(
        Surfaces(ground).textPairs().every((p) => p.worstContrast >= 4.5),
        isTrue,
      );
    }
  });
}
