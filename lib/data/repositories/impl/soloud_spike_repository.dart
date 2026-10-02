import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:path_provider/path_provider.dart';
import 'package:synesterra_core/synesterra_core.dart';

import '../../audio/fixture_events.dart';
import '../../audio/playback_scheduler.dart';
import '../../audio/soloud_audio_clock.dart';
import '../../audio/soloud_plugin_binding.dart';
import '../../audio/soloud_voice_sink.dart';
import '../../audio/wav_encoder.dart';
import '../audio_spike_repository.dart';

final class _SpikePlaybackState implements PlaybackStateSource {
  _SpikePlaybackState(this.snapshot);
  @override
  PlaybackSnapshot snapshot;
}

/// The production adapter and the C0 fixture harness share one audio engine.
/// An explicit Start is the only operation that initializes SoLoud.
final class SoloudSpikeRepository implements AudioSpikeRepository {
  SoloudSpikeRepository();

  final _status = ValueNotifier(const AudioSpikeStatus());
  final List<Map<String, Object?>> _entries = [];
  final SoLoud _soloud = SoLoud.instance;
  SoloudAudioClock? _clock;
  SoloudVoiceSink? _sink;
  FixtureEvents? _fixture;
  _SpikePlaybackState? _state;
  PlaybackScheduler? _scheduler;
  Timer? _maintenance;
  int _generation = 0;
  int _pausedBeat = 0;
  int _droppedLogEntries = 0;
  bool _disposed = false;

  @override
  ValueListenable<AudioSpikeStatus> get status => _status;

  void _log(Map<String, Object?> entry) {
    if (_entries.length == 300000) {
      _droppedLogEntries++;
      return;
    }
    _entries.add({'utc': DateTime.now().toUtc().toIso8601String(), ...entry});
  }

  void _publish({bool? busy, String? error, String? exportPath}) {
    if (_disposed) return;
    final old = _status.value;
    _status.value = AudioSpikeStatus(
      transport: old.transport,
      scene: old.scene,
      bpm: old.bpm,
      layers: old.layers,
      drone: old.drone,
      busy: busy ?? old.busy,
      error: error,
      exportPath: exportPath ?? old.exportPath,
      activeVoices: _sink?.activeVoices ?? 0,
      totalVoices: _sink?.totalVoices ?? 0,
      maxVoices: _sink?.maxVoices ?? 0,
      loadedBuffers: _sink?.loadedBuffers ?? 0,
      rejected: _sink?.rejected ?? 0,
      late: _sink?.late ?? 0,
    );
  }

  void _setTransport(SpikeTransport transport) {
    final old = _status.value;
    _status.value = AudioSpikeStatus(
      transport: transport,
      scene: old.scene,
      bpm: old.bpm,
      layers: old.layers,
      drone: old.drone,
      busy: old.busy,
      activeVoices: _sink?.activeVoices ?? 0,
      totalVoices: _sink?.totalVoices ?? 0,
      maxVoices: _sink?.maxVoices ?? 0,
      loadedBuffers: _sink?.loadedBuffers ?? 0,
      rejected: _sink?.rejected ?? 0,
      late: _sink?.late ?? 0,
      exportPath: old.exportPath,
    );
  }

