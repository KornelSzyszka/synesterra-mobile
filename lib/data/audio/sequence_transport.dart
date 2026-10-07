import 'package:synesterra_core/synesterra_core.dart';

import 'playback_scheduler.dart';

/// Mix staging of a planned hit. Placeholders until the `musical` gate.
const unaccentedGain = 0.7;
const mixHeadroom = 0.6;

/// Scene A of one document, ready to plan, with a loaded sound per layer.
final class TransportSection {
  TransportSection({
    required this.document,
    required Map<String, String?> soundIds,
    this.originalIndex,
    this.repeats,
  }) : project = SessionProject(document, sceneId: 'A'),
       soundIds = Map.unmodifiable(soundIds) {
    if (repeats != null && repeats! < 1) {
      throw ArgumentError.value(repeats, 'repeats');
    }
  }

  final SessionDocument document;
  final SessionProject project;

  /// Layer id to loaded sound id; null for a missing instrument (silence).
  final Map<String, String?> soundIds;

  /// Index in the caller's arrangement; null for a single loop.
  final int? originalIndex;

  /// Practice cycles before the next section; null plays forever.
  final int? repeats;

  late final EventPlanner planner = EventPlanner(project);

  /// The practice cycle in ticks is [cycleTicksNumerator] / [cycleTicksDenominator].
  int get cycleTicksNumerator =>
      document.transport.practiceCycleBeats.numerator * ticksPerQuarter;
  int get cycleTicksDenominator =>
      document.transport.practiceCycleBeats.denominator;
}

/// One run of a section on the transport's beat timeline.
final class _Segment {
  _Segment(this.index, this.sectionIndex, this.startTick, this.endTick);
  final int index;
  final int sectionIndex;
  final int startTick;

  /// Exclusive; null for a loop that never ends.
  final int? endTick;
}

typedef TransportPosition = ({
  bool playing,
  double cyclePosition,
  int cycleIndex,
  int generation,
  int? sectionIndex,
});

/// The runtime transport of session playback: tempo map, generation and a
/// beat timeline of section runs. It is the [PlaybackStateSource] and the
/// [BeatEventSource] of the existing [PlaybackScheduler].
///
/// Hard changes (start, stop, tempo) start a new run: the scheduler cancels
/// older generations. A section boundary inside a run is a handover: the
/// next section gets its own generation once planning reaches the boundary,
/// without a cancel, so the previous section's queued hits still sound.
final class SequenceTransport implements PlaybackStateSource, BeatEventSource {
  SequenceTransport(this._clock);

  final AudioClock _clock;
  List<TransportSection> _sections = const [];
  bool _repeatAll = false;
  final List<_Segment> _segments = [];
  final Map<String, double> _gainOverrides = {};
  int _planSegment = 0;
  int? _plannedTo;

  /// (tick, generation): from that tick on, the heard generation.
  final List<(int, Generation)> _marks = [(0, 0)];
  Generation _generation = 0;
  Generation _runSince = 0;
  PlaybackTransport _transport = PlaybackTransport.stopped;
  TempoMap _tempoMap = TempoMap(
    bpm: 120,
    anchorBeat: 0,
    anchorTime: AudioTime(0),
  );

  Generation get generation => _generation;
  int get bpm => _tempoMap.bpm;
  bool get isPlaying => _transport == PlaybackTransport.playing;
  List<TransportSection> get sections => _sections;
  bool get isSequence => _sections.any((s) => s.repeats != null);

  /// Starts a new run at the first section's cycle start at [anchorTime].
  void start(
    List<TransportSection> sections, {
    required bool repeatAll,
    required int bpm,
    required AudioTime anchorTime,
  }) {
    if (sections.isEmpty) throw ArgumentError.value(sections, 'sections');
    _sections = List.unmodifiable(sections);
    _repeatAll = repeatAll;
    _gainOverrides.clear();
    _segments
      ..clear()
      ..add(_newSegment(0, 0, 0));
    _tempoMap = TempoMap(bpm: bpm, anchorBeat: 0, anchorTime: anchorTime);
    _transport = PlaybackTransport.playing;
    _hardChange(0);
  }

  /// A new generation that silences everything pending.
  void stop() {
    _transport = PlaybackTransport.stopped;
    _hardChange(0);
  }

  /// Keeps the phase: the beat reached at [at] continues at the new rate.
  void changeTempo(int bpm, AudioTime at) {
    if (!isPlaying) return;
    final beat = _tempoMap.beatAt(at);
    _tempoMap = TempoMap(bpm: bpm, anchorBeat: beat, anchorTime: at);
    _hardChange(beat);
  }

  /// Swaps a section's document for one with the same structure (a mix
  /// change). Takes effect for the next planned window; no new generation.
  void replaceSection(int index, TransportSection section) {
    final list = [..._sections];
    list[index] = section;
    _sections = List.unmodifiable(list);
    _gainOverrides.clear();
  }

  void setLayerGain(String layerId, double gain) =>
      _gainOverrides[layerId] = gain;

  void _hardChange(int fromTick) {
    _generation++;
    _runSince = _generation;
    _plannedTo = null;
    _planSegment = isPlaying ? _segmentIndexAt(fromTick) : 0;
    _marks
      ..clear()
      ..add((0, _generation));
  }

  @override
  PlaybackSnapshot get snapshot {
    _advance();
    return PlaybackSnapshot(
      transport: _transport,
      generation: _generation,
      tempoMap: _tempoMap,
      continuousSince: _runSince,
      planUntilBeat: isPlaying ? _segments[_planSegment].endTick : null,
    );
  }

