import 'dart:math';

import 'instrument.dart';

/// Instrument traits: a radar-chart view on the [Instrument] recipe.
///
/// A handful of plain-language traits, each from 0 (centre of the chart) to 1
/// (edge), describe a sound. [instrumentForTraits] turns them into an ordinary
/// [Instrument]; [traitsForInstrument] is an approximate inverse, so a saved or
/// factory instrument can be shown on the chart. The recipe and its JSON do not
/// change. The traits are data ([defaultTraitDefinitions]); the mapping reads
/// each trait's [TraitEffect], so an added trait drives its recipe field and a
/// removed one leaves that field neutral.
/// See `docs/modules/instrument.md` (Traits).

/// The ids of the default traits (any id may be used in a custom list).
abstract final class TraitIds {
  static const brightness = 'brightness';
  static const fullness = 'fullness';
  static const warmth = 'warmth';
  static const air = 'air';
  static const softness = 'softness';
  static const length = 'length';
}

/// The recipe field a trait drives. This is what makes a definition
/// data-driven: a new trait picks one of these effects and needs no code.
enum TraitEffect {
  /// Tilt of the harmonic amplitudes, dark (0) to bright (1).
  harmonicTilt,

  /// How many harmonics are present, 1..32.
  harmonicCount,

  /// Low shelf EQ gain, -12..+12 dB.
  lowShelf,

  /// High shelf EQ gain, -12..+12 dB.
  highShelf,

  /// Attack time, hard (0) to soft (1).
  attack,

  /// Decay time, short (0) to long (1).
  decay,
}

/// One axis of the radar chart: a stable [id], a user-facing English [label]
/// (localization comes later), the value on the neutral shape and the
/// recipe field it drives ([effect]).
class TraitDefinition {
  const TraitDefinition({
    required this.id,
    required this.label,
    required this.defaultValue,
    required this.effect,
  });

  final String id;
  final String label;

  /// 0..1.
  final double defaultValue;
  final TraitEffect effect;

  @override
  bool operator ==(Object other) =>
      other is TraitDefinition &&
      id == other.id &&
      label == other.label &&
      defaultValue == other.defaultValue &&
      effect == other.effect;

  @override
  int get hashCode => Object.hash(id, label, defaultValue, effect);
}

/// The default six traits (coordinator proposal, **untuned**; the Founder may
/// rename or change them). The order is the order around the chart.
const List<TraitDefinition> defaultTraitDefinitions = [
  TraitDefinition(
    id: TraitIds.brightness,
    label: 'Brightness',
    defaultValue: 0.5,
    effect: TraitEffect.harmonicTilt,
  ),
  TraitDefinition(
    id: TraitIds.fullness,
    label: 'Fullness',
    defaultValue: 0.5,
    effect: TraitEffect.harmonicCount,
  ),
  TraitDefinition(
    id: TraitIds.warmth,
    label: 'Warmth',
    defaultValue: 0.5,
    effect: TraitEffect.lowShelf,
  ),
  TraitDefinition(
    id: TraitIds.air,
    label: 'Air',
    defaultValue: 0.5,
    effect: TraitEffect.highShelf,
  ),
  TraitDefinition(
    id: TraitIds.softness,
    label: 'Softness',
    defaultValue: 0.5,
    effect: TraitEffect.attack,
  ),
  TraitDefinition(
    id: TraitIds.length,
    label: 'Length',
    defaultValue: 0.5,
    effect: TraitEffect.decay,
  ),
];

/// Immutable, validated trait values: one number 0..1 per definition.
class InstrumentTraits {
  /// Creates traits from [values]. An id without a definition throws an
  /// [ArgumentError], as does a value that is not finite or not in 0..1; an id
  /// left out takes its definition's default.
  InstrumentTraits(
    Map<String, double> values, {
    List<TraitDefinition> definitions = defaultTraitDefinitions,
  }) : definitions = List.unmodifiable(definitions),
       values = _validate(values, definitions);

  /// Every trait at its default value.
  factory InstrumentTraits.neutral({
    List<TraitDefinition> definitions = defaultTraitDefinitions,
  }) => InstrumentTraits(const {}, definitions: definitions);

