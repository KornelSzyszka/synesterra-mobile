import 'dart:math';

/// Amplitude at -60 dB, where an instrument's decay ends.
const envelopeFloor = 0.001;

/// The envelope of an instrument at [seconds] after the hit, 0..1: a linear
/// attack up to full level, then an exponential decay that reaches -60 dB
/// [decayMs] later and stays there. The renderer and the editor's graph both
/// use this, so the picture is the sound.
double envelopeLevel({
  required int attackMs,
  required int decayMs,
  required double seconds,
}) {
  final attack = attackMs / 1000.0;
  final decay = decayMs / 1000.0;
  if (seconds < attack) return seconds / attack;
  final progress = ((seconds - attack) / decay).clamp(0.0, 1.0);
  return pow(envelopeFloor, progress).toDouble();
}
