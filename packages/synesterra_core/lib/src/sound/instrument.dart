/// Sound recipes: what one rhythm voice sounds like.
///
/// An [Instrument] describes timbre only (pitch, harmonics, envelope, EQ). It
/// knows nothing about rhythm, tempo or the audio backend. A recipe is later
/// rendered into a buffer by the audio layer.
final _idPattern = RegExp(r'^[A-Za-z0-9-]{1,64}$');
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
    required this.fundamentalHz,
    required List<double> harmonics,
    required this.attackMs,
    required this.decayMs,
    InstrumentEq? eq,
  }) : harmonics = List.unmodifiable(harmonics),
       eq = eq ?? InstrumentEq() {
    if (!_idPattern.hasMatch(id)) throw ArgumentError.value(id, 'id');
    if (name.trim().isEmpty ||
        name.length > maxNameLength ||
        _controlCharacters.hasMatch(name)) {
      throw ArgumentError.value(name, 'name');
    }
    _range(fundamentalHz, minFundamentalHz, maxFundamentalHz, 'fundamentalHz');
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
  }

  /// Parses and validates a recipe. Throws only [FormatException].
  factory Instrument.fromJson(Object? json) {
    try {
      final map = _object(json, r'$', _keys);
      if (map['version'] != schemaVersion) {
        throw FormatException(r'$.version: unsupported version');
      }
      final envelope = _object(map['envelope'], r'$.envelope', _envelopeKeys);
      final eq = _object(map['eq'], r'$.eq', _eqKeys);
      final harmonics = map['harmonics'];
      if (harmonics is! List<dynamic>) {
        throw FormatException(r'$.harmonics: expected a list');
      }
      return Instrument(
        id: _string(map['id'], r'$.id'),
        name: _string(map['name'], r'$.name'),
        fundamentalHz: _number(map['fundamentalHz'], r'$.fundamentalHz'),
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

  static const schemaVersion = 1;
  static const maxNameLength = 40;
  static const minFundamentalHz = 40.0;
  static const maxFundamentalHz = 2000.0;
  static const maxHarmonics = 32;
  static const maxAttackMs = 500;
  static const minDecayMs = 20;
  static const maxDecayMs = 5000;

  static const _keys = {
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
  final double fundamentalHz;

  /// Amplitude 0..1 of each harmonic; index 0 is the fundamental.
  final List<double> harmonics;
  final int attackMs;
  final int decayMs;
  final InstrumentEq eq;

  Instrument copyWith({
    String? id,
    String? name,
    double? fundamentalHz,
    List<double>? harmonics,
    int? attackMs,
    int? decayMs,
    InstrumentEq? eq,
  }) => Instrument(
    id: id ?? this.id,
    name: name ?? this.name,
    fundamentalHz: fundamentalHz ?? this.fundamentalHz,
    harmonics: harmonics ?? this.harmonics,
    attackMs: attackMs ?? this.attackMs,
    decayMs: decayMs ?? this.decayMs,
    eq: eq ?? this.eq,
  );

  Map<String, Object> toJson() => {
    'version': schemaVersion,
    'id': id,
    'name': name,
    'fundamentalHz': fundamentalHz,
    'harmonics': harmonics,
    'envelope': {'attackMs': attackMs, 'decayMs': decayMs},
    'eq': eq.toJson(),
  };

  @override
  bool operator ==(Object other) =>
      other is Instrument &&
      id == other.id &&
      name == other.name &&
      fundamentalHz == other.fundamentalHz &&
      _sameDoubles(harmonics, other.harmonics) &&
      attackMs == other.attackMs &&
      decayMs == other.decayMs &&
      eq == other.eq;

  @override
  int get hashCode => Object.hash(
    id,
    name,
    fundamentalHz,
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

/// Starting points for a new instrument. The numbers are placeholders until
/// they are tuned by ear (`musical` gate).
final List<Instrument> factoryInstruments = List.unmodifiable([
  Instrument(
    id: 'factory-wood',
    name: 'Wood',
    fundamentalHz: 800,
    harmonics: [1, 0.55, 0.3, 0.15, 0.08, 0.04],
    attackMs: 1,
    decayMs: 70,
    eq: InstrumentEq(lowDb: -3, midDb: 2),
  ),
  Instrument(
    id: 'factory-sine',
    name: 'Sine',
    fundamentalHz: 660,
    harmonics: [1],
    attackMs: 2,
    decayMs: 120,
  ),
  Instrument(
    id: 'factory-bell',
    name: 'Bell',
    fundamentalHz: 1046,
    harmonics: [1, 0, 0.6, 0, 0.4, 0, 0.25, 0.12],
    attackMs: 1,
    decayMs: 900,
    eq: InstrumentEq(highDb: 3),
  ),
]);
