import 'dart:convert';
import 'dart:io';

/// One stored file. [text] is null when the file could not be read.
class StoredInstrumentFile {
  const StoredInstrumentFile({required this.name, required this.text});

  final String name;
  final String? text;
}

/// Reads and writes one JSON file per instrument in [directory]. Stateless:
/// it knows nothing about what the files contain.
class InstrumentFileStore {
  InstrumentFileStore(this.directory);

  final Directory directory;
  final _writes = <String, Future<void>>{};

  String _path(String id, [String suffix = '.json']) =>
      '${directory.path}${Platform.pathSeparator}$id$suffix';

  Future<List<StoredInstrumentFile>> readAll() async {
    if (!await directory.exists()) return const [];
    final stored = <StoredInstrumentFile>[];
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      final name = entity.uri.pathSegments.last;
      try {
        stored.add(
          StoredInstrumentFile(
            name: name,
            text: utf8.decode(await entity.readAsBytes()),
          ),
        );
      } on FileSystemException {
        stored.add(StoredInstrumentFile(name: name, text: null));
      } on FormatException {
        stored.add(StoredInstrumentFile(name: name, text: null));
      }
    }
    return stored;
  }

  /// Writes to a temporary file first, then renames it over the target, so a
  /// crash never leaves a half-written instrument behind.
  Future<void> write(String id, String text) async {
    final previous = _writes[id];
    final write = _writeAfter(previous, id, text);
    _writes[id] = write;
    try {
      await write;
    } finally {
      if (identical(_writes[id], write)) _writes.remove(id);
    }
  }

  Future<void> _writeAfter(
    Future<void>? previous,
    String id,
    String text,
  ) async {
    if (previous != null) {
      try {
        await previous;
      } catch (_) {
        // A later save still gets its own complete write attempt.
      }
    }
    await directory.create(recursive: true);
    final temporary = File(_path(id, '.json.tmp'));
    await temporary.writeAsString(text, flush: true);
    await temporary.rename(_path(id));
  }

  Future<void> remove(String id) async {
    final file = File(_path(id));
    if (await file.exists()) await file.delete();
  }
}
