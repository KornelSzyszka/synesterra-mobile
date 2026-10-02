import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:synesterra/data/audio/playback_scheduler.dart';
import 'package:synesterra_core/synesterra_core.dart';

void main() {
  test('generation cutoff is applied while paused or stopped', () {
    final clock = FakeClock();
    final sink = FakeSink();
    final state = FakeState();
    final scheduler = PlaybackScheduler(
      clock: clock,
      sink: sink,
      state: state,
      events: FakeEvents(),
    );
    addTearDown(scheduler.dispose);

    scheduler.replan();
    expect(sink.cutoffs, [0]);
    state.snapshot = PlaybackSnapshot(
      transport: PlaybackTransport.paused,
      generation: 1,
      tempoMap: state.snapshot.tempoMap,
    );
    scheduler.replan();
    expect(sink.cutoffs, [0, 1]);
    state.snapshot = PlaybackSnapshot(
      transport: PlaybackTransport.stopped,
      generation: 2,
      tempoMap: state.snapshot.tempoMap,
    );
    scheduler.replan();
    expect(sink.cutoffs, [0, 1, 2]);
  });

  test('fixture windows are half-open for both polyrhythms', () {
    final fixture = FixtureEvents();
    expect(fixture.plan(0, 768).map((event) => event.eventId), [11, 12]);
    expect(fixture.plan(768, 960).map((event) => event.eventId), [13]);
    expect(fixture.plan(960, 1536).map((event) => event.eventId), [14]);
    fixture.select('3:2');
    expect(fixture.plan(0, 1280).map((event) => event.eventId), [1, 2]);
    expect(fixture.plan(1280, 1920).map((event) => event.eventId), [3]);
  });

  test('future anchor does not start before the audio clock reaches it', () {
    final clock = FakeClock();
    final sink = FakeSink();
    final state = FakeState();
    state.snapshot = PlaybackSnapshot(
      transport: PlaybackTransport.playing,
      generation: 0,
      tempoMap: TempoMap(
        bpm: 120,
        anchorBeat: 0,
        anchorTime: AudioTime(300000),
      ),
    );
    final scheduler = PlaybackScheduler(
      clock: clock,
      sink: sink,
      state: state,
      events: FixedEvents([hit(0), hit(192)]),
    );
    addTearDown(scheduler.dispose);
    scheduler.replan();
    expect(sink.batches, isEmpty);
    clock.moveTo(120000);
    scheduler.replan();
    expect(sink.batches, isNotEmpty);
    expect(sink.batches.single.map((event) => event.at.microseconds), [300000]);
    clock.moveTo(220000);
    scheduler.replan();
    expect(sink.batches.last.single.at.microseconds, 400000);
  });

  test('large clock jump skips missed hits without a catch-up burst', () {
    final clock = FakeClock();
    final sink = FakeSink();
    final state = FakeState();
    final scheduler = PlaybackScheduler(
      clock: clock,
      sink: sink,
      state: state,
      events: FixedEvents([hit(96), hit(288), hit(960), hit(2016)]),
    );
    addTearDown(scheduler.dispose);
    scheduler.replan();
    expect(sink.eventIds, [96, 288]);
    clock.moveTo(1000000);
    scheduler.replan();
    expect(sink.eventIds, [96, 288, 2016]);
    expect(sink.batches.last.single.at.microseconds, 1050000);
  });

  test('a hit at the exclusive window end is scheduled once next time', () {
    final clock = FakeClock();
    final sink = FakeSink();
    final state = FakeState();
    final scheduler = PlaybackScheduler(
      clock: clock,
      sink: sink,
      state: state,
      events: FixedEvents([hit(384)]),
    );
    addTearDown(scheduler.dispose);
    scheduler.replan();
    expect(sink.eventIds, isEmpty);
    clock.moveTo(25000);
    scheduler.replan();
    scheduler.replan();
    expect(sink.eventIds, [384]);
  });

  test('generation change cancels before new events are scheduled', () {
    final clock = FakeClock();
    final sink = FakeSink();
    final state = FakeState();
    final scheduler = PlaybackScheduler(
      clock: clock,
      sink: sink,
      state: state,
      events: FixedEvents([hit(96), hit(288)]),
    );
    addTearDown(scheduler.dispose);
    scheduler.replan();
    state.snapshot = PlaybackSnapshot(
      transport: PlaybackTransport.playing,
      generation: 1,
      tempoMap: state.snapshot.tempoMap,
    );
    scheduler.replan();
    expect(sink.actions, ['cancel:0', 'schedule:0', 'cancel:1', 'schedule:1']);
    expect(sink.pending.map((event) => event.eventId), [96, 288]);
  });

  test('pause and stop purge pending hits and orphan a sounding drone', () {
    for (final transport in [
      PlaybackTransport.paused,
      PlaybackTransport.stopped,
    ]) {
      final clock = FakeClock();
      final sink = FakeSink();
      final state = FakeState();
      final scheduler = PlaybackScheduler(
        clock: clock,
        sink: sink,
        state: state,
        events: FixedEvents([
          PlannedVoiceEvent(
            beat: 96,
            eventId: 1,
            kind: PlannedVoiceKind.sustainOn,
            sound: 'drone',
            key: 'root',
          ),
          hit(288),
        ]),
      );
      addTearDown(scheduler.dispose);
      scheduler.replan();
      sink.renderThrough(100000);
      expect(sink.activeDroneKeys, {'root'});
      expect(sink.pending.map((event) => event.eventId), [288]);
      clock.moveTo(100000);
      state.snapshot = PlaybackSnapshot(
        transport: transport,
        generation: 1,
        tempoMap: state.snapshot.tempoMap,
      );
      scheduler.replan();
      expect(sink.pending, isEmpty);
      expect(sink.orphanedDroneKeys, {'root'});
      expect(sink.batches.length, 1);
    }
  });

  test('resume replans from current audio time, not the old window', () {
    final clock = FakeClock();
    final sink = FakeSink();
    final state = FakeState();
    final scheduler = PlaybackScheduler(
      clock: clock,
      sink: sink,
      state: state,
      events: FixedEvents([hit(96), hit(288), hit(768)]),
    );
    addTearDown(scheduler.dispose);
    scheduler.replan();
    state.snapshot = PlaybackSnapshot(
      transport: PlaybackTransport.paused,
      generation: 1,
      tempoMap: state.snapshot.tempoMap,
    );
    scheduler.replan();
    clock.moveTo(300000);
    state.snapshot = PlaybackSnapshot(
      transport: PlaybackTransport.playing,
      generation: 1,
      tempoMap: state.snapshot.tempoMap,
    );
    scheduler.replan();
    expect(sink.eventIds, [96, 288, 768]);
    expect(sink.pending.map((event) => event.eventId), [768]);
  });

  test('cutoff runs even when the engine is stopped', () {
    final clock = FakeClock();
    final sink = FakeSink();
    final state = FakeState();
    final scheduler = PlaybackScheduler(
      clock: clock,
      sink: sink,
      state: state,
      events: FakeEvents(),
    );
    addTearDown(scheduler.dispose);
    scheduler.replan();
    clock.reading = AudioClockReading(
      renderTime: AudioTime(0),
      outputTime: null,
      fallbackOutputLatency: Duration.zero,
      minLead: const Duration(milliseconds: 10),
      state: EngineState.stopped,
    );
    state.snapshot = PlaybackSnapshot(
      transport: PlaybackTransport.stopped,
      generation: 1,
      tempoMap: state.snapshot.tempoMap,
    );
    scheduler.replan();
    expect(sink.cutoffs, [0, 1]);
  });
}

