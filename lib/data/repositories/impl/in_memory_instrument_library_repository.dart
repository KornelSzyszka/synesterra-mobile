import 'package:flutter/foundation.dart';
import 'package:synesterra_core/synesterra_core.dart';

import '../instrument_library_repository.dart';

/// Keeps instruments in memory only. For tests and previews.
class InMemoryInstrumentLibraryRepository
    implements InstrumentLibraryRepository {
  InMemoryInstrumentLibraryRepository([Iterable<Instrument> initial = const []])
    : _snapshot = ValueNotifier(
        InstrumentLibrarySnapshot(
          instruments: initial.toList()..sort(compareInstrumentNames),
        ),
      );

  final ValueNotifier<InstrumentLibrarySnapshot> _snapshot;

  @override
  ValueListenable<InstrumentLibrarySnapshot> get snapshot => _snapshot;

  @override
  Future<void> load() async {}

  @override
  Future<void> save(Instrument instrument) async => _publish([
    ..._snapshot.value.instruments.where((i) => i.id != instrument.id),
    instrument,
  ]);

  @override
  Future<void> delete(String id) async =>
      _publish(_snapshot.value.instruments.where((i) => i.id != id));

  void _publish(Iterable<Instrument> instruments) {
    _snapshot.value = InstrumentLibrarySnapshot(
      instruments: instruments.toList()..sort(compareInstrumentNames),
    );
  }
}
