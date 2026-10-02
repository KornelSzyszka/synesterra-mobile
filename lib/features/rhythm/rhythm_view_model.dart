import 'package:flutter/foundation.dart';

import '../../data/repositories/rhythm_settings_repository.dart';

class RhythmCommand<T> extends ChangeNotifier {
  RhythmCommand(this._action);

  final Future<void> Function(T value) _action;
  bool _isRunning = false;
  Object? _error;

  bool get isRunning => _isRunning;
  Object? get error => _error;

  Future<void> execute(T value) async {
    if (_isRunning) return;
    _isRunning = true;
    _error = null;
    notifyListeners();
    try {
      await _action(value);
    } catch (error) {
      _error = error;
      rethrow;
    } finally {
      _isRunning = false;
      notifyListeners();
    }
  }
}

class RhythmViewModel extends ChangeNotifier {
  RhythmViewModel({required RhythmSettingsRepository repository})
    : _repository = repository,
      _state = repository.read() {
    setTempo = RhythmCommand<int>(_setTempo);
    setLayerEnabled = RhythmCommand<RhythmLayerEnabledCommand>(
      _setLayerEnabled,
    );
    setLayerBeats = RhythmCommand<RhythmLayerBeatsCommand>(_setLayerBeats);
  }

  final RhythmSettingsRepository _repository;
  RhythmSettings _state;
  late final RhythmCommand<int> setTempo;
  late final RhythmCommand<RhythmLayerEnabledCommand> setLayerEnabled;
  late final RhythmCommand<RhythmLayerBeatsCommand> setLayerBeats;

  RhythmSettings get state => _state;

  Future<void> _setTempo(int bpm) async {
    if (bpm < 20 || bpm > 300 || bpm == _state.tempoBpm) return;
    _save(_state.copyWith(tempoBpm: bpm));
  }

  Future<void> _setLayerEnabled(RhythmLayerEnabledCommand command) async {
    final index = command.index;
    final enabled = command.enabled;
    if (index < 0 || index >= _state.layers.length) return;
    if (_state.layers[index].enabled == enabled) return;
    _updateLayer(index, _state.layers[index].copyWith(enabled: enabled));
  }

  Future<void> _setLayerBeats(RhythmLayerBeatsCommand command) async {
    final index = command.index;
    final beats = command.beats;
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

  @override
  void dispose() {
    setTempo.dispose();
    setLayerEnabled.dispose();
    setLayerBeats.dispose();
    super.dispose();
  }
}

class RhythmLayerEnabledCommand {
  const RhythmLayerEnabledCommand(this.index, this.enabled);
  final int index;
  final bool enabled;
}

class RhythmLayerBeatsCommand {
  const RhythmLayerBeatsCommand(this.index, this.beats);
  final int index;
  final int beats;
}
