import 'dart:typed_data';

/// A sound loaded into an engine. Opaque to everything but its engine.
abstract class AuditionSource {}

/// A sound that is playing. Opaque to everything but its engine.
abstract class AuditionVoice {}

/// What auditioning an instrument needs from an audio engine: load a WAV
/// created in memory, play it once, stop it. Not timing-critical, so there is
/// no scheduling here (that is the job of the scheduler and its ports).
abstract class AuditionEngine {
  /// Starts the engine. Safe to call again; it does nothing once started.
  Future<void> start();

  Future<AuditionSource> load(String id, Uint8List wav);

  AuditionVoice play(AuditionSource source, {double volume = 1});

  Future<void> stop(AuditionVoice voice);

  Future<void> unload(AuditionSource source);

  Future<void> dispose();
}
