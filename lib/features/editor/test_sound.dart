import 'dart:math' as math;

import '../../shared/formatting/note_name.dart';

/// Chord shapes for testing an instrument, as semitones above the root.
enum ChordQuality {
  major('Major', [0, 4, 7]),
  minor('Minor', [0, 3, 7]),
  dominant7('Dom 7', [0, 4, 7, 10]),
  major7('Maj 7', [0, 4, 7, 11]),
  minor7('Min 7', [0, 3, 7, 10]),
  sus4('Sus 4', [0, 5, 7]),
  power('Power', [0, 7, 12]);

  const ChordQuality(this.label, this.semitones);

  final String label;
  final List<int> semitones;
}

/// What the editor plays to let the user hear an instrument. An instrument
/// has no pitch, so this is only a test: it is not saved with the instrument
/// and never changes it.
sealed class TestSound {
  const TestSound();

  /// The lowest and highest root, as MIDI numbers (C1 and B7).
  static const lowestMidi = 24;
  static const highestMidi = 107;

  /// The default test: A4.
  static const defaultNote = TestNote(69);

  int get rootMidi;

  /// Every note that sounds, root first.
  List<double> get frequenciesHz;

  /// A short name for the semantics and the UI, such as `A4` or `C3 Minor`.
  String get label;

  /// The root's frequency; the Figure and Wave views use it.
  double get rootHz => midiToHz(rootMidi);
}

double midiToHz(int midi) => 440 * math.pow(2, (midi - 69) / 12).toDouble();

final class TestNote extends TestSound {
  const TestNote(this.midi);

  final int midi;

  @override
  int get rootMidi => midi;

  @override
  List<double> get frequenciesHz => [midiToHz(midi)];

  @override
  String get label => noteName(midiToHz(midi));

  @override
  bool operator ==(Object other) => other is TestNote && midi == other.midi;

  @override
  int get hashCode => midi.hashCode;
}

final class TestChord extends TestSound {
  const TestChord(this.root, this.quality);

  final int root;
  final ChordQuality quality;

  @override
  int get rootMidi => root;

  @override
  List<double> get frequenciesHz => [
    for (final step in quality.semitones) midiToHz(root + step),
  ];

  @override
  String get label => '${noteName(midiToHz(root))} ${quality.label}';

  @override
  bool operator ==(Object other) =>
      other is TestChord && root == other.root && quality == other.quality;

  @override
  int get hashCode => Object.hash(root, quality);
}
