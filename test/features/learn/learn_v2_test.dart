import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synesterra/data/repositories/impl/noop_playback_repository.dart';
import 'package:synesterra/features/learn/learn_view.dart';
import 'package:synesterra/shared/theme/synesterra_theme.dart';
import 'package:synesterra/shared/widgets/round_components.dart';

Future<void> _pump(WidgetTester tester) async {
  tester.view
    ..physicalSize = const Size(412, 892)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: synesterraTheme(SynesterraPalette.graphite),
      home: Navigator(
        onGenerateRoute: (_) => MaterialPageRoute<void>(
          builder: (_) =>
              LearnView(playback: NoopPlaybackRepository(), onTryIt: (_) {}),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the lesson list: organic cards, 48 dp targets, labels', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _pump(tester);
    expect(find.byType(OrganicCard), findsWidgets);
    expect(find.byType(Card), findsNothing);
    expect(find.byType(BackdropFilter), findsNothing);
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    handle.dispose();
  });

  testWidgets('a lesson page: round buttons, 48 dp targets, labels, Back', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _pump(tester);
    // Tall enough to build the whole lesson, buttons included.
    tester.view.physicalSize = const Size(412, 2000);
    await tester.tap(find.byKey(const Key('lesson-two-against-three')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(OutlinedButton), findsNothing);
    expect(find.byType(FilledButton), findsNothing);
    // Hear it, Run picture and Try it.
    expect(find.byType(TactileChip), findsNWidgets(3));
    expect(find.byTooltip('Back'), findsOneWidget);
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

    // Back is a round button and leaves the lesson.
    await tester.tap(find.byTooltip('Back'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byKey(const Key('learn-list')), findsOneWidget);
    handle.dispose();
  });
}