  Future<void> _ensureReady() async {
    if (_scheduler != null) return;
    await _soloud.init(lowLatency: true);
    final fixture = FixtureEvents(
      await rootBundle.loadString('test/data/audio/fixtures/polyrhythms.json'),
    );
    fixture.scene = _status.value.scene;
    fixture.layers = _status.value.layers;
    final clock = SoloudAudioClock(FlutterSoloudClockSource(_soloud));
    final sink = SoloudVoiceSink(
      FlutterSoloudVoiceEngine(_soloud),
      clock,
      onLog: _log,
    );
    _clock = clock;
    _sink = sink;
    _fixture = fixture;
    _setVoiceCapacity();
    // Buffer bytes are rendered in an isolate, wrapped in WAV and loaded
    // through loadMem. No raw PCM is passed to the file-loading API.
    await _loadInstrument('three', factoryInstruments[0], 440);
    await _loadInstrument('two', factoryInstruments[1], 330);
    await _loadInstrument('five', factoryInstruments[0], 520);
    await _loadInstrument('four', factoryInstruments[1], 390);
    await _loadInstrument('drone', factoryInstruments[2], 110);
    final state = _SpikePlaybackState(
      PlaybackSnapshot(
        transport: PlaybackTransport.stopped,
        generation: _generation,
        tempoMap: TempoMap(
          bpm: _status.value.bpm,
          anchorBeat: 0,
          anchorTime: AudioTime(0),
        ),
      ),
    );
    _state = state;
    _scheduler = PlaybackScheduler(
      clock: clock,
      sink: sink,
      state: state,
      events: fixture,
      onDiagnostics: _log,
    );
    _maintenance = Timer.periodic(const Duration(milliseconds: 250), (_) {
      unawaited(sink.collectRetired());
      _publish();
    });
    _log({
      'type': 'ready',
      'fixture': 'C0 polyrhythms.json',
      'outputTime': 'unavailable',
    });
  }

  Future<void> _loadInstrument(String id, Instrument recipe, double hz) async {
    final samples = await Isolate.run(
      () => renderInstrument(recipe, fundamentalHz: hz),
    );
    await _sink!.loadWav(id, encodeWav16(samples, sampleRate: 48000));
  }

  void _setVoiceCapacity() {
    final current = _status.value;
    final hitsPerQuarter = current.scene == '5:4' ? 2.25 : 1.25;
    _sink?.setVoiceLimit(
      concurrentVoiceLimit(
        layers: current.layers,
        bpm: current.bpm,
        hitsPerQuarterPerLayer: hitsPerQuarter,
        // Validated recipes may ring for attack (0.5 s) plus decay (5 s).
        maxRing: const Duration(seconds: 6),
        auditionVoices: 10,
      ),
    );
  }

  @override
  Future<void> start() async {
    if (_status.value.busy ||
        _status.value.transport == SpikeTransport.playing) {
      return;
    }
    _publish(busy: true);
    try {
      await _ensureReady();
      _soloud.setAudioDeviceIdleTimeout(null);
      final clock = _clock!;
      clock.start();
      final anchor = clock.now().renderTime + const Duration(milliseconds: 100);
      _generation++;
      _state!.snapshot = PlaybackSnapshot(
        transport: PlaybackTransport.playing,
        generation: _generation,
        tempoMap: TempoMap(
          bpm: _status.value.bpm,
          anchorBeat: _pausedBeat,
          anchorTime: anchor,
        ),
      );
      _setTransport(SpikeTransport.playing);
      _scheduler!.replan();
      if (_status.value.drone) {
        _sink!.schedule(_generation, [
          SustainOn(
            at: anchor,
            eventId: _generation * 1000000 + 999999,
            key: 'drone',
            sound: 'drone',
            gain: 0.12,
            pan: 0,
          ),
        ]);
      }
      _log({
        'type': 'start',
        'generation': _generation,
        'anchorBeat': _pausedBeat,
        'anchorUs': anchor.microseconds,
      });
    } catch (error) {
      _clock?.stop();
      _publish(busy: false, error: '$error');
      return;
    }
    _publish(busy: false);
  }

  @override
  Future<void> pause() async {
    if (_status.value.transport != SpikeTransport.playing) return;
    final reading = _clock!.now();
    _pausedBeat = _state!.snapshot.tempoMap.beatAt(reading.renderTime);
    _generation++;
    _state!.snapshot = PlaybackSnapshot(
      transport: PlaybackTransport.paused,
      generation: _generation,
      tempoMap: _state!.snapshot.tempoMap,
    );
    _scheduler!.replan();
    await _sink!.releaseOrphanedSustains();
    _soloud.setAudioDeviceIdleTimeout(Duration.zero);
    _clock!.stop();
    _setTransport(SpikeTransport.paused);
    _log({
      'type': 'pause',
      'generation': _generation,
      'renderUs': reading.renderTime.microseconds,
    });
  }

