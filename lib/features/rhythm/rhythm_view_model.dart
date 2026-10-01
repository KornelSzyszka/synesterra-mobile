import 'package:flutter/foundation.dart';

import '../../data/repositories/rhythm_settings_repository.dart';

class RhythmViewModel extends ChangeNotifier {
  RhythmViewModel({required RhythmSettingsRepository repository})
    : _repository = repository,
      _state = repository.read();

  final RhythmSettingsRepository _repository;
  RhythmSettings _state;

  RhythmSettings get state => _state;

  void setTempo(int bpm) {
    if (bpm < 20 || bpm > 300 || bpm == _state.tempoBpm) return;
    _save(_state.copyWith(tempoBpm: bpm));
  }

  void setLayerEnabled(int index, bool enabled) {
    if (index < 0 || index >= _state.layers.length) return;
    if (_state.layers[index].enabled == enabled) return;
    _updateLayer(index, _state.layers[index].copyWith(enabled: enabled));
  }

  void setLayerBeats(int index, int beats) {
    if (index < 0 || index >= _state.layers.length || beats < 1 || beats > 16) {
      return;
    }
    if (_state.layers[index].beatsPerCycle == beats) return;
    _updateLayer(index, _state.layers[index].copyWith(beatsPerCycle: beats));
  }

  void _updateLayer(int index, RhythmLayerSettings layer) {
    final layers = [..._state.layers];
    layers[index] = layer;
    _save(_state.copyWith(layers: layers));
  }

  void _save(RhythmSettings settings) {
    _repository.save(settings);
    _state = settings;
    notifyListeners();
  }
}
