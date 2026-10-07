import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:synesterra/data/audio/soloud_audio_clock.dart';
import 'package:synesterra/data/audio/soloud_playback_engine.dart';
import 'package:synesterra/data/audio/soloud_voice_sink.dart';
import 'package:synesterra/data/repositories/impl/engine_playback_repository.dart';
import 'package:synesterra/data/repositories/impl/in_memory_instrument_library_repository.dart';
import 'package:synesterra/data/repositories/playback_repository.dart';

import '../playback_fakes.dart' show threeTwo;

final class _ClockSource implements SoloudClockSource {
  Duration time = Duration.zero;
  @override
  Duration get engineTime => time;
}

final class _Lifecycle implements SoloudEngineLifecycle {
  @override
  bool isInitialized = false;
  int initializations = 0;
  bool? deviceOpen;

  @override
  Future<void> initialize() async {
    isInitialized = true;
    initializations++;
  }

  @override
  void keepDeviceOpen(bool open) => deviceOpen = open;
}

/// Plugin stand-in: records scheduled engine times; stop invalidates.
final class _VoiceEngine implements SoloudVoiceEngine {
  int _next = 1;
  int _max = 16;
  bool ignoreLimit = false;
  final loaded = <Object>{};
  final valid = <Object>{};
  final scheduled = <({Object handle, Duration at})>[];
  int loads = 0;

  @override
  Future<Object> loadWav(String id, Uint8List wav) async {
    loads++;
    final source = 'source-${_next++}';
    loaded.add(source);
    return source;
  }

  @override
  Object playScheduled(
    Object source,
    Duration at, {
    required double gain,
    required double pan,
    bool looping = false,
  }) {
    final handle = _next++;
    valid.add(handle);
    scheduled.add((handle: handle, at: at));
    return handle;
  }

  @override
  bool isValid(Object handle) => valid.contains(handle);

  @override
  Future<void> stop(Object handle) async => valid.remove(handle);

  @override
  void stopScheduled(Object handle, Duration at) => valid.remove(handle);

  @override
  void retune(Object handle, {required double gain, required double pan}) {}

  @override
  Future<void> disposeSource(Object source) async => loaded.remove(source);

  @override
  void setMaxVoices(int count) {
    if (!ignoreLimit) _max = count;
  }

  @override
  int get maxVoices => _max;

  @override
  int get activeVoices => valid.length < _max ? valid.length : _max;

  @override
  int get totalVoices => valid.length;
}

final class _Rig {
  _Rig() {
    engine = SoloudPlaybackEngine(
      clockSource: source,
      voiceEngine: voices,
      lifecycle: lifecycle,
      isSourceLoaded: voices.loaded.contains,
      hostElapsed: () => host,
    );
    repository = EnginePlaybackRepository(
      engine: engine,
      instruments: InMemoryInstrumentLibraryRepository(),
      render: (instrument, hz) async => Float32List(4),
    );
  }

  final source = _ClockSource();
  final voices = _VoiceEngine();
  final lifecycle = _Lifecycle();
  Duration host = Duration.zero;
  late final SoloudPlaybackEngine engine;
  late final EnginePlaybackRepository repository;

  /// The engine mixes, so engine time and host time advance together.
  void advance(Duration by) {
    source.time += by;
    host += by;
    repository.pump();
  }
}

void main() {
  test('events reach SoLoud at engineAt = event.at - offset', () async {
    final rig = _Rig();
    addTearDown(rig.repository.dispose);
    // Audition has kept the shared engine mixing for five seconds.
    rig.source.time = const Duration(seconds: 5);
    await rig.repository.play(threeTwo());
    expect(rig.lifecycle.initializations, 1);
    expect(rig.lifecycle.deviceOpen, isTrue);

    // Timeline 0 = engine 5 s; beat 0 at minLead (30 ms) + startPad (30 ms).
    expect(rig.voices.scheduled.map((e) => e.at), [
      const Duration(microseconds: 5060000),
      const Duration(microseconds: 5060000),
    ]);
    rig.advance(const Duration(milliseconds: 600));
    expect(
      rig.voices.scheduled.last.at,
      const Duration(microseconds: 5060000 + 666667),
    );

    final pending = rig.voices.scheduled.last.handle;
    expect(rig.voices.valid, contains(pending));
    await rig.repository.stop();
    await Future<void>.delayed(Duration.zero);
    expect(rig.voices.valid, isNot(contains(pending)));
    expect(rig.lifecycle.deviceOpen, isFalse);
  });

  test('buffers load again after another owner deinitialized SoLoud', () async {
    final rig = _Rig();
    addTearDown(rig.repository.dispose);
    await rig.repository.play(threeTwo());
    await rig.repository.stop();
    expect(rig.voices.loads, 2);

    // E.g. the spike screen was closed: deinit drops every source.
    rig.lifecycle.isInitialized = false;
    rig.voices.loaded.clear();
    await rig.repository.play(threeTwo());
    expect(rig.lifecycle.initializations, 2);
    expect(rig.voices.loads, 4);
    expect(rig.repository.status.value.state, PlaybackState.playing);
  });

  test('a voice cap the engine does not accept stops with an error', () async {
    final rig = _Rig();
    addTearDown(rig.repository.dispose);
    rig.voices.ignoreLimit = true;
    await rig.repository.play(threeTwo());
    final status = rig.repository.status.value;
    expect(status.stopReason, PlaybackStopReason.error);
    expect(status.error, contains('SoLoud voice limit is 16'));
    expect(rig.voices.scheduled, isEmpty);
  });
}