  static Map<String, double> _validate(
    Map<String, double> values,
    List<TraitDefinition> definitions,
  ) {
    final known = <String>{};
    final effects = <TraitEffect>{};
    for (final definition in definitions) {
      if (!known.add(definition.id)) {
        throw ArgumentError.value(definition.id, 'definitions', 'repeated id');
      }
      if (!effects.add(definition.effect)) {
        throw ArgumentError.value(
          definition.effect,
          'definitions',
          'two traits drive the same effect',
        );
      }
      _checkValue(definition.id, definition.defaultValue);
    }
    for (final id in values.keys) {
      if (!known.contains(id)) {
        throw ArgumentError.value(id, 'values', 'unknown trait id');
      }
    }
    return Map.unmodifiable({
      for (final definition in definitions)
        definition.id: _checkValue(
          definition.id,
          values[definition.id] ?? definition.defaultValue,
        ),
    });
  }

  static double _checkValue(String id, double value) {
    if (!value.isFinite || value < 0 || value > 1) {
      throw ArgumentError.value(value, id, 'must be finite and in 0..1');
    }
    return value;
  }

  final List<TraitDefinition> definitions;

  /// Trait id to value, in the order of [definitions]. Unmodifiable.
  final Map<String, double> values;

  /// The value of [id]; throws an [ArgumentError] for an unknown id.
  double operator [](String id) {
    final value = values[id];
    if (value == null) throw ArgumentError.value(id, 'id', 'unknown trait id');
    return value;
  }

  /// The value of the trait that drives [effect], or null when no active
  /// definition has that effect.
  double? valueFor(TraitEffect effect) {
    for (final definition in definitions) {
      if (definition.effect == effect) return values[definition.id];
    }
    return null;
  }

  /// A copy with [changes] applied (validated like the constructor).
  InstrumentTraits withValues(Map<String, double> changes) =>
      InstrumentTraits({...values, ...changes}, definitions: definitions);

  @override
  bool operator ==(Object other) {
    if (other is! InstrumentTraits ||
        other.definitions.length != definitions.length) {
      return false;
    }
    for (var i = 0; i < definitions.length; i++) {
      if (other.definitions[i] != definitions[i]) return false;
    }
    for (final entry in values.entries) {
      if (other.values[entry.key] != entry.value) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    Object.hashAll(definitions),
    Object.hashAll([for (final d in definitions) values[d.id]]),
  );

  @override
  String toString() => 'InstrumentTraits($values)';
}

/// A named trait shape.
class TraitPreset {
  const TraitPreset(this.name, this.traits);

