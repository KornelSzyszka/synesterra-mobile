import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synesterra/shared/living_blobs/living_field.dart';
import 'package:synesterra/shared/living_blobs/living_motion.dart';
import 'package:synesterra/shared/living_blobs/living_surface.dart';
import 'package:synesterra/shared/theme/ground_palette.dart';
import 'package:synesterra/shared/theme/surfaces.dart';
import 'package:synesterra/shared/theme/synesterra_theme.dart';
import 'package:synesterra/shared/widgets/round_components.dart';

const _fieldKey = Key('field');

/// A gallery of [count] living cards, 100 dp apart, in a 400 x 800 view.
Widget _gallery({int count = 12, int cap = maxAnimatedBlobs}) => MaterialApp(
  theme: synesterraTheme(SynesterraPalette.graphite),
  home: Scaffold(
    body: LivingField(
      key: _fieldKey,
      cap: cap,
      child: ListView(
        children: [
          for (var i = 0; i < count; i++)
            SizedBox(
              height: 100,
              child: OrganicCard(
                key: Key('card-$i'),
                label: 'Card $i',
                onTap: () {},
                living: true,
                morphSeed: i,
                child: Text('Card $i'),
              ),
            ),
        ],
      ),
    ),
  ),
);

Future<void> _pump(
  WidgetTester tester,
  Widget widget, {
  bool reduceMotion = false,
}) async {
  tester.view
    ..physicalSize = const Size(400, 800)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  if (reduceMotion) {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  }
  await tester.pumpWidget(widget);
}

/// Pumps frames of 100 ms for [duration] (one long pump counts as a pause).
Future<void> _frames(WidgetTester tester, Duration duration) async {
  for (var t = Duration.zero; t < duration; t += _step) {
    await tester.pump(_step);
  }
}

const _step = Duration(milliseconds: 100);

LivingFieldState _field(WidgetTester tester) =>
    tester.state<LivingFieldState>(find.byKey(_fieldKey));

List<LivingBlobState> _blobs(WidgetTester tester) =>
    tester.stateList<LivingBlobState>(find.byType(LivingBlob)).toList();

