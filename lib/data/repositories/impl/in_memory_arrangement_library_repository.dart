import 'package:flutter/foundation.dart';

import '../arrangement_library_repository.dart';
import '../interim_arrangement.dart';
import '../library_item.dart';
import 'file_library.dart';

/// Keeps arrangements in memory only. For tests and previews.
class InMemoryArrangementLibraryRepository
    implements ArrangementLibraryRepository {
  InMemoryArrangementLibraryRepository([
    Iterable<InterimArrangement> initial = const [],
  ]) : _library = MemoryLibrary(
         initial,
         idOf: (arrangement) => arrangement.id,
         compare: compareArrangements,
       );

  final MemoryLibrary<InterimArrangement> _library;

  @override
  ValueListenable<LibrarySnapshot<InterimArrangement>> get snapshot =>
      _library.snapshot;

  @override
  Future<void> load() => _library.load();

  @override
  Future<void> save(InterimArrangement arrangement) =>
      _library.save(arrangement);

  @override
  Future<void> delete(String id) => _library.delete(id);
}