  final String name;
  final InstrumentTraits traits;
}

// ---------------------------------------------------------------------------
// Mapping constants. All **untuned**; tune by ear (`musical` gate).

/// Value used for an effect no active trait drives.
const double _neutralValue = 0.5;

/// Harmonic amplitude falls like `k^-slope` (k = 1 is the fundamental). The
/// slope runs from [_darkSlope] at brightness 0 to 0 (all harmonics equal) at
/// brightness 1.
const double _darkSlope = 2.0;

/// Harmonics weaker than this (relative to the strongest) count as absent when
/// measuring. At the darkest slope the 32nd harmonic is 32^-2 ~ 1e-3, so every
/// harmonic the forward mapping makes stays above it.
const double _presenceThreshold = 1e-4;

/// Attack: `attackMs = c * (exp(s * ln(1 + 500 / c)) - 1)`, rounded. The offset
/// `c` keeps one whole millisecond below ~0.008 of the softness range.
const double _attackOffsetMs = 20.0;

/// Below this fullness (fewer than about four harmonics) brightness is not
/// observable and reads as neutral.
const double _brightnessMinFullness = 0.1;

double _slope(double brightness) => _darkSlope * (1 - brightness);

/// Harmonic amplitudes for [brightness] and a real-valued harmonic count
/// [count] (1..32): the last partial harmonic fades in, which keeps the
/// mapping continuous in fullness.
List<double> _harmonics(double brightness, double count) {
  final slope = _slope(brightness);
  final length = count.ceil().clamp(1, Instrument.maxHarmonics);
  return [
    for (var k = 1; k <= length; k++)
      (count - (k - 1)).clamp(0.0, 1.0) * pow(k, -slope).toDouble(),
  ];
}

double _count(double fullness) => 1 + (Instrument.maxHarmonics - 1) * fullness;

double _centroid(List<double> harmonics) {
  var weighted = 0.0;
  var total = 0.0;
  for (final (i, amplitude) in harmonics.indexed) {
    weighted += (i + 1) * amplitude;
    total += amplitude;
  }
  return weighted / total;
}

/// Maps [traits] to a valid [Instrument].
///
/// - **Brightness**: harmonic `k` has amplitude `k^-slope`, the slope falling
///   linearly from 2 (dark) to 0 (every harmonic equal).
/// - **Fullness**: `1 + 31 * fullness` harmonics; the last, partial one fades
///   in, so a small change never makes a harmonic jump.
/// - **Warmth**: low shelf, `-12..+12 dB` linearly.
/// - **Air**: high shelf, `-12..+12 dB` linearly.
/// - **Softness**: attack 0..500 ms, exponential in the trait.
/// - **Length**: decay 20..5000 ms, exponential in the trait.
///
/// The mid EQ band stays at 0 dB. Deterministic, continuous (up to the whole
/// milliseconds of the recipe), monotonic in every trait with the others held
/// fixed, and always a valid, non-silent instrument: the fundamental is 1. A
/// trait missing from the definitions counts as 0.5. [id], [name] and [tags]
/// are validated by [Instrument].
Instrument instrumentForTraits(
  InstrumentTraits traits, {
  required String id,
  required String name,
  List<String> tags = const [],
}) {
  double value(TraitEffect effect) => traits.valueFor(effect) ?? _neutralValue;

  const gain = InstrumentEq.maxGainDb;
  final attack =
      _attackOffsetMs *
      (exp(
            value(TraitEffect.attack) *
                log(1 + Instrument.maxAttackMs / _attackOffsetMs),
          ) -
          1);
  final decay =
      Instrument.minDecayMs *
      pow(
        Instrument.maxDecayMs / Instrument.minDecayMs,
        value(TraitEffect.decay),
      );
  return Instrument(
    id: id,
    name: name,
    tags: tags,
    harmonics: _harmonics(
      value(TraitEffect.harmonicTilt),
      _count(value(TraitEffect.harmonicCount)),
    ),
    attackMs: attack.round().clamp(0, Instrument.maxAttackMs),
    decayMs: decay.round().clamp(Instrument.minDecayMs, Instrument.maxDecayMs),
    eq: InstrumentEq(
      lowDb: (value(TraitEffect.lowShelf) * 2 - 1) * gain,
      highDb: (value(TraitEffect.highShelf) * 2 - 1) * gain,
    ),
  );
}

/// Shows [instrument] on the radar: an approximate inverse of
/// [instrumentForTraits].
///
/// How each trait is measured (every value is clamped into 0..1):
///
/// - **Fullness**: the last harmonic above [_presenceThreshold] of the
///   strongest one gives the count; when it is the partial harmonic of the
///   forward mapping, its fraction is recovered from the measured slope.
/// - **Brightness**: the amplitude-weighted harmonic centroid
///   `sum(k * a_k) / sum(a_k)` is matched by bisection against the centroid the
///   forward mapping gives for the measured count. Below fullness 0.1 the
///   centroid barely moves, so brightness reads as 0.5.
/// - **Warmth** and **Air**: the low and high shelf gains over +-12 dB.
/// - **Softness**: the attack on the same exponential scale as the forward
///   mapping.
/// - **Length**: the decay on the same exponential scale.
///
/// Error bound (tested): for an instrument made by [instrumentForTraits], every
/// measured trait is within 0.02 of the original (worst measured case below).
/// Below fullness 0.1 (fewer than about four harmonics) brightness is not
/// observable and always reads 0.5; it is excluded from the bound there.
/// For other recipes (factory instruments, hand-drawn spectra) the result is
/// the nearest reading of each quantity, not a promise that
/// [instrumentForTraits] gives the same sound back. Each trait is
/// measured by its [TraitEffect], so renamed or added traits read back too.
InstrumentTraits traitsForInstrument(
  Instrument instrument, {
  List<TraitDefinition> definitions = defaultTraitDefinitions,
}) {
  final harmonics = instrument.harmonics;
  final peak = harmonics.reduce(max);
  final first = harmonics.first;

  var last = 1;
  for (var k = 1; k <= harmonics.length; k++) {
    if (harmonics[k - 1] > _presenceThreshold * peak) last = k;
  }
  // With two harmonics the slope is unknown, so the fade cannot be told from
  // the slope: take the middle of its range (error at most 0.5 / 31).
  var count = last == 2 ? 1.5 : last.toDouble();
  if (last >= 3 && first > 0) {
    // The forward mapping makes the last harmonic partial: undo its fade with
    // the slope read from the harmonic before it.
    final slope = (-log(harmonics[last - 2] / first) / log(last - 1)).clamp(
      0.0,
      _darkSlope,
    );
    final fade = (harmonics[last - 1] / first * pow(last, slope)).clamp(
      0.0,
      1.0,
    );
    count = last - 1 + fade;
  }
  final fullness = ((count - 1) / (Instrument.maxHarmonics - 1)).clamp(
    0.0,
    1.0,
  );

  var brightness = 0.5;
  if (fullness >= _brightnessMinFullness) {
    final target = _centroid(harmonics);
    var lo = 0.0;
    var hi = 1.0;
    for (var i = 0; i < 40; i++) {
      final mid = (lo + hi) / 2;
      if (_centroid(_harmonics(mid, count)) < target) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    brightness = (lo + hi) / 2;
  }

  const gain = InstrumentEq.maxGainDb;
  final measured = <TraitEffect, double>{
    TraitEffect.harmonicTilt: brightness,
    TraitEffect.harmonicCount: fullness,
    TraitEffect.lowShelf: (instrument.eq.lowDb / gain + 1) / 2,
    TraitEffect.highShelf: (instrument.eq.highDb / gain + 1) / 2,
    TraitEffect.attack:
        log(1 + instrument.attackMs / _attackOffsetMs) /
        log(1 + Instrument.maxAttackMs / _attackOffsetMs),
    TraitEffect.decay:
        log(instrument.decayMs / Instrument.minDecayMs) /
        log(Instrument.maxDecayMs / Instrument.minDecayMs),
  };
  return InstrumentTraits({
    for (final definition in definitions)
      definition.id: (measured[definition.effect]!).clamp(0.0, 1.0),
  }, definitions: definitions);
}

/// Named trait shapes: a neutral one and the five characters of the old pad.
/// **untuned**; the intent is dark soft long (`warm drone`), bright soft
/// (`airy pad`), dark hard (`bass`), bright hard (`guitar`) and hardest and
/// shortest (`click`).
final List<TraitPreset> traitPresets = List.unmodifiable([
  TraitPreset('neutral', InstrumentTraits.neutral()),
  TraitPreset(
    'warm drone',
    InstrumentTraits({
      TraitIds.brightness: 0.2,
      TraitIds.fullness: 0.1,
      TraitIds.warmth: 0.6,
      TraitIds.air: 0.25,
      TraitIds.softness: 0.9,
      TraitIds.length: 1.0,
    }),
  ),
  TraitPreset(
    'airy pad',
    InstrumentTraits({
      TraitIds.brightness: 0.6,
      TraitIds.fullness: 0.3,
      TraitIds.warmth: 0.4,
      TraitIds.air: 0.75,
      TraitIds.softness: 0.85,
      TraitIds.length: 0.95,
    }),
  ),
  TraitPreset(
    'bass',
    InstrumentTraits({
      TraitIds.brightness: 0.3,
      TraitIds.fullness: 0.15,
      TraitIds.warmth: 0.75,
      TraitIds.air: 0.25,
      TraitIds.softness: 0.1,
      TraitIds.length: 0.6,
    }),
  ),
  TraitPreset(
    'guitar',
    InstrumentTraits({
      TraitIds.brightness: 0.7,
      TraitIds.fullness: 0.35,
      TraitIds.warmth: 0.45,
      TraitIds.air: 0.6,
      TraitIds.softness: 0.0,
      TraitIds.length: 0.75,
    }),
  ),
  TraitPreset(
    'click',
    InstrumentTraits({
      TraitIds.brightness: 0.8,
      TraitIds.fullness: 0.3,
      TraitIds.warmth: 0.3,
      TraitIds.air: 0.75,
      TraitIds.softness: 0.0,
      TraitIds.length: 0.0,
    }),
  ),
]);
