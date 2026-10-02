/// Settings owned by the app until the session domain model is available.
class RhythmLayerSettings {
  RhythmLayerSettings({required this.enabled, required int beatsPerCycle})
    : beatsPerCycle = _validateBeats(beatsPerCycle);

  final bool enabled;
  final int beatsPerCycle;

  static int _validateBeats(int value) {
    if (value < 1 || value > 16) {
      throw RangeError.range(value, 1, 16, 'beatsPerCycle');
    }
    return value;
  }

  RhythmLayerSettings copyWith({bool? enabled, int? beatsPerCycle}) {
    return RhythmLayerSettings(
      enabled: enabled ?? this.enabled,
      beatsPerCycle: beatsPerCycle ?? this.beatsPerCycle,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is RhythmLayerSettings &&
        other.enabled == enabled &&
        other.beatsPerCycle == beatsPerCycle;
  }

  @override
  int get hashCode => Object.hash(enabled, beatsPerCycle);
}

class RhythmSettings {
  RhythmSettings({
    required int tempoBpm,
    required List<RhythmLayerSettings> layers,
  }) : tempoBpm = _validateTempo(tempoBpm),
       layers = List.unmodifiable(_validateLayers(layers));

  final int tempoBpm;
  final List<RhythmLayerSettings> layers;

  static int _validateTempo(int value) {
    if (value < 20 || value > 300) {
      throw RangeError.range(value, 20, 300, 'tempoBpm');
    }
    return value;
  }

  static List<RhythmLayerSettings> _validateLayers(
    List<RhythmLayerSettings> value,
  ) {
    if (value.length != 4) {
      throw ArgumentError.value(value.length, 'layers.length', 'Must be 4');
    }
    return value;
  }

  RhythmSettings copyWith({int? tempoBpm, List<RhythmLayerSettings>? layers}) {
    return RhythmSettings(
      tempoBpm: tempoBpm ?? this.tempoBpm,
      layers: layers ?? this.layers,
    );
  }

  @override
  bool operator ==(Object other) {
    if (other is! RhythmSettings ||
        other.tempoBpm != tempoBpm ||
        other.layers.length != layers.length) {
      return false;
    }
    for (var index = 0; index < layers.length; index++) {
      if (other.layers[index] != layers[index]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(tempoBpm, Object.hashAll(layers));
}

abstract class RhythmSettingsRepository {
  RhythmSettings read();
  void save(RhythmSettings settings);
}
