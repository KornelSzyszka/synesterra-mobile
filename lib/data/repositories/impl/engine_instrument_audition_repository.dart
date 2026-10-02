import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:synesterra_core/synesterra_core.dart';

import '../../audio/audition_engine.dart';
import '../../audio/wav_encoder.dart';
import '../instrument_audition_repository.dart';

typedef InstrumentRender = Future<Float32List> Function(Instrument instrument);

/// Renders in a background isolate so a heavy recipe never blocks the UI.
Future<Float32List> renderInIsolate(Instrument instrument) =>
    Isolate.run(() => renderInstrument(instrument));

/// Audition on top of any [AuditionEngine]: renders the recipe to PCM, loads
/// it as a WAV, keeps recent sounds so an unchanged recipe is not rendered
/// again, and lets the newest request win.
class EngineInstrumentAuditionRepository
    implements InstrumentAuditionRepository {
  EngineInstrumentAuditionRepository(
    this._engine, {
    this._render = renderInIsolate,
    this.sampleRate = 48000,
    this.cacheSize = 16,
    this.volume = 0.8,
  });

  final AuditionEngine _engine;
  final InstrumentRender _render;
  final int sampleRate;
  final int cacheSize;

  /// Leaves headroom so a full-scale recipe does not clip.
  final double volume;

  final _available = ValueNotifier<bool>(true);
  // Insertion order is recency order: the first entry is the oldest.
  final _sources = <Instrument, Future<AuditionSource>>{};
  int _latest = 0;
  int _loaded = 0;
  AuditionVoice? _voice;

  @override
  ValueListenable<bool> get available => _available;

  /// Name and id do not change the sound, so they must not change the key.
  Instrument _key(Instrument instrument) =>
      instrument.copyWith(id: 'audition', name: 'audition');

  @override
  Future<bool> play(Instrument instrument) async {
    final request = ++_latest;
    try {
      await _engine.start();
      final source = await _source(instrument);
      if (request != _latest) return false;
      final previous = _voice;
      _voice = null;
      if (previous != null) await _engine.stop(previous);
      // Another tap may have arrived while the old sound was stopping.
      if (request != _latest) return false;
      _voice = _engine.play(source, volume: volume);
      _available.value = true;
      return true;
    } catch (_) {
      if (request == _latest) _available.value = false;
      return false;
    }
  }

  Future<AuditionSource> _source(Instrument instrument) {
    final key = _key(instrument);
    final cached = _sources.remove(key);
    if (cached != null) {
      _sources[key] = cached; // most recent again
      return cached;
    }
    final future = _load(instrument);
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

  Future<AuditionSource> _load(Instrument instrument) async {
    final samples = await _render(instrument);
    final wav = encodeWav16(samples, sampleRate: sampleRate);
    return _engine.load('audition-${_loaded++}', wav);
  }

  @override
  Future<void> dispose() async {
    _latest++;
    final sources = _sources.values.toList();
    _sources.clear();
    final voice = _voice;
    _voice = null;
    try {
      if (voice != null) await _engine.stop(voice);
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
