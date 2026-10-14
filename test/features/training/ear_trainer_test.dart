import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synesterra/features/training/ear_trainer_model.dart';
import 'package:synesterra/features/training/training_documents.dart';
import 'package:synesterra/features/training/training_view.dart';
import 'package:synesterra/shared/theme/synesterra_theme.dart';
import 'package:synesterra_core/synesterra_core.dart';

import 'training_fakes.dart';

void main() {
  group('documents', () {
    test('a note is one sounding layer and a muted twin', () {
      final doc = earSectionDocument([60]);
      final layers = doc.scenes.first.layers;
      expect(layers.map((l) => l.mix.muted), [false, true]);
      expect(layers.first.pitch, 60);
    });

    test('a chord has one layer per tone and plays once per cycle', () {
      final doc = earSectionDocument([60, 64, 67]);
      final layers = doc.scenes.first.layers;
      expect(layers.map((l) => l.pitch), [60, 64, 67]);
      expect(layers.every((l) => !l.mix.muted), isTrue);
      expect(layers.every((l) => l.pattern.steps.length == 1), isTrue);
      expect(doc.transport.practiceCycleBeats, Rational(2, 1));
    });

    test('every generated question maps to valid one-cycle sections', () {
      for (final mode in EarMode.values) {
        final generator = EarQuestionGenerator(mode, seed: 9);
        for (var i = 0; i < 40; i++) {
          final q = generator.next();
          final sections = earSections(q);
          expect(sections, hasLength(q.steps.length));
          expect(sections.every((s) => s.repeats == 1), isTrue);
        }
      }
    });

    test('too many tones are rejected', () {
      expect(() => earSectionDocument([60, 62, 64, 65]), throwsArgumentError);
      expect(() => earSectionDocument(const []), throwsArgumentError);
    });
  });

  group('model', () {
    late ScriptedPlayback playback;
    late ValueNotifier<EarScore> score;
    late EarTrainerModel model;

    setUp(() {
      playback = ScriptedPlayback();
      score = ValueNotifier(const EarScore());
      model = EarTrainerModel(
        playback: playback,
        mode: EarMode.progression,
        seed: 4,
        score: score,
      );
    });
    tearDown(() => model.dispose());

    test(
      'play sends the question as four sections owned by the model',
      () async {
        await model.play();
        expect(playback.sequences.single, hasLength(4));
        expect(playback.owners.single, same(model));
        await model.play();
        expect(playback.sequences, hasLength(2), reason: 'replay');
      },
    );

    test('a right answer extends the streak, a wrong one resets it', () async {
      model.answer(model.question.correctIndex);
      expect(model.right, isTrue);
      expect(score.value.streak, 1);
      // Answered once only.
      model.answer((model.question.correctIndex + 1) % 4);
      expect(score.value.answered, 1);

      await model.next();
      expect(model.answered, isFalse);
      model.answer((model.question.correctIndex + 1) % 4);
      expect(model.right, isFalse);
      expect(score.value.streak, 0);
      expect(score.value.bestStreak, 1);
    });

    test('next needs an answer and plays the new question', () async {
      await model.next();
      expect(playback.sequences, isEmpty);
      model.answer(0);
      await model.next();
      expect(playback.sequences, hasLength(1));
    });

    test(
      'a failing engine is reported, the question stays answerable',
      () async {
        playback.failStart = true;
        await model.play();
        expect(model.unavailable, isTrue);
        model.answer(0);
        expect(model.answered, isTrue);
      },
    );

    test('dispose stops the sound', () {
      model.dispose();
      expect(playback.stops, 1);
      model = EarTrainerModel(
        playback: playback,
        mode: EarMode.note,
        seed: 1,
        score: score,
      );
    });
  });

  group('view', () {
    Future<ScriptedPlayback> pump(WidgetTester tester) async {
      tester.view
        ..physicalSize = const Size(412, 1200)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final playback = ScriptedPlayback();
      await tester.pumpWidget(
        MaterialApp(
          theme: synesterraTheme(SynesterraPalette.graphite),
          home: TrainingView(playback: playback, earSeed: 21),
        ),
      );
      return playback;
    }

    testWidgets('the entry lists all four exercises', (tester) async {
      await pump(tester);
      for (final id in ['tap', 'note', 'chord', 'progression']) {
        expect(find.byKey(Key('training-$id')), findsOneWidget);
      }
      expect(find.textContaining('Lessons'), findsNothing);
    });

    testWidgets('chord: plays on open, shows right, streak and next', (
      tester,
    ) async {
      final playback = await pump(tester);
      await tester.tap(find.byKey(const Key('training-chord')));
      await tester.pumpAndSettle();
      expect(playback.sequences, hasLength(1));
      expect(find.byKey(const Key('ear-prompt')), findsOneWidget);
      expect(find.byKey(const Key('ear-verdict')), findsNothing);

      final first = EarQuestionGenerator(EarMode.chord, seed: 21).next();
      await tester.tap(find.byKey(Key('ear-option-${first.correct.id}')));
      await tester.pump();
      expect(find.textContaining('Right!'), findsOneWidget);
      expect(find.textContaining('Streak 1'), findsOneWidget);

      await tester.tap(find.byKey(const Key('ear-next')));
      await tester.pumpAndSettle();
      expect(playback.sequences, hasLength(2));
      expect(find.byKey(const Key('ear-verdict')), findsNothing);

      await tester.tap(find.byKey(const Key('ear-replay')));
      await tester.pump();
      expect(playback.sequences, hasLength(3));
    });

    testWidgets('note: a wrong answer says what it was', (tester) async {
      await pump(tester);
      await tester.tap(find.byKey(const Key('training-note')));
      await tester.pumpAndSettle();
      final q = EarQuestionGenerator(EarMode.note, seed: 21).next();
      final wrong = q.options[(q.correctIndex + 1) % 4];
      await tester.tap(find.byKey(Key('ear-option-${wrong.id}')));
      await tester.pump();
      expect(
        find.text('Not quite. It was ${q.correct.label}.'),
        findsOneWidget,
      );
      expect(find.textContaining('Streak 0'), findsOneWidget);
    });

    testWidgets('score survives leaving and re-entering an exercise', (
      tester,
    ) async {
      await pump(tester);
      await tester.tap(find.byKey(const Key('training-chord')));
      await tester.pumpAndSettle();
      final q = EarQuestionGenerator(EarMode.chord, seed: 21).next();
      await tester.tap(find.byKey(Key('ear-option-${q.correct.id}')));
      await tester.pump();
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('training-chord')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Best 1'), findsOneWidget);
    });
  });
}
