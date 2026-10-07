import 'dart:typed_data';

import 'package:synesterra_core/synesterra_core.dart';

import 'playback_engine.dart';
import 'soloud_audio_clock.dart';
import 'soloud_voice_sink.dart';
import 'wav_encoder.dart';

/// The parts of the shared SoLoud engine's life cycle that playback uses.
/// The engine is shared with instrument audition, so playback never
/// deinitializes it.
abstract interface class SoloudEngineLifecycle {
  bool get isInitialized;
  Future<void> initialize();

  /// Keeps the output device open while playing; lets it idle otherwise.
  void keepDeviceOpen(bool open);
}

/// [PlaybackEngine] built from the spike adapters: [SoloudAudioClock] (rebased
/// engine time) and [SoloudVoiceSink] (inverse rebase, late drop, handles by
/// generation, source retirement and the verified voice cap).
final class SoloudPlaybackEngine implements PlaybackEngine {
  SoloudPlaybackEngine({
    required SoloudClockSource clockSource,
    required SoloudVoiceEngine voiceEngine,
    required this._lifecycle,
    bool Function(Object source)? isSourceLoaded,
    Duration Function()? hostElapsed,
    void Function(Map<String, Object?>)? onLog,
  }) : _clock = SoloudAudioClock(clockSource, hostElapsed: hostElapsed) {
    _sink = SoloudVoiceSink(
      voiceEngine,
      _clock,
      onLog: onLog,
      isSourceLoaded: isSourceLoaded,
      stopSoundingOnCancel: true,
    );
  }

  final SoloudEngineLifecycle _lifecycle;
  final SoloudAudioClock _clock;
  late final SoloudVoiceSink _sink;
  bool _running = false;

  @override
  AudioClock get clock => _clock;

  @override
  VoiceSink get sink => _sink;

  @override
  Future<void> start() async {
    if (!_lifecycle.isInitialized) await _lifecycle.initialize();
    // Another owner may have deinitialized and restarted the shared engine;
    // its old sources are gone, so the buffers must be loaded again.
    if (_sink.lostSources) _sink.forgetEngineState();
    _lifecycle.keepDeviceOpen(true);
    if (!_running) {
      _clock.start();
      _running = true;
    }
  }

  @override
  Future<void> stop() async {
    if (!_engineGone) {
      await _sink.releaseOrphanedSustains();
      _lifecycle.keepDeviceOpen(false);
    }
    if (_running) {
      _clock.stop();
      _running = false;
    }
  }

  @override
  bool hasBuffer(String soundId) => _sink.hasSound(soundId);

  @override
  Future<void> loadBuffer(
    String soundId,
    Float32List samples,
    int sampleRate,
  ) => _sink.loadWav(soundId, encodeWav16(samples, sampleRate: sampleRate));

  @override
  Future<void> unloadBuffer(String soundId) => _sink.retire(soundId);

  @override
  int setVoiceLimit(int count) {
    _sink.setVoiceLimit(count);
    return _sink.maxVoices;
  }

  @override
  Future<void> maintain() async {
    if (!_engineGone) await _sink.collectRetired();
  }

  @override
  Future<void> dispose() async {
    await stop();
    if (_engineGone) {
      _sink.forgetEngineState();
    } else {
      await _sink.dispose();
    }
  }

  /// The shared engine was deinitialized by another owner: nothing of ours
  /// is left to stop or release.
  bool get _engineGone => !_lifecycle.isInitialized || _sink.lostSources;
}
