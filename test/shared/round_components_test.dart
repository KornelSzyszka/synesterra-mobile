import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synesterra/shared/theme/ambient_scope.dart';
import 'package:synesterra/shared/theme/ground_palette.dart';
import 'package:synesterra/shared/theme/round_shapes.dart';
import 'package:synesterra/shared/theme/synesterra_theme.dart';
import 'package:synesterra/shared/theme/tap_effect.dart';
import 'package:synesterra/shared/widgets/round_components.dart';
import 'package:synesterra/shared/widgets/tap_glitch.dart';

/// The test's clock for the flash gate.
Duration _now = Duration.zero;

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  bool reduceMotion = false,
  GlitchStrength? strength,
  GroundTone tone = GroundTone.dark,
  SynesterraTokens? tokens,
}) async {
  _now = const Duration(seconds: 10);
  if (reduceMotion) {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  }
  final theme = synesterraTheme(SynesterraPalette.graphite);
  final themed = tokens == null ? theme : theme.copyWith(extensions: [tokens]);
  final t = tokens ?? SynesterraTokens.graphite;
  await tester.pumpWidget(
    MaterialApp(
      theme: themed,
      home: Scaffold(
        body: AmbientScope(
          palette: GroundPalette.of(t, tone, t.layerColors.first),
          tapStrength: strength,
          gate: FlashGate(clock: () => _now),
          child: Center(child: child),
        ),
      ),
    ),
  );
  // Let a theme change between pumps finish its cross-fade.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Iterable<TapGlitchPainter> _glitches(WidgetTester tester) => tester
    .widgetList<CustomPaint>(find.byType(CustomPaint))
    .map((paint) => paint.foregroundPainter)
    .whereType<TapGlitchPainter>();

bool _flashing(WidgetTester tester) =>
    _glitches(tester).any((painter) => painter.flash.isAnimating);

Widget _gallery({
  VoidCallback? onPlay,
  ValueChanged<String>? onSegment,
  ValueChanged<double>? onLevel,
}) => SingleChildScrollView(
  child: Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      RoundActionButton(
        key: const Key('play'),
        icon: Icons.play_arrow_rounded,
        label: 'Play',
        onPressed: onPlay ?? () {},
      ),
      RoundIconButton(
        key: const Key('loop'),
        icon: Icons.repeat_rounded,
        label: 'Loop',
        selected: true,
        onPressed: () {},
      ),
      RoundIconButton(
        icon: Icons.stop_rounded,
        label: 'Stop',
        onPressed: () {},
      ),
      TactileChip(label: 'bell', selected: false, onPressed: () {}),
      TactileChip(label: 'Keep', primary: true, onPressed: () {}),
      SizedBox(
        width: 320,
        child: RoundSegmented<String>(
          options: const [('mist', 'Mist'), ('figure', 'Figure')],
          value: 'mist',
          onChanged: onSegment ?? (_) {},
        ),
      ),
      SizedBox(
        width: 320,
        child: RoundSlider(
          label: 'Level',
          value: .5,
          onChanged: onLevel ?? (_) {},
        ),
      ),
      SizedBox(
        width: 320,
        child: OrganicCard(
          label: 'Open Bell',
          onTap: () {},
          child: const Text('Bell'),
        ),
      ),
      const SizedBox(width: 320, child: GlassPanel(child: Text('Transport'))),
    ],
  ),
);

