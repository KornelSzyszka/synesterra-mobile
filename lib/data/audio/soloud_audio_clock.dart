import 'package:synesterra_core/synesterra_core.dart';

/// The engine clock can pause or reset when its output stream is restarted.
abstract interface class SoloudClockSource {
  Duration get engineTime;
}

/// One clock read and its inverse mapping to SoLoud's absolute engine time.
final class SoloudClockSnapshot {
  const SoloudClockSnapshot(this.reading, this.offsetUs, this.engineUs);

  final AudioClockReading reading;
  final int offsetUs;
  final int engineUs;

  Duration engineTimeOf(AudioTime at) =>
      Duration(microseconds: (at.microseconds - offsetUs).clamp(0, 1 << 62));
}

/// Rebases SoLoud's mix clock onto a process-long, monotonic audio timeline.
/// Call [start] after engine initialization and [stop] before transport pause,
/// stop, or a known stream restart. A backwards engine clock is also rebased.
final class SoloudAudioClock implements AudioClock {
  SoloudAudioClock(
    this._source, {
    Duration Function()? hostElapsed,
    this.minLead = const Duration(milliseconds: 30),
    this.fallbackOutputLatency = const Duration(milliseconds: 50),
  }) : _hostElapsed = hostElapsed ?? _newHostClock() {
    _lastHost = _hostElapsed();
  }

  final SoloudClockSource _source;
  final Duration Function() _hostElapsed;
  final Duration minLead;
  final Duration fallbackOutputLatency;
  Duration _lastHost = Duration.zero;
  Duration _lastEngineAdvanceHost = Duration.zero;
  int _timelineUs = 0;
  int _offsetUs = 0;
  int? _lastEngineUs;
  EngineState _state = EngineState.stopped;

  void start() {
    _advanceHost();
    _state = EngineState.running;
    final engineUs = _source.engineTime.inMicroseconds;
    _offsetUs = _timelineUs - engineUs;
    _lastEngineUs = engineUs;
    _lastEngineAdvanceHost = _lastHost;
  }

  void stop({bool interrupted = false}) {
    now();
    _state = interrupted ? EngineState.interrupted : EngineState.stopped;
    _lastEngineUs = null;
  }

  Duration _advanceHost() {
    final host = _hostElapsed();
    final delta = host - _lastHost;
    if (delta > Duration.zero && _state != EngineState.running) {
      _timelineUs += delta.inMicroseconds;
    }
    _lastHost = host;
    return delta;
  }

  @override
  AudioClockReading now() => snapshot().reading;

  SoloudClockSnapshot snapshot() {
    final hostDelta = _advanceHost();
    if (_state == EngineState.running) {
      final engineUs = _source.engineTime.inMicroseconds;
      if (_lastEngineUs != null && engineUs < _lastEngineUs!) {
        _offsetUs = _timelineUs - engineUs;
      }
      if (engineUs != _lastEngineUs) {
        final candidate = engineUs + _offsetUs;
        if (candidate > _timelineUs) {
          _timelineUs = candidate;
        } else {
          _offsetUs = _timelineUs - engineUs;
        }
        _lastEngineAdvanceHost = _lastHost;
      } else if (_lastHost - _lastEngineAdvanceHost >
          const Duration(milliseconds: 100)) {
        // SoLoud can stop mixing between sparse hits. Pending voices keep it
        // alive, but an empty horizon needs the host clock to reach the next.
        _timelineUs += hostDelta.inMicroseconds;
        _offsetUs = _timelineUs - engineUs;
      }
      _lastEngineUs = engineUs;
    }
    final reading = AudioClockReading(
      renderTime: AudioTime(_timelineUs),
      outputTime: null, // SoLoud playhead lacks route latency.
      fallbackOutputLatency: fallbackOutputLatency,
      minLead: minLead,
      state: _state,
    );
    return SoloudClockSnapshot(reading, _offsetUs, _lastEngineUs ?? 0);
  }

  /// Converts an absolute port timestamp back to SoLoud's mix-clock domain.
  Duration engineTimeOf(AudioTime time) =>
      Duration(microseconds: (time.microseconds - _offsetUs).clamp(0, 1 << 62));
}

Duration Function() _newHostClock() {
  final watch = Stopwatch()..start();
  return () => watch.elapsed;
}
