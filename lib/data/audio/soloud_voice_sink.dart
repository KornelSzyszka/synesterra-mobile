import 'dart:async';
import 'dart:typed_data';

import 'package:synesterra_core/synesterra_core.dart';

import 'soloud_audio_clock.dart';

/// Thin boundary around the plugin so scheduling and retirement can be tested
/// without a native engine. Sources are supported-file bytes, not raw PCM.
abstract interface class SoloudVoiceEngine {
  Future<Object> loadWav(String id, Uint8List wav);
  Object playScheduled(
    Object source,
    Duration at, {
    required double gain,
    required double pan,
    bool looping,
  });
  bool isValid(Object handle);
  Future<void> stop(Object handle);
  void stopScheduled(Object handle, Duration at);
  void retune(Object handle, {required double gain, required double pan});
  Future<void> disposeSource(Object source);
  void setMaxVoices(int count);
  int get maxVoices;
  int get activeVoices;
  int get totalVoices;
}

/// Bound includes voices still ringing from earlier windows and the next
/// horizon, plus drone and audition. Keep below the plugin's 1023 edge.
int concurrentVoiceLimit({
  required int layers,
  required int bpm,
  required double hitsPerQuarterPerLayer,
  required Duration maxRing,
  Duration horizon = const Duration(milliseconds: 200),
  int droneVoices = 1,
  int auditionVoices = 1,
}) {
  if (layers < 1 ||
      bpm < 1 ||
      hitsPerQuarterPerLayer <= 0 ||
      maxRing.isNegative) {
    throw ArgumentError('invalid voice-capacity inputs');
  }
  final seconds = (maxRing + horizon).inMicroseconds / 1000000;
  final hits = (layers * hitsPerQuarterPerLayer * bpm / 60 * seconds).ceil();
  final bound = hits + droneVoices + auditionVoices;
  if (bound >= 1023) {
    throw StateError(
      'session needs $bound voices; the reliable SoLoud limit is below 1023',
    );
  }
  return bound < 17 ? 17 : bound;
}

final class _LoadedSource {
  _LoadedSource(this.id, this.source);
  final String id;
  final Object source;
  final Set<Object> handles = {};
  bool retired = false;
}

final class _ScheduledHandle {
  _ScheduledHandle(
    this.handle,
    this.source,
    this.generation,
    this.at,
    this.sustained,
  );
  final Object handle;
  final _LoadedSource source;
  Generation generation;
  final AudioTime at;
  final bool sustained;
}

/// Records what Dart sent to the engine. It cannot observe the actual DAC
/// onset, xrun count, or output-route latency; the phone protocol measures those.
final class SoloudVoiceSink implements VoiceSink {
  SoloudVoiceSink(
    this._engine,
    this._clock, {
    this.onLog,
    this._isSourceLoaded,
    this.stopSoundingOnCancel = false,
  });

  /// When true, [cancelFrom] also stops older voices that already started.
  /// Session playback uses it: its only cancels are hard changes (stop,
  /// structure, tempo); a section hand-over never cancels. The spike keeps
  /// ADR 0002's "sounding one-shots finish their envelope".
  final bool stopSoundingOnCancel;

  final SoloudVoiceEngine _engine;
  final SoloudAudioClock _clock;
  final void Function(Map<String, Object?>)? onLog;
  final bool Function(Object source)? _isSourceLoaded;
  final Map<String, _LoadedSource> _current = {};
  final List<_LoadedSource> _retired = [];
  final List<_ScheduledHandle> _handles = [];
  final Map<String, _ScheduledHandle> _sustained = {};
  bool _collecting = false;
  Generation _cutoff = 0;
  int rejected = 0;
  int late = 0;

  int get activeVoices => _engine.activeVoices;
  int get totalVoices => _engine.totalVoices;
  int get maxVoices => _engine.maxVoices;
  int get loadedBuffers => _current.length + _retired.length;
  int get retiredBuffers => _retired.length;

  void setVoiceLimit(int count) {
    if (count < 1 || count >= 1023) {
      throw ArgumentError.value(count, 'count', 'must be 1..1022');
    }
    _engine.setMaxVoices(count);
    final actual = _engine.maxVoices;
    onLog?.call({'type': 'voice_limit', 'requested': count, 'actual': actual});
    if (actual != count) {
      throw StateError('SoLoud voice limit is $actual, requested $count');
    }
  }

  Future<void> loadWav(String id, Uint8List wav) async {
    if (wav.length < 44 || String.fromCharCodes(wav.take(4)) != 'RIFF') {
      throw ArgumentError.value(id, 'id', 'loadWav needs WAV file bytes');
    }
    final source = await _engine.loadWav(id, wav);
    final previous = _current[id];
    _current[id] = _LoadedSource(id, source);
    onLog?.call({'type': 'load_mem_wav', 'sound': id, 'bytes': wav.length});
    if (previous != null) {
      previous.retired = true;
      _retired.add(previous);
      await collectRetired();
    }
  }

  bool hasSound(String id) => _current.containsKey(id);

  /// Stops using [id] for new events. Its source is disposed once its last
  /// voice has finished, like a replaced buffer.
  Future<void> retire(String id) async {
    final source = _current.remove(id);
    if (source == null) return;
    source.retired = true;
    _retired.add(source);
    await collectRetired();
  }

  /// True when the engine no longer knows a source this sink loaded, which
  /// happens when another owner deinitialized the shared engine.
  bool get lostSources {
    final loaded = _isSourceLoaded;
    if (loaded == null) return false;
    return [..._current.values, ..._retired].any((s) => !loaded(s.source));
  }

  /// Drops every source and handle without calling the engine. Only for an
  /// engine that was deinitialized: its sources and voices no longer exist.
  void forgetEngineState() {
    _current.clear();
    _retired.clear();
    _handles.clear();
    _sustained.clear();
    onLog?.call({'type': 'engine_state_forgotten'});
  }

