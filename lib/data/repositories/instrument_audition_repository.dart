import 'package:flutter/foundation.dart';
import 'package:synesterra_core/synesterra_core.dart';

/// Plays an instrument once so the user can hear what they are shaping.
abstract class InstrumentAuditionRepository {
  /// False after the engine failed to start or play; true again after a
  /// successful sound. Starts as true because nothing has failed yet.
  ValueListenable<bool> get available;

  /// Plays [instrument], replacing a sound that is still playing. Returns
  /// true when this call started a sound, false when it failed or a newer
  /// call took over before it could start.
  Future<bool> play(Instrument instrument);

  Future<void> dispose();
}
