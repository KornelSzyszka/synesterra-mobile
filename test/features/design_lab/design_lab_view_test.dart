import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synesterra/features/design_lab/design_lab_view.dart';
import 'package:synesterra/features/design_lab/lab_components.dart';
import 'package:synesterra/features/design_lab/lab_motion.dart';
import 'package:synesterra/features/design_lab/lab_skin.dart';
import 'package:synesterra/shared/theme/synesterra_theme.dart';

/// A phone width; tall enough that the whole lab is built at once.
Future<void> _pumpLab(
  WidgetTester tester, {
  bool reduceMotion = false,
  double height = 2600,
}) async {
  tester.view
    ..physicalSize = Size(412 * 3, height * 3)
    ..devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  if (reduceMotion) {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  }
  await tester.pumpWidget(
    MaterialApp(
      theme: synesterraTheme(SynesterraPalette.forest),
      home: const DesignLabView(),
    ),
  );
  await tester.pump();
}

const _components = [
  'lab-pad',
  'lab-segmented',
  'lab-slider',
  'lab-chips',
  'lab-card',
  'lab-card-play',
  'lab-transport',
  'lab-play',
  'lab-stop',
  'lab-loop',
  'lab-open-sheet',
  'lab-sheet',
];

Future<void> _select(WidgetTester tester, LabVariant variant) async {
  await tester.tap(find.byKey(ValueKey('lab-variant-${variant.name}')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  testWidgets('the switcher shows each variant with the same components', (
    tester,
  ) async {
    await _pumpLab(tester);
    for (final variant in LabVariant.values) {
      await _select(tester, variant);
      expect(
        find.byKey(ValueKey('lab-canvas-${variant.name}-dark')),
        findsOneWidget,
      );
      for (final key in _components) {
        expect(
          find.byKey(ValueKey(key)),
          findsOneWidget,
          reason: '$key in ${variant.name}',
        );
      }
      final scope = tester.widget<LabScope>(find.byType(LabScope).first);
      expect(scope.skin.variant, variant);
    }
  });

  testWidgets('the ground switches between dark and light', (tester) async {
    await _pumpLab(tester);
    final dark = tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor;

    await tester.tap(find.byKey(const Key('lab-tone')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      find.byKey(const ValueKey('lab-canvas-glass-light')),
      findsOneWidget,
    );
    final light = tester
        .widget<Scaffold>(find.byType(Scaffold))
        .backgroundColor!;
    expect(light.computeLuminance(), greaterThan(dark!.computeLuminance()));
  });

  testWidgets('every control is labelled for TalkBack and at least 48 dp', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _pumpLab(tester);
    for (final variant in LabVariant.values) {
      await _select(tester, variant);
      for (final label in [
        'Sound pad',
        'Play',
        'Stop',
        'Loop',
        'Level',
        'Mist',
        'Figure',
        'Wave',
        'bell',
        'Play Bell',
        'Open as sheet',
        'Keep',
        'Not now',
        'Glass variant',
        'Organic variant',
        'Material variant',
        'Tap flash off',
        'Tap flash subtle',
        'Tap flash strong',
      ]) {
        expect(
          find.bySemanticsLabel(label),
          findsWidgets,
          reason: '"$label" in ${variant.name}',
        );
      }
      expect(find.byTooltip('Back'), findsOneWidget);
      expect(find.byTooltip('Show on a light ground'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp(r'^Open Bell\.')), findsOneWidget);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    }
    handle.dispose();
  });

  testWidgets('the pad announces its position and moves on a drag', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _pumpLab(tester);
    final before = tester.getSemantics(find.byKey(const Key('lab-pad'))).value;

    await tester.drag(find.byKey(const Key('lab-pad')), const Offset(-60, 40));
    await tester.pump();

    final after = tester.getSemantics(find.byKey(const Key('lab-pad'))).value;
    expect(after, isNot(before));
    expect(after, contains('Brightness'));
    handle.dispose();
  });

  testWidgets('with reduce motion nothing drifts and a tap only fades', (
    tester,
  ) async {
    await _pumpLab(tester, reduceMotion: true);
    expect(tester.binding.hasScheduledFrame, isFalse);

    await tester.tap(find.byKey(const Key('lab-play')));
    await tester.pump();
    final flashes = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((paint) => paint.foregroundPainter)
        .whereType<LabFlashPainter>();
    expect(flashes, isNotEmpty);
    expect(flashes.every((f) => f.mode == GlitchMode.fade), isTrue);
    await tester.pump(glitchDuration);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('without reduce motion the drift runs and a tap glitches', (
    tester,
  ) async {
    await _pumpLab(tester);
    expect(tester.binding.hasScheduledFrame, isTrue);

    await tester.tap(find.byKey(const Key('lab-play')));
    await tester.pump();
    final flashes = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((paint) => paint.foregroundPainter)
        .whereType<LabFlashPainter>();
    expect(flashes.every((f) => f.mode == GlitchMode.full), isTrue);
    // Every variant paints its flash mid-way without throwing.
    for (final variant in LabVariant.values) {
      await _select(tester, variant);
      await tester.tap(find.byKey(const Key('lab-stop')));
      await tester.pump(const Duration(milliseconds: 110));
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(milliseconds: 400));
    }
  });

  testWidgets('the flash strength Off removes the flash', (tester) async {
    await _pumpLab(tester);
    await tester.tap(find.byKey(const ValueKey('lab-glitch-off')));
    await tester.pump();

    final flashes = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((paint) => paint.foregroundPainter)
        .whereType<LabFlashPainter>();
    expect(flashes, isEmpty);
  });

  testWidgets('Play toggles to Pause and the sheet opens as a sheet', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _pumpLab(tester);
    await tester.tap(find.byKey(const Key('lab-play')));
    await tester.pump();
    expect(find.bySemanticsLabel('Pause'), findsOneWidget);

    await tester.tap(find.byKey(const Key('lab-open-sheet')));
    await tester.pumpAndSettleWithDrift();
    expect(find.text('Keep this sound?'), findsNWidgets(2));

    await tester.tap(find.byKey(const Key('lab-sheet-keep')).last);
    await tester.pumpAndSettleWithDrift();
    expect(find.text('Keep this sound?'), findsOneWidget);
    handle.dispose();
  });
}

extension on WidgetTester {
  /// The drift never settles; pump long enough for a route transition.
  Future<void> pumpAndSettleWithDrift() async {
    for (var i = 0; i < 10; i++) {
      await pump(const Duration(milliseconds: 100));
    }
  }
}
