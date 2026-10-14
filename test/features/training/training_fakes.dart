import 'package:flutter/foundation.dart';
import 'package:synesterra/data/repositories/impl/noop_playback_repository.dart';
import 'package:synesterra/data/repositories/playback_repository.dart';
import 'package:synesterra_core/synesterra_core.dart';

/// A silent playback whose transport position the test sets.
class ScriptedPlayback extends NoopPlaybackRepository {
  final _pos = ValueNotifier(PlaybackPosition.stopped(0));
  final documents = <SessionDocument>[];
  final owners = <Object?>[];
  final sequences = <List<PlaybackSection>>[];
  int stops = 0;
  bool failStart = false;

  @override
  ValueListenable<PlaybackPosition> get position => _pos;

  @override
  PlaybackPosition readPosition() => _pos.value;

  /// Moves the transport to [ms] of a cycle of [cycleMs].
  void at(double ms, {required double cycleMs}) {
    final cycles = ms / cycleMs;
    final index = cycles.floor();
    _pos.value = PlaybackPosition(
      playing: true,
      cyclePosition: cycles - index,
      cycleIndex: index,
      generation: 1,
    );
  }

  @override
  Future<void> play(SessionDocument document, {Object? owner}) async {
    documents.add(document);
    owners.add(owner);
    if (failStart) {
      (status as ValueNotifier<PlaybackStatus>).value = PlaybackStatus(
        stopReason: PlaybackStopReason.error,
        error: 'no engine',
      );
      return;
    }
    await super.play(document, owner: owner);
  }

  @override
  Future<void> playSequence(
    List<PlaybackSection> sections, {
    required bool repeatAll,
    Object? owner,
  }) async {
    sequences.add(sections);
    owners.add(owner);
    if (failStart) {
      (status as ValueNotifier<PlaybackStatus>).value = PlaybackStatus(
        stopReason: PlaybackStopReason.error,
        error: 'no engine',
      );
      return;
    }
    await super.playSequence(sections, repeatAll: repeatAll, owner: owner);
  }

  @override
  Future<void> stop({Object? owner}) async {
    stops++;
    await super.stop(owner: owner);
  }
}
