import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../services/json_file_store.dart';
import '../library_item.dart';

/// The shared core of the file-backed loop and arrangement libraries: one
/// JSON file per item, named `<id>.json`, atomic writes, strict reads.
///
/// A stored file is skipped and counted in
/// [LibrarySnapshot.unreadableCount] when it cannot be read or decoded, fails
/// validation, is larger than [maxFileLength], has a name that does not match
/// its id, or claims a factory id. Such a file is never changed or deleted
/// here; only the user saving an item with the same id replaces it.
class FileLibrary<T> {
  FileLibrary(
    this._store, {
    required this.decode,
    required this.encode,
    required this.idOf,
    required this.compare,
  });

  final JsonFileStore _store;

  /// Strict parse; throws [FormatException] for anything invalid.
  final T Function(Object? json) decode;
  final Map<String, Object> Function(T item) encode;
  final String Function(T item) idOf;
  final int Function(T a, T b) compare;

  /// Far above any valid item (a session is at most 128 KiB).
  static const maxFileLength = 256 * 1024;

  final _snapshot = ValueNotifier(LibrarySnapshot<T>());

  ValueListenable<LibrarySnapshot<T>> get snapshot => _snapshot;

  Future<void> load() async {
    final items = <T>[];
    var unreadable = 0;
    for (final file in await _store.readAll()) {
      final item = _read(file);
      if (item == null) {
        unreadable++;
      } else {
        items.add(item);
      }
    }
    _publish(items, unreadable);
  }

  T? _read(StoredJsonFile file) {
    final text = file.text;
    if (text == null || text.length > maxFileLength) return null;
    try {
      final item = decode(jsonDecode(text));
      final id = idOf(item);
      if (file.name != '$id.json' || isFactoryId(id)) return null;
      return item;
    } on FormatException {
      return null;
    } on ArgumentError {
      return null;
    }
  }

  Future<void> save(T item) async {
    final id = idOf(item);
    _checkWritable(id);
    await _store.write(id, jsonEncode(encode(item)));
    _publish([
      ..._snapshot.value.items.where((i) => idOf(i) != id),
      item,
    ], _snapshot.value.unreadableCount);
  }

  Future<void> delete(String id) async {
    _checkWritable(id);
    await _store.remove(id);
    _publish(
      _snapshot.value.items.where((i) => idOf(i) != id),
      _snapshot.value.unreadableCount,
    );
  }

  void _publish(Iterable<T> items, int unreadable) {
    _snapshot.value = LibrarySnapshot(
      items: items.toList()..sort(compare),
      unreadableCount: unreadable,
    );
  }
}

/// Throws [ArgumentError] for a factory id: factory items are read-only.
void _checkWritable(String id) {
  if (isFactoryId(id)) {
    throw ArgumentError.value(id, 'id', 'factory items are read-only');
  }
}

/// The in-memory twin of [FileLibrary], for tests and previews.
class MemoryLibrary<T> {
  MemoryLibrary(
    Iterable<T> initial, {
    required this.idOf,
    required this.compare,
  }) : _snapshot = ValueNotifier(
         LibrarySnapshot(items: initial.toList()..sort(compare)),
       );

  final String Function(T item) idOf;
  final int Function(T a, T b) compare;
  final ValueNotifier<LibrarySnapshot<T>> _snapshot;

  ValueListenable<LibrarySnapshot<T>> get snapshot => _snapshot;

  Future<void> load() async {}

  Future<void> save(T item) async {
    final id = idOf(item);
    _checkWritable(id);
    _publish([..._snapshot.value.items.where((i) => idOf(i) != id), item]);
  }

  Future<void> delete(String id) async {
    _checkWritable(id);
    _publish(_snapshot.value.items.where((i) => idOf(i) != id));
  }

  void _publish(Iterable<T> items) {
    _snapshot.value = LibrarySnapshot(items: items.toList()..sort(compare));
  }
}
