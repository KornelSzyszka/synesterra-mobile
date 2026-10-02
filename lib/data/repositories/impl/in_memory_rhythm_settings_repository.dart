import '../rhythm_settings_repository.dart';

class InMemoryRhythmSettingsRepository implements RhythmSettingsRepository {
  RhythmSettings _settings = RhythmSettings(
    tempoBpm: 120,
    layers: [
      RhythmLayerSettings(enabled: true, beatsPerCycle: 4),
      RhythmLayerSettings(enabled: false, beatsPerCycle: 3),
      RhythmLayerSettings(enabled: false, beatsPerCycle: 5),
      RhythmLayerSettings(enabled: false, beatsPerCycle: 7),
    ],
  );

  @override
  RhythmSettings read() => _settings;

  @override
  void save(RhythmSettings settings) => _settings = settings;
}
