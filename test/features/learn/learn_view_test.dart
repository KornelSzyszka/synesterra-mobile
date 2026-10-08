import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synesterra/data/repositories/impl/noop_playback_repository.dart';
import 'package:synesterra/data/repositories/loop.dart';
import 'package:synesterra/data/repositories/playback_repository.dart';
import 'package:synesterra/features/learn/learn_lessons.dart';
import 'package:synesterra/features/learn/learn_view.dart';
import 'package:synesterra/shared/loop_view/loop_view.dart';
import 'package:synesterra/shared/theme/synesterra_theme.dart';
import 'package:synesterra_core/synesterra_core.dart';

class _RecordingPlayback extends NoopPlaybackRepository {
  final calls = <String>[];
  bool fail = false;

  /// Like the real engine: play() resolves, and the status says it failed.
  bool failWithStatus = false;

  @override
  Future<void> play(SessionDocument document, {Object? owner}) async {
    calls.add('play');
    if (fail) throw StateError('no engine');
    if (failWithStatus) {
      (status as ValueNotifier<PlaybackStatus>).value = PlaybackStatus(
        stopReason: PlaybackStopReason.error,
        error: 'no engine',
      );
      return;
    }
    await super.play(document, owner: owner);
  }

  @override
  Future<void> stop({Object? owner}) async {
    calls.add('stop');
    await super.stop(owner: owner);
  }
}

Future<void> _pump(
  WidgetTester tester, {
  required PlaybackRepository playback,
  required void Function(Loop) onTryIt,
  double textScale = 1,
  bool disableAnimations = false,
  Size size = const Size(800, 2400),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: synesterraTheme(SynesterraPalette.forest),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
          disableAnimations: disableAnimations,
        ),
        child: child!,
      ),
      home: LearnView(playback: playback, onTryIt: onTryIt),
    ),
  );
}