void main() {
  setUp(() => livingBlobsEnabled.value = true);

  testWidgets('one clock moves the gallery, then it settles and stops', (
    tester,
  ) async {
    await _pump(tester, _gallery());
    await tester.pump(const Duration(milliseconds: 16));
    expect(_field(tester).isTicking, isTrue);
    // One ticker for the whole gallery, not one per card.
    expect(tester.binding.transientCallbackCount, 1);

    await _frames(tester, LivingTiming.awake + LivingTiming.settle);
    await tester.pump(_step);
    expect(_field(tester).isTicking, isFalse);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('only visible cards animate, at most the cap', (tester) async {
    await _pump(tester, _gallery(count: 12, cap: 3));
    await tester.pump(const Duration(milliseconds: 16));
    final animated = _blobs(tester).where((b) => b.animated).toList();
    expect(animated, hasLength(3));
    expect(_field(tester).animatedMembers, hasLength(3));

    // With the default cap, the eight cards on screen give six slots.
    await _pump(tester, _gallery(count: 12));
    await tester.pump(const Duration(milliseconds: 16));
    expect(
      _blobs(tester).where((b) => b.animated),
      hasLength(maxAnimatedBlobs),
    );
    // Cards in the cache extent below the screen never animate.
    final offscreen = _blobs(tester)
        .where((b) => tester.getTopLeft(find.byWidget(b.widget)).dy >= 800);
    expect(offscreen.where((b) => b.animated), isEmpty);
  });

  testWidgets('touching a visible card without a slot never raises the '
      'number of cards following the clock above the cap', (tester) async {
    await _pump(tester, _gallery(count: 12));
    await tester.pump(const Duration(milliseconds: 16));
    final slotless = _blobs(tester).firstWhere(
      (b) => !b.animated && tester.getTopLeft(find.byWidget(b.widget)).dy < 700,
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.byWidget(slotless.widget)) + const Offset(120, 0),
    );
    var most = 0;
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      final listening = _blobs(tester).where((b) => b.listening).length;
      if (listening > most) most = listening;
    }
    await gesture.up();
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      final listening = _blobs(tester).where((b) => b.listening).length;
      if (listening > most) most = listening;
    }
    expect(most, lessThanOrEqualTo(maxAnimatedBlobs));
    expect(slotless.listening, isFalse);
  });

  testWidgets('a leaning card that loses its slot is repainted still', (
    tester,
  ) async {
    await _pump(tester, _gallery(count: 3));
    await tester.pump(const Duration(milliseconds: 16));
    final card = find.byKey(const Key('card-1'));
    final blob = tester.state<LivingBlobState>(
      find.descendant(of: card, matching: find.byType(LivingBlob)),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(card) + const Offset(150, 0),
    );
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(blob.debugPainted!.$1.dx, greaterThan(.3));

    // The field takes the slot away (as after a small scroll) while the
    // finger is down; nothing else rebuilds or repaints the card.
    blob.animated = false;
    await tester.pump(const Duration(milliseconds: 16));
    expect(blob.animated, isFalse);
    expect(blob.debugPainted, (Offset.zero, 0.0));
    // The painted outline is the still one: no lean, no swell, no morph.
    final size = tester.getSize(find.byWidget(blob.widget));
    final still = livingOutline(
      size,
      blob.widget.shape,
      morphSeed: blob.widget.morphSeed,
      time: 0,
      life: 0,
      lean: Offset.zero,
      swell: 0,
    );
    final painted = blob.debugPaintedOutline!;
    for (final metric in still.computeMetrics()) {
      final other = painted.computeMetrics().first;
      for (var i = 0; i < 24; i++) {
        final a = metric.getTangentForOffset(metric.length * i / 24)!.position;
        final b = other.getTangentForOffset(other.length * i / 24)!.position;
        expect((a - b).distance, lessThan(.01), reason: 'point $i');
      }
    }
    await gesture.up();
  });

  testWidgets('switching reduce motion on mid-lean repaints the card still', (
    tester,
  ) async {
    await _pump(tester, _gallery(count: 3));
    await tester.pump(const Duration(milliseconds: 16));
    final card = find.byKey(const Key('card-1'));
    final blob = tester.state<LivingBlobState>(
      find.descendant(of: card, matching: find.byType(LivingBlob)),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(card) + const Offset(150, 0),
    );
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(blob.debugPainted!.$1.dx, greaterThan(.3));
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    expect(blob.debugPainted, (Offset.zero, 0.0));
    await gesture.up();
  });

  testWidgets('scrolling hands the slots to the cards that come into view', (
    tester,
  ) async {
    await _pump(tester, _gallery(count: 30));
    await tester.pump(const Duration(milliseconds: 16));
    await tester.drag(find.byType(ListView), const Offset(0, -1500));
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));
    final slots = _blobs(tester).where((b) => b.animated).toList();
    expect(slots, hasLength(maxAnimatedBlobs));
    for (final blob in slots) {
      final top = tester.getTopLeft(find.byWidget(blob.widget)).dy;
      expect(top, inInclusiveRange(-100, 800));
    }
  });

  testWidgets('a covered gallery pauses and resumes when uncovered', (
    tester,
  ) async {
    await _pump(tester, _gallery());
    await tester.pump(const Duration(milliseconds: 16));
    expect(_field(tester).isTicking, isTrue);

    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.push(
      MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('x'))),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .state<LivingFieldState>(find.byKey(_fieldKey, skipOffstage: false))
          .isTicking,
      isFalse,
    );
    expect(tester.binding.transientCallbackCount, 0);

    navigator.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    expect(_field(tester).isTicking, isTrue);
  });

  testWidgets('a backgrounded app pauses the gallery', (tester) async {
    await _pump(tester, _gallery());
    await tester.pump(const Duration(milliseconds: 16));
    expect(_field(tester).isTicking, isTrue);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(_field(tester).isTicking, isFalse);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(milliseconds: 16));
    expect(_field(tester).isTicking, isTrue);
  });

  testWidgets('under reduce motion nothing moves, the depth stays', (
    tester,
  ) async {
    await _pump(tester, _gallery(), reduceMotion: true);
    await tester.pump(const Duration(milliseconds: 16));
    expect(_field(tester).isTicking, isFalse);
    expect(tester.binding.transientCallbackCount, 0);
    // Still living cards (static depth), but none follows the clock.
    expect(_blobs(tester), isNotEmpty);
    expect(_blobs(tester).any((b) => b.listening), isFalse);
    expect(
      find.byWidgetPredicate(
        (w) => w is CustomPaint && w.painter is LivingBlobPainter,
      ),
      findsWidgets,
    );

    await tester.press(find.byKey(const Key('card-1')));
    await tester.pump(const Duration(milliseconds: 16));
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('a touch leans and swells the card on a spring, which settles '
      'back after the finger lifts', (tester) async {
    await _pump(tester, _gallery(count: 3));
    await _frames(tester, LivingTiming.awake + LivingTiming.settle);
    await tester.pump(_step);
    expect(_field(tester).isTicking, isFalse);

    final card = find.byKey(const Key('card-1'));
    final gesture = await tester.startGesture(
      tester.getCenter(card) + const Offset(150, 0),
    );
    await tester.pump(const Duration(milliseconds: 16));
    expect(_field(tester).isTicking, isTrue, reason: 'a touch wakes it');
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    final blob = tester.state<LivingBlobState>(
      find.descendant(of: card, matching: find.byType(LivingBlob)),
    );
    expect(blob.debugLean.dx, greaterThan(.3), reason: 'leans to the right');
    expect(blob.debugSwell, greaterThan(.5));

    await gesture.up();
    await _frames(tester, const Duration(seconds: 2));
    expect(blob.debugLean.distance, lessThan(.01));
    expect(blob.debugSwell.abs(), lessThan(.01));
  });

  testWidgets('cards enter one after another when the gallery opens', (
    tester,
  ) async {
    await _pump(tester, _gallery(count: 4));
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 150));
    double opacity(int i) => tester
        .widget<Opacity>(
          find
              .descendant(
                of: find.byKey(Key('card-$i')),
                matching: find.byType(Opacity),
              )
              .first,
        )
        .opacity;
    expect(opacity(0), greaterThan(opacity(2)));
    await _frames(tester, const Duration(seconds: 1));
    for (var i = 0; i < 4; i++) {
      expect(opacity(i), 1);
    }
  });

  testWidgets('the flat comparison paints the still card', (tester) async {
    await _pump(tester, _gallery(count: 3));
    expect(find.byType(LivingBlob), findsNWidgets(3));
    livingBlobsEnabled.value = false;
    await tester.pump();
    expect(find.byType(LivingBlob), findsNothing);
    expect(_field(tester).isTicking, isFalse);
    livingBlobsEnabled.value = true;
    await tester.pump();
    expect(find.byType(LivingBlob), findsNWidgets(3));
  });

  testWidgets('disposing the gallery leaves no ticker and no listener', (
    tester,
  ) async {
    await _pump(tester, _gallery());
    await tester.pump(const Duration(milliseconds: 16));
    final field = _field(tester);
    expect(_blobs(tester).any((b) => b.listening), isTrue);
    await tester.pumpWidget(const SizedBox());
    expect(field.mounted, isFalse);
    expect(tester.binding.transientCallbackCount, 0);
    // A late toggle after disposal must not touch the dead field.
    livingBlobsEnabled.value = false;
    livingBlobsEnabled.value = true;
    expect(tester.takeException(), isNull);
  });

  testWidgets('a living card keeps one button with its label and 48 dp', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, _gallery(count: 3));
    expect(find.bySemanticsLabel(RegExp(r'^Card 1')), findsOneWidget);
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    expect(find.byType(BackdropFilter), findsNothing);
    handle.dispose();
  });

  test('text keeps 4.5:1 on a living card with every light at its '
      'strongest, for every palette, tone, aura and tint', () {
    final failures = <String>[];
    for (final palette in SynesterraPalette.values) {
      final tokens = SynesterraTokens.forPalette(palette);
      for (final tone in GroundTone.values) {
        for (final aura in tokens.layerColors) {
          final ground = GroundPalette.of(tokens, tone, aura);
          final surfaces = Surfaces(ground);
          for (final tint in tokens.layerColors) {
            final samples = livingFillSamples(ground, tint);
            for (final (name, text) in [
              ('text', surfaces.textOn(SurfaceStyle.organic)),
              ('muted', surfaces.mutedOn(SurfaceStyle.organic)),
            ]) {
              final worst = TextContrastPair(name, text, samples).worstContrast;
              if (worst < 4.5) {
                failures.add(
                  '${palette.name} ${tone.name} tint '
                  '${tint.toARGB32().toRadixString(16)} $name: '
                  '${worst.toStringAsFixed(2)}',
                );
              }
            }
          }
        }
      }
    }
    expect(failures, isEmpty, reason: failures.take(20).join('\n'));
  });
}