  @override
  Future<void> stop() async {
    if (_scheduler == null) return;
    _generation++;
    _pausedBeat = 0;
    _state!.snapshot = PlaybackSnapshot(
      transport: PlaybackTransport.stopped,
      generation: _generation,
      tempoMap: _state!.snapshot.tempoMap,
    );
    _scheduler!.replan();
    await _sink!.releaseOrphanedSustains();
    _soloud.setAudioDeviceIdleTimeout(Duration.zero);
    _clock!.stop();
    _setTransport(SpikeTransport.stopped);
    _log({'type': 'stop', 'generation': _generation});
  }

  void _change({int? bpm, String? scene, int? layers, bool? drone}) {
    final old = _status.value;
    final next = AudioSpikeStatus(
      transport: old.transport,
      bpm: bpm ?? old.bpm,
      scene: scene ?? old.scene,
      layers: layers ?? old.layers,
      drone: drone ?? old.drone,
      activeVoices: old.activeVoices,
      totalVoices: old.totalVoices,
      maxVoices: old.maxVoices,
      loadedBuffers: old.loadedBuffers,
      rejected: old.rejected,
      late: old.late,
    );
    _status.value = next;
    final fixture = _fixture;
    if (fixture == null) return;
    fixture.scene = next.scene;
    fixture.layers = next.layers;
    _setVoiceCapacity();
    final oldSnapshot = _state!.snapshot;
    final render = _clock!.now().renderTime;
    final beat = oldSnapshot.transport == PlaybackTransport.playing
        ? oldSnapshot.tempoMap.beatAt(render)
        : _pausedBeat;
    _pausedBeat = beat;
    _generation++;
    _state!.snapshot = PlaybackSnapshot(
      transport: oldSnapshot.transport,
      generation: _generation,
      tempoMap: TempoMap(
        bpm: next.bpm,
        anchorBeat: beat,
        anchorTime: render + const Duration(milliseconds: 100),
      ),
    );
    _scheduler!.replan();
    if (oldSnapshot.transport == PlaybackTransport.playing) {
      if (next.drone) {
        _sink!.schedule(_generation, [
          SustainOn(
            at: render + const Duration(milliseconds: 100),
            eventId: _generation * 1000000 + 999999,
            key: 'drone',
            sound: 'drone',
            gain: 0.12,
            pan: 0,
          ),
        ]);
      } else {
        unawaited(_sink!.releaseOrphanedSustains());
      }
    }
    _log({
      'type': 'change',
      'generation': _generation,
      'bpm': next.bpm,
      'scene': next.scene,
      'layers': next.layers,
      'drone': next.drone,
    });
  }

  @override
  void setTempo(int bpm) {
    if (bpm < 20 || bpm > 300) throw ArgumentError.value(bpm, 'bpm');
    _change(bpm: bpm);
  }

  @override
  void setScene(String scene) {
    if (scene != '3:2' && scene != '5:4') {
      throw ArgumentError.value(scene, 'scene');
    }
    _change(scene: scene);
  }

  @override
  void setLayers(int layers) {
    if (layers != 2 && layers != 4) throw ArgumentError.value(layers, 'layers');
    _change(layers: layers);
  }

  @override
  void setDrone(bool enabled) => _change(drone: enabled);

  @override
  void setStress(bool enabled) =>
      _log({'type': 'ui_stress', 'enabled': enabled});