  /// Hands planning over to the next section once it reached the boundary,
  /// or once the clock passed it (after a stall).
  void _advance() {
    if (!isPlaying) return;
    final reading = _clock.now();
    final earliestBeat = reading.state == EngineState.running
        ? _tempoMap.beatAt(reading.renderTime + reading.minLead)
        : -1;
    while (true) {
      final end = _segments[_planSegment].endTick;
      if (end == null) return;
      final reached = (_plannedTo ?? -1) >= end || earliestBeat >= end;
      if (!reached) return;
      final next = _segmentAfter(_planSegment);
      if (next == null) return;
      _planSegment = next.index;
      _generation++;
      _marks.add((next.startTick, _generation));
    }
  }

  _Segment? _segmentAfter(int index) {
    if (index + 1 < _segments.length) return _segments[index + 1];
    final previous = _segments[index];
    var sectionIndex = previous.sectionIndex + 1;
    if (sectionIndex >= _sections.length) {
      if (!_repeatAll) return null;
      sectionIndex = 0;
    }
    final segment = _newSegment(index + 1, sectionIndex, previous.endTick!);
    _segments.add(segment);
    return segment;
  }

  _Segment _newSegment(int index, int sectionIndex, int startTick) {
    final section = _sections[sectionIndex];
    final repeats = section.repeats;
    final int? end;
    if (repeats == null) {
      end = null;
    } else {
      final numerator = repeats * section.cycleTicksNumerator;
      final denominator = section.cycleTicksDenominator;
      end = startTick + (numerator + denominator - 1) ~/ denominator;
    }
    return _Segment(index, sectionIndex, startTick, end);
  }

  /// The segment containing [tick], or the last created one.
  int _segmentIndexAt(int tick) {
    for (var i = _segments.length - 1; i >= 0; i--) {
      if (_segments[i].startTick <= tick) return i;
    }
    return 0;
  }

  @override
  List<PlannedVoiceEvent> plan(int fromBeat, int toBeat) {
    final plannedTo = _plannedTo;
    if (plannedTo == null || toBeat > plannedTo) _plannedTo = toBeat;
    final planned = <PlannedVoiceEvent>[];
    // Newest first: a long "repeat all" run keeps many finished segments.
    for (final segment in _segments.reversed) {
      final end = segment.endTick;
      if (segment.startTick >= toBeat) continue;
      if (end != null && end <= fromBeat) break;
      final section = _sections[segment.sectionIndex];
      final localFrom = (fromBeat - segment.startTick).clamp(0, 1 << 62);
      final localTo =
          (end == null || end > toBeat ? toBeat : end) - segment.startTick;
      if (localTo <= localFrom) continue;
      for (final event in section.planner.plan(localFrom, localTo)) {
        final sound = section.soundIds[event.layerId];
        if (sound == null) continue; // missing instrument: silent layer
        final layerGain =
            _gainOverrides[event.layerId] ?? event.layerGain.toDouble();
        final gain =
            (event.velocity *
                    layerGain *
                    event.masterGain *
                    (event.accent ? 1 : unaccentedGain) *
                    mixHeadroom)
                .clamp(0, 1)
                .toDouble();
        planned.add(
          PlannedVoiceEvent(
            beat: segment.startTick + event.beat,
            // Unique across section runs; planner ids repeat per run.
            eventId: segment.index * 0x100000000 + event.eventId,
            kind: PlannedVoiceKind.trigger,
            sound: sound,
            gain: gain,
            pan: event.pan.toDouble(),
          ),
        );
      }
    }
    planned.sort((a, b) => a.beat.compareTo(b.beat));
    return planned;
  }

  /// The heard position from [reading]: the presentation time when the
  /// engine reports one, otherwise render time minus the fallback latency.
  TransportPosition positionAt(AudioClockReading reading) {
    if (!isPlaying) {
      return (
        playing: false,
        cyclePosition: 0.0,
        cycleIndex: 0,
        generation: _generation,
        sectionIndex: null,
      );
    }
    final tick = _heardTick(reading);
    // The section layout is fixed, so a read may run ahead of planning.
    var index = _segmentIndexAt(tick);
    while (true) {
      final end = _segments[index].endTick;
      if (end == null || tick < end) break;
      final next = _segmentAfter(index);
      if (next == null) break;
      index = next.index;
    }
    final segment = _segments[index];
    final section = _sections[segment.sectionIndex];
    var local = tick - segment.startTick;
    final end = segment.endTick;
    if (end != null && tick >= end) local = end - 1 - segment.startTick;
    if (local < 0) local = 0;
    final scaled = local * section.cycleTicksDenominator;
    final cycle = section.cycleTicksNumerator;
    // Planning hands over one generation per section run, so a section not
    // reached by planning yet gets the generation it is about to receive.
    var generation = _generation + (index - _planSegment);
    if (index <= _planSegment) {
      generation = _marks.first.$2;
      for (final (markTick, markGeneration) in _marks.reversed) {
        if (markTick <= tick) {
          generation = markGeneration;
          break;
        }
      }
    }
    return (
      playing: true,
      cyclePosition: (scaled % cycle) / cycle,
      cycleIndex: scaled ~/ cycle,
      generation: generation,
      sectionIndex: section.originalIndex,
    );
  }

  /// True once a sequence without "repeat all" has been heard to its end.
  bool finishedAt(AudioClockReading reading) {
    if (!isPlaying || _repeatAll) return false;
    final last = _segments.last;
    final end = last.endTick;
    if (end == null || last.sectionIndex != _sections.length - 1) return false;
    return _heardTick(reading) >= end;
  }

  int _heardTick(AudioClockReading reading) {
    final heard =
        reading.outputTime?.microseconds ??
        reading.renderTime.microseconds -
            reading.fallbackOutputLatency.inMicroseconds;
    return _tempoMap.beatAt(AudioTime(heard < 0 ? 0 : heard));
  }
}
