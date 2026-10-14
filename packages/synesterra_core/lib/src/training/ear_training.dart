import '../randomizer/seeded_random.dart';

/// What the listener is asked to recognise.
enum EarMode {
  /// The pitch name of one note.
  note('Note'),

  /// The quality of a triad.
  chord('Chord'),

  /// Which chord progression was played.
  progression('Progression');

  const EarMode(this.label);

  final String label;
}

/// One answer the listener can choose.
class EarOption {
  const EarOption(this.id, this.label);

  final String id;
  final String label;

  @override
  bool operator ==(Object other) =>
      other is EarOption && id == other.id && label == other.label;

  @override
  int get hashCode => Object.hash(id, label);

  @override
  String toString() => 'EarOption($id)';
}

/// A question: what to play, and the options to choose from.
class EarQuestion {
  EarQuestion({
    required this.mode,
    required List<EarOption> options,
    required this.correctIndex,
    required List<List<int>> steps,
  }) : options = List.unmodifiable(options),
       steps = List.unmodifiable([
         for (final step in steps) List<int>.unmodifiable(step),
       ]) {
    if (correctIndex < 0 || correctIndex >= options.length) {
      throw RangeError.index(correctIndex, options, 'correctIndex');
    }
    if (steps.isEmpty || steps.any((s) => s.isEmpty)) {
      throw ArgumentError.value(steps, 'steps', 'empty');
    }
  }

  final EarMode mode;
  final List<EarOption> options;
  final int correctIndex;

  /// What to sound, in order: each step is a set of MIDI pitches played
  /// together (one pitch for a note, three for a chord).
  final List<List<int>> steps;

  EarOption get correct => options[correctIndex];

  String get prompt => switch (mode) {
    EarMode.note => 'Which note is it?',
    EarMode.chord => 'What kind of chord is it?',
    EarMode.progression => 'Which progression is it?',
  };
}

/// Streak and counts of one practice session. Immutable; nothing is stored.
class EarScore {
  const EarScore({
    this.answered = 0,
    this.correct = 0,
    this.streak = 0,
    this.bestStreak = 0,
  });

  final int answered;
  final int correct;

  /// Right answers in a row.
  final int streak;
  final int bestStreak;

  EarScore answer({required bool right}) => EarScore(
    answered: answered + 1,
    correct: correct + (right ? 1 : 0),
    streak: right ? streak + 1 : 0,
    bestStreak: right && streak + 1 > bestStreak ? streak + 1 : bestStreak,
  );
}

/// Lowest and highest MIDI pitch a question may use (the layer range is
/// 24..107; questions stay well inside it).
const earLowestPitch = 48;
const earHighestPitch = 71;

const _noteNames = [
  'C',
  'C#',
  'D',
  'D#',
  'E',
  'F',
  'F#',
  'G',
  'G#',
  'A',
  'A#',
  'B',
];

/// Pitch name without octave for a MIDI [pitch].
String earNoteName(int pitch) => _noteNames[pitch % 12];

/// The triad qualities of the chord mode, in the order they are offered.
const earChordQualities = <(String, String, List<int>)>[
  ('major', 'Major', [0, 4, 7]),
  ('minor', 'Minor', [0, 3, 7]),
  ('dim', 'Diminished', [0, 3, 6]),
  ('aug', 'Augmented', [0, 4, 8]),
];

/// A scale degree of a major key: semitones above the key and its triad.
class _Degree {
  const _Degree(this.name, this.offset, this.triad);

  final String name;
  final int offset;
  final List<int> triad;
}

const _major = [0, 4, 7];
const _minor = [0, 3, 7];

const _degrees = {
  'I': _Degree('I', 0, _major),
  'ii': _Degree('ii', 2, _minor),
  'iii': _Degree('iii', 4, _minor),
  'IV': _Degree('IV', 5, _major),
  'V': _Degree('V', 7, _major),
  'vi': _Degree('vi', 9, _minor),
};

/// The progressions of the progression mode, as degree names.
const earProgressions = <List<String>>[
  ['I', 'IV', 'V', 'I'],
  ['I', 'vi', 'IV', 'V'],
  ['I', 'V', 'vi', 'IV'],
  ['I', 'IV', 'vi', 'V'],
  ['I', 'vi', 'ii', 'V'],
  ['I', 'iii', 'IV', 'V'],
];

/// Deterministic question source: the same [mode] and seed always give the
/// same questions. No question repeats the previous right answer.
class EarQuestionGenerator {
  EarQuestionGenerator(this.mode, {required int seed})
    : _random = SeededRandom(seed);

  final EarMode mode;
  final SeededRandom _random;
  String? _previous;

  EarQuestion next() {
    EarQuestion question;
    var tries = 0;
    do {
      question = switch (mode) {
        EarMode.note => _note(),
        EarMode.chord => _chord(),
        EarMode.progression => _progression(),
      };
    } while (question.correct.id == _previous && ++tries < 16);
    _previous = question.correct.id;
    return question;
  }

  EarQuestion _note() {
    final pitch =
        earLowestPitch + _random.nextInt(earHighestPitch - earLowestPitch + 1);
    final correct = pitch % 12;
    final others = shuffled(_random, [
      for (var i = 0; i < 12; i++)
        if (i != correct) i,
    ]).take(3);
    final classes = [correct, ...others]..sort();
    return EarQuestion(
      mode: EarMode.note,
      options: [
        for (final c in classes) EarOption(_noteNames[c], _noteNames[c]),
      ],
      correctIndex: classes.indexOf(correct),
      steps: [
        [pitch],
      ],
    );
  }

  EarQuestion _chord() {
    final root = earLowestPitch + _random.nextInt(12);
    final index = _random.nextInt(earChordQualities.length);
    final (_, _, intervals) = earChordQualities[index];
    return EarQuestion(
      mode: EarMode.chord,
      options: [
        for (final (id, label, _) in earChordQualities) EarOption(id, label),
      ],
      correctIndex: index,
      steps: [
        [for (final i in intervals) root + i],
      ],
    );
  }

  EarQuestion _progression() {
    final key = earLowestPitch + _random.nextInt(12);
    final correct = _random.nextInt(earProgressions.length);
    final others = shuffled(_random, [
      for (var i = 0; i < earProgressions.length; i++)
        if (i != correct) i,
    ]).take(3);
    final chosen = shuffled(_random, [correct, ...others]);
    String label(int i) => earProgressions[i].join('-');
    return EarQuestion(
      mode: EarMode.progression,
      options: [for (final i in chosen) EarOption(label(i), label(i))],
      correctIndex: chosen.indexOf(correct),
      steps: [
        for (final name in earProgressions[correct])
          [
            for (final i in _degrees[name]!.triad)
              key + _degrees[name]!.offset + i,
          ],
      ],
    );
  }
}
