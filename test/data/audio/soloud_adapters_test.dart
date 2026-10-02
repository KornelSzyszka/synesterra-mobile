import 'dart:typed_data';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:synesterra/data/audio/fixture_events.dart';
import 'package:synesterra/data/audio/soloud_audio_clock.dart';
import 'package:synesterra/data/audio/soloud_voice_sink.dart';
import 'package:synesterra/data/audio/wav_encoder.dart';
import 'package:synesterra_core/synesterra_core.dart';

final class _ClockSource implements SoloudClockSource {
  Duration time = Duration.zero;
  @override
  Duration get engineTime => time;
}

final class _VoiceEngine implements SoloudVoiceEngine {
  int nextHandle = 1;
  int _maxVoices = 16;
  bool ignoreLimit = false;
  final valid = <int>{};
  final disposed = <Object>[];
  final scheduled = <({Object source, Duration at, int handle})>[];

  @override
  Future<Object> loadWav(String id, Uint8List wav) async => '$id/$nextHandle';

  @override
  Object playScheduled(
    Object source,
    Duration at, {
    required double gain,
    required double pan,
    bool looping = false,
  }) {
    final handle = nextHandle++;
    valid.add(handle);
    scheduled.add((source: source, at: at, handle: handle));
    return handle;
  }

  @override
  bool isValid(Object handle) => valid.contains(handle);

  @override
  Future<void> stop(Object handle) async {
    valid.remove(handle);
  }

  @override
  void stopScheduled(Object handle, Duration at) {
    valid.remove(handle);
  }

  @override
  void retune(Object handle, {required double gain, required double pan}) {}

  @override
  Future<void> disposeSource(Object source) async {
    disposed.add(source);
  }

  @override
  void setMaxVoices(int count) {
    if (!ignoreLimit) _maxVoices = count;
  }

  @override
  int get activeVoices => valid.length;

  @override
  int get totalVoices => valid.length;

  @override
  int get maxVoices => _maxVoices;
}

