import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:synesterra_core/synesterra_core.dart';

import '../../data/repositories/instrument_library_repository.dart';

/// Edits one instrument. The draft is always a valid [Instrument]; only the
/// name can be temporarily invalid, and then saving is disabled.
class InstrumentEditorViewModel extends ChangeNotifier {
  /// [instrument] null starts a new instrument. A factory preset or a copy is
  /// passed with [existing] false and gets a fresh id, so presets are never
  /// overwritten. A library instrument is passed with [existing] true and
  /// keeps its id.
  InstrumentEditorViewModel({
    required this._repository,
    Instrument? instrument,
    bool existing = false,
    String Function()? newId,
  }) : _newId = newId ?? _defaultId {
    final source = instrument ?? factoryInstruments[1];
    final draft = existing
        ? source
        : source.copyWith(
            id: _newId(),
            name: instrument == null ? 'New instrument' : source.name,
          );
    _draft = draft;
    _baseline = draft;
    _persisted = existing;
    _name = draft.name;
    _brightness = fitBrightness(draft.harmonics);
  }

  final InstrumentLibraryRepository _repository;
  final String Function() _newId;

  late Instrument _draft;
  late Instrument _baseline;
  late bool _persisted;
  late String _name;
  late double _brightness;
  bool _saving = false;
  String? _saveError;

  static String _defaultId() =>
      'inst-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}-'
      '${math.Random().nextInt(1 << 20).toRadixString(36)}';

  /// The recipe as edited. Its name is the last valid name.
  Instrument get instrument => _draft;

  /// The text in the name field, valid or not.
  String get name => _name;

  /// 0..1: how strongly higher harmonics sound.
  double get brightness => _brightness;
  int get harmonicCount => _draft.harmonics.length;
  bool get saving => _saving;
  String? get saveError => _saveError;

  bool get nameValid => _tryName(_name) != null;

  /// There is something to lose when leaving.
  bool get dirty => _draft != _baseline || _name != _baseline.name;

  /// A new instrument can be saved as it is; a saved one only after a change.
  bool get canSave => nameValid && !_saving && (dirty || !_persisted);

  Instrument? _tryName(String name) {
    try {
      return _draft.copyWith(name: name);
    } on ArgumentError {
      return null;
    }
  }

  void setName(String name) {
    if (name == _name) return;
    _name = name;
    final valid = _tryName(name);
    if (valid != null) _draft = valid;
    _changed();
  }

  void setPitchHz(double hz) => _edit(
    (i) => i.copyWith(
      fundamentalHz: _clampDouble(
        hz,
        Instrument.minFundamentalHz,
        Instrument.maxFundamentalHz,
      ),
    ),
  );

  void setHarmonicCount(int count) {
    final clamped = _clampInt(count, 1, Instrument.maxHarmonics);
    _edit((i) => i.copyWith(harmonics: spectrum(clamped, _brightness)));
  }

  void setBrightness(double value) {
    _brightness = _clampDouble(value, 0, 1);
    _edit((i) => i.copyWith(harmonics: spectrum(harmonicCount, _brightness)));
  }

  void setAttackMs(int ms) => _edit(
    (i) => i.copyWith(attackMs: _clampInt(ms, 0, Instrument.maxAttackMs)),
  );

  void setDecayMs(int ms) => _edit(
    (i) => i.copyWith(
      decayMs: _clampInt(ms, Instrument.minDecayMs, Instrument.maxDecayMs),
    ),
  );

  void setEq({double? lowDb, double? midDb, double? highDb}) {
    double gain(double value) =>
        _clampDouble(value, -InstrumentEq.maxGainDb, InstrumentEq.maxGainDb);
    _edit(
      (i) => i.copyWith(
        eq: i.eq.copyWith(
          lowDb: lowDb == null ? null : gain(lowDb),
          midDb: midDb == null ? null : gain(midDb),
          highDb: highDb == null ? null : gain(highDb),
        ),
      ),
    );
  }

  /// Replaces the draft with a copy of [preset] under a new id.
  void startFrom(Instrument preset) {
    _draft = preset.copyWith(id: _newId());
    _baseline = _draft;
    _persisted = false;
    _name = _draft.name;
    _brightness = fitBrightness(_draft.harmonics);
    _saveError = null;
    notifyListeners();
  }

  void _edit(Instrument Function(Instrument) change) {
    _draft = change(_draft);
    _changed();
  }

  void _changed() {
    _saveError = null;
    notifyListeners();
  }

  /// Returns true when the instrument is stored. On failure nothing is
  /// reported as saved, the draft stays and [saveError] says so.
  Future<bool> save() async {
    if (!canSave) return false;
    _saving = true;
    _saveError = null;
    notifyListeners();
    try {
      final saved = _draft.copyWith(name: _name);
      await _repository.save(saved);
      _draft = saved;
      _baseline = saved;
      _persisted = true;
      return true;
    } on Exception {
      _saveError = 'Could not save. Try again.';
      return false;
    } finally {
      _saving = false;
      notifyListeners();
    }
  }

  /// A power-law spectrum: harmonic n has amplitude `n^-slope`. Brightness 1
  /// gives equal amplitudes (harsh), 0 gives a nearly pure tone.
  static List<double> spectrum(int count, double brightness) {
    final slope = 3 * (1 - brightness);
    return [for (var n = 1; n <= count; n++) math.pow(n, -slope).toDouble()];
  }

  /// The brightness whose power-law spectrum best matches [harmonics],
  /// judged from the first overtone. A spectrum that is not a power law is
  /// replaced when the user moves a harmonic control.
  static double fitBrightness(List<double> harmonics) {
    if (harmonics.length < 2 || harmonics[0] <= 0 || harmonics[1] <= 0) {
      return 0.5;
    }
    final slope = -math.log(harmonics[1] / harmonics[0]) / math.ln2;
    return _clampDouble(1 - slope / 3, 0, 1);
  }
}

double _clampDouble(double value, double min, double max) =>
    value < min ? min : (value > max ? max : value);

int _clampInt(int value, int min, int max) =>
    value < min ? min : (value > max ? max : value);
