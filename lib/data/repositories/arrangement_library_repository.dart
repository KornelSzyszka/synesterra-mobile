import 'package:flutter/foundation.dart';
import 'package:synesterra_core/synesterra_core.dart';

import 'library_item.dart';

/// Source of truth for the user's arrangements. There are no factory
/// arrangements.
abstract class ArrangementLibraryRepository {
  /// The user's readable arrangements, sorted by name, and the unreadable
  /// count.
  ValueListenable<LibrarySnapshot<Arrangement>> get snapshot;

  /// Reads everything from storage and publishes a new [snapshot]. A file that
  /// cannot be read is counted and skipped, never changed.
  Future<void> load();

  /// Adds the arrangement or replaces the one with the same id (so a rename
  /// is a save). Throws [ArgumentError] for a factory id.
  Future<void> save(Arrangement arrangement);

  /// Removes the arrangement. Saving it again undoes this.
  Future<void> delete(String id);
}

int compareArrangements(Arrangement a, Arrangement b) =>
    compareLibraryNames(a.name, a.id, b.name, b.id);

/// Library helpers over the core [Arrangement] (which stays pure data).
extension ArrangementLibraryValues on Arrangement {
  /// Cycles played once through, before any "repeat all".
  int get totalRepeats => sections.fold(0, (sum, s) => sum + s.repeats);

  /// The same arrangement under a new name (a rename is a save of this).
  Arrangement renamed(String name) =>
      Arrangement(id: id, name: name, sections: sections);
}
