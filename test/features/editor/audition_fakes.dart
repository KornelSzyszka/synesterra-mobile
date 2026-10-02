import 'package:flutter/foundation.dart';
import 'package:synesterra/data/repositories/instrument_audition_repository.dart';
import 'package:synesterra_core/synesterra_core.dart';

/// Remembers what was played instead of making a sound.
class RecordingAudition implements InstrumentAuditionRepository {
  final played = <Instrument>[];
  final _available = ValueNotifier<bool>(true);

  set isAvailable(bool value) => _available.value = value;

  @override
  ValueListenable<bool> get available => _available;

  @override
  Future<bool> play(Instrument instrument) async {
    played.add(instrument);
    return true;
  }

  @override
  Future<void> dispose() async {}
}
