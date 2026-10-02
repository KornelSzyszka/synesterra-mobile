import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:synesterra_core/synesterra_core.dart';

import '../../audio/audition_engine.dart';
import '../../audio/wav_encoder.dart';
import '../instrument_audition_repository.dart';

/// Renders [instrument] at [fundamentalHz] to mono samples.
typedef InstrumentRender = Future<Float32List> Function(
  Instrument instrument,
  double fundamentalHz,
);

/// Renders in a background isolate so a heavy recipe never blocks the UI.
Future<Float32List> renderInIsolate(Instrument instrument, double hz) =>
    Isolate.run(() => renderInstrument(instrument, fundamentalHz: hz));

/// What makes one buffer: the sound-defining part of the recipe at one pitch.
/// Name, id and tags do not change the sound, so they are not in the key.
typedef _BufferKey = ({Instrument sound, double hz});

/// Audition on top of any [AuditionEngine]: renders the recipe at each
/// requested pitch to PCM, loads each as a WAV, keeps recent buffers so an
/// unchanged recipe at an unchanged pitch is not rendered again, plays all
/// the notes of a chord together, and lets the newest request win.
class EngineInstrumentAuditionRepository
    implements InstrumentAuditionRepository {
  EngineInstrumentAuditionRepository(
    this._engine, {
    this._render = renderInIsolate,
    this.sampleRate = 48000,
    this.cacheSize = 24,
    this.volume = 0.8,
  });

  final AuditionEngine _engine;
  final InstrumentRender _render;
  final int sampleRate;
  final int cacheSize;

  /// Volume of a single note. A chord is scaled down by its note count so
  /// that several notes together do not clip.
  final double volume;

  final _available = ValueNotifier<bool>(true);
  // Insertion order is recency order: the first entry is the oldest.
  final _sources = <_BufferKey, Future<AuditionSource>>{};
  int _latest = 0;
  int _loaded = 0;
  List<AuditionVoice> _voices = const [];

  @override
  ValueListenable<bool> get available => _available;

  _BufferKey _key(Instrument instrument, double hz) => (
    sound: instrument.copyWith(
      id: 'audition',
      name: 'audition',
      tags: const [],
    ),
    hz: hz,
  );

  @override
  Future<bool> play(Instrument instrument, List<double> frequenciesHz) async {
    if (frequenciesHz.isEmpty) return false;
    final request = ++_latest;
    final started = <AuditionVoice>[];
    try {
      await _engine.start();
      final sources = await Future.wait([
        for (final hz in frequenciesHz) _source(instrument, hz),
      ]);
      if (request != _latest) return false;
      final previous = _voices;
      _voices = const [];
      for (final voice in previous) {
        await _engine.stop(voice);
      }
      // Another tap may have arrived while the old sound was stopping.
      if (request != _latest) return false;
      final each = volume / sources.length;
      for (final source in sources) {
        started.add(_engine.play(source, volume: each));
      }
      _voices = started;
      _available.value = true;
      return true;
    } catch (_) {
      for (final voice in started) {
        try {
          await _engine.stop(voice);
        } catch (_) {
          // Preserve the original play failure and try to stop every voice.
        }
      }
      if (request == _latest) _available.value = false;
      return false;
    }
  }

  Future<AuditionSource> _source(Instrument instrument, double hz) {
    final key = _key(instrument, hz);
    final cached = _sources.remove(key);
    if (cached != null) {
      _sources[key] = cached; // most recent again
      return cached;
    }
    final future = _load(instrument, hz);
    _sources[key] = future;
    // A failed load must not stay cached, or the next tap would fail too.
    future.then(
      (_) {},
      onError: (_) {
        _sources.remove(key);
      },
    );
    while (_sources.length > cacheSize) {
      final oldest = _sources.keys.first;
      final evicted = _sources.remove(oldest)!;
      evicted.then(_engine.unload, onError: (_) {});
    }
    return future;
  }

  Future<AuditionSource> _load(Instrument instrument, double hz) async {
    final samples = await _render(instrument, hz);
    final wav = encodeWav16(samples, sampleRate: sampleRate);
    return _engine.load('audition-${_loaded++}', wav);
  }

  @override
  Future<void> dispose() async {
    _latest++;
    final sources = _sources.values.toList();
    _sources.clear();
    final voices = _voices;
    _voices = const [];
    try {
      for (final voice in voices) {
        await _engine.stop(voice);
      }
      for (final source in sources) {
        await _engine.unload(await source);
      }
    } catch (_) {
      // Shutting down: a sound that cannot be released is not worth a crash.
    }
    await _engine.dispose();
    _available.dispose();
  }
}
