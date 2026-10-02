import 'package:flutter/foundation.dart';
import 'package:synesterra_core/synesterra_core.dart';

/// Plays an instrument once so the user can hear what they are shaping.
abstract class InstrumentAuditionRepository {
  /// False after the engine failed to start or play; true again after a
  /// successful sound. Starts as true because nothing has failed yet.
  ValueListenable<bool> get available;

  /// Plays [instrument] at every frequency in [frequenciesHz] together (one
  /// for a note, several for a chord), replacing a sound that is still
  /// playing. The instrument has no pitch of its own; the caller chooses it.
  /// Returns true when this call started the sound, false when it failed, was
  /// empty, or a newer call took over before it could start.
  Future<bool> play(Instrument instrument, List<double> frequenciesHz);

  Future<void> dispose();
}
