import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synesterra/shared/loop_view/loop_view.dart';
import 'package:synesterra/shared/loop_view/loop_view_demo.dart';
import 'package:synesterra/shared/theme/synesterra_theme.dart';

void main() {
  testWidgets(
    'demo shows the 3:2 and 5:4 loops and plays on the tutorial clock',
    (tester) async {
      tester.view.physicalSize = const Size(800, 3200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: synesterraTheme(SynesterraPalette.forest),
          home: const Scaffold(body: LoopViewDemo()),
        ),
      );

      expect(find.text('3:2'), findsOneWidget);
      expect(find.text('5:4'), findsOneWidget);
      expect(find.byType(LoopView), findsNWidgets(2));
      expect(find.byType(ArrangementStrip), findsOneWidget);

      await tester.tap(find.text('Play'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
      expect(find.text('Stop'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('Stop'));
      await tester.pump();
      expect(find.text('Play'), findsOneWidget);
    },
  );
}
