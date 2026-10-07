import 'package:flutter/foundation.dart';

import 'library_item.dart';
import 'strict_json.dart';

// TODO(DOM-089): replace InterimArrangement and InterimArrangementSection with
// the core `Arrangement` model once issue #89 is merged, and delete this file.
// The JSON shape and limits below copy the #89 acceptance criteria exactly
// ({version: 1, id, name, sections: [{loopId, repeats}]}), so files written
// now stay readable by the core model. The names differ on purpose: a second
// `Arrangement` type would clash with the core export the day #89 lands.

/// One section of an arrangement: a loop played [repeats] cycles.
@immutable
class InterimArrangementSection {
  InterimArrangementSection({required this.loopId, required this.repeats}) {
    if (!libraryIdPattern.hasMatch(loopId)) {
      throw ArgumentError.value(loopId, 'loopId');
    }
    if (repeats < 1 || repeats > InterimArrangement.maxRepeats) {
      throw ArgumentError.value(repeats, 'repeats');
    }
  }

  final String loopId;
  final int repeats;

  Map<String, Object> toJson() => {'loopId': loopId, 'repeats': repeats};

  @override
  bool operator ==(Object other) =>
      other is InterimArrangementSection &&
      loopId == other.loopId &&
      repeats == other.repeats;

  @override
  int get hashCode => Object.hash(loopId, repeats);
}

/// An arrangement: loops chained into ordered sections (1..16).
@immutable
class InterimArrangement {
  /// Throws [ArgumentError] for an invalid id, name or section list.
  InterimArrangement({
    required this.id,
    required this.name,
    required List<InterimArrangementSection> sections,
  }) : sections = List.unmodifiable(sections) {
    if (!libraryIdPattern.hasMatch(id)) throw ArgumentError.value(id, 'id');
    if (!isValidLibraryName(name)) throw ArgumentError.value(name, 'name');
    if (sections.isEmpty || sections.length > maxSections) {
      throw ArgumentError.value(
        sections.length,
        'sections',
        'must have 1..$maxSections entries',
      );
    }
  }

  /// Strict parse. Throws only [FormatException] with the JSON path.
  factory InterimArrangement.fromJson(Object? json) {
    var path = r'$';
    try {
      if (json is! Map<String, dynamic>) failJson(r'$', 'expected an object');
      if (!json.containsKey('version')) failJson(r'$.version', 'missing field');
      if (json['version'] is! int || json['version'] != schemaVersion) {
        failJson(r'$.version', 'unsupported version');
      }
      final map = jsonObject(json, r'$', _keys);
      final id = jsonString(map['id'], r'$.id');
      final name = jsonString(map['name'], r'$.name');
      final raw = jsonList(map['sections'], r'$.sections');
      final sections = <InterimArrangementSection>[];
      for (var i = 0; i < raw.length; i++) {
        path = '\$.sections[$i]';
        final section = jsonObject(raw[i], path, _sectionKeys);
        sections.add(
          InterimArrangementSection(
            loopId: jsonString(section['loopId'], '$path.loopId'),
            repeats: jsonInt(section['repeats'], '$path.repeats'),
          ),
        );
      }
      path = r'$';
      return InterimArrangement(id: id, name: name, sections: sections);
    } on ArgumentError catch (error) {
      throw FormatException(
        '$path.${error.name}: ${error.message ?? 'invalid value'}',
      );
    }
  }

  static const schemaVersion = 1;
  static const maxSections = 16;
  static const maxRepeats = 32;
  static const _keys = {'version', 'id', 'name', 'sections'};
  static const _sectionKeys = {'loopId', 'repeats'};

  final String id;
  final String name;
  final List<InterimArrangementSection> sections;

  /// Cycles played once through, before any "repeat all".
  int get totalRepeats => sections.fold(0, (sum, s) => sum + s.repeats);

  Map<String, Object> toJson() => {
    'version': schemaVersion,
    'id': id,
    'name': name,
    'sections': [for (final section in sections) section.toJson()],
  };

  InterimArrangement copyWith({
    String? id,
    String? name,
    List<InterimArrangementSection>? sections,
  }) => InterimArrangement(
    id: id ?? this.id,
    name: name ?? this.name,
    sections: sections ?? this.sections,
  );

  @override
  bool operator ==(Object other) =>
      other is InterimArrangement &&
      id == other.id &&
      name == other.name &&
      listEquals(sections, other.sections);

  @override
  int get hashCode => Object.hash(id, name, Object.hashAll(sections));

  @override
  String toString() => 'InterimArrangement($id, $name)';
}

int compareArrangements(InterimArrangement a, InterimArrangement b) =>
    compareLibraryNames(a.name, a.id, b.name, b.id);