  @override
  Future<void> runInstrumentCheck() async {
    if (_status.value.transport != SpikeTransport.playing ||
        _status.value.busy) {
      return;
    }
    _publish(busy: true);
    try {
      final recipe = factoryInstruments[2];
      for (var i = 0; i < 8; i++) {
        await _loadInstrument('ci-$i', recipe, 220 + i * 40);
      }
      final now = _clock!.now().renderTime;
      final voiceCount =
          (_soloud.getMaxActiveVoiceCount() - _sink!.activeVoices - 2).clamp(
            8,
            900,
          );
      final events = <VoiceEvent>[
        for (var i = 0; i < voiceCount; i++)
          Trigger(
            at: now + Duration(milliseconds: 100 + i % 20),
            eventId: 900000 + i,
            sound: 'ci-${i % 8}',
            gain: 0.4 / voiceCount,
            pan: 0,
          ),
      ];
      _sink!.schedule(_generation, events);
      _log({
        'type': 'ci_overlap',
        'bufferCount': 8,
        'scheduledOneshots': events.length,
        'maxVoices': _soloud.getMaxActiveVoiceCount(),
      });
      await Future<void>.delayed(const Duration(milliseconds: 180));
      final changeStarted = Stopwatch()..start();
      final replacement = recipe.copyWith(decayMs: 1200);
      final replacementSamples = await Isolate.run(
        () => renderInstrument(replacement, fundamentalHz: 220),
      );
      final before = _sink!.activeVoices;
      await _sink!.loadWav(
        'ci-0',
        encodeWav16(replacementSamples, sampleRate: 48000),
      );
      final after = _sink!.activeVoices;
      final auditionAt =
          _clock!.now().renderTime + const Duration(milliseconds: 60);
      _sink!.schedule(_generation, [
        Trigger(
          at: auditionAt,
          eventId: 999011,
          sound: 'ci-0',
          gain: 0.08,
          pan: 0,
        ),
      ]);
      _log({
        'type': 'ci_replace',
        'parameter': 'decayMs',
        'oldValue': recipe.decayMs,
        'newValue': replacement.decayMs,
        'oldVoicesBefore': before,
        'oldVoicesAfter': after,
        'retiredBuffers': _sink!.retiredBuffers,
        'auditionPlannedUs': auditionAt.microseconds,
        'changeToPlannedAuditionMs': changeStarted.elapsedMilliseconds + 60,
        'auditionDelay': 'not measured: requires physical recording',
      });
    } catch (error) {
      _log({'type': 'ci_error', 'error': '$error'});
      _publish(busy: false, error: '$error');
      return;
    }
    _publish(busy: false);
  }

  @override
  Future<String> exportDiagnostics() async {
    final directory = Platform.isAndroid
        ? await getExternalStorageDirectory()
        : await getApplicationDocumentsDirectory();
    if (directory == null) {
      throw StateError('diagnostics directory unavailable');
    }
    final file = File(
      '${directory.path}${Platform.pathSeparator}aud-043-${DateTime.now().toUtc().millisecondsSinceEpoch}.json',
    );
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'schema': 'AUD-043-spike-1',
        'evidence': 'adapter log; physical device measurement required',
        'fixture': _status.value.scene,
        'bpm': _status.value.bpm,
        'layers': _status.value.layers,
        'drone': _status.value.drone,
        'generation': _generation,
        'late': _sink?.late ?? 0,
        'rejected': _sink?.rejected ?? 0,
        'activeVoices': _sink?.activeVoices ?? 0,
        'totalVoices': _sink?.totalVoices ?? 0,
        'maxVoices': _sink?.maxVoices ?? 0,
        'droppedLogEntries': _droppedLogEntries,
        'entries': _entries,
      }),
    );
    _publish(exportPath: file.path);
    return file.path;
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    await stop();
    _maintenance?.cancel();
    _scheduler?.dispose();
    await _sink?.dispose();
    if (_soloud.isInitialized) await _soloud.deinitAsync();
    _disposed = true;
    _status.dispose();
  }
}
