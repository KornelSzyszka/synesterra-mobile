import 'dart:typed_data';

import 'package:synesterra_core/synesterra_core.dart';

/// What session playback needs from an audio engine: the two ports, a
/// lifecycle, generated buffers and a verified voice cap. Implemented on
/// `flutter_soloud` by `SoloudPlaybackEngine` and by fakes in tests.
abstract interface class PlaybackEngine {
  /// Stable for the life of the engine object.
  AudioClock get clock;

  /// Stable for the life of the engine object.
  VoiceSink get sink;

  /// Initializes the engine when needed and starts the clock. Safe to call
  /// while running. Never called at app launch, only on an explicit Play.
  Future<void> start();

  /// Releases orphaned sustained voices, lets the device idle and stops the
  /// clock. Call after the stop generation has been cancelled in the sink.
  Future<void> stop();

  /// Whether [soundId] is loaded and usable for new events.
  bool hasBuffer(String soundId);

  /// Loads mono [samples] (-1..1) as [soundId], replacing an older buffer
  /// without cutting its sounding voices.
  Future<void> loadBuffer(String soundId, Float32List samples, int sampleRate);

  /// Stops using [soundId]; it is released after its last voice ends.
  Future<void> unloadBuffer(String soundId);

  /// Requests a cap on simultaneous voices and returns the accepted value.
  /// Throws when the engine does not accept exactly [count].
  int setVoiceLimit(int count);

  /// Periodic housekeeping, such as releasing retired buffers.
  Future<void> maintain();

  /// Stops every voice and releases every buffer.
  Future<void> dispose();
}
