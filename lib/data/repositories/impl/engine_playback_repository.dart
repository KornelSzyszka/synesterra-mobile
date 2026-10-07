import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:synesterra_core/synesterra_core.dart';

import '../../audio/playback_engine.dart';
import '../../audio/playback_scheduler.dart';
import '../../audio/sequence_transport.dart';
import '../../audio/soloud_voice_sink.dart' show concurrentVoiceLimit;
import '../instrument_library_repository.dart';
import '../playback_repository.dart';

/// Renders [instrument] at [fundamentalHz] to mono samples.
typedef PlaybackRender = Future<Float32List> Function(
  Instrument instrument,
  double fundamentalHz,
);

/// Renders off the UI isolate.
Future<Float32List> renderPlaybackBufferInIsolate(
  Instrument instrument,
  double hz,
) => Isolate.run(() => renderInstrument(instrument, fundamentalHz: hz));

/// `440 * 2^((pitch - 69) / 12)`.
double pitchToHz(int pitch) => 440 * math.pow(2, (pitch - 69) / 12).toDouble();

/// What makes one buffer: the sound-defining recipe at one frequency.
typedef _BufferKey = ({Instrument sound, double hz});

/// [PlaybackRepository] on a [PlaybackEngine] and the existing
/// [PlaybackScheduler]. Instruments resolve through the factory list and
/// [InstrumentLibraryRepository]; a missing one plays silence.
final class EnginePlaybackRepository implements PlaybackRepository {
  EnginePlaybackRepository({
    required PlaybackEngine engine,
    required this._instruments,
    this._render = renderPlaybackBufferInIsolate,
    this.sampleRate = 48000,
    this.cacheSize = 24,
    this.startPad = const Duration(milliseconds: 30),
    this.auditionVoices = 8,
  }) : _engine = engine,
       _transport = SequenceTransport(engine.clock);

  final PlaybackEngine _engine;
  final InstrumentLibraryRepository _instruments;
  final PlaybackRender _render;
  final SequenceTransport _transport;
  final int sampleRate;

  /// Loaded buffers kept for reuse beyond the playing program.
  final int cacheSize;

  /// Silence between Play and the first beat, after the clock's minLead
  /// (ADR 0002 `startPad`, a hypothesis).
  final Duration startPad;

  /// Voices reserved for instrument audition on the shared engine.
  final int auditionVoices;

  final _status = ValueNotifier(PlaybackStatus());
  late final _position = ValueNotifier(PlaybackPosition.stopped(0));
  // Insertion order is recency order: the first entry is the oldest.
  final _bufferIds = <_BufferKey, String>{};
  final _loading = <String, Future<void>>{};
  int _nextBuffer = 0;
  int _request = 0;
  int _wakes = 0;
  PlaybackScheduler? _scheduler;
  Timer? _ticker;
  _VoiceDemand? _demand;
  bool _disposed = false;

  @override
  ValueListenable<PlaybackStatus> get status => _status;

  @override
  ValueListenable<PlaybackPosition> get position => _position;

  @override
  PlaybackPosition readPosition() {
    final p = _transport.positionAt(_engine.clock.now());
    return PlaybackPosition(
      playing: p.playing,
      cyclePosition: p.cyclePosition,
      cycleIndex: p.cycleIndex,
      generation: p.generation,
      sectionIndex: p.sectionIndex,
    );
  }

  @override
  Future<void> play(SessionDocument document) async {
    _checkAlive();
    final current = _transport.sections;
    if (_transport.isPlaying &&
        !_transport.isSequence &&
        current.length == 1 &&
        _sameStructure(current.single.document, document)) {
      _request++; // a newer command supersedes a pending start
      final bpm = _bpmOf(document);
      if (!_sameMix(current.single.document, document)) {
        _transport.replaceSection(
          0,
          TransportSection(
            document: document,
            soundIds: current.single.soundIds,
          ),
        );
      }
      if (bpm != _transport.bpm) _changeTempo(bpm);
      return;
    }
    await _start(
      [(document: document, originalIndex: null, repeats: null)],
      (repeatAll: false),
    );
  }

  @override
  Future<void> playSequence(
    List<PlaybackSection> sections, {
    required bool repeatAll,
  }) async {
    _checkAlive();
    if (sections.isEmpty) {
      _request++;
      _halt();
      _publish(PlaybackStatus(stopReason: PlaybackStopReason.emptySequence));
      return;
    }
    await _start(
      [
        for (final section in sections)
          (
            document: section.document,
            originalIndex: section.originalIndex,
            repeats: section.repeats,
          ),
      ],
      (repeatAll: repeatAll),
    );
  }

