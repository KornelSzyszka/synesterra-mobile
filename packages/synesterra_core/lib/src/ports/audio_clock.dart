import '../playback/audio_time.dart';

enum EngineState { stopped, starting, running, interrupted }

/// One atomic snapshot of the engine's published audio timeline state.
final class AudioClockReading {
  AudioClockReading({
    required this.renderTime,
    required this.outputTime,
    required this.fallbackOutputLatency,
    required this.minLead,
    required this.state,
  }) {
    if (fallbackOutputLatency.isNegative) {
      throw ArgumentError.value(fallbackOutputLatency, 'fallbackOutputLatency');
    }
    if (minLead.isNegative) {
      throw ArgumentError.value(minLead, 'minLead');
    }
  }

  /// Timeline time of the first frame the engine has not rendered yet.
  final AudioTime renderTime;

  /// Estimated presentation time, used for position display only.
  final AudioTime? outputTime;

  /// Estimate used for display when [outputTime] is unavailable.
  final Duration fallbackOutputLatency;

  /// Minimum safe distance from [renderTime] to an inserted event.
  final Duration minLead;

  final EngineState state;
}

abstract interface class AudioClock {
  /// Returns a synchronous snapshot without waiting for the audio thread.
  AudioClockReading now();
}
