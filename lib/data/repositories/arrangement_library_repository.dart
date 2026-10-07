import 'package:flutter/foundation.dart';

import 'interim_arrangement.dart';
import 'library_item.dart';

/// Source of truth for the user's arrangements. There are no factory
/// arrangements.
///
/// TODO(DOM-089): switch [InterimArrangement] to the core `Arrangement`.
abstract class ArrangementLibraryRepository {
  /// The user's readable arrangements, sorted by name, and the unreadable
  /// count.
  ValueListenable<LibrarySnapshot<InterimArrangement>> get snapshot;

  /// Reads everything from storage and publishes a new [snapshot]. A file that
  /// cannot be read is counted and skipped, never changed.
  Future<void> load();

  /// Adds the arrangement or replaces the one with the same id (so a rename
  /// is a save). Throws [ArgumentError] for a factory id.
  Future<void> save(InterimArrangement arrangement);

  /// Removes the arrangement. Saving it again undoes this.
  Future<void> delete(String id);
}