  Future<void> _start(
    List<({SessionDocument document, int? originalIndex, int? repeats})>
    requested,
    ({bool repeatAll}) options,
  ) async {
    final request = ++_request;
    // The old structure must not keep sounding while buffers are prepared.
    _halt();
    final bpm = _bpmOf(requested.first.document);
    _publish(PlaybackStatus(state: PlaybackState.preparing, bpm: bpm));
    try {
      await _engine.start();
      if (request != _request) return;
      final missing = <String>{};
      var maxRing = Duration.zero;
      final sections = <TransportSection>[];
      for (final item in requested) {
        final soundIds = <String, String?>{};
        for (final layer in SessionProject(
          item.document,
          sceneId: 'A',
        ).layers) {
          final instrument = _resolve(layer.instrumentId);
          if (instrument == null) {
            missing.add(layer.instrumentId);
            soundIds[layer.id] = null;
            continue;
          }
          final ring = Duration(
            milliseconds: instrument.attackMs + instrument.decayMs,
          );
          if (ring > maxRing) maxRing = ring;
          soundIds[layer.id] = await _buffer(
            _key(instrument, pitchToHz(layer.pitch)),
          );
          if (request != _request) return;
        }
        sections.add(
          TransportSection(
            document: item.document,
            soundIds: soundIds,
            originalIndex: item.originalIndex,
            repeats: item.repeats,
          ),
        );
      }
      _demand = _VoiceDemand.of(sections, maxRing);
      final cap = _applyVoiceLimit(bpm);
      _ensureScheduler();
      final reading = _engine.clock.now();
      _transport.start(
        sections,
        repeatAll: options.repeatAll,
        bpm: bpm,
        anchorTime: reading.renderTime + reading.minLead + startPad,
      );
      _scheduler!.replan();
      _publish(
        PlaybackStatus(
          state: PlaybackState.playing,
          bpm: bpm,
          missingInstrumentIds: missing,
          voiceLimit: cap.limit,
          voiceLimitSaturated: cap.saturated,
        ),
      );
      _refresh();
      unawaited(_trimCache(sections));
    } catch (error) {
      if (request != _request) return;
      await _fail(error);
    }
  }

  Future<void> _fail(Object error) async {
    _request++;
    _halt();
    _publish(
      PlaybackStatus(stopReason: PlaybackStopReason.error, error: '$error'),
    );
    try {
      await _engine.stop();
    } catch (_) {
      // Already failing; the first error is the one to report.
    }
  }

  @override
  Future<void> stop() async {
    _checkAlive();
    _request++;
    _halt();
    _publish(PlaybackStatus());
    await _engine.stop();
  }

  /// New generation, cancel in the sink, reset the position.
  void _halt() {
    _transport.stop();
    _scheduler?.replan();
    _scheduler?.dispose();
    _scheduler = null;
    _ticker?.cancel();
    _ticker = null;
    _position.value = PlaybackPosition.stopped(_transport.generation);
  }

  @override
  void setTempo(int bpm) {
    _checkAlive();
    if (bpm < 20 || bpm > 300) throw ArgumentError.value(bpm, 'bpm');
    if (!_transport.isPlaying || bpm == _transport.bpm) return;
    _changeTempo(bpm);
  }

  void _changeTempo(int bpm) {
    final reading = _engine.clock.now();
    final ({int limit, bool saturated}) cap;
    try {
      cap = _applyVoiceLimit(bpm);
    } catch (error) {
      unawaited(_fail(error));
      return;
    }
    _transport.changeTempo(bpm, reading.renderTime + reading.minLead);
    _scheduler?.replan();
    final old = _status.value;
    _publish(
      PlaybackStatus(
        state: old.state,
        bpm: bpm,
        missingInstrumentIds: old.missingInstrumentIds,
        voiceLimit: cap.limit,
        voiceLimitSaturated: cap.saturated,
      ),
    );
    _refresh();
  }

  @override
  void setLayerGain(String layerId, double gain) {
    _checkAlive();
    if (!gain.isFinite || gain < 0 || gain > 1) {
      throw ArgumentError.value(gain, 'gain', 'must be in 0..1');
    }
    _transport.setLayerGain(layerId, gain);
  }

  ({int limit, bool saturated}) _applyVoiceLimit(int bpm) {
    final demand = _demand!;
    var saturated = false;
    int requested;
    try {
      requested = concurrentVoiceLimit(
        layers: demand.layers,
        bpm: bpm,
        hitsPerQuarterPerLayer: demand.hitsPerQuarter,
        maxRing: demand.maxRing,
        horizon: PlaybackScheduler.horizon,
        droneVoices: 0,
        auditionVoices: auditionVoices,
      );
    } on StateError {
      requested = 1022;
      saturated = true;
    }
    return (limit: _engine.setVoiceLimit(requested), saturated: saturated);
  }

  void _ensureScheduler() {
    _scheduler ??= PlaybackScheduler(
      clock: _engine.clock,
      sink: _engine.sink,
      state: _transport,
      events: _transport,
    );
    _ticker ??= Timer.periodic(
      const Duration(milliseconds: 25),
      (_) => _refresh(),
    );
  }

