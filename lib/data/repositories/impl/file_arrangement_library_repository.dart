import 'package:flutter/foundation.dart';

import '../../services/json_file_store.dart';
import '../arrangement_library_repository.dart';
import '../interim_arrangement.dart';
import '../library_item.dart';
import 'file_library.dart';

/// Arrangements as one JSON file each (see [FileLibrary] for the read and
/// write rules).
class FileArrangementLibraryRepository implements ArrangementLibraryRepository {
  FileArrangementLibraryRepository(JsonFileStore store)
    : _library = FileLibrary(
        store,
        decode: InterimArrangement.fromJson,
        encode: (arrangement) => arrangement.toJson(),
        idOf: (arrangement) => arrangement.id,
        compare: compareArrangements,
      );

  final FileLibrary<InterimArrangement> _library;

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
