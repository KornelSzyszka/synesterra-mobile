import 'dart:typed_data';

import 'package:synesterra/data/audio/playback_engine.dart';
import 'package:synesterra/data/repositories/impl/engine_playback_repository.dart';
import 'package:synesterra/data/repositories/impl/in_memory_instrument_library_repository.dart';
import 'package:synesterra_core/synesterra_core.dart';

/// Audio clock under test control. Fallback latency is zero by default, so
/// the heard position equals the render position.
final class FakeClock implements AudioClock {
  int microseconds = 0;
  EngineState state = EngineState.stopped;
  Duration minLead = const Duration(milliseconds: 10);
  Duration fallbackOutputLatency = Duration.zero;

  @override
  AudioClockReading now() => AudioClockReading(
    renderTime: AudioTime(microseconds),
    outputTime: null,
    fallbackOutputLatency: fallbackOutputLatency,
    minLead: minLead,
    state: state,
  );
}

typedef SinkEvent = ({int generation, Trigger event});

/// Keeps what was queued, drops older generations on cancel like the real
/// sink, and "sounds" an event once the clock renders past it.
final class FakeSink implements VoiceSink {
  FakeSink(this.log);

  final List<String> log;
  int cutoff = -1;
  final pending = <SinkEvent>[];
  final sounded = <SinkEvent>[];
  final scheduled = <SinkEvent>[];

  @override
  void cancelFrom(Generation generation) {
    if (generation <= cutoff) return;
    cutoff = generation;
    log.add('cancel:$generation');
    pending.removeWhere((e) => e.generation < generation);
  }

  @override
  void schedule(Generation generation, List<VoiceEvent> events) {
    if (generation < cutoff) return;
    log.add('schedule:$generation');
    for (final event in events) {
      final item = (generation: generation, event: event as Trigger);
      scheduled.add(item);
      pending.add(item);
    }
  }

  void renderThrough(int microseconds) {
    final due = pending
        .where((e) => e.event.at.microseconds <= microseconds)
        .toList();
    pending.removeWhere(due.contains);
    sounded.addAll(due);
  }
}

final class FakeEngine implements PlaybackEngine {
  FakeEngine() {
    sink = FakeSink(log);
  }

  final log = <String>[];
  @override
  final FakeClock clock = FakeClock();
  @override
  late final FakeSink sink;
  final buffers = <String>{};
  final voiceLimits = <int>[];
  bool refuseVoiceLimit = false;
  int maintained = 0;

  @override
  Future<void> start() async {
    clock.state = EngineState.running;
    log.add('start');
  }

  @override
  Future<void> stop() async {
    clock.state = EngineState.stopped;
    log.add('stop');
  }

  @override
  bool hasBuffer(String soundId) => buffers.contains(soundId);

  @override
  Future<void> loadBuffer(
    String soundId,
    Float32List samples,
    int sampleRate,
  ) async {
    buffers.add(soundId);
    log.add('load:$soundId');
  }

  @override
  Future<void> unloadBuffer(String soundId) async {
    buffers.remove(soundId);
    log.add('unload:$soundId');
  }

  @override
  int setVoiceLimit(int count) {
    voiceLimits.add(count);
    if (refuseVoiceLimit) throw StateError('voice limit refused');
    return count;
  }

  @override
  Future<void> maintain() async => maintained++;

  @override
  Future<void> dispose() async => log.add('dispose');
}

/// The recipe arrives without its name or id; decay identifies it in tests.
typedef RenderCall = ({int decayMs, double hz});

/// A repository on fakes, plus a clock driver that wakes the scheduler every
/// 25 ms of audio time, as the real timer would.
final class Harness {
  Harness({List<Instrument> library = const []}) {
    repository = EnginePlaybackRepository(
      engine: engine,
      instruments: InMemoryInstrumentLibraryRepository(library),
      render: (instrument, hz) async {
        renders.add((decayMs: instrument.decayMs, hz: hz));
        return Float32List(1);
      },
    );
  }

  final engine = FakeEngine();
  final renders = <RenderCall>[];
  late final EnginePlaybackRepository repository;

  FakeClock get clock => engine.clock;
  FakeSink get sink => engine.sink;

  void runTo(int microseconds) {
    while (clock.microseconds < microseconds) {
      final next = clock.microseconds + 25000;
      clock.microseconds = next < microseconds ? next : microseconds;
      repository.pump();
      sink.renderThrough(clock.microseconds);
    }
  }

  /// Sounded start times in microseconds for one sound id.
  List<int> times(String soundId) => [
    for (final e in sink.sounded)
      if (e.event.sound == soundId) e.event.at.microseconds,
  ];
}

/// 120 BPM: one tick is 500000 / 960 microseconds; rounded like TempoMap.
int at(int anchorMicroseconds, int tick) =>
    anchorMicroseconds + (tick * 60000000 + 57600) ~/ (120 * 960);

typedef LayerSpec = ({String id, String instrumentId, int pitch, int steps});

SessionDocument loopDocument(
  List<LayerSpec> layers, {
  int cycleBeats = 4,
  num bpm = 120,
  double gain = 1,
  bool accent = false,
}) {
  List<RhythmLayer> build() => [
    for (final layer in layers)
      RhythmLayer(
        id: layer.id,
        instrumentId: layer.instrumentId,
        pitch: layer.pitch,
        pattern: Pattern(
          durationBeats: Rational(cycleBeats, 1),
          steps: [
            for (var i = 0; i < layer.steps; i++)
              PatternStep(
                enabled: true,
                velocity: 1,
                accent: accent,
                probability: 1,
              ),
          ],
        ),
        phaseSteps: 0,
        swing: Swing(grid: 'off', amount: 0),
        mix: LayerMix(gain: gain, pan: 0, muted: false, solo: false),
      ),
  ];
  Scene scene(String id) => Scene(
    id: id,
    layers: build(),
    masterGain: 1,
    drone: Drone(
      enabled: false,
      root: 0,
      octave: 3,
      mode: 'major',
      chord: 'root',
      gain: 0.5,
      filterHz: 1000,
      spread: 0,
    ),
  );
  return SessionDocument(
    title: 'test',
    transport: SessionTransport(
      bpm: bpm,
      practiceCycleBeats: Rational(cycleBeats, 1),
    ),
    referenceClick: ReferenceClick(0),
    randomSeed: 1,
    scenes: [scene('A'), scene('B')],
    defaultSceneId: 'A',
    presentation: Presentation('circle'),
  );
}

/// 3 hits against 2 in a four-beat cycle, on two different buffers.
SessionDocument threeTwo({num bpm = 120, double gain = 1}) => loopDocument(
  [
    (id: 'three', instrumentId: 'factory-wood', pitch: 69, steps: 3),
    (id: 'two', instrumentId: 'factory-sine', pitch: 57, steps: 2),
  ],
  bpm: bpm,
  gain: gain,
);