  @override
  void schedule(Generation generation, List<VoiceEvent> events) {
    if (generation < _cutoff) return;
    final activeBefore = _engine.activeVoices;
    final totalBefore = _engine.totalVoices;
    var enqueued = 0;
    for (final event in events) {
      final snapshot = _clock.snapshot();
      final reading = snapshot.reading;
      final engineAt = snapshot.engineTimeOf(event.at);
      if (event.at.compareTo(reading.renderTime + reading.minLead) < 0 ||
          engineAt.inMicroseconds <= snapshot.engineUs) {
        late++;
        onLog?.call({
          'type': 'late',
          'eventId': event.eventId,
          'generation': generation,
        });
        continue;
      }
      if (event is SustainOff) {
        final old = _sustained.remove(event.key);
        if (old != null) {
          _engine.stopScheduled(old.handle, engineAt);
          onLog?.call({
            'type': 'sustain_off',
            'key': event.key,
            'atUs': event.at.microseconds,
          });
        }
        continue;
      }
      final sound = event is Trigger ? event.sound : (event as SustainOn).sound;
      final source = _current[sound];
      if (source == null) {
        rejected++;
        onLog?.call({
          'type': 'missing_source',
          'eventId': event.eventId,
          'sound': sound,
        });
        continue;
      }
      if (event is SustainOn) {
        final old = _sustained[event.key];
        if (old != null &&
            _engine.isValid(old.handle) &&
            identical(old.source, source) &&
            old.at.compareTo(reading.renderTime) <= 0) {
          old.generation = generation; // adopt without a drone retrigger
          _engine.retune(old.handle, gain: event.gain, pan: event.pan);
          onLog?.call({
            'type': 'adopt',
            'key': event.key,
            'generation': generation,
          });
          continue;
        }
        if (old != null) unawaited(_stop(old));
      }
      try {
        final handle = _engine.playScheduled(
          source.source,
          engineAt,
          gain: event is Trigger ? event.gain : (event as SustainOn).gain,
          pan: event is Trigger ? event.pan : (event as SustainOn).pan,
          looping: event is SustainOn,
        );
        if (!_engine.isValid(handle)) {
          rejected++;
          onLog?.call({'type': 'voice_rejected', 'eventId': event.eventId});
          continue;
        }
        final tracked = _ScheduledHandle(
          handle,
          source,
          generation,
          event.at,
          event is SustainOn,
        );
        source.handles.add(handle);
        _handles.add(tracked);
        enqueued++;
        if (event is SustainOn) _sustained[event.key] = tracked;
        onLog?.call({
          'type': 'enqueue',
          'eventId': event.eventId,
          'generation': generation,
          'sound': sound,
          'plannedUs': event.at.microseconds,
          'engineUs': engineAt.inMicroseconds,
          'clockOffsetUs': snapshot.offsetUs,
          'engineNowUs': snapshot.engineUs,
          'enqueuedUs': reading.renderTime.microseconds,
          'handle': handle.toString(),
        });
      } catch (error) {
        rejected++;
        onLog?.call({
          'type': 'voice_error',
          'eventId': event.eventId,
          'error': '$error',
        });
      }
    }
    onLog?.call({
      'type': 'voice_counts',
      'generation': generation,
      'planned': events.length,
      'enqueued': enqueued,
      'activeBefore': activeBefore,
      'activeAfter': _engine.activeVoices,
      'totalBefore': totalBefore,
      'totalAfter': _engine.totalVoices,
      'limit': _engine.maxVoices,
    });
  }

  @override
  void cancelFrom(Generation generation) {
    if (generation <= _cutoff) return;
    _cutoff = generation;
    final render = _clock.now().renderTime;
    for (final tracked in _handles.toList()) {
      if (tracked.generation >= generation) continue;
      // Already sounding one-shots may finish their envelope. Pending old
      // starts and old drones are silenced at the software cutoff.
      if (stopSoundingOnCancel || tracked.at.compareTo(render) > 0) {
        unawaited(_stop(tracked));
      }
    }
    onLog?.call({
      'type': 'cancel',
      'generation': generation,
      'renderUs': render.microseconds,
    });
  }

  Future<void> releaseOrphanedSustains() async {
    for (final entry in _sustained.entries.toList()) {
      if (entry.value.generation < _cutoff) {
        _sustained.remove(entry.key);
        await _stop(entry.value);
      }
    }
  }

  Future<void> _stop(_ScheduledHandle tracked) async {
    try {
      await _engine.stop(tracked.handle);
    } catch (error) {
      onLog?.call({
        'type': 'stop_error',
        'handle': tracked.handle.toString(),
        'error': '$error',
      });
      return;
    }
    tracked.source.handles.remove(tracked.handle);
    _handles.remove(tracked);
  }

  Future<void> collectRetired() async {
    if (_collecting) return;
    _collecting = true;
    try {
      _handles.removeWhere((tracked) {
        if (_engine.isValid(tracked.handle)) return false;
        tracked.source.handles.remove(tracked.handle);
        return true;
      });
      for (final source in _retired.toList()) {
        if (source.handles.isNotEmpty) continue;
        await _engine.disposeSource(source.source);
        _retired.remove(source);
        onLog?.call({'type': 'retired_disposed', 'sound': source.id});
      }
    } finally {
      _collecting = false;
    }
  }

  Future<void> dispose() async {
    for (final tracked in _handles.toList()) {
      await _stop(tracked);
    }
    for (final source in [..._current.values, ..._retired]) {
      await _engine.disposeSource(source.source);
    }
    _current.clear();
    _retired.clear();
    _sustained.clear();
  }
}
