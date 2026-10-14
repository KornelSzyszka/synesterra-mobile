/// Tap tempo: turns the times of a user's taps into a tempo.
///
/// Pure: the caller passes the time of each tap (any monotonic clock), the
/// core reads no clock. The tempo is the average interval of the last taps,
/// available from the third tap. A pause longer than [resetAfter], or a time
/// that does not move forward, starts a new count with that tap.
class TapTempo {
  TapTempo({
    this.minTaps = 3,
    this.maxTaps = 8,
    this.resetAfter = const Duration(seconds: 2),
    this.minBpm = 20,
    this.maxBpm = 300,
  }) {
    if (minTaps < 2) {
      throw ArgumentError.value(minTaps, 'minTaps', 'at least 2');
    }
    if (maxTaps < minTaps) {
      throw ArgumentError.value(maxTaps, 'maxTaps', 'below minTaps');
    }
    if (minBpm < 1 || maxBpm < minBpm) {
      throw ArgumentError.value(maxBpm, 'maxBpm', 'bad BPM range');
    }
  }

  /// Taps needed before a tempo is given.
  final int minTaps;

  /// Most recent taps that are averaged.
  final int maxTaps;

  /// Silence after which the next tap starts over.
  final Duration resetAfter;

  /// The result is clamped to this range, whole BPM.
  final int minBpm;
  final int maxBpm;

  final List<Duration> _taps = [];

  /// How many taps are counted now.
  int get count => _taps.length;

  /// Registers a tap at [at]. Returns the tempo in whole BPM once [minTaps]
  /// taps are counted, otherwise null.
  int? tap(Duration at) {
    if (_taps.isNotEmpty) {
      final gap = at - _taps.last;
      if (gap <= Duration.zero || gap > resetAfter) _taps.clear();
    }
    _taps.add(at);
    if (_taps.length > maxTaps) _taps.removeAt(0);
    if (_taps.length < minTaps) return null;
    final span = _taps.last - _taps.first;
    final average = span.inMicroseconds / (_taps.length - 1);
    final bpm = (Duration.microsecondsPerMinute / average).round();
    return bpm < minBpm ? minBpm : (bpm > maxBpm ? maxBpm : bpm);
  }

  /// Forgets the taps.
  void reset() => _taps.clear();
}
