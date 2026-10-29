/// Sound recipes: what a voice sounds like, independent of pitch.
///
/// An [Instrument] is a reusable timbre preset: harmonics, envelope and EQ,
/// plus tags to find it again. It has no pitch; whoever plays it (a loop
/// layer, or the editor's test sound) chooses the frequency. It knows nothing
/// about rhythm, tempo or the audio backend. A recipe is rendered into a
/// buffer for one frequency by the audio layer.
final _idPattern = RegExp(r'^[A-Za-z0-9-]{1,64}$');
final _tagPattern = RegExp(r'^[a-z0-9][a-z0-9 -]{0,23}$');
final _controlCharacters = RegExp(r'[\x00-\x1F\x7F]');

void _range(num value, num min, num max, String name) {
  if (!value.isFinite || value < min || value > max) {
    throw ArgumentError.value(value, name, 'must be finite and in $min..$max');
  }
}

bool _sameDoubles(List<double> a, List<double> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

bool _sameStrings(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Three fixed bands: low shelf, mid peak and high shelf, in dB.
class InstrumentEq {
  InstrumentEq({this.lowDb = 0, this.midDb = 0, this.highDb = 0}) {
    _range(lowDb, -maxGainDb, maxGainDb, 'lowDb');
    _range(midDb, -maxGainDb, maxGainDb, 'midDb');
    _range(highDb, -maxGainDb, maxGainDb, 'highDb');
  }

  static const maxGainDb = 12.0;
  static const lowShelfHz = 200.0;
  static const midPeakHz = 1000.0;
  static const highShelfHz = 4000.0;

  final double lowDb;
  final double midDb;
  final double highDb;

  InstrumentEq copyWith({double? lowDb, double? midDb, double? highDb}) =>
      InstrumentEq(
        lowDb: lowDb ?? this.lowDb,
        midDb: midDb ?? this.midDb,
        highDb: highDb ?? this.highDb,
      );

  Map<String, Object> toJson() => {
    'lowDb': lowDb,
    'midDb': midDb,
    'highDb': highDb,
  };

  @override
  bool operator ==(Object other) =>
      other is InstrumentEq &&
      lowDb == other.lowDb &&
      midDb == other.midDb &&
      highDb == other.highDb;

  @override
  int get hashCode => Object.hash(lowDb, midDb, highDb);
}

class Instrument {
  /// Creates an instrument. Every value is validated here, so an existing
  /// [Instrument] is always renderable.
  Instrument({
    required this.id,
    required this.name,
    required List<double> harmonics,
    required this.attackMs,
    required this.decayMs,
    List<String> tags = const [],
    InstrumentEq? eq,
  }) : harmonics = List.unmodifiable(harmonics),
       tags = List.unmodifiable(tags),
       eq = eq ?? InstrumentEq() {
    if (!_idPattern.hasMatch(id)) throw ArgumentError.value(id, 'id');
    if (name.trim().isEmpty ||
        name.length > maxNameLength ||
        _controlCharacters.hasMatch(name)) {
      throw ArgumentError.value(name, 'name');
    }
    if (this.harmonics.isEmpty || this.harmonics.length > maxHarmonics) {
      throw ArgumentError.value(
        this.harmonics.length,
        'harmonics',
        'must have 1..$maxHarmonics entries',
      );
    }
    for (final amplitude in this.harmonics) {
      _range(amplitude, 0, 1, 'harmonics');
    }
    if (!this.harmonics.any((amplitude) => amplitude > 0)) {
      throw ArgumentError.value(harmonics, 'harmonics', 'must not be silent');
    }
    _range(attackMs, 0, maxAttackMs, 'attackMs');
    _range(decayMs, minDecayMs, maxDecayMs, 'decayMs');
    if (this.tags.length > maxTags) {
      throw ArgumentError.value(
        this.tags.length,
        'tags',
        'must have at most $maxTags entries',
      );
    }
    for (final tag in this.tags) {
      if (!_tagPattern.hasMatch(tag)) throw ArgumentError.value(tag, 'tags');
    }
    if (this.tags.toSet().length != this.tags.length) {
      throw ArgumentError.value(tags, 'tags', 'must not repeat');
    }
  }

  /// Parses and validates a recipe. Version 1 files (which stored a pitch)
  /// load too: the pitch is dropped and the tags are empty. Throws only
  /// [FormatException].
  factory Instrument.fromJson(Object? json) {
    try {
      if (json is! Map<String, dynamic>) {
        throw FormatException(r'$: expected an object');
      }
      if (!json.containsKey('version')) {
        throw FormatException(r'$.version: missing field');
      }
      final version = json['version'];
      if (version != 1 && version != schemaVersion) {
        throw FormatException(r'$.version: unsupported version');
      }
      final map = _object(json, r'$', version == 1 ? _keysV1 : _keys);
      final envelope = _object(map['envelope'], r'$.envelope', _envelopeKeys);
      final eq = _object(map['eq'], r'$.eq', _eqKeys);
      final harmonics = map['harmonics'];
      if (harmonics is! List<dynamic>) {
        throw FormatException(r'$.harmonics: expected a list');
      }
      if (version == 1) {
        // Still checked, so a damaged file is not accepted, but not kept.
        _number(map['fundamentalHz'], r'$.fundamentalHz');
      }
      final tags = version == 1 ? const <Object?>[] : map['tags'];
      if (tags is! List<dynamic>) {
        throw FormatException(r'$.tags: expected a list');
      }
      return Instrument(
        id: _string(map['id'], r'$.id'),
        name: _string(map['name'], r'$.name'),
        tags: [
          for (var i = 0; i < tags.length; i++) _string(tags[i], '\$.tags[$i]'),
        ],
        harmonics: [
          for (var i = 0; i < harmonics.length; i++)
            _number(harmonics[i], '\$.harmonics[$i]'),
        ],
        attackMs: _integer(envelope['attackMs'], r'$.envelope.attackMs'),
        decayMs: _integer(envelope['decayMs'], r'$.envelope.decayMs'),
        eq: InstrumentEq(
          lowDb: _number(eq['lowDb'], r'$.eq.lowDb'),
          midDb: _number(eq['midDb'], r'$.eq.midDb'),
          highDb: _number(eq['highDb'], r'$.eq.highDb'),
        ),
      );
    } on FormatException {
      rethrow;
    } on ArgumentError catch (error) {
      throw FormatException('${error.name ?? r'$'}: ${error.message}');
    }
  }

  /// Lowercases, trims and collapses spaces. Returns null when the result is
  /// not a valid tag (empty, too long, or with other characters).
  static String? normalizeTag(String raw) {
    final tag = raw.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    return _tagPattern.hasMatch(tag) ? tag : null;
  }

  static const schemaVersion = 2;
  static const maxNameLength = 40;
  static const maxTags = 6;
  static const maxHarmonics = 32;
  static const maxAttackMs = 500;
  static const minDecayMs = 20;
  static const maxDecayMs = 5000;

  static const _keys = {
    'version',
    'id',
    'name',
    'tags',
    'harmonics',
    'envelope',
    'eq',
  };
  static const _keysV1 = {
    'version',
    'id',
    'name',
    'fundamentalHz',
    'harmonics',
    'envelope',
    'eq',
  };
  static const _envelopeKeys = {'attackMs', 'decayMs'};
  static const _eqKeys = {'lowDb', 'midDb', 'highDb'};

  final String id;
  final String name;

  /// Lowercase labels to find the instrument again (click, bell, dark...).
  final List<String> tags;

  /// Amplitude 0..1 of each harmonic; index 0 is the fundamental.
  final List<double> harmonics;
  final int attackMs;
  final int decayMs;
  final InstrumentEq eq;

  Instrument copyWith({
    String? id,
    String? name,
    List<String>? tags,
    List<double>? harmonics,
    int? attackMs,
    int? decayMs,
    InstrumentEq? eq,
  }) => Instrument(
    id: id ?? this.id,
    name: name ?? this.name,
    tags: tags ?? this.tags,
    harmonics: harmonics ?? this.harmonics,
    attackMs: attackMs ?? this.attackMs,
    decayMs: decayMs ?? this.decayMs,
    eq: eq ?? this.eq,
  );

  Map<String, Object> toJson() => {
    'version': schemaVersion,
    'id': id,
    'name': name,
    'tags': tags,
    'harmonics': harmonics,
    'envelope': {'attackMs': attackMs, 'decayMs': decayMs},
    'eq': eq.toJson(),
  };

  @override
  bool operator ==(Object other) =>
      other is Instrument &&
      id == other.id &&
      name == other.name &&
      _sameStrings(tags, other.tags) &&
      _sameDoubles(harmonics, other.harmonics) &&
      attackMs == other.attackMs &&
      decayMs == other.decayMs &&
      eq == other.eq;

  @override
  int get hashCode => Object.hash(
    id,
    name,
    Object.hashAll(tags),
    Object.hashAll(harmonics),
    attackMs,
    decayMs,
    eq,
  );
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

double _number(Object? input, String path) {
  if (input is! num || !input.isFinite) {
    throw FormatException('$path: expected a finite number');
  }
  return input.toDouble();
}

int _integer(Object? input, String path) {
  if (input is! int) throw FormatException('$path: expected an integer');
  return input;
}

/// Tags offered as suggestions when saving. Any valid tag is allowed.
const suggestedInstrumentTags = [
  'click',
  'wood',
  'metal',
  'bell',
  'tone',
  'drum',
  'soft',
  'bright',
  'dark',
];

/// Starting points for a new instrument. The numbers are placeholders until
/// they are tuned by ear (`musical` gate).
final List<Instrument> factoryInstruments = List.unmodifiable([
  Instrument(
    id: 'factory-wood',
    name: 'Wood',
    tags: ['wood', 'click'],
    harmonics: [1, 0.55, 0.3, 0.15, 0.08, 0.04],
    attackMs: 1,
    decayMs: 70,
    eq: InstrumentEq(lowDb: -3, midDb: 2),
  ),
  Instrument(
    id: 'factory-sine',
    name: 'Sine',
    tags: ['tone', 'soft'],
    harmonics: [1],
    attackMs: 2,
    decayMs: 120,
  ),
  Instrument(
    id: 'factory-bell',
    name: 'Bell',
    tags: ['bell', 'metal', 'bright'],
    harmonics: [1, 0, 0.6, 0, 0.4, 0, 0.25, 0.12],
    attackMs: 1,
    decayMs: 900,
    eq: InstrumentEq(highDb: 3),
  ),
]);

/// A long, soft, nearly pure tone for ear training and the tuner's reference.
///
/// It is deliberately not in [factoryInstruments]: that list feeds the
/// randomizer pool, the library and the editor presets, which should keep
/// offering the percussive voices. The playback layer resolves it by id
/// (see [builtInInstruments]). The decay is the time to -60 dB, so a hit is
/// inaudible by about 3.5 s; the 2nd and 3rd harmonics are very soft so
/// stacked chord notes stay clear. The numbers are unproven by ear
/// (`musical` gate).
final Instrument sustainedToneInstrument = Instrument(
  id: 'factory-tone',
  name: 'Tone',
  tags: ['tone', 'soft'],
  harmonics: [1, 0.1, 0.05],
  attackMs: 30,
  decayMs: 3500,
);

/// Every instrument playback can resolve without the library: the factory
/// presets and [sustainedToneInstrument].
final List<Instrument> builtInInstruments = List.unmodifiable([
  ...factoryInstruments,
  sustainedToneInstrument,
]);
