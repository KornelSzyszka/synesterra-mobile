import 'dart:async';

import 'package:synesterra_core/synesterra_core.dart';

/// C0 transport snapshot. RuntimePerformanceState will replace or extend it.
enum PlaybackTransport { playing, paused, stopped }

final class PlaybackSnapshot {
  PlaybackSnapshot({
    required this.transport,
    required this.generation,
    required this.tempoMap,
  }) {
    if (generation < 0) throw ArgumentError.value(generation, 'generation');
  }

  final PlaybackTransport transport;
  final Generation generation;
  final TempoMap tempoMap;
}

abstract interface class PlaybackStateSource {
  PlaybackSnapshot get snapshot;
}

enum PlannedVoiceKind { trigger, sustainOn, sustainOff }

/// C0 event shape for fixture playback until the DOM EventPlanner exists.
final class PlannedVoiceEvent {
  PlannedVoiceEvent({
    required this.beat,
    required this.eventId,
    required this.kind,
    required this.sound,
    this.key = '',
    this.gain = 1,
    this.pan = 0,
  }) {
    if (beat < 0) throw ArgumentError.value(beat, 'beat');
    if (eventId < 0) throw ArgumentError.value(eventId, 'eventId');
    if (kind != PlannedVoiceKind.sustainOff && sound.isEmpty) {
      throw ArgumentError.value(sound, 'sound');
    }
    if (kind != PlannedVoiceKind.trigger && key.isEmpty) {
      throw ArgumentError.value(key, 'key');
    }
  }

  final int beat;
  final int eventId;
  final PlannedVoiceKind kind;
  final String sound;
  final String key;
  final double gain;
  final double pan;

  VoiceEvent at(AudioTime time) => switch (kind) {
    PlannedVoiceKind.trigger => Trigger(
      at: time,
      eventId: eventId,
      sound: sound,
      gain: gain,
      pan: pan,
    ),
    PlannedVoiceKind.sustainOn => SustainOn(
      at: time,
      eventId: eventId,
      key: key,
      sound: sound,
      gain: gain,
      pan: pan,
    ),
    PlannedVoiceKind.sustainOff => SustainOff(
      at: time,
      eventId: eventId,
      key: key,
    ),
  };
}

abstract interface class BeatEventSource {
  /// Returns only events in [fromBeat, toBeat), in absolute ticks.
  List<PlannedVoiceEvent> plan(int fromBeat, int toBeat);
}

/// Wakes on a timer, but measures and schedules solely against [clock].
final class PlaybackScheduler {
  PlaybackScheduler({
    required this._clock,
    required this._sink,
    required this._state,
    required this._events,
  }) {
    _timer = Timer.periodic(const Duration(milliseconds: 25), (_) => replan());
  }

  static const horizon = Duration(milliseconds: 200);

  final AudioClock _clock;
  final VoiceSink _sink;
  final PlaybackStateSource _state;
  final BeatEventSource _events;
  late final Timer _timer;
  Generation? _lastGeneration;
  int? _plannedToBeat;

  /// Call synchronously after each transport, tempo or scene state change.
  void replan() {
    final runtime = _state.snapshot;
    if (_lastGeneration != runtime.generation) {
      _sink.cancelFrom(runtime.generation);
      _lastGeneration = runtime.generation;
      _plannedToBeat = null;
    }
    final reading = _clock.now();
    if (runtime.transport != PlaybackTransport.playing ||
        reading.state != EngineState.running) {
      return;
    }
    final earliest = reading.renderTime + reading.minLead;
    final tempoMap = runtime.tempoMap;
    final fromBeat = _max(
      _plannedToBeat ?? tempoMap.anchorBeat,
      tempoMap.beatAt(earliest),
    );
    final toBeat = tempoMap.beatAt(reading.renderTime + horizon);
    if (toBeat <= fromBeat) return;
    final planned = _events.plan(fromBeat, toBeat);
    final timed = <VoiceEvent>[];
    for (final event in planned) {
      if (event.beat < fromBeat || event.beat >= toBeat) continue;
      final at = tempoMap.audioTimeOf(event.beat);
      if (at.compareTo(earliest) >= 0) timed.add(event.at(at));
    }
    if (timed.isNotEmpty) _sink.schedule(runtime.generation, timed);
    _plannedToBeat = toBeat;
  }

  void dispose() => _timer.cancel();
}

int _max(int a, int b) => a >= b ? a : b;
