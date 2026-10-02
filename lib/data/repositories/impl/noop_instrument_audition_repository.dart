import 'package:flutter/foundation.dart';
import 'package:synesterra_core/synesterra_core.dart';

import '../instrument_audition_repository.dart';

/// Plays nothing. For tests and previews.
class NoopInstrumentAuditionRepository implements InstrumentAuditionRepository {
  final _available = ValueNotifier<bool>(true);

  @override
  ValueListenable<bool> get available => _available;

  @override
  Future<bool> play(Instrument instrument) async => true;

  @override
  Future<void> dispose() async {}
}
