import 'package:flutter/foundation.dart';
import 'package:synesterra_core/synesterra_core.dart';

import '../arrangement_library_repository.dart';
import '../library_item.dart';
import 'file_library.dart';

/// Keeps arrangements in memory only. For tests and previews.
class InMemoryArrangementLibraryRepository
    implements ArrangementLibraryRepository {
  InMemoryArrangementLibraryRepository([
    Iterable<Arrangement> initial = const [],
  ]) : _library = MemoryLibrary(
         initial,
         idOf: (arrangement) => arrangement.id,
         compare: compareArrangements,
       );

  final MemoryLibrary<Arrangement> _library;

  @override
  ValueListenable<LibrarySnapshot<Arrangement>> get snapshot =>
      _library.snapshot;

  @override
  Future<void> load() => _library.load();

  @override
  Future<void> save(Arrangement arrangement) => _library.save(arrangement);

  @override
  Future<void> delete(String id) => _library.delete(id);
}
