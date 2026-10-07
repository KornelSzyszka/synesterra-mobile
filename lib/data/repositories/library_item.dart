import 'dart:math' as math;

import 'package:flutter/foundation.dart';

// Rules and helpers shared by the loop and arrangement libraries.

/// Id rule of every library item (instrument, loop, arrangement, layer).
final libraryIdPattern = RegExp(r'^[A-Za-z0-9-]{1,64}$');

/// Longest library item name in UTF-16 units (as for instruments).
const maxLibraryNameLength = 40;

final _controlCharacters = RegExp(r'[\u0000-\u001f\u007f-\u009f]');

/// A name is 1..40 UTF-16 units, not blank and without control characters.
bool isValidLibraryName(String name) =>
    name.trim().isNotEmpty &&
    name.length <= maxLibraryNameLength &&
    !_controlCharacters.hasMatch(name);

/// Factory items ship with the app, are always present and are read-only.
/// Their ids start with `factory-`; a user item never gets such an id.
bool isFactoryId(String id) => id.startsWith('factory-');

/// A fresh, practically unique id for a user item, such as `loop-…`.
String newLibraryId(String prefix) =>
    '$prefix-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}-'
    '${math.Random().nextInt(1 << 20).toRadixString(36)}';

/// The name of a copy: `<name> copy`, shortened so it stays a valid name.
String copyName(String name) {
  const suffix = ' copy';
  final room = maxLibraryNameLength - suffix.length;
  final base = name.length > room ? name.substring(0, room).trimRight() : name;
  return '$base$suffix';
}

/// What a library holds at a moment: the readable user items and how many
/// stored files could not be read.
@immutable
class LibrarySnapshot<T> {
  LibrarySnapshot({List<T> items = const [], this.unreadableCount = 0})
    : items = List.unmodifiable(items);

  /// User items sorted by name, case-insensitive. Factory items are not here.
  final List<T> items;

  /// Stored files that were skipped because they could not be read. They are
  /// never deleted or overwritten, so the user's data is not lost silently.
  final int unreadableCount;
}

/// Orders by name ignoring case, then by id, so the order is stable.
int compareLibraryNames(String nameA, String idA, String nameB, String idB) {
  final byName = nameA.toLowerCase().compareTo(nameB.toLowerCase());
  return byName != 0 ? byName : idA.compareTo(idB);
}
