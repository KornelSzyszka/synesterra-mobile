import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synesterra/features/training/training_view.dart';
import 'package:synesterra/shared/theme/synesterra_theme.dart';
import 'package:synesterra_core/synesterra_core.dart';

import 'training_fakes.dart';

Future<ScriptedPlayback> _pump(WidgetTester tester) async {
  tester.view
    ..physicalSize = const Size(412, 1200)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final playback = ScriptedPlayback();
  await tester.pumpWidget(
    MaterialApp(
      theme: synesterraTheme(SynesterraPalette.graphite),
      home: TrainingView(playback: playback),
    ),
  );
  return playback;
}

void main() {
  testWidgets('the entry lists the tap trainer and opens it', (tester) async {
    await _pump(tester);
    expect(find.text('Training'), findsOneWidget);
    expect(find.byKey(const Key('training-tap')), findsOneWidget);
    await tester.tap(find.byKey(const Key('training-tap')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('tap-pad')), findsOneWidget);
    expect(find.text('Press Start'), findsOneWidget);
  });

  testWidgets('tap, early/late feedback, summary and the offset', (
    tester,
  ) async {
    final playback = await _pump(tester);
    await tester.tap(find.byKey(const Key('training-tap')));
    await tester.pumpAndSettle();
    final cycle = tapPresets.first.cycleMs;

    await tester.tap(find.byKey(const Key('tap-offset-up')));
    await tester.pump();
    expect(find.textContaining('+10 ms'), findsOneWidget);
    await tester.tap(find.byKey(const Key('tap-offset-down')));
    await tester.pump();

    await tester.tap(find.byKey(const Key('tap-start')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Count-in'), findsOneWidget);
    expect(find.text('Stop'), findsOneWidget);

    Future<void> tapAt(double ms) async {
      playback.at(ms, cycleMs: cycle);
      await tester.tap(find.byKey(const Key('tap-pad')));
      await tester.pump();
    }

    await tapAt(cycle * .3); // count-in: not scored
    expect(find.textContaining('Count-in'), findsOneWidget);
    await tapAt(cycle + 25); // first hit, 25 ms late
    expect(find.text('25 ms late'), findsOneWidget);
    await tapAt(cycle + 750 + 45);
    expect(find.text('45 ms late'), findsOneWidget);

    playback.at(5 * cycle + 300, cycleMs: cycle);
    await tester.pump();
    expect(find.byKey(const Key('tap-summary')), findsOneWidget);
    expect(find.byKey(const Key('tap-score')), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('an unavailable engine says so', (tester) async {
    final playback = await _pump(tester);
    playback.failStart = true;
    await tester.tap(find.byKey(const Key('training-tap')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('tap-start')));
    await tester.pumpAndSettle();
    expect(find.text('Sound is not available on this device.'), findsOneWidget);
  });
}
