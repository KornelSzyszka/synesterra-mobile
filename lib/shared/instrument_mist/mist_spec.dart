import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:synesterra_core/synesterra_core.dart';

/// One blurred blob of the mist: a single audible harmonic.
@immutable
class MistLobe {
  const MistLobe({
    required this.harmonic,
    required this.angle,
    required this.distance,
    required this.radius,
    required this.opacity,
  });

  /// Index in the recipe; 1 is the first overtone (0 is the core).
  final int harmonic;

  /// Radians, spread by the golden angle so lobes never line up.
  final double angle;

  /// 0..1 of the mist radius, from the centre.
  final double distance;

  /// 0..1 of the mist radius.
  final double radius;
  final double opacity;

  @override
  bool operator ==(Object other) =>
      other is MistLobe &&
      harmonic == other.harmonic &&
      angle == other.angle &&
      distance == other.distance &&
      radius == other.radius &&
      opacity == other.opacity;

  @override
  int get hashCode => Object.hash(harmonic, angle, distance, radius, opacity);
}

/// Everything the painter needs, computed from a recipe alone (no audio, no
/// FFT). The same recipe always gives the same spec, so it is unit-testable
/// and the picture reacts to every parameter.
@immutable
class MistSpec {
  const MistSpec({
    required this.pitchClass,
    required this.lobes,
    required this.coreRadius,
    required this.coreOpacity,
    required this.haloRadius,
    required this.haloOpacity,
    required this.attack,
    required this.decay,
  });

  /// 0..11, C is 0. Picks the colour from the theme's 12-colour palette.
  final int pitchClass;
  final List<MistLobe> lobes;

  /// Low EQ and the fundamental make the centre bigger and denser.
  final double coreRadius;
  final double coreOpacity;

  /// High EQ and strong upper harmonics widen the outer glow.
  final double haloRadius;
  final double haloOpacity;

  /// Length of the visual pulse, from the recipe's envelope.
  final Duration attack;
  final Duration decay;

  @override
  bool operator ==(Object other) =>
      other is MistSpec &&
      pitchClass == other.pitchClass &&
      listEquals(lobes, other.lobes) &&
      coreRadius == other.coreRadius &&
      coreOpacity == other.coreOpacity &&
      haloRadius == other.haloRadius &&
      haloOpacity == other.haloOpacity &&
      attack == other.attack &&
      decay == other.decay;

  @override
  int get hashCode => Object.hash(
    pitchClass,
    Object.hashAll(lobes),
    coreRadius,
    coreOpacity,
    haloRadius,
    haloOpacity,
    attack,
    decay,
  );
}

/// Harmonics weaker than this make no visible lobe.
const audibleHarmonic = 0.02;

const _goldenAngle = 2.399963229728653;

double _clamp(double value, double min, double max) =>
    value < min ? min : (value > max ? max : value);

MistSpec buildMistSpec(Instrument instrument) {
  final harmonics = instrument.harmonics;
  final eq = instrument.eq;
  final midScale = _clamp(1 + eq.midDb / 24, 0.5, 1.5);

  final lobes = <MistLobe>[
    for (var n = 1; n < harmonics.length; n++)
      if (harmonics[n] >= audibleHarmonic)
        MistLobe(
          harmonic: n,
          angle: (n * _goldenAngle) % (2 * math.pi),
          distance: 0.15 + 0.75 * math.sqrt(n / (Instrument.maxHarmonics - 1)),
          radius: 0.1 + 0.25 * math.sqrt(harmonics[n]),
          opacity: _clamp((0.25 + 0.6 * harmonics[n]) * midScale, 0, 1),
        ),
  ];

  var total = 0.0;
  var upper = 0.0;
  for (var n = 0; n < harmonics.length; n++) {
    total += harmonics[n];
    if (n >= 3) upper += harmonics[n];
  }
  final brightness = total == 0 ? 0.0 : upper / total;

  final pitchClass =
      (12 * math.log(instrument.fundamentalHz / 440) / math.ln2 + 69).round() %
      12;

  return MistSpec(
    pitchClass: pitchClass,
    lobes: lobes,
    coreRadius: _clamp(
      0.22 + 0.12 * harmonics[0] + eq.lowDb / 12 * 0.08,
      0,
      0.5,
    ),
    coreOpacity: _clamp(0.55 + eq.lowDb / 12 * 0.3, 0.2, 1),
    haloRadius: _clamp(0.85 + eq.highDb / 12 * 0.15, 0.6, 1),
    haloOpacity: _clamp(0.05 + 0.4 * brightness + eq.highDb / 12 * 0.1, 0, 0.7),
    attack: Duration(milliseconds: math.max(instrument.attackMs, 16)),
    decay: Duration(milliseconds: instrument.decayMs),
  );
}
