import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:synesterra_core/synesterra_core.dart';

import '../../data/repositories/loop.dart';
import '../../data/repositories/microphone_repository.dart';
import '../../data/repositories/playback_repository.dart';

enum TunerPhase {
  /// Not listening.
  idle,

  /// Waiting for the permission answer or for the microphone to open.
  starting,
  listening,

  /// The user refused the microphone.
  denied,

  /// The microphone could not be opened or stopped working.
  failed,
}

/// State of the Tuner: whether it listens, the note it hears and the
/// reference pitch. Samples come from the microphone repository; pitch maths
/// is the core's. Playback never runs while the tuner listens (the speaker
/// would be heard as the instrument): starting stops it, and the reference
/// tone stops listening first.
class TunerModel extends ChangeNotifier {
  TunerModel({
    required this.microphone,
    required this.playback,
    double referenceA4 = defaultReferenceA4,
  }) : _tracker = PitchTracker(
         detector: PitchDetector(
           sampleRate: microphone.sampleRate,
           // Two periods of the lowest note must fit in one frame.
           minFrequencyHz: 40,
           maxFrequencyHz: 2000,
         ),
         referenceA4: referenceA4,
       );

  final MicrophoneRepository microphone;
  final PlaybackRepository playback;
  final PitchTracker _tracker;

  /// Reference-tone pulse: A4 sine every 1.5 s. Layers are pitched in whole
  /// semitones, so the tone is 440 Hz only.
  static final SessionDocument toneDocument = simpleLoopDocument(
    title: 'Tuner tone',
    bpm: 80,
    cycleBeats: 2,
    layers: [
      for (var i = 0; i < 2; i++)
        const LoopLayerSpec(instrumentId: 'factory-sine', pitch: 69, hits: 1),
    ],
  );

  TunerPhase _phase = TunerPhase.idle;
  TunerNote? _note;
  bool _toneOn = false;
  bool _disposed = false;
  int _session = 0;
  StreamSubscription<Float32List>? _subscription;

  TunerPhase get phase => _phase;

  /// The smoothed note being played, or null when nothing clear is heard.
  TunerNote? get note => _note;

  double get referenceA4 => _tracker.referenceA4;

  bool get listening => _phase == TunerPhase.listening;

  /// True while the reference tone sounds.
  bool get toneOn => _toneOn;

  /// The tone is A4 = 440 Hz, so it is offered at that reference only.
  bool get toneAvailable => referenceA4 == defaultReferenceA4;

  /// Sets the reference pitch (400..480 Hz, whole Hz).
  void setReference(double hz) {
    final value = hz.roundToDouble().clamp(minReferenceA4, maxReferenceA4);
    if (value == referenceA4) return;
    _tracker.referenceA4 = value;
    _note = null;
    if (_toneOn && !toneAvailable) _stopTone();
    _notify();
  }

  /// Stops playback, asks for the microphone if needed and starts listening.
  Future<void> start() async {
    if (_phase == TunerPhase.starting || _phase == TunerPhase.listening) {
      return;
    }
    final session = ++_session;
    _toneOn = false;
    _phase = TunerPhase.starting;
    _note = null;
    _tracker.reset();
    _notify();
    await playback.stop();
    final access = await microphone.requestAccess();
    if (_disposed || session != _session) return;
    if (access == MicrophoneAccess.denied) {
      _phase = TunerPhase.denied;
      _notify();
      return;
    }
    _subscription = microphone.frames().listen(
      _onFrame,
      onError: (Object _) => _fail(session),
      onDone: () => _fail(session),
      cancelOnError: true,
    );
    _phase = TunerPhase.listening;
    _notify();
  }

  void _onFrame(Float32List frame) {
    final note = _tracker.process(frame);
    if (_note == null && note == null) return;
    _note = note;
    _notify();
  }

  void _fail(int session) {
    if (session != _session || _disposed) return;
    _subscription = null;
    _phase = TunerPhase.failed;
    _note = null;
    _notify();
  }

  /// Stops listening and closes the microphone.
  Future<void> stop() async {
    _session++;
    final subscription = _subscription;
    _subscription = null;
    await subscription?.cancel();
    if (_disposed) return;
    _phase = TunerPhase.idle;
    _note = null;
    _tracker.reset();
    _notify();
  }

  /// Plays or stops the reference tone. Listening stops first.
  Future<void> toggleTone() async {
    if (_toneOn) {
      _stopTone();
      _notify();
      return;
    }
    if (!toneAvailable) return;
    await stop();
    if (_disposed) return;
    _toneOn = true;
    _notify();
    try {
      await playback.play(toneDocument, owner: this);
    } catch (_) {
      _toneOn = false;
      _notify();
      return;
    }
    final status = playback.status.value;
    if (status.state == PlaybackState.stopped &&
        status.stopReason == PlaybackStopReason.error) {
      _toneOn = false;
      _notify();
    }
  }

  void _stopTone() {
    _toneOn = false;
    playback.stop(owner: this);
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _session++;
    _subscription?.cancel();
    _subscription = null;
    playback.stop(owner: this);
    super.dispose();
  }
}