void main() {
  test('clock rebases across stop, start and stream reset', () {
    final source = _ClockSource();
    var host = Duration.zero;
    final clock = SoloudAudioClock(source, hostElapsed: () => host);
    clock.start();
    source.time = const Duration(milliseconds: 100);
    expect(clock.now().renderTime, AudioTime(100000));
    expect(clock.now().outputTime, isNull);

    clock.stop();
    host = const Duration(milliseconds: 350);
    expect(clock.now().renderTime, AudioTime(450000));
    source.time = Duration.zero;
    clock.start();
    expect(clock.now().renderTime, AudioTime(450000));
    source.time = const Duration(milliseconds: 25);
    expect(clock.now().renderTime, AudioTime(475000));

    source.time = Duration.zero; // route restarts the stream
    expect(clock.now().renderTime, AudioTime(475000));
    expect(
      clock.engineTimeOf(AudioTime(505000)),
      const Duration(milliseconds: 30),
    );
  });

  test('clock advances on host while an idle stream is not mixing', () {
    final source = _ClockSource();
    var host = Duration.zero;
    final clock = SoloudAudioClock(source, hostElapsed: () => host);
    clock.start();
    host = const Duration(milliseconds: 150);
    expect(clock.now().renderTime, AudioTime(150000));
    expect(
      clock.engineTimeOf(AudioTime(200000)),
      const Duration(milliseconds: 50),
    );
  });

  test('old source is retired until its last voice has finished', () async {
    final source = _ClockSource();
    final clock = SoloudAudioClock(source, hostElapsed: () => Duration.zero);
    final engine = _VoiceEngine();
    final sink = SoloudVoiceSink(engine, clock);
    clock.start();
    final wav = encodeWav16(
      Float32List.fromList([0, 0.5, 0]),
      sampleRate: 48000,
    );
    await sink.loadWav('bell', wav);
    sink.schedule(1, [
      Trigger(
        at: AudioTime(100000),
        eventId: 1,
        sound: 'bell',
        gain: 0.5,
        pan: 0,
      ),
    ]);
    final oldSource = engine.scheduled.single.source;
    await sink.loadWav('bell', wav);
    expect(sink.retiredBuffers, 1);
    expect(engine.disposed, isEmpty);
    sink.schedule(1, [
      Trigger(
        at: AudioTime(120000),
        eventId: 2,
        sound: 'bell',
        gain: 0.5,
        pan: 0,
      ),
    ]);
    expect(engine.scheduled.last.source, isNot(oldSource));
    await sink.collectRetired();
    expect(engine.disposed, isEmpty);
    engine.valid.remove(engine.scheduled.first.handle);
    await sink.collectRetired();
    expect(engine.disposed, [oldSource]);
    await sink.dispose();
  });

  test(
    'generation cancellation stops future handles and rejects stale batches',
    () async {
      final clock = SoloudAudioClock(
        _ClockSource(),
        hostElapsed: () => Duration.zero,
      );
      final engine = _VoiceEngine();
      final sink = SoloudVoiceSink(engine, clock);
      clock.start();
      final wav = encodeWav16(Float32List(4), sampleRate: 48000);
      await sink.loadWav('hit', wav);
      sink.schedule(1, [
        Trigger(
          at: AudioTime(100000),
          eventId: 1,
          sound: 'hit',
          gain: 1,
          pan: 0,
        ),
      ]);
      sink.cancelFrom(2);
      await Future<void>.delayed(Duration.zero);
      expect(engine.valid, isEmpty);
      sink.schedule(1, [
        Trigger(
          at: AudioTime(150000),
          eventId: 2,
          sound: 'hit',
          gain: 1,
          pan: 0,
        ),
      ]);
      expect(engine.scheduled.length, 1);
      await sink.dispose();
    },
  );

  test(
    'sink uses the clock snapshot offset after restart and drops late starts',
    () async {
      final source = _ClockSource();
      var host = Duration.zero;
      final clock = SoloudAudioClock(source, hostElapsed: () => host);
      final engine = _VoiceEngine();
      final entries = <Map<String, Object?>>[];
      final sink = SoloudVoiceSink(engine, clock, onLog: entries.add);
      final wav = encodeWav16(Float32List(4), sampleRate: 48000);
      await sink.loadWav('hit', wav);
      clock.start();
      source.time = const Duration(milliseconds: 100);
      expect(clock.now().renderTime, AudioTime(100000));
      clock.stop();
      host = const Duration(milliseconds: 400);
      expect(clock.now().renderTime, AudioTime(500000));
      source.time = Duration.zero;
      clock.start();
      sink.schedule(1, [
        Trigger(
          at: AudioTime(600000),
          eventId: 1,
          sound: 'hit',
          gain: 1,
          pan: 0,
        ),
      ]);
      expect(engine.scheduled.single.at, const Duration(milliseconds: 100));
      expect(
        entries.lastWhere((e) => e['type'] == 'enqueue')['clockOffsetUs'],
        500000,
      );

      sink.cancelFrom(2);
      await Future<void>.delayed(Duration.zero);
      source.time = const Duration(milliseconds: 50);
      expect(clock.now().renderTime, AudioTime(550000));
      source.time = Duration.zero; // route restart
      expect(clock.now().renderTime, AudioTime(550000));
      sink.schedule(2, [
        Trigger(
          at: AudioTime(560000),
          eventId: 2,
          sound: 'hit',
          gain: 1,
          pan: 0,
        ),
        Trigger(
          at: AudioTime(650000),
          eventId: 3,
          sound: 'hit',
          gain: 1,
          pan: 0,
        ),
      ]);
      expect(sink.late, 1);
      expect(engine.scheduled.length, 2);
      expect(engine.scheduled.last.at, const Duration(milliseconds: 100));
      expect(
        entries.lastWhere((e) => e['type'] == 'enqueue')['clockOffsetUs'],
        550000,
      );
      final counts = entries.lastWhere((e) => e['type'] == 'voice_counts');
      expect(counts['planned'], 2);
      expect(counts['enqueued'], 1);
      expect(counts['activeAfter'], 1);
      expect(counts['totalAfter'], 1);
      await sink.dispose();
    },
  );

  test('voice limit is checked against readback and never set at 1023', () {
    final engine = _VoiceEngine();
    final clock = SoloudAudioClock(
      _ClockSource(),
      hostElapsed: () => Duration.zero,
    );
    final sink = SoloudVoiceSink(engine, clock);
    sink.setVoiceLimit(200);
    expect(engine.maxVoices, 200);
    expect(() => sink.setVoiceLimit(1023), throwsArgumentError);
    engine.ignoreLimit = true;
    expect(() => sink.setVoiceLimit(201), throwsStateError);
  });

  test('capacity includes ringing voices from prior windows', () {
    expect(
      concurrentVoiceLimit(
        layers: 4,
        bpm: 300,
        hitsPerQuarterPerLayer: 2.25,
        maxRing: const Duration(seconds: 5),
        auditionVoices: 10,
      ),
      greaterThan(200),
    );
    expect(
      () => concurrentVoiceLimit(
        layers: 4,
        bpm: 300,
        hitsPerQuarterPerLayer: 20,
        maxRing: const Duration(seconds: 5),
      ),
      throwsStateError,
    );
  });

  test(
    'fixture repeats the committed C0 beats without boundary duplicates',
    () {
      final fixture = FixtureEvents(
        File('test/data/audio/fixtures/polyrhythms.json').readAsStringSync(),
      );
      expect(fixture.plan(0, 1280).map((e) => e.beat), [0, 0, 0, 0]);
      expect(fixture.plan(1280, 1920).map((e) => e.beat), [1280, 1280]);
      expect(fixture.plan(3840, 3841).map((e) => e.beat), [
        3840,
        3840,
        3840,
        3840,
      ]);
    },
  );
}
