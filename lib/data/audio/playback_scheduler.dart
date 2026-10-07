import 'dart:async';

import 'package:synesterra_core/synesterra_core.dart';

/// C0 transport snapshot. RuntimePerformanceState will replace or extend it.
enum PlaybackTransport { playing, paused, stopped }

final class PlaybackSnapshot {
  PlaybackSnapshot({
    required this.transport,
    required this.generation,
    required this.tempoMap,
    this.continuousSince,
    this.planUntilBeat,
  }) {
    if (generation < 0) throw ArgumentError.value(generation, 'generation');
    final since = continuousSince;
    if (since != null && (since < 0 || since > generation)) {
      throw ArgumentError.value(since, 'continuousSince');
    }
    if (planUntilBeat != null && planUntilBeat! < 0) {
      throw ArgumentError.value(planUntilBeat, 'planUntilBeat');
    }
  }

  final PlaybackTransport transport;
  final Generation generation;
  final TempoMap tempoMap;

  /// First generation of one continuous run on a single beat timeline (the
  /// sections of a sequence). Moving from a generation in
  /// [continuousSince, generation) to [generation] is a planned handover on a
  /// section boundary: events already queued stay valid, so the scheduler
  /// neither cancels nor restarts planning. Null means every generation
  /// change cancels, which is the rule for pause, stop, tempo and edits.
  final Generation? continuousSince;

  /// Planning never reaches this beat (exclusive) under [generation]; the
  /// owner hands over to the next generation once planning arrives here.
  final int? planUntilBeat;
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
    this.onDiagnostics,
  }) {
    _watch.start();
    _timer = Timer.periodic(const Duration(milliseconds: 25), (_) {
      final now = _watch.elapsed;
      final lateness = now - (_lastWake + const Duration(milliseconds: 25));
      _lastWake = now;
      onDiagnostics?.call({
        'type': 'wake',
        'latenessUs': lateness.inMicroseconds,
      });
      replan();
    });
  }

  static const horizon = Duration(milliseconds: 200);

  final AudioClock _clock;
  final VoiceSink _sink;
  final PlaybackStateSource _state;
  final BeatEventSource _events;
  final void Function(Map<String, Object?>)? onDiagnostics;
  late final Timer _timer;
  final Stopwatch _watch = Stopwatch();
  Duration _lastWake = Duration.zero;
  Generation? _lastGeneration;
  int? _plannedToBeat;

  /// Call synchronously after each transport, tempo or scene state change.
  void replan() {
    final runtime = _state.snapshot;
    if (_lastGeneration != runtime.generation) {
      final last = _lastGeneration;
      final since = runtime.continuousSince;
      final handover =
          last != null &&
          since != null &&
          last >= since &&
          last < runtime.generation;
      if (!handover) {
        _sink.cancelFrom(runtime.generation);
        _plannedToBeat = null;
      }
      _lastGeneration = runtime.generation;
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
    final horizonBeat = tempoMap.beatAt(reading.renderTime + horizon);
    final limit = runtime.planUntilBeat;
    final toBeat = limit != null && limit < horizonBeat ? limit : horizonBeat;
    if (_plannedToBeat != null && fromBeat > _plannedToBeat!) {
      final skipped = _events.plan(_plannedToBeat!, fromBeat);
      if (skipped.isNotEmpty) {
        onDiagnostics?.call({
          'type': 'scheduler_skip',
          'count': skipped.length,
          'fromBeat': _plannedToBeat,
          'toBeat': fromBeat,
        });
      }
    }
    onDiagnostics?.call({
      'type': 'coverage',
      'renderUs': reading.renderTime.microseconds,
      'minLeadUs': reading.minLead.inMicroseconds,
      'plannedCoverageUs':
          (tempoMap.audioTimeOf(toBeat) - reading.renderTime).inMicroseconds,
      'fromBeat': fromBeat,
      'toBeat': toBeat,
    });
    if (toBeat <= fromBeat) return;
    final planned = _events.plan(fromBeat, toBeat);
    final timed = <VoiceEvent>[];
    for (final event in planned) {
      if (event.beat < fromBeat || event.beat >= toBeat) continue;
      final at = tempoMap.audioTimeOf(event.beat);
      if (at.compareTo(earliest) >= 0) {
        timed.add(event.at(at));
      } else {
        onDiagnostics?.call({
          'type': 'scheduler_skip',
          'count': 1,
          'eventId': event.eventId,
          'reason': 'inside minLead',
        });
      }
    }
    if (timed.isNotEmpty) _sink.schedule(runtime.generation, timed);
    _plannedToBeat = toBeat;
  }

  void dispose() => _timer.cancel();
}

int _max(int a, int b) => a >= b ? a : b;