void main() {
  testWidgets('every component is labelled and at least 48 dp', (tester) async {
    final handle = tester.ensureSemantics();
    for (final tone in GroundTone.values) {
      await _pump(tester, _gallery(), tone: tone);
      for (final label in [
        'Play',
        'Loop',
        'Stop',
        'bell',
        'Keep',
        'Mist',
        'Figure',
        'Level',
      ]) {
        expect(find.bySemanticsLabel(label), findsWidgets, reason: label);
      }
      // The card is one button that keeps its content readable.
      expect(find.bySemanticsLabel(RegExp(r'^Open Bell')), findsOneWidget);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      expect(tester.takeException(), isNull);
    }
    handle.dispose();
  });

  testWidgets('toggles, choices and the slider expose their state', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    String? segment;
    double? level;
    await _pump(
      tester,
      _gallery(onSegment: (v) => segment = v, onLevel: (v) => level = v),
    );
    expect(
      tester.getSemantics(find.byKey(const Key('loop'))),
      matchesSemantics(
        label: 'Loop',
        isButton: true,
        hasSelectedState: true,
        isSelected: true,
        hasEnabledState: true,
        isEnabled: true,
        hasTapAction: true,
      ),
    );
    await tester.tap(find.text('Figure'));
    expect(segment, 'figure');

    final slider = find.bySemanticsLabel('Level');
    expect(tester.getSemantics(slider).value, '50 %');
    tester
        .widget<Semantics>(
          find.byWidgetPredicate(
            (w) => w is Semantics && w.properties.label == 'Level',
          ),
        )
        .properties
        .onIncrease!();
    expect(level, closeTo(.6, 1e-9));
    handle.dispose();
  });

  testWidgets('disabled components carry no tap effect at all', (tester) async {
    await _pump(
      tester,
      const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TactileChip(label: 'bell', onPressed: null),
          TactileChip(label: 'Keep', primary: true, onPressed: null),
          RoundIconButton(
            icon: Icons.stop_rounded,
            label: 'Stop',
            onPressed: null,
          ),
          RoundActionButton(
            icon: Icons.play_arrow_rounded,
            label: 'Play',
            onPressed: null,
          ),
          SizedBox(width: 300, child: OrganicCard(child: Text('Bell'))),
        ],
      ),
    );
    expect(find.byType(TapGlitch), findsNothing);
    await tester.tap(find.text('bell'), warnIfMissed: false);
    await tester.pump();
    expect(_flashing(tester), isFalse);
  });

  testWidgets('a disabled action is announced as disabled and does not flash', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _pump(
      tester,
      const RoundActionButton(
        icon: Icons.play_arrow_rounded,
        label: 'Play',
        onPressed: null,
      ),
    );
    expect(
      tester.getSemantics(find.bySemanticsLabel('Play')),
      matchesSemantics(
        label: 'Play',
        isButton: true,
        hasEnabledState: true,
        isEnabled: false,
      ),
    );
    await tester.tap(find.bySemanticsLabel('Play'), warnIfMissed: false);
    await tester.pump();
    expect(_flashing(tester), isFalse);
    handle.dispose();
  });

  group('TapGlitch', () {
    testWidgets('a tap glitches briefly, then nothing is scheduled', (
      tester,
    ) async {
      var taps = 0;
      await _pump(tester, _gallery(onPlay: () => taps++));
      expect(tester.binding.hasScheduledFrame, isFalse);

      await tester.tap(find.byKey(const Key('play')));
      await tester.pump();
      expect(taps, 1);
      expect(_flashing(tester), isTrue);
      expect(_glitches(tester).every((g) => g.mode == GlitchMode.full), isTrue);
      await tester.pump(const Duration(milliseconds: 110));
      expect(tester.takeException(), isNull);
      await tester.pump(glitchDuration);
      expect(_flashing(tester), isFalse);
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('no more than three flashes per second, the taps still work', (
      tester,
    ) async {
      var taps = 0;
      await _pump(tester, _gallery(onPlay: () => taps++));
      final starts = <Duration>[];
      // A tap every 50 ms for two seconds, alternating two buttons.
      for (var ms = 0; ms < 2000; ms += 50) {
        _now = Duration(seconds: 10, milliseconds: ms);
        final key = ms % 100 == 0 ? const Key('play') : const Key('loop');
        await tester.tap(find.byKey(key));
        await tester.pump();
        final started = _glitches(tester)
            .any((g) => g.flash.isAnimating && g.flash.value == 0);
        if (started) starts.add(_now);
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(taps, 20);
      expect(starts, isNotEmpty);
      for (final start in starts) {
        final inWindow = starts.where(
          (s) => s >= start && s < start + const Duration(seconds: 1),
        );
        expect(inWindow.length, lessThanOrEqualTo(maxFlashesPerSecond));
      }
    });

    testWidgets('under reduce motion a tap only fades', (tester) async {
      await _pump(tester, _gallery(), reduceMotion: true);
      await tester.tap(find.byKey(const Key('play')));
      await tester.pump();
      expect(_flashing(tester), isTrue);
      expect(_glitches(tester).every((g) => g.mode == GlitchMode.fade), isTrue);
      await tester.pump(glitchDuration);
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('strength off removes the effect; the token sets the default', (
      tester,
    ) async {
      await _pump(tester, _gallery(), strength: GlitchStrength.off);
      expect(_glitches(tester), isEmpty);

      await _pump(
        tester,
        _gallery(),
        tokens: SynesterraTokens.graphite.copyWith(
          tapEffect: GlitchStrength.off,
        ),
      );
      expect(_glitches(tester), isEmpty);

      await _pump(
        tester,
        _gallery(),
        tokens: SynesterraTokens.graphite.copyWith(
          tapEffect: GlitchStrength.strong,
        ),
      );
      expect(
        _glitches(tester)
            .every((g) => g.amount == GlitchStrength.strong.amount),
        isTrue,
      );
    });

    testWidgets('a drag across an element does not flash', (tester) async {
      await _pump(
        tester,
        TapGlitch(
          shape: RoundShape.capsule,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragUpdate: (_) {},
            child: const SizedBox(width: 200, height: 60),
          ),
        ),
      );
      await tester.drag(find.byType(TapGlitch), const Offset(80, 0));
      await tester.pump();
      expect(_flashing(tester), isFalse);
    });
  });

  testWidgets('without a scope the components use the dark ground', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: synesterraTheme(SynesterraPalette.graphite),
        home: Scaffold(body: Center(child: _gallery())),
      ),
    );
    expect(tester.takeException(), isNull);
    final context = tester.element(find.byKey(const Key('play')));
    final palette = AmbientScope.paletteOf(context);
    expect(palette.tone, GroundTone.dark);
    expect(palette.ground, SynesterraTokens.graphite.background);
    expect(AmbientScope.gateOf(context), same(FlashGate.app));
    expect(AmbientScope.tapStrengthOf(context), GlitchStrength.subtle);
  });
}
