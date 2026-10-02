import 'audio_time.dart';

/// C0 beat unit. The DOM planner may extend this contract.
const ticksPerQuarter = 960;

/// C0 generation token. RuntimePerformanceState will own its increments.
typedef Generation = int;

/// C0 constant-tempo conversion. This is the only beat/audio-time conversion.
final class TempoMap {
  TempoMap({
    required this.bpm,
    required this.anchorBeat,
    required this.anchorTime,
  }) {
    if (bpm <= 0 || anchorBeat < 0) {
      throw ArgumentError('bpm must be positive and anchorBeat non-negative');
    }
  }

  final int bpm;
  final int anchorBeat;
  final AudioTime anchorTime;

  AudioTime audioTimeOf(int beat) {
    if (beat < 0) throw ArgumentError.value(beat, 'beat');
    final delta = (beat - anchorBeat) * Duration.microsecondsPerMinute;
    final micros =
        anchorTime.microseconds + _roundDivide(delta, bpm * ticksPerQuarter);
    return AudioTime(micros);
  }

  /// Floor to the containing tick; callers use half-open beat windows.
  int beatAt(AudioTime time) {
    final delta = time.microseconds - anchorTime.microseconds;
    final beat =
        anchorBeat +
        _floorDivide(
          delta * bpm * ticksPerQuarter,
          Duration.microsecondsPerMinute,
        );
    return beat < 0 ? 0 : beat;
  }
}

int _roundDivide(int numerator, int denominator) {
  if (numerator < 0) return -_roundDivide(-numerator, denominator);
  return (numerator + denominator ~/ 2) ~/ denominator;
}

int _floorDivide(int numerator, int denominator) {
  final quotient = numerator ~/ denominator;
  return numerator < 0 && numerator % denominator != 0
      ? quotient - 1
      : quotient;
}