/// A route transition. `pumpAndSettle` never settles on a lesson page: the
/// tutorial clock ticks for as long as the page is open.
Future<void> _transition(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

/// Scrolls the lazily built list until [finder] is on screen.
Future<void> _show(WidgetTester tester, Finder finder, String list) async {
  await tester.scrollUntilVisible(
    finder,
    200,
    scrollable: find.descendant(
      of: find.byKey(Key(list)),
      matching: find.byType(Scrollable),
    ),
  );
  await tester.ensureVisible(finder);
  await tester.pump();
}

Future<void> _open(WidgetTester tester, String id) async {
  final tile = find.byKey(Key('lesson-$id'));
  await _show(tester, tile, 'learn-list');
  await tester.tap(tile);
  await _transition(tester);
}

void main() {
  testWidgets('the list shows the seven lessons as labelled 48 dp targets', (
    tester,
  ) async {
    await _pump(tester, playback: NoopPlaybackRepository(), onTryIt: (_) {});

    expect(find.byKey(const Key('learn-list')), findsOneWidget);
    for (final lesson in learnLessons) {
      final tile = find.byKey(Key('lesson-${lesson.id}'));
      await _show(tester, tile, 'learn-list');
      expect(tester.getSize(tile).height, greaterThanOrEqualTo(48));
      expect(find.text(lesson.title), findsOneWidget);
    }
    expect(
      find.bySemanticsLabel(RegExp(r'^Lesson 2 of 7\. Two against three')),
      findsOneWidget,
    );
  });

  testWidgets('a lesson page shows its text, a picture and Try it', (
    tester,
  ) async {
    await _pump(tester, playback: NoopPlaybackRepository(), onTryIt: (_) {});
    await _open(tester, 'two-against-three');

    expect(
      tester.widget<Text>(find.byKey(const Key('lesson-text'))).data,
      learnLessons[1].text,
    );
    expect(find.byKey(const Key('loop-canvas')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('^Loop of 2 beats')), findsOneWidget);
    for (final key in ['lesson-hear', 'lesson-motion', 'lesson-try-it']) {
      await _show(tester, find.byKey(Key(key)), 'lesson-body');
      expect(
        tester.getSize(find.byKey(Key(key))).height,
        greaterThanOrEqualTo(48),
      );
    }
  });

  testWidgets('Try it passes the lesson loop to the shell callback', (
    tester,
  ) async {
    final opened = <Loop>[];
    await _pump(
      tester,
      playback: NoopPlaybackRepository(),
      onTryIt: opened.add,
    );
    await _open(tester, 'four-against-five');
    await _show(tester, find.byKey(const Key('lesson-try-it')), 'lesson-body');
    await tester.tap(find.byKey(const Key('lesson-try-it')));

    expect(opened, [learnLessons[2].loop]);
  });

  testWidgets('every lesson renders a picture', (tester) async {
    await _pump(tester, playback: NoopPlaybackRepository(), onTryIt: (_) {});
    for (final lesson in learnLessons) {
      await _open(tester, lesson.id);
      expect(
        find.byType(LoopView).evaluate().length +
            find.byType(ArrangementStrip).evaluate().length,
        1,
        reason: lesson.id,
      );
      await tester.pageBack();
      await _transition(tester);
    }
  });

  testWidgets('the chaining lesson shows a strip whose section advances', (
    tester,
  ) async {
    await _pump(tester, playback: NoopPlaybackRepository(), onTryIt: (_) {});
    await _open(tester, 'chaining-loops');

    expect(find.byKey(const Key('lesson-try-it')), findsNothing);
    expect(find.byKey(const Key('lesson-hear')), findsNothing);
    expect(find.bySemanticsLabel(RegExp(r'^Section 1 of 3')), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    expect(
      find.bySemanticsLabel(RegExp(r'^Section [23] of 3')),
      findsOneWidget,
    );
  });

  testWidgets('the tutorial clock runs on the page and is gone after leaving', (
    tester,
  ) async {
    await _pump(tester, playback: NoopPlaybackRepository(), onTryIt: (_) {});
    expect(tester.binding.transientCallbackCount, 0);
    await _open(tester, 'two-against-three');

    expect(tester.binding.transientCallbackCount, greaterThan(0));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Pause picture'), findsOneWidget);

    await tester.pageBack();
    await _transition(tester);
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('with reduced motion the picture starts still and can run', (
    tester,
  ) async {
    await _pump(
      tester,
      playback: NoopPlaybackRepository(),
      onTryIt: (_) {},
      disableAnimations: true,
    );
    await _open(tester, 'two-against-three');

    expect(tester.binding.transientCallbackCount, 0);
    await tester.tap(find.byKey(const Key('lesson-motion')));
    await tester.pump();
    expect(tester.binding.transientCallbackCount, greaterThan(0));
    await tester.tap(find.byKey(const Key('lesson-motion')));
    // Settles only when the clock has stopped (it would time out otherwise).
    await tester.pumpAndSettle();
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('tapping the picture plays and stops the loop', (tester) async {
    final playback = _RecordingPlayback();
    await _pump(tester, playback: playback, onTryIt: (_) {});
    await _open(tester, 'two-against-three');

    await tester.tap(find.byKey(const Key('lesson-picture')));
    await tester.pump();
    expect(playback.calls, ['play']);
    expect(find.text('Stop sound'), findsOneWidget);

    await tester.tap(find.byKey(const Key('lesson-hear')));
    await tester.pump();
    expect(playback.calls, ['play', 'stop']);
    expect(find.text('Hear it'), findsOneWidget);
  });

  testWidgets('sound that is unavailable shows a note and nothing breaks', (
    tester,
  ) async {
    final playback = _RecordingPlayback()..fail = true;
    await _pump(tester, playback: playback, onTryIt: (_) {});
    await _open(tester, 'two-against-three');

    await tester.tap(find.byKey(const Key('lesson-hear')));
    await tester.pump();
    expect(find.text('Sound is not available on this device.'), findsOneWidget);
    expect(find.text('Hear it'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an error status without a throw shows the unavailable note', (
    tester,
  ) async {
    final playback = _RecordingPlayback()..failWithStatus = true;
    await _pump(tester, playback: playback, onTryIt: (_) {});
    await _open(tester, 'two-against-three');

    await tester.tap(find.byKey(const Key('lesson-hear')));
    await tester.pump();
    expect(find.text('Sound is not available on this device.'), findsOneWidget);
    expect(find.text('Stop sound'), findsNothing);
    expect(find.text('Hear it'), findsOneWidget);
  });

  testWidgets('leaving a lesson stops its sound', (tester) async {
    final playback = _RecordingPlayback();
    await _pump(tester, playback: playback, onTryIt: (_) {});
    await _open(tester, 'two-against-three');
    await tester.tap(find.byKey(const Key('lesson-hear')));
    await tester.pump();

    await tester.pageBack();
    await _transition(tester);
    expect(playback.calls, ['play', 'stop']);
  });

  testWidgets('every lesson page fits a small phone at double text size', (
    tester,
  ) async {
    await _pump(
      tester,
      size: const Size(360, 640),
      playback: NoopPlaybackRepository(),
      onTryIt: (_) {},
      textScale: 2,
    );
    for (final lesson in learnLessons) {
      await _open(tester, lesson.id);
      expect(tester.takeException(), isNull, reason: lesson.id);
      await tester.pageBack();
      await _transition(tester);
    }
  });
}
