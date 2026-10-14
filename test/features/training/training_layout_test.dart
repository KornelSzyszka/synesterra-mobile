import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synesterra/features/training/training_view.dart';
import 'package:synesterra/shared/theme/synesterra_theme.dart';
import 'package:synesterra_core/synesterra_core.dart';

import 'training_fakes.dart';

/// 320 dp wide and the largest common text scale: nothing may overflow and
/// the main controls stay reachable.
Future<ScriptedPlayback> _pump(WidgetTester tester, double scale) async {
  tester.view
    ..physicalSize = const Size(320, 640)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final playback = ScriptedPlayback();
  await tester.pumpWidget(
    MaterialApp(
      theme: synesterraTheme(SynesterraPalette.graphite),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: TrainingView(playback: playback),
    ),
  );
  return playback;
}

void main() {
  for (final scale in [1.0, 2.0]) {
    testWidgets('entry at 320 dp, text x$scale, has no overflow', (
      tester,
    ) async {
      await _pump(tester, scale);
      expect(tester.takeException(), isNull);
      for (final id in ['tap']) {
        await tester.scrollUntilVisible(
          find.byKey(Key('training-$id')),
          100,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.byKey(Key('training-$id')), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('tap screen at 320 dp, text x$scale, has no overflow', (
      tester,
    ) async {
      final playback = await _pump(tester, scale);
      await tester.tap(find.byKey(const Key('training-tap')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(
        find.byKey(const Key('tap-start')),
        100,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byKey(const Key('tap-start')));
      await tester.pumpAndSettle();
      final cycle = tapPresets.first.cycleMs;
      playback.at(5 * cycle + 300, cycleMs: cycle);
      await tester.pump();
      expect(find.byKey(const Key('tap-summary')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
