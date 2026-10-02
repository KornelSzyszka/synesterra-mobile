import 'dart:math' as math;

const _names = [
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

/// The nearest equal-tempered note, for example `A4` for 440 Hz.
String noteName(double hz) {
  final midi = (69 + 12 * math.log(hz / 440) / math.ln2).round();
  return '${_names[midi % 12]}${midi ~/ 12 - 1}';
}

/// `440 Hz · A4`, with the Hz value rounded for display.
String pitchLabel(double hz) => '${hz.round()} Hz · ${noteName(hz)}';
