import 'package:flutter/foundation.dart';

import 'library_item.dart';
import 'loop.dart';

/// Source of truth for the user's loops. The factory loops ([factoryLoops])
/// are not stored and not part of [snapshot]; they are read-only.
abstract class LoopLibraryRepository {
  /// The user's readable loops, sorted by name, and the unreadable count.
  ValueListenable<LibrarySnapshot<Loop>> get snapshot;

  /// Reads everything from storage and publishes a new [snapshot]. A file that
  /// cannot be read is counted and skipped, never changed.
  Future<void> load();

  /// Adds the loop or replaces the one with the same id (so a rename is a
  /// save). Throws [ArgumentError] for a factory id: those are read-only.
  Future<void> save(Loop loop);

  /// Removes the loop. Saving it again undoes this. Throws [ArgumentError]
  /// for a factory id.
  Future<void> delete(String id);
}

/// The loop with [id]: a factory loop or one of the user's, or null when it
/// is missing (deleted, or unreadable on disk).
Loop? findLoop(LibrarySnapshot<Loop> snapshot, String id) {
  for (final loop in [...factoryLoops, ...snapshot.items]) {
    if (loop.id == id) return loop;
  }
  return null;
}
