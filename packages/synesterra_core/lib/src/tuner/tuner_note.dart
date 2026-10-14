import 'dart:math' as math;

const List<String> _noteNames = [
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

/// Lowest and highest accepted reference pitch for A4, in Hz.
const double minReferenceA4 = 400;
const double maxReferenceA4 = 480;
const double defaultReferenceA4 = 440;

/// A frequency read as the nearest equal-tempered note and the deviation.
class TunerNote {
  const TunerNote({
    required this.midi,
    required this.name,
    required this.octave,
    required this.cents,
    required this.frequencyHz,
    required this.targetHz,
  });

  /// MIDI note number (A4 = 69).
  final int midi;

  /// `C`, `C#` ... `B`.
  final String name;

  /// Scientific octave: C4 is middle C, A4 is the reference.
  final int octave;

  /// Deviation from the nearest note, -50..+50; positive is sharp.
  final double cents;

  /// The measured frequency.
  final double frequencyHz;

  /// The exact frequency of the nearest note for the chosen reference.
  final double targetHz;

  String get label => '$name$octave';

  /// True when within [toleranceCents] of the note.
  bool inTune([double toleranceCents = 5]) => cents.abs() <= toleranceCents;
}

void _checkReference(double referenceA4) {
  if (!(referenceA4 >= minReferenceA4 && referenceA4 <= maxReferenceA4)) {
    throw ArgumentError.value(
      referenceA4,
      'referenceA4',
      'between $minReferenceA4 and $maxReferenceA4 Hz',
    );
  }
}

/// The continuous MIDI number of [frequencyHz] (69 = A4, fractional between).
double midiOfFrequency(
  double frequencyHz, {
  double referenceA4 = defaultReferenceA4,
}) {
  _checkReference(referenceA4);
  if (!(frequencyHz > 0) || frequencyHz.isInfinite) {
    throw ArgumentError.value(frequencyHz, 'frequencyHz', 'positive, finite');
  }
  return 69 + 12 * math.log(frequencyHz / referenceA4) / math.ln2;
}

/// The frequency of MIDI note [midi] for the chosen reference.
double frequencyOfMidi(int midi, {double referenceA4 = defaultReferenceA4}) {
  _checkReference(referenceA4);
  return referenceA4 * math.pow(2, (midi - 69) / 12);
}

/// The nearest note to [frequencyHz] and the deviation in cents.
TunerNote noteOfFrequency(
  double frequencyHz, {
  double referenceA4 = defaultReferenceA4,
}) {
  return noteOfMidi(
    midiOfFrequency(frequencyHz, referenceA4: referenceA4),
    referenceA4: referenceA4,
  );
}

/// Like [noteOfFrequency] for a continuous MIDI number (already relative to
/// [referenceA4]), used for smoothed values.
TunerNote noteOfMidi(
  double midiValue, {
  double referenceA4 = defaultReferenceA4,
}) {
  _checkReference(referenceA4);
  final midi = midiValue.round();
  return TunerNote(
    midi: midi,
    name: _noteNames[midi % 12],
    octave: midi ~/ 12 - 1,
    cents: (midiValue - midi) * 100,
    frequencyHz: referenceA4 * math.pow(2, (midiValue - 69) / 12),
    targetHz: frequencyOfMidi(midi, referenceA4: referenceA4),
  );
}
