import '../rhythm/rhythm_values.dart';

class Drone {
  Drone({
    required this.enabled,
    required this.root,
    required this.octave,
    required this.mode,
    required this.chord,
    required this.gain,
    required this.filterHz,
    required this.spread,
  }) {
    if (root < 0 || root > 11) throw ArgumentError.value(root, 'root');
    if (octave < 1 || octave > 5) throw ArgumentError.value(octave, 'octave');
    if (!const {'root', 'fifth', 'octave', 'triad'}.contains(chord)) {
      throw ArgumentError.value(chord, 'chord');
    }
    if (!filterHz.isFinite ||
        filterHz < 100 ||
        filterHz > 8000 ||
        filterHz == 0 && filterHz.isNegative) {
      throw ArgumentError.value(filterHz, 'filterHz');
    }
    unitInterval(gain, 'gain');
    unitInterval(spread, 'spread');
  }
  final bool enabled;
  final int root;
  final int octave;
  final String mode;
  final String chord;
  final num gain;
  final num filterHz;
  final num spread;
  Map<String, Object> toJson() => {
    'enabled': enabled,
    'root': root,
    'octave': octave,
    'mode': mode,
    'chord': chord,
    'gain': gain,
    'filterHz': filterHz,
    'spread': spread,
  };
  @override
  bool operator ==(Object other) =>
      other is Drone &&
      enabled == other.enabled &&
      root == other.root &&
      octave == other.octave &&
      mode == other.mode &&
      chord == other.chord &&
      gain == other.gain &&
      filterHz == other.filterHz &&
      spread == other.spread;
  @override
  int get hashCode =>
      Object.hash(enabled, root, octave, mode, chord, gain, filterHz, spread);
}
