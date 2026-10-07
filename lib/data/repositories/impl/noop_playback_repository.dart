import 'package:flutter/foundation.dart';
import 'package:synesterra_core/synesterra_core.dart';

import '../playback_repository.dart';

/// Plays nothing and keeps the position at the cycle start. Reports the
/// transport state and generation like the real repository, so views can be
/// tested and previewed without an engine.
class NoopPlaybackRepository implements PlaybackRepository {
  final _status = ValueNotifier(PlaybackStatus());
  final _position = ValueNotifier(PlaybackPosition.stopped(0));
  int _generation = 0;

  @override
  ValueListenable<PlaybackStatus> get status => _status;

  @override
  ValueListenable<PlaybackPosition> get position => _position;

  @override
  PlaybackPosition readPosition() => _position.value;

  void _set({required bool playing, int? bpm, PlaybackStopReason? reason}) {
    _generation++;
    _status.value = PlaybackStatus(
      state: playing ? PlaybackState.playing : PlaybackState.stopped,
      stopReason: reason ?? PlaybackStopReason.user,
      bpm: bpm,
    );
    _position.value = PlaybackPosition(
      playing: playing,
      cyclePosition: 0,
      cycleIndex: 0,
      generation: _generation,
    );
  }

  @override
  Future<void> play(SessionDocument document) async =>
      _set(playing: true, bpm: document.transport.bpm.round());

  @override
  Future<void> playSequence(
    List<PlaybackSection> sections, {
    required bool repeatAll,
  }) async => sections.isEmpty
      ? _set(playing: false, reason: PlaybackStopReason.emptySequence)
      : _set(playing: true, bpm: sections.first.document.transport.bpm.round());

  @override
  Future<void> stop() async => _set(playing: false);

  @override
  void setTempo(int bpm) {
    if (_status.value.state == PlaybackState.playing) {
      _set(playing: true, bpm: bpm);
    }
  }

  @override
  void setLayerGain(String layerId, double gain) {}

  @override
  Future<void> dispose() async {
    _status.dispose();
    _position.dispose();
  }
}
