import 'package:flutter/foundation.dart';
import 'package:synesterra/data/repositories/impl/noop_playback_repository.dart';
import 'package:synesterra/data/repositories/playback_repository.dart';
import 'package:synesterra_core/synesterra_core.dart';

/// A silent playback repository that records the commands it gets.
class RecordingPlayback implements PlaybackRepository {
  final _inner = NoopPlaybackRepository();
  final played = <SessionDocument>[];
  final commands = <String>[];

  /// Mirrors the inner position, but a sequence reports its section like
  /// the real repository does.
  late final _position = ValueNotifier(_inner.position.value);
  int? _section;

  RecordingPlayback() {
    _inner.position.addListener(_mirror);
  }

  void _mirror() {
    final p = _inner.position.value;
    _position.value = PlaybackPosition(
      playing: p.playing,
      cyclePosition: p.cyclePosition,
      cycleIndex: p.cycleIndex,
      generation: p.generation,
      sectionIndex: p.playing ? _section : null,
    );
  }

  @override
  ValueListenable<PlaybackStatus> get status => _inner.status;

  @override
  ValueListenable<PlaybackPosition> get position => _position;

  @override
  PlaybackPosition readPosition() => _position.value;

  @override
  Future<void> play(SessionDocument document, {Object? owner}) {
    _section = null;
    played.add(document);
    commands.add('play');
    return _inner.play(document, owner: owner);
  }

  @override
  Future<void> playSequence(
    List<PlaybackSection> sections, {
    required bool repeatAll,
    Object? owner,
  }) {
    commands.add('sequence');
    _section = sections.isEmpty ? null : sections.first.originalIndex;
    return _inner.playSequence(sections, repeatAll: repeatAll, owner: owner);
  }

  @override
  Future<void> stop({Object? owner}) {
    final current = _inner.status.value.owner;
    if (owner == null || identical(owner, current)) _section = null;
    commands.add('stop');
    return _inner.stop(owner: owner);
  }

  @override
  void setTempo(int bpm) {
    commands.add('tempo:$bpm');
    _inner.setTempo(bpm);
  }

  @override
  void setLayerGain(String layerId, double gain) =>
      commands.add('gain:$layerId:$gain');

  @override
  Future<void> dispose() => _inner.dispose();
}
