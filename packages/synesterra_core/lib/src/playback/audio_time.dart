/// A point on the engine timeline, measured in microseconds.
final class AudioTime implements Comparable<AudioTime> {
  AudioTime(this.microseconds) {
    if (microseconds < 0) {
      throw ArgumentError.value(
        microseconds,
        'microseconds',
        'must be non-negative',
      );
    }
  }

  final int microseconds;

  AudioTime operator +(Duration offset) =>
      AudioTime(microseconds + offset.inMicroseconds);

  Duration operator -(AudioTime other) =>
      Duration(microseconds: microseconds - other.microseconds);

  @override
  int compareTo(AudioTime other) => microseconds.compareTo(other.microseconds);

  @override
  bool operator ==(Object other) =>
      other is AudioTime && microseconds == other.microseconds;

  @override
  int get hashCode => microseconds.hashCode;
}
