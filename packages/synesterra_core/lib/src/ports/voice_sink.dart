import '../playback/audio_time.dart';
import '../playback/tempo_map.dart';

sealed class VoiceEvent {
  AudioTime get at;
  int get eventId;
}

/// A one-shot with its mix already applied.
final class Trigger implements VoiceEvent {
  Trigger({
    required this.at,
    required this.eventId,
    required this.sound,
    required this.gain,
    required this.pan,
  }) {
    _validateEvent(eventId, sound);
    _validateMix(gain, pan);
  }

  @override
  final AudioTime at;
  @override
  final int eventId;
  final String sound;
  final double gain;
  final double pan;
}

/// Starts or retunes the sustained voice identified by [key].
final class SustainOn implements VoiceEvent {
  SustainOn({
    required this.at,
    required this.eventId,
    required this.key,
    required this.sound,
    required this.gain,
    required this.pan,
  }) {
    _validateEvent(eventId, sound);
    _validateKey(key);
    _validateMix(gain, pan);
  }

  @override
  final AudioTime at;
  @override
  final int eventId;
  final String key;
  final String sound;
  final double gain;
  final double pan;
}

/// Releases a sustained voice with an engine-owned short ramp.
final class SustainOff implements VoiceEvent {
  SustainOff({required this.at, required this.eventId, required this.key}) {
    if (eventId < 0) throw ArgumentError.value(eventId, 'eventId');
    _validateKey(key);
  }

  @override
  final AudioTime at;
  @override
  final int eventId;
  final String key;
}

void _validateEvent(int eventId, String sound) {
  if (eventId < 0) throw ArgumentError.value(eventId, 'eventId');
  if (sound.isEmpty) throw ArgumentError.value(sound, 'sound');
}

void _validateKey(String key) {
  if (key.isEmpty) throw ArgumentError.value(key, 'key');
}

void _validateMix(double gain, double pan) {
  if (!gain.isFinite ||
      gain < 0 ||
      gain > 1 ||
      !pan.isFinite ||
      pan < -1 ||
      pan > 1) {
    throw ArgumentError('gain must be in 0..1 and pan in -1..1');
  }
}

abstract interface class VoiceSink {
  /// Queues a batch; stale, late and overflow drops are counted by the engine.
  void schedule(Generation generation, List<VoiceEvent> events);

  /// Only [generation] or newer may start after the render cutoff.
  /// A newer event may adopt an orphaned sustained voice within the engine's
  /// adoption window; otherwise the orphan is released with a short ramp.
  /// The audible tail depends on output-route latency.
  void cancelFrom(Generation generation);
}
