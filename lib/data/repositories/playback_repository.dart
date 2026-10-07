import 'package:flutter/foundation.dart';
import 'package:synesterra_core/synesterra_core.dart';

/// Where the transport is, as the listener hears it (approximately: see
/// docs/modules/playback.md). Derived from one audio clock reading, never
/// from a UI timer.
@immutable
final class PlaybackPosition {
  PlaybackPosition({
    required this.playing,
    required this.cyclePosition,
    required this.cycleIndex,
    required this.generation,
    this.sectionIndex,
  }) {
    if (!cyclePosition.isFinite || cyclePosition < 0 || cyclePosition >= 1) {
      throw ArgumentError.value(cyclePosition, 'cyclePosition', 'in [0, 1)');
    }
    if (cycleIndex < 0) throw ArgumentError.value(cycleIndex, 'cycleIndex');
    if (generation < 0) throw ArgumentError.value(generation, 'generation');
    if (sectionIndex != null && sectionIndex! < 0) {
      throw ArgumentError.value(sectionIndex, 'sectionIndex');
    }
  }

  /// Not playing: the cycle start of [generation].
  PlaybackPosition.stopped(int generation)
    : this(
        playing: false,
        cyclePosition: 0,
        cycleIndex: 0,
        generation: generation,
      );

  final bool playing;

  /// Position within the current practice cycle, half-open [0, 1): a cycle
  /// boundary is 0 of the next cycle.
  final double cyclePosition;

  /// Whole cycles since the loop (or the current section) started.
  final int cycleIndex;

  /// Increments on play, stop, tempo, structural change and, in a sequence,
  /// when a section boundary is heard. A new value means "do not interpolate
  /// from the previous position".
  final int generation;

  /// Index of the playing section in the caller's arrangement (the
  /// `originalIndex` of [PlaybackSection]); null outside a sequence.
  final int? sectionIndex;

  @override
  bool operator ==(Object other) =>
      other is PlaybackPosition &&
      playing == other.playing &&
      cyclePosition == other.cyclePosition &&
      cycleIndex == other.cycleIndex &&
      generation == other.generation &&
      sectionIndex == other.sectionIndex;

  @override
  int get hashCode =>
      Object.hash(playing, cyclePosition, cycleIndex, generation, sectionIndex);

  @override
  String toString() =>
      'PlaybackPosition(playing: $playing, cycle: $cycleIndex + '
      '$cyclePosition, generation: $generation, section: $sectionIndex)';
}

/// One section of a sequence. The caller has already dropped sections whose
/// loop is missing; [originalIndex] is the section's index in the arrangement.
@immutable
final class PlaybackSection {
  PlaybackSection({
    required this.originalIndex,
    required this.document,
    required this.repeats,
  }) {
    if (originalIndex < 0) {
      throw ArgumentError.value(originalIndex, 'originalIndex');
    }
    if (repeats < 1 || repeats > 32) {
      throw ArgumentError.value(repeats, 'repeats', 'must be 1..32');
    }
  }

  final int originalIndex;
  final SessionDocument document;

  /// How many practice cycles of [document] to play before the next section.
  final int repeats;
}

enum PlaybackState {
  stopped,

  /// Rendering instrument buffers or starting the engine; silent.
  preparing,
  playing,
}

enum PlaybackStopReason {
  /// Nothing has played yet, or the caller pressed Stop.
  user,

  /// [PlaybackRepository.playSequence] got no playable section.
  emptySequence,

  /// A sequence without "repeat all" played its last section to the end.
  finished,

  /// The engine failed; see [PlaybackStatus.error].
  error,
}

@immutable
final class PlaybackStatus {
  PlaybackStatus({
    this.state = PlaybackState.stopped,
    this.stopReason = PlaybackStopReason.user,
    this.bpm,
    Set<String> missingInstrumentIds = const {},
    this.voiceLimit,
    this.voiceLimitSaturated = false,
    this.error,
  }) : missingInstrumentIds = Set.unmodifiable(missingInstrumentIds);

  final PlaybackState state;

  /// Why playback is stopped; meaningless while preparing or playing.
  final PlaybackStopReason stopReason;

  /// Transport tempo while preparing or playing.
  final int? bpm;

  /// Instrument ids that resolve neither to a factory instrument nor to the
  /// library. Their layers play silence.
  final Set<String> missingInstrumentIds;

  /// Simultaneous-voice cap the engine accepted for the current program.
  final int? voiceLimit;

  /// The program could need more voices than the engine's safe cap (1022);
  /// the quietest voices may then be dropped by the engine.
  final bool voiceLimitSaturated;

  final String? error;
}

/// Plays scene A of a [SessionDocument], or a sequence of them, through the
/// audio engine. Owns the transport and its generation; view models only send
/// commands and read [status] and [position]. Timing is not measured on a
/// device (issue #43).
abstract interface class PlaybackRepository {
  ValueListenable<PlaybackStatus> get status;

  /// Refreshed on every scheduler wake (about every 25 ms) and on every
  /// command. For smooth animation, call [readPosition] once per frame.
  ValueListenable<PlaybackPosition> get position;

  /// The position from a fresh audio clock reading.
  PlaybackPosition readPosition();

  /// Plays scene A of [document] as a loop. While a loop is already playing,
  /// the difference decides: tempo only keeps the phase (new generation, no
  /// restart); mix only (gain, pan, mute, solo, master gain) applies to the
  /// next planned events without a new generation; anything else restarts
  /// from the cycle start under a new generation.
  Future<void> play(SessionDocument document);

  /// Plays [sections] in order, each for its repeats of its practice cycle,
  /// switching on a cycle boundary. With [repeatAll] it wraps to the first
  /// section. An empty list stops with [PlaybackStopReason.emptySequence].
  /// The tempo is the first section's; [setTempo] changes it for all.
  Future<void> playSequence(
    List<PlaybackSection> sections, {
    required bool repeatAll,
  });

  /// Silences pending events (new generation) and resets the position.
  Future<void> stop();

  /// Changes the running tempo (20..300 BPM) and keeps the phase. Does
  /// nothing while stopped: playback takes its tempo from the document.
  void setTempo(int bpm);

  /// Overrides the gain (0..1) of every layer with [layerId] for events
  /// planned from now on; no replanning. Reset by the next [play] or
  /// [playSequence] with a new document.
  void setLayerGain(String layerId, double gain);

  Future<void> dispose();
}
