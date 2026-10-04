import 'dart:typed_data';

import 'package:flutter_soloud/flutter_soloud.dart';

import 'soloud_audio_clock.dart';
import 'soloud_voice_sink.dart';

/// The only spike adapter file that depends on plugin types.
final class FlutterSoloudClockSource implements SoloudClockSource {
  FlutterSoloudClockSource(this.soloud);

  final SoLoud soloud;

  @override
  Duration get engineTime => soloud.getEngineTime();
}

final class FlutterSoloudVoiceEngine implements SoloudVoiceEngine {
  FlutterSoloudVoiceEngine(this.soloud);

  final SoLoud soloud;

  @override
  Future<Object> loadWav(String id, Uint8List wav) => soloud.loadMem(id, wav);

  @override
  Object playScheduled(
    Object source,
    Duration at, {
    required double gain,
    required double pan,
    bool looping = false,
  }) => soloud
      .playScheduled(
        source as AudioSource,
        at,
        volume: gain,
        pan: pan,
        looping: looping,
      )
      .id;

  @override
  bool isValid(Object handle) =>
      soloud.getIsValidVoiceHandle(SoundHandle(handle as int));

  @override
  Future<void> stop(Object handle) => soloud.stop(SoundHandle(handle as int));

  @override
  void stopScheduled(Object handle, Duration at) =>
      soloud.stopScheduled(SoundHandle(handle as int), at);

  @override
  void retune(Object handle, {required double gain, required double pan}) {
    soloud.setVolume(SoundHandle(handle as int), gain);
    soloud.setPan(SoundHandle(handle), pan);
  }

  @override
  Future<void> disposeSource(Object source) =>
      soloud.disposeSource(source as AudioSource);

  @override
  void setMaxVoices(int count) => soloud.setMaxActiveVoiceCount(count);

  @override
  int get maxVoices => soloud.getMaxActiveVoiceCount();

  @override
  int get activeVoices => soloud.getActiveVoiceCount();

  @override
  int get totalVoices => soloud.getVoiceCount();
}
