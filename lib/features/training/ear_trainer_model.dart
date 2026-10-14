import 'package:flutter/foundation.dart';
import 'package:synesterra_core/synesterra_core.dart';

import '../../data/repositories/playback_repository.dart';
import 'training_documents.dart';

/// State of one ear-training session (note, chord or progression). Questions
/// come from the seeded core generator; sound goes through the playback
/// repository as a sequence of one-cycle sections.
class EarTrainerModel extends ChangeNotifier {
  EarTrainerModel({
    required this.playback,
    required this.mode,
    required int seed,
    required this.score,
  }) : _generator = EarQuestionGenerator(mode, seed: seed) {
    question = _generator.next();
  }

  final PlaybackRepository playback;
  final EarMode mode;

  /// The session's streak and counts. Owned by the caller so it survives
  /// leaving and re-entering the exercise; nothing is stored on disk.
  final ValueNotifier<EarScore> score;

  final EarQuestionGenerator _generator;
  late EarQuestion question;

  /// The option the user chose, or null while the question is open.
  int? chosen;

  /// The sound failed to start.
  bool unavailable = false;
  bool _disposed = false;

  bool get answered => chosen != null;
  bool get right => chosen == question.correctIndex;

  /// Plays (or replays) the current question.
  Future<void> play() async {
    unavailable = false;
    try {
      await playback.playSequence(
        earSections(question),
        repeatAll: false,
        owner: this,
      );
    } catch (_) {
      _fail();
      return;
    }
    final status = playback.status.value;
    if (status.state == PlaybackState.stopped &&
        status.stopReason == PlaybackStopReason.error) {
      _fail();
    }
  }

  void _fail() {
    if (_disposed) return;
    unavailable = true;
    notifyListeners();
  }

  /// Records the answer. A question is answered once.
  void answer(int index) {
    if (answered || index < 0 || index >= question.options.length) return;
    chosen = index;
    score.value = score.value.answer(right: right);
    notifyListeners();
  }

  /// Moves on to a new question and plays it.
  Future<void> next() async {
    if (!answered) return;
    chosen = null;
    question = _generator.next();
    notifyListeners();
    await play();
  }

  @override
  void dispose() {
    _disposed = true;
    playback.stop(owner: this);
    super.dispose();
  }
}
