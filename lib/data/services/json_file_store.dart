import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// One stored file. [text] is null when the file could not be read.
class StoredJsonFile {
  const StoredJsonFile({required this.name, required this.text});

  /// File name with the `.json` extension, such as `loop-1.json`.
  final String name;
  final String? text;
}

/// Reads and writes one JSON file per item, named `<id>.json`, in
/// [directory]. Stateless about content: it knows nothing about what the
/// files hold. Writes and removals of one id run in call order.
class JsonFileStore {
  JsonFileStore(this.directory);

  final Directory directory;
  final _pending = <String, Future<void>>{};

  static final _idPattern = RegExp(r'^[A-Za-z0-9-]{1,64}$');

  String _path(String id, [String suffix = '.json']) {
    // The id becomes a file name, so it must never reach outside directory.
    if (!_idPattern.hasMatch(id)) throw ArgumentError.value(id, 'id');
    return '${directory.path}${Platform.pathSeparator}$id$suffix';
  }

  /// Every `*.json` file in [directory]; leftover `*.json.tmp` files are
  /// ignored. Never changes a file.
  Future<List<StoredJsonFile>> readAll() async {
    if (!await directory.exists()) return const [];
    final stored = <StoredJsonFile>[];
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      final name = entity.uri.pathSegments.last;
      try {
        stored.add(
          StoredJsonFile(
            name: name,
            text: utf8.decode(await entity.readAsBytes()),
          ),
        );
      } on FileSystemException {
        stored.add(StoredJsonFile(name: name, text: null));
      } on FormatException {
        stored.add(StoredJsonFile(name: name, text: null));
      }
    }
    return stored;
  }

  /// Writes to a temporary file first, then renames it over the target, so a
  /// crash never leaves a half-written item behind.
  Future<void> write(String id, String text) {
    final path = _path(id);
    return _enqueue(id, () async {
      await directory.create(recursive: true);
      final temporary = File(_path(id, '.json.tmp'));
      try {
        await writeTemporary(temporary, text);
        await replaceTarget(temporary, path);
      } catch (_) {
        // The target was never touched; drop the partial temporary file so
        // nothing half-written stays on disk, then report the failure.
        try {
          if (await temporary.exists()) await temporary.delete();
        } on FileSystemException {
          // Best effort: a leftover `.json.tmp` is ignored by readAll.
        }
        rethrow;
      }
    });
  }

  /// Writes the complete text to [temporary] and flushes it to disk.
  @visibleForTesting
  Future<void> writeTemporary(File temporary, String text) =>
      temporary.writeAsString(text, flush: true);

  /// Renames [temporary] over [targetPath] in one step (same directory).
  @visibleForTesting
  Future<void> replaceTarget(File temporary, String targetPath) =>
      temporary.rename(targetPath);

  /// Deletes `<id>.json` if it exists, after any earlier write of that id.
  Future<void> remove(String id) {
    final file = File(_path(id));
    return _enqueue(id, () async {
      if (await file.exists()) await file.delete();
    });
  }

  /// Runs [operation] after the previous operation on [id] has finished,
  /// whether it succeeded or not, so overlapping calls never share the
  /// temporary file and the last call decides what is on disk.
  Future<void> _enqueue(String id, Future<void> Function() operation) async {
    final previous = _pending[id];
    final current = () async {
      if (previous != null) {
        try {
          await previous;
        } catch (_) {
          // A later call still gets its own complete attempt.
        }
      }
      await operation();
    }();
    _pending[id] = current;
    try {
      await current;
    } finally {
      if (identical(_pending[id], current)) _pending.remove(id);
    }
  }
}
