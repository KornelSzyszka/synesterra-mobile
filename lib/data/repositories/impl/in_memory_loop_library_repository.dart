import 'package:flutter/foundation.dart';

import '../library_item.dart';
import '../loop.dart';
import '../loop_library_repository.dart';
import 'file_library.dart';

/// Keeps loops in memory only. For tests and previews.
class InMemoryLoopLibraryRepository implements LoopLibraryRepository {
  InMemoryLoopLibraryRepository([Iterable<Loop> initial = const []])
    : _library = MemoryLibrary(
        initial,
        idOf: (loop) => loop.id,
        compare: compareLoops,
      );

  final MemoryLibrary<Loop> _library;

  @override
  ValueListenable<LibrarySnapshot<Loop>> get snapshot => _library.snapshot;

  @override
  Future<void> load() => _library.load();

  @override
  Future<void> save(Loop loop) => _library.save(loop);

  @override
  Future<void> delete(String id) => _library.delete(id);
}
