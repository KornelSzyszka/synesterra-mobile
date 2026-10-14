import 'package:flutter/foundation.dart';
import 'package:synesterra_core/synesterra_core.dart';

import '../../data/repositories/playback_repository.dart';
import 'training_documents.dart';

enum TapPhase {
  /// Choosing an exercise.
  idle,

  /// The engine is starting.
  starting,

  /// One cycle of clicks before scoring.
  countIn,

  /// Taps are scored.
  scoring,

  /// The summary is shown.
  done,

  /// The sound could not start.
  unavailable,
}

/// State of the tap-in-rhythm trainer. Time comes only from the playback
/// position (the audio clock), so a test drives it with a fake repository.
/// Scoring is `scoreTaps` in the core.
class TapTrainerModel extends ChangeNotifier {
  TapTrainerModel({required this.playback, ValueNotifier<int>? offset})
    : offsetMs = offset ?? ValueNotifier(0);

  final PlaybackRepository playback;

  /// Manual latency offset, ms. Positive: the user taps late. Owned by the
  /// caller so it survives between exercises.
  final ValueNotifier<int> offsetMs;

  TapPreset preset = tapPresets.first;
  TapDifficulty difficulty = TapDifficulty.medium;

  TapPhase _phase = TapPhase.idle;
  TapPhase get phase => _phase;

  final _taps = <double>[];

  /// The result of the latest scored tap, for live feedback; null until one.
  TapResult? lastResult;

  /// Scored taps so far, for "Tap 5 of 16".
  int get scoredTaps => _scoreNow().results.length;
  int get totalHits => preset.targetHits * tapScoredCycles;

  TapScore? score;

  bool _disposed = false;
  bool get running =>
      _phase == TapPhase.starting ||
      _phase == TapPhase.countIn ||
      _phase == TapPhase.scoring;

  void selectPreset(TapPreset value) {
    if (running || preset == value) return;
    preset = value;
    _toIdle();
  }

  void selectDifficulty(TapDifficulty value) {
    if (running || difficulty == value) return;
    difficulty = value;
    _toIdle();
  }

  void setOffset(int value) =>
      offsetMs.value = value.clamp(-tapOffsetLimitMs, tapOffsetLimitMs);

  void _toIdle() {
    _phase = TapPhase.idle;
    score = null;
    lastResult = null;
    notifyListeners();
  }

  TapScore _scoreNow() => _score(_taps);

  TapScore _score(List<double> taps) => scoreTaps(
    targetTimesMs: preset.targetTimesMs,
    cycleMs: preset.cycleMs,
    tapsMs: taps,
    toleranceMs: difficulty.toleranceMs,
    offsetMs: offsetMs.value.toDouble(),
  );

  double _nowMs(PlaybackPosition p) => tapTimeMs(
    cycleIndex: p.cycleIndex,
    cyclePosition: p.cyclePosition,
    cycleMs: preset.cycleMs,
  );

  /// Where the scored window ends, and a margin for the last late tap.
  double get _endMs =>
      (tapCountInCycles + tapScoredCycles) * preset.cycleMs + 250;

  Future<void> start() async {
    if (running) return;
    _taps.clear();
    score = null;
    lastResult = null;
    _phase = TapPhase.starting;
    notifyListeners();
    try {
      await playback.play(tapExerciseDocument(preset), owner: this);
    } catch (_) {
      _fail();
      return;
    }
    if (_disposed || _phase != TapPhase.starting) return;
    final status = playback.status.value;
    if (status.state == PlaybackState.stopped &&
        status.stopReason == PlaybackStopReason.error) {
      _fail();
      return;
    }
    _phase = TapPhase.countIn;
    playback.position.addListener(_onPosition);
    notifyListeners();
  }

  void _fail() {
    if (_disposed) return;
    _phase = TapPhase.unavailable;
    notifyListeners();
  }

  void _onPosition() {
    if (!running) return;
    final now = _nowMs(playback.position.value);
    if (now >= _endMs) {
      _finish();
    } else if (_phase == TapPhase.countIn &&
        now >= tapCountInCycles * preset.cycleMs) {
      _phase = TapPhase.scoring;
      notifyListeners();
    }
  }

  /// Registers a tap at the audio clock's current time.
  void tap() {
    if (!running) return;
    final p = playback.readPosition();
    final now = _nowMs(p);
    if (_phase == TapPhase.starting) return;
    // Taps before scoring begins belong to the count-in: they are dropped,
    // so a tap shown as count-in can never score against the first hit.
    if (now < tapCountInCycles * preset.cycleMs) return;
    final before = _scoreNow().results.length;
    _taps.add(now);
    final results = _scoreNow().results;
    if (results.length > before) lastResult = results.last;
    _phase = TapPhase.scoring;
    notifyListeners();
  }

  void _finish() {
    playback.position.removeListener(_onPosition);
    score = _scoreNow();
    _phase = TapPhase.done;
    playback.stop(owner: this);
    notifyListeners();
  }

  /// Ends a running exercise without a summary.
  Future<void> stop() async {
    if (!running) return;
    playback.position.removeListener(_onPosition);
    _phase = TapPhase.idle;
    lastResult = null;
    notifyListeners();
    await playback.stop(owner: this);
  }

  @override
  void dispose() {
    _disposed = true;
    playback.position.removeListener(_onPosition);
    if (running) playback.stop(owner: this);
    super.dispose();
  }
}
