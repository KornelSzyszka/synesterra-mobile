import 'package:flutter/foundation.dart';
import 'package:synesterra_core/synesterra_core.dart';

/// What the library holds at a moment: the readable user instruments and how
/// many stored files could not be read.
@immutable
class InstrumentLibrarySnapshot {
  InstrumentLibrarySnapshot({
    List<Instrument> instruments = const [],
    this.unreadableCount = 0,
  }) : instruments = List.unmodifiable(instruments);

  /// Sorted by name, case-insensitive. Factory instruments are not included.
  final List<Instrument> instruments;

  /// Stored files that were skipped because they could not be read. They are
  /// never deleted or overwritten, so the user's data is not lost silently.
  final int unreadableCount;
}

/// Source of truth for the user's instruments.
abstract class InstrumentLibraryRepository {
  ValueListenable<InstrumentLibrarySnapshot> get snapshot;

  /// Reads everything from storage and publishes a new [snapshot].
  Future<void> load();

  /// Adds the instrument or replaces the one with the same id.
  Future<void> save(Instrument instrument);

  Future<void> delete(String id);
}

int compareInstrumentNames(Instrument a, Instrument b) {
  final byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
  return byName != 0 ? byName : a.id.compareTo(b.id);
}
