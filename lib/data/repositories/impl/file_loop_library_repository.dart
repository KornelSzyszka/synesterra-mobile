import 'package:flutter/foundation.dart';

import '../../services/json_file_store.dart';
import '../library_item.dart';
import '../loop.dart';
import '../loop_library_repository.dart';
import 'file_library.dart';

/// Loops as one JSON file each (see [FileLibrary] for the read and write
/// rules).
class FileLoopLibraryRepository implements LoopLibraryRepository {
  FileLoopLibraryRepository(JsonFileStore store)
    : _library = FileLibrary(
        store,
        decode: Loop.fromJson,
        encode: (loop) => loop.toJson(),
        idOf: (loop) => loop.id,
        compare: compareLoops,
      );

  final FileLibrary<Loop> _library;

  @override
  ValueListenable<LibrarySnapshot<Loop>> get snapshot => _library.snapshot;

  @override
  Future<void> load() => _library.load();

  @override
  Future<void> save(Loop loop) => _library.save(loop);

  @override
  Future<void> delete(String id) => _library.delete(id);
}
