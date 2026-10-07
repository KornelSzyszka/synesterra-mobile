final _idPattern = RegExp(r'^[A-Za-z0-9-]{1,64}$');
final _controlCharacters = RegExp(r'[\x00-\x1F\x7F]');

/// One step of an [Arrangement]: a loop played for [repeats] cycles.
class ArrangementSection {
  static const minRepeats = 1;
  static const maxRepeats = 32;

  /// Validates the values; throws [ArgumentError] named after the field.
  ArrangementSection({required this.loopId, required this.repeats}) {
    if (!_idPattern.hasMatch(loopId)) {
      throw ArgumentError.value(loopId, 'loopId');
    }
    if (repeats < minRepeats || repeats > maxRepeats) {
      throw ArgumentError.value(
        repeats,
        'repeats',
        'must be $minRepeats..$maxRepeats',
      );
    }
  }

  final String loopId;
  final int repeats;

  Map<String, dynamic> toJson() => {'loopId': loopId, 'repeats': repeats};

  @override
  bool operator ==(Object other) =>
      other is ArrangementSection &&
      loopId == other.loopId &&
      repeats == other.repeats;

  @override
  int get hashCode => Object.hash(loopId, repeats);

  @override
  String toString() => 'ArrangementSection($loopId x$repeats)';
}

/// Loops chained into a song. Pure data: it knows nothing about playback.
class Arrangement {
  static const currentVersion = 1;
  static const maxNameLength = 40;
  static const minSections = 1;
  static const maxSections = 16;

  /// Validates the values; throws [ArgumentError] named after the field.
  Arrangement({
    required this.id,
    required this.name,
    required List<ArrangementSection> sections,
  }) : sections = List.unmodifiable(sections) {
    if (!_idPattern.hasMatch(id)) throw ArgumentError.value(id, 'id');
    if (name.trim().isEmpty ||
        name.length > maxNameLength ||
        _controlCharacters.hasMatch(name)) {
      throw ArgumentError.value(name, 'name');
    }
    if (this.sections.length < minSections ||
        this.sections.length > maxSections) {
      throw ArgumentError.value(
        this.sections.length,
        'sections',
        'must have $minSections..$maxSections entries',
      );
    }
  }

  /// Parses and validates strictly. Throws only [FormatException], whose
  /// message starts with the JSON path (`$.sections[1].repeats: ...`).
  factory Arrangement.fromJson(Object? json) {
    final map = _object(json, r'$', _keys);
    final version = map['version'];
    if (version != currentVersion) {
      throw const FormatException(r'$.version: unsupported version');
    }
    final id = _string(map['id'], r'$.id');
    final name = _string(map['name'], r'$.name');
    final rawSections = map['sections'];
    if (rawSections is! List<Object?>) {
      throw const FormatException(r'$.sections: expected a list');
    }
    final sections = <ArrangementSection>[];
    for (var i = 0; i < rawSections.length; i++) {
      final path = '\$.sections[$i]';
      final section = _object(rawSections[i], path, _sectionKeys);
      final loopId = _string(section['loopId'], '$path.loopId');
      final repeats = section['repeats'];
      if (repeats is! int) {
        throw FormatException('$path.repeats: expected an integer');
      }
      try {
        sections.add(ArrangementSection(loopId: loopId, repeats: repeats));
      } on ArgumentError catch (error) {
        throw FormatException('$path.${error.name}: ${error.message}');
      }
    }
    try {
      return Arrangement(id: id, name: name, sections: sections);
    } on ArgumentError catch (error) {
      throw FormatException('\$.${error.name}: ${error.message}');
    }
  }

  static const _keys = {'version', 'id', 'name', 'sections'};
  static const _sectionKeys = {'loopId', 'repeats'};

  final String id;
  final String name;
  final List<ArrangementSection> sections;

  Map<String, dynamic> toJson() => {
    'version': currentVersion,
    'id': id,
    'name': name,
    'sections': [for (final section in sections) section.toJson()],
  };

  @override
  bool operator ==(Object other) =>
      other is Arrangement &&
      id == other.id &&
      name == other.name &&
      _sameSections(sections, other.sections);

  @override
  int get hashCode => Object.hash(id, name, Object.hashAll(sections));

  @override
  String toString() => 'Arrangement($id, $name, ${sections.length} sections)';
}

bool _sameSections(List<ArrangementSection> a, List<ArrangementSection> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

Map<String, dynamic> _object(Object? input, String path, Set<String> keys) {
  if (input is! Map<String, dynamic>) {
    throw FormatException('$path: expected an object');
  }
  for (final key in input.keys) {
    if (!keys.contains(key)) throw FormatException('$path.$key: unknown field');
  }
  for (final key in keys) {
    if (!input.containsKey(key)) {
      throw FormatException('$path.$key: missing field');
    }
  }
  return input;
}

String _string(Object? input, String path) {
  if (input is! String) throw FormatException('$path: expected a string');
  return input;
}

/// Where an arrangement is at a given cycle count.
sealed class SequencePosition {
  const SequencePosition();
}

/// Cycle [cycleInSection] (0-based) of the section at [sectionIndex], an
/// index into the original `sections` list (skipped sections keep their slot).
final class SequenceAt extends SequencePosition {
  const SequenceAt({required this.sectionIndex, required this.cycleInSection});

  final int sectionIndex;
  final int cycleInSection;

  @override
  bool operator ==(Object other) =>
      other is SequenceAt &&
      sectionIndex == other.sectionIndex &&
      cycleInSection == other.cycleInSection;

  @override
  int get hashCode => Object.hash(sectionIndex, cycleInSection);

  @override
  String toString() => 'SequenceAt($sectionIndex, $cycleInSection)';
}

/// Nothing left to play: the end was reached without `repeatAll`, or every
/// section is skipped.
final class SequenceDone extends SequencePosition {
  const SequenceDone();

  @override
  bool operator ==(Object other) => other is SequenceDone;

  @override
  int get hashCode => (SequenceDone).hashCode;

  @override
  String toString() => 'SequenceDone';
}

/// Maps a zero-based [cycleIndex] (counted from the start of the sequence, in
/// whole cycles) to the section and cycle playing then. A section changes on
/// a cycle start, so the position of a cycle never depends on tempo.
///
/// [isSkipped] marks sections that cannot play (for example a missing loop);
/// they take no cycles. With [repeatAll] the playable sections loop forever;
/// with none playable the result is [SequenceDone], never a spin.
/// Throws [ArgumentError] for a negative [cycleIndex].
SequencePosition sequenceAt({
  required List<ArrangementSection> sections,
  required bool repeatAll,
  required int cycleIndex,
  bool Function(ArrangementSection section)? isSkipped,
}) {
  if (cycleIndex < 0) throw ArgumentError.value(cycleIndex, 'cycleIndex');
  var total = 0;
  for (final section in sections) {
    if (isSkipped?.call(section) != true) total += section.repeats;
  }
  if (total == 0) return const SequenceDone();
  var remaining = cycleIndex;
  if (remaining >= total) {
    if (!repeatAll) return const SequenceDone();
    remaining %= total;
  }
  for (var i = 0; i < sections.length; i++) {
    final section = sections[i];
    if (isSkipped?.call(section) == true) continue;
    if (remaining < section.repeats) {
      return SequenceAt(sectionIndex: i, cycleInSection: remaining);
    }
    remaining -= section.repeats;
  }
  throw StateError('unreachable: remaining < total');
}
