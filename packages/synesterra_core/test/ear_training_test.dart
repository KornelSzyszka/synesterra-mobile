import 'package:synesterra_core/synesterra_core.dart';
import 'package:test/test.dart';

List<EarQuestion> draw(EarMode mode, int seed, [int count = 200]) {
  final generator = EarQuestionGenerator(mode, seed: seed);
  return [for (var i = 0; i < count; i++) generator.next()];
}

void main() {
  for (final mode in EarMode.values) {
    group(mode.name, () {
      test('is deterministic for a seed and differs between seeds', () {
        String sig(List<EarQuestion> qs) =>
            qs.map((q) => '${q.correct.id}:${q.steps}').join('|');
        expect(sig(draw(mode, 7, 30)), sig(draw(mode, 7, 30)));
        expect(sig(draw(mode, 7, 30)), isNot(sig(draw(mode, 8, 30))));
      });

      test('has four distinct options, one of them correct', () {
        for (final q in draw(mode, 1)) {
          expect(q.options, hasLength(4));
          expect({for (final o in q.options) o.id}, hasLength(4));
          expect(q.options[q.correctIndex], q.correct);
        }
      });

      test('keeps pitches inside the layer range 24..107', () {
        for (final q in draw(mode, 2)) {
          for (final step in q.steps) {
            for (final p in step) {
              expect(p, inInclusiveRange(minLayerPitch, maxLayerPitch));
            }
          }
        }
      });

      test('never repeats the previous right answer', () {
        final qs = draw(mode, 3);
        for (var i = 1; i < qs.length; i++) {
          expect(qs[i].correct.id, isNot(qs[i - 1].correct.id));
        }
      });

      test('covers every option as the right answer', () {
        final seen = {for (final q in draw(mode, 4, 600)) q.correct.id};
        expect(
          seen.length,
          greaterThanOrEqualTo(mode == EarMode.note ? 12 : 4),
        );
      });
    });
  }

  test('note: the correct option names the sounded pitch', () {
    for (final q in draw(EarMode.note, 5)) {
      expect(q.steps, hasLength(1));
      expect(q.steps.single, hasLength(1));
      expect(q.correct.id, earNoteName(q.steps.single.single));
    }
  });

  test('chord: intervals match the named quality', () {
    for (final q in draw(EarMode.chord, 6)) {
      final step = q.steps.single;
      final intervals = [for (final p in step) p - step.first];
      final quality = earChordQualities.firstWhere((c) => c.$1 == q.correct.id);
      expect(intervals, quality.$3);
    }
  });

  test('progression: four triads, the label names the degrees', () {
    for (final q in draw(EarMode.progression, 7)) {
      expect(q.steps, hasLength(4));
      expect(q.steps.every((s) => s.length == 3), isTrue);
      final degrees = q.correct.id.split('-');
      expect(earProgressions.any((p) => p.join('-') == q.correct.id), isTrue);
      // I is the key's major triad, and so is the first chord.
      expect(degrees.first, 'I');
      final first = q.steps.first;
      expect([first[1] - first[0], first[2] - first[0]], [4, 7]);
    }
  });

  test('a progression is sounded as the first option says: I-IV-V-I', () {
    final q = draw(
      EarMode.progression,
      11,
      100,
    ).firstWhere((q) => q.correct.id == 'I-IV-V-I');
    final key = q.steps.first.first;
    expect([for (final s in q.steps) s.first - key], [0, 5, 7, 0]);
  });

  test('EarScore tracks the streak and its best', () {
    var s = const EarScore();
    s = s.answer(right: true).answer(right: true).answer(right: false);
    expect((s.answered, s.correct, s.streak, s.bestStreak), (3, 2, 0, 2));
    s = s.answer(right: true);
    expect((s.streak, s.bestStreak), (1, 2));
  });

  test('EarQuestion validates its input', () {
    expect(
      () => EarQuestion(
        mode: EarMode.note,
        options: const [EarOption('C', 'C')],
        correctIndex: 1,
        steps: const [
          [60],
        ],
      ),
      throwsRangeError,
    );
  });
}
