import 'package:flutter/foundation.dart';
import 'package:synesterra/data/repositories/loop.dart';
import 'package:synesterra/data/repositories/playback_repository.dart';
import 'package:synesterra_core/synesterra_core.dart';

/// A playback repository whose status and position tests set by hand, and
/// that records every command. Like the real one, a stop with an owner only
/// acts when that owner's playback is the current one.
class RecordingPlayback implements PlaybackRepository {
  final statusNotifier = ValueNotifier(PlaybackStatus());
  final positionNotifier = ValueNotifier(PlaybackPosition.stopped(0));
  final sequences = <(List<PlaybackSection>, bool)>[];

  /// Stops that took effect.
  int stops = 0;
  int plays = 0;

  @override
  ValueListenable<PlaybackStatus> get status => statusNotifier;

  @override
  ValueListenable<PlaybackPosition> get position => positionNotifier;

  @override
  PlaybackPosition readPosition() => positionNotifier.value;

  @override
  Future<void> play(SessionDocument document, {Object? owner}) async {
    plays++;
    statusNotifier.value = PlaybackStatus(
      state: PlaybackState.playing,
      owner: owner,
    );
    positionNotifier.value = PlaybackPosition(
      playing: true,
      cyclePosition: 0,
      cycleIndex: 0,
      generation: positionNotifier.value.generation + 1,
    );
  }

  @override
  Future<void> playSequence(
    List<PlaybackSection> sections, {
    required bool repeatAll,
    Object? owner,
  }) async {
    sequences.add((List.of(sections), repeatAll));
    statusNotifier.value = PlaybackStatus(
      state: PlaybackState.playing,
      bpm: sections.isEmpty ? null : 90,
      owner: owner,
    );
    positionNotifier.value = PlaybackPosition(
      playing: true,
      cyclePosition: 0,
      cycleIndex: 0,
      generation: positionNotifier.value.generation + 1,
      sectionIndex: sections.isEmpty ? null : sections.first.originalIndex,
    );
  }

  @override
  Future<void> stop({Object? owner}) async {
    if (owner != null && !identical(owner, statusNotifier.value.owner)) return;
    stops++;
    statusNotifier.value = PlaybackStatus();
    positionNotifier.value = PlaybackPosition.stopped(
      positionNotifier.value.generation + 1,
    );
  }

  /// What the engine reports when a sequence without "repeat all" ends.
  void finish() {
    statusNotifier.value = PlaybackStatus(
      stopReason: PlaybackStopReason.finished,
    );
    positionNotifier.value = PlaybackPosition.stopped(
      positionNotifier.value.generation + 1,
    );
  }

  @override
  void setTempo(int bpm) {}

  @override
  void setLayerGain(String layerId, double gain) {}

  @override
  Future<void> dispose() async {}
}

Loop userLoop(String id, String name, {List<int> hits = const [3, 2]}) => Loop(
  id: id,
  name: name,
  document: simpleLoopDocument(
    bpm: 120,
    cycleBeats: 4,
    layers: [
      for (final h in hits)
        LoopLayerSpec(instrumentId: 'factory-wood', pitch: 69, hits: h),
    ],
  ),
);

Arrangement arrangementOf(
  String id,
  String name,
  List<(String, int)> sections,
) => Arrangement(
  id: id,
  name: name,
  sections: [
    for (final (loopId, repeats) in sections)
      ArrangementSection(loopId: loopId, repeats: repeats),
  ],
);
