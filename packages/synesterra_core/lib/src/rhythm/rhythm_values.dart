/// Values shared by the session document and later rhythm planning.
bool sameValues<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

void unitInterval(num value, String name) {
  if (!value.isFinite ||
      value < 0 ||
      value > 1 ||
      value == 0 && value.isNegative) {
    throw ArgumentError.value(value, name, 'must be finite and in 0..1');
  }
}

class Rational {
  Rational(this.numerator, this.denominator) {
    if (numerator < 1 ||
        numerator > 1024 ||
        denominator < 1 ||
        denominator > 32 ||
        numerator * 16 < denominator ||
        numerator > denominator * 32 ||
        _gcd(numerator, denominator) != 1) {
      throw ArgumentError('Rational must be canonical and in 1/16..32');
    }
  }

  final int numerator;
  final int denominator;

  num get value => numerator / denominator;

  Map<String, Object> toJson() => {
    'numerator': numerator,
    'denominator': denominator,
  };

  static int _gcd(int a, int b) {
    while (b != 0) {
      final next = a % b;
      a = b;
      b = next;
    }
    return a;
  }

  @override
  bool operator ==(Object other) =>
      other is Rational &&
      numerator == other.numerator &&
      denominator == other.denominator;
  @override
  int get hashCode => Object.hash(numerator, denominator);
}

class PatternStep {
  PatternStep({
    required this.enabled,
    required this.velocity,
    required this.accent,
    required this.probability,
  }) {
    unitInterval(velocity, 'velocity');
    unitInterval(probability, 'probability');
  }
  final bool enabled;
  final num velocity;
  final bool accent;
  final num probability;
  Map<String, Object> toJson() => {
    'enabled': enabled,
    'velocity': velocity,
    'accent': accent,
    'probability': probability,
  };
  @override
  bool operator ==(Object other) =>
      other is PatternStep &&
      enabled == other.enabled &&
      velocity == other.velocity &&
      accent == other.accent &&
      probability == other.probability;
  @override
  int get hashCode => Object.hash(enabled, velocity, accent, probability);
}

class Pattern {
  Pattern({required this.durationBeats, required List<PatternStep> steps})
    : steps = List.unmodifiable(steps) {
    if (steps.isEmpty ||
        steps.length > 32 ||
        durationBeats.numerator * 16 <
            durationBeats.denominator * steps.length) {
      throw ArgumentError(
        'Pattern requires 1..32 steps at density at least 1/16 beat',
      );
    }
  }
  final Rational durationBeats;
  final List<PatternStep> steps;
  Map<String, Object> toJson() => {
    'durationBeats': durationBeats.toJson(),
    'steps': steps.map((step) => step.toJson()).toList(),
  };
  @override
  bool operator ==(Object other) =>
      other is Pattern &&
      durationBeats == other.durationBeats &&
      sameValues(steps, other.steps);
  @override
  int get hashCode => Object.hash(durationBeats, Object.hashAll(steps));
}

class Swing {
  Swing({required this.grid, required this.amount}) {
    if (!const {'off', 'eighth', 'sixteenth'}.contains(grid)) {
      throw ArgumentError.value(grid, 'grid');
    }
    unitInterval(amount, 'amount');
    if (grid == 'off' && amount != 0) {
      throw ArgumentError('off swing requires zero amount');
    }
  }
  final String grid;
  final num amount;
  Map<String, Object> toJson() => {'grid': grid, 'amount': amount};
  @override
  bool operator ==(Object other) =>
      other is Swing && grid == other.grid && amount == other.amount;
  @override
  int get hashCode => Object.hash(grid, amount);
}

class LayerMix {
  LayerMix({
    required this.gain,
    required this.pan,
    required this.muted,
    required this.solo,
  }) {
    unitInterval(gain, 'gain');
    if (!pan.isFinite || pan < -1 || pan > 1 || pan == 0 && pan.isNegative) {
      throw ArgumentError.value(pan, 'pan');
    }
  }
  final num gain;
  final num pan;
  final bool muted;
  final bool solo;
  Map<String, Object> toJson() => {
    'gain': gain,
    'pan': pan,
    'muted': muted,
    'solo': solo,
  };
  @override
  bool operator ==(Object other) =>
      other is LayerMix &&
      gain == other.gain &&
      pan == other.pan &&
      muted == other.muted &&
      solo == other.solo;
  @override
  int get hashCode => Object.hash(gain, pan, muted, solo);
}

class RhythmLayer {
  RhythmLayer({
    required this.id,
    required this.sound,
    required this.pattern,
    required this.phaseSteps,
    required this.swing,
    required this.mix,
  }) {
    if (!RegExp(r'^[A-Za-z0-9-]{1,64}$').hasMatch(id)) {
      throw ArgumentError.value(id, 'id');
    }
    if (!const {'wood', 'sine', 'bell'}.contains(sound)) {
      throw ArgumentError.value(sound, 'sound');
    }
    if (phaseSteps < 0 || phaseSteps >= pattern.steps.length) {
      throw ArgumentError.value(phaseSteps, 'phaseSteps');
    }
    if (swing.grid != 'off') {
      final gridDenominator = swing.grid == 'eighth' ? 2 : 4;
      for (var index = 0; index < pattern.steps.length; index++) {
        if (!pattern.steps[index].enabled) continue;
        final numerator =
            pattern.durationBeats.numerator * index * gridDenominator;
        final denominator =
            pattern.durationBeats.denominator * pattern.steps.length;
        if (numerator % denominator != 0) {
          throw ArgumentError('Active step is not on swing grid');
        }
      }
    }
  }
  final String id;
  final String sound;
  final Pattern pattern;
  final int phaseSteps;
  final Swing swing;
  final LayerMix mix;
  Map<String, Object> toJson() => {
    'id': id,
    'sound': sound,
    'pattern': pattern.toJson(),
    'phaseSteps': phaseSteps,
    'swing': swing.toJson(),
    'mix': mix.toJson(),
  };
  @override
  bool operator ==(Object other) =>
      other is RhythmLayer &&
      id == other.id &&
      sound == other.sound &&
      pattern == other.pattern &&
      phaseSteps == other.phaseSteps &&
      swing == other.swing &&
      mix == other.mix;
  @override
  int get hashCode => Object.hash(id, sound, pattern, phaseSteps, swing, mix);
}