PlannedVoiceEvent hit(int beat) => PlannedVoiceEvent(
  beat: beat,
  eventId: beat,
  kind: PlannedVoiceKind.trigger,
  sound: 'click',
);

final class FakeClock implements AudioClock {
  AudioClockReading reading = AudioClockReading(
    renderTime: AudioTime(0),
    outputTime: null,
    fallbackOutputLatency: Duration.zero,
    minLead: const Duration(milliseconds: 10),
    state: EngineState.running,
  );

  @override
  AudioClockReading now() => reading;

  void moveTo(int microseconds) {
    reading = AudioClockReading(
      renderTime: AudioTime(microseconds),
      outputTime: null,
      fallbackOutputLatency: Duration.zero,
      minLead: const Duration(milliseconds: 10),
      state: EngineState.running,
    );
  }
}

final class FakeSink implements VoiceSink {
  final cutoffs = <int>[];
  final batches = <List<VoiceEvent>>[];
  final actions = <String>[];
  final pending = <VoiceEvent>[];
  final activeDroneKeys = <String>{};
  final orphanedDroneKeys = <String>{};
  int cutoff = -1;

  List<int> get eventIds => [
    for (final batch in batches) ...batch.map((e) => e.eventId),
  ];

  @override
  void cancelFrom(Generation generation) {
    if (generation <= cutoff) return;
    cutoffs.add(generation);
    actions.add('cancel:$generation');
    cutoff = generation;
    pending.clear();
    orphanedDroneKeys.addAll(activeDroneKeys);
  }

  @override
  void schedule(Generation generation, List<VoiceEvent> events) {
    if (generation < cutoff) return;
    actions.add('schedule:$generation');
    batches.add(events);
    pending.addAll(events);
  }

  void renderThrough(int microseconds) {
    final due = pending
        .where((event) => event.at.microseconds <= microseconds)
        .toList();
    pending.removeWhere((event) => due.contains(event));
    for (final event in due) {
      if (event is SustainOn) activeDroneKeys.add(event.key);
      if (event is SustainOff) activeDroneKeys.remove(event.key);
    }
  }
}

final class FakeState implements PlaybackStateSource {
  @override
  PlaybackSnapshot snapshot = PlaybackSnapshot(
    transport: PlaybackTransport.playing,
    generation: 0,
    tempoMap: TempoMap(bpm: 120, anchorBeat: 0, anchorTime: AudioTime(0)),
  );
}

final class FakeEvents implements BeatEventSource {
  @override
  List<PlannedVoiceEvent> plan(int fromBeat, int toBeat) => [];
}

final class FixedEvents implements BeatEventSource {
  FixedEvents(this.all);

  final List<PlannedVoiceEvent> all;

  @override
  List<PlannedVoiceEvent> plan(int fromBeat, int toBeat) => [
    for (final event in all)
      if (fromBeat <= event.beat && event.beat < toBeat) event,
  ];
}

final class FixtureEvents implements BeatEventSource {
  FixtureEvents() {
    final raw = jsonDecode(
      File('test/data/audio/fixtures/polyrhythms.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    _fixtures = {
      for (final entry in raw.entries)
        entry.key: [
          for (final item in entry.value as List<dynamic>)
            PlannedVoiceEvent(
              beat: (item as Map<String, dynamic>)['beat'] as int,
              eventId: item['eventId'] as int,
              kind: PlannedVoiceKind.trigger,
              sound: item['sound'] as String,
            ),
        ],
    };
  }

  late final Map<String, List<PlannedVoiceEvent>> _fixtures;
  String selected = '5:4';

  void select(String rhythm) => selected = rhythm;

  @override
  List<PlannedVoiceEvent> plan(int fromBeat, int toBeat) => [
    for (final event in _fixtures[selected]!)
      if (fromBeat <= event.beat && event.beat < toBeat) event,
  ];
}