  /// Publishes the position and ends a finished sequence. A timer only wakes
  /// this; the position comes from the audio clock.
  void _refresh() {
    if (_disposed || !_transport.isPlaying) return;
    final reading = _engine.clock.now();
    if (_transport.finishedAt(reading)) {
      _request++;
      _halt();
      _publish(PlaybackStatus(stopReason: PlaybackStopReason.finished));
      unawaited(_engine.stop());
      return;
    }
    _position.value = readPosition();
    if (++_wakes % 40 == 0) unawaited(_engine.maintain());
  }

  @visibleForTesting
  void pump() {
    _scheduler?.replan();
    _refresh();
  }

  Instrument? _resolve(String id) {
    for (final instrument in factoryInstruments) {
      if (instrument.id == id) return instrument;
    }
    for (final instrument in _instruments.snapshot.value.instruments) {
      if (instrument.id == id) return instrument;
    }
    return null;
  }

  _BufferKey _key(Instrument instrument, double hz) => (
    sound: instrument.copyWith(id: 'playback', name: 'playback', tags: []),
    hz: hz,
  );

  Future<String> _buffer(_BufferKey key) async {
    final known = _bufferIds.remove(key);
    final id = known ?? 'playback-${_nextBuffer++}';
    _bufferIds[key] = id; // most recent again
    if (_engine.hasBuffer(id)) return id;
    final pending = _loading[id];
    if (pending != null) {
      await pending;
      return id;
    }
    final load = _render(
      key.sound,
      key.hz,
    ).then((samples) => _engine.loadBuffer(id, samples, sampleRate));
    _loading[id] = load;
    try {
      await load;
    } finally {
      _loading.remove(id);
    }
    return id;
  }

  /// Selects and retires synchronously, so a later start never picks up an
  /// id that is being unloaded.
  Future<void> _trimCache(List<TransportSection> playing) async {
    final inUse = {
      for (final section in playing) ...section.soundIds.values.nonNulls,
    };
    final unloads = <Future<void>>[];
    var excess = _bufferIds.length - cacheSize;
    for (final key in _bufferIds.keys.toList()) {
      if (excess <= 0) break;
      final id = _bufferIds[key]!;
      if (inUse.contains(id) || _loading.containsKey(id)) continue;
      _bufferIds.remove(key);
      excess--;
      unloads.add(_engine.unloadBuffer(id));
    }
    await Future.wait(unloads);
  }

  void _publish(PlaybackStatus status) {
    if (!_disposed) _status.value = status;
  }

  void _checkAlive() {
    if (_disposed) throw StateError('PlaybackRepository is disposed');
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _request++;
    _halt();
    _disposed = true;
    await _engine.dispose();
    _status.dispose();
    _position.dispose();
  }
}

/// Session bound for the voice cap: layers, densest layer and longest ring.
final class _VoiceDemand {
  _VoiceDemand(this.layers, this.hitsPerQuarter, this.maxRing);

  factory _VoiceDemand.of(List<TransportSection> sections, Duration maxRing) {
    var layers = 1;
    var density = 0.0;
    for (final section in sections) {
      final sceneLayers = section.project.layers;
      layers = math.max(layers, sceneLayers.length);
      for (final layer in sceneLayers) {
        final beats = layer.pattern.durationBeats.value;
        density = math.max(density, layer.pattern.steps.length / beats);
      }
    }
    // The renderer caps a buffer at six seconds.
    const longest = Duration(seconds: 6);
    return _VoiceDemand(
      layers,
      density > 0 ? density : 1,
      maxRing > longest ? longest : maxRing,
    );
  }

  final int layers;
  final double hitsPerQuarter;
  final Duration maxRing;
}

int _bpmOf(SessionDocument document) =>
    document.transport.bpm.round().clamp(20, 300);

/// Same scene A rhythm, instruments, pitches, cycle and seed.
bool _sameStructure(SessionDocument a, SessionDocument b) {
  if (a.transport.practiceCycleBeats != b.transport.practiceCycleBeats ||
      a.randomSeed != b.randomSeed) {
    return false;
  }
  final x = SessionProject(a, sceneId: 'A').layers;
  final y = SessionProject(b, sceneId: 'A').layers;
  if (x.length != y.length) return false;
  for (var i = 0; i < x.length; i++) {
    if (x[i].id != y[i].id ||
        x[i].instrumentId != y[i].instrumentId ||
        x[i].pitch != y[i].pitch ||
        x[i].pattern != y[i].pattern ||
        x[i].phaseSteps != y[i].phaseSteps ||
        x[i].swing != y[i].swing) {
      return false;
    }
  }
  return true;
}

bool _sameMix(SessionDocument a, SessionDocument b) {
  final x = SessionProject(a, sceneId: 'A');
  final y = SessionProject(b, sceneId: 'A');
  if (x.masterGain != y.masterGain) return false;
  for (var i = 0; i < x.layers.length; i++) {
    if (x.layers[i].mix != y.layers[i].mix) return false;
  }
  return true;
}
