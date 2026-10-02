import 'package:flutter/foundation.dart';
import 'package:synesterra/data/repositories/instrument_audition_repository.dart';
import 'package:synesterra_core/synesterra_core.dart';

/// Remembers what was played instead of making a sound.
class RecordingAudition implements InstrumentAuditionRepository {
  final played = <Instrument>[];

  /// The frequencies of each call, parallel to [played].
  final frequencies = <List<double>>[];
  final _available = ValueNotifier<bool>(true);

  set isAvailable(bool value) => _available.value = value;

  @override
  ValueListenable<bool> get available => _available;

  @override
  Future<bool> play(Instrument instrument, List<double> frequenciesHz) async {
    played.add(instrument);
    frequencies.add(frequenciesHz);
    return true;
  }

  @override
  Future<void> dispose() async {}
}
