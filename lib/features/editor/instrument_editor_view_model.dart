import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:synesterra_core/synesterra_core.dart';

import '../../data/repositories/instrument_audition_repository.dart';
import '../../data/repositories/instrument_library_repository.dart';
import 'test_sound.dart';

/// Edits one instrument. The draft is always a valid [Instrument]; only the
/// name can be temporarily invalid, and then saving is disabled.
class InstrumentEditorViewModel extends ChangeNotifier {
  /// [instrument] null starts a new instrument. A factory preset or a copy is
  /// passed with [existing] false and gets a fresh id, so presets are never
  /// overwritten. A library instrument is passed with [existing] true and
  /// keeps its id.
  InstrumentEditorViewModel({
    required this._repository,
    required this._audition,
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
            // A brand-new instrument starts untagged; a copy of a preset keeps
            // the preset's tags.
            tags: instrument == null ? const [] : source.tags,
          );
    _draft = draft;
    _baseline = draft;
    _persisted = existing;
    _name = draft.name;
    _brightness = fitBrightness(draft.harmonics);
  }

  final InstrumentLibraryRepository _repository;
  final InstrumentAuditionRepository _audition;
  final String Function() _newId;

  /// Dragging a slider fires many changes; the sound is played once, shortly
  /// after the last one.
  static const auditionDelay = Duration(milliseconds: 150);

  Timer? _auditionTimer;
  int _auditionCount = 0;
  TestSound _testSound = TestSound.defaultNote;

  late Instrument _draft;
  late Instrument _baseline;
  late bool _persisted;
  late String _name;
  late double _brightness;
  int _selectedHarmonic = 0;
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

  /// What is played to test the instrument: a note or a chord. It is not part
  /// of the instrument, so changing it never marks the instrument as changed
  /// and it is not saved.
  TestSound get testSound => _testSound;

  /// The root frequency of the test sound.
  double get testHz => _testSound.rootHz;

  void setTestSound(TestSound sound) {
    if (sound == _testSound) return;
    _testSound = sound;
    notifyListeners();
    auditionSoon();
  }

  /// Tags are part of the instrument and are saved with it.
  List<String> get tags => _draft.tags;

  bool get canAddTag => _draft.tags.length < Instrument.maxTags;

  /// Adds a tag after normalizing it. Returns false when it is not a valid
  /// tag, is already there, or the instrument already has the most it can.
  bool addTag(String raw) {
    final tag = Instrument.normalizeTag(raw);
    if (tag == null || _draft.tags.contains(tag) || !canAddTag) return false;
    _edit((i) => i.copyWith(tags: [...i.tags, tag]));
    return true;
  }

  void removeTag(String tag) {
    if (!_draft.tags.contains(tag)) return;
    _edit(
      (i) => i.copyWith(
        tags: [
          for (final t in i.tags)
            if (t != tag) t,
        ],
      ),
    );
  }

  /// Counts audition requests; the mist pulses when it changes, so the
  /// picture and the sound start from the same tap.
  int get auditionCount => _auditionCount;

  /// False when the engine could not start or play.
  ValueListenable<bool> get soundAvailable => _audition.available;

  /// Plays the instrument now. Only ever called from a user gesture.
  void audition() {
    _auditionTimer?.cancel();
    _auditionCount++;
    notifyListeners();
    unawaited(_audition.play(_draft, _testSound.frequenciesHz));
  }

  /// Plays the instrument once the controls have been still for a moment.
  void auditionSoon() {
    _auditionTimer?.cancel();
    _auditionTimer = Timer(auditionDelay, audition);
  }

  @override
  void dispose() {
    _auditionTimer?.cancel();
    super.dispose();
  }

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

  /// Changes how many harmonics there are. The bars already drawn are kept;
  /// new bars continue the brightness curve, removed bars are cut off.
  void setHarmonicCount(int count) {
    final clamped = _clampInt(count, 1, Instrument.maxHarmonics);
    final old = _draft.harmonics;
    final slope = 3 * (1 - _brightness);
    final next = [
      for (var n = 0; n < clamped; n++)
        n < old.length ? old[n] : math.pow(n + 1, -slope).toDouble(),
    ];
    // Cutting off every bar that had sound would leave silence.
    if (!next.any((amplitude) => amplitude > 0)) next[0] = 1;
    _selectedHarmonic = _clampInt(_selectedHarmonic, 0, clamped - 1);
    _edit((i) => i.copyWith(harmonics: next));
  }

  void setBrightness(double value) {
    _brightness = _clampDouble(value, 0, 1);
    _edit((i) => i.copyWith(harmonics: spectrum(harmonicCount, _brightness)));
  }

  /// The harmonic (0-based) the user touched last; the editor shows it for
  /// fine tuning.
  int get selectedHarmonic =>
      _clampInt(_selectedHarmonic, 0, harmonicCount - 1);

  void selectHarmonic(int index) {
    final clamped = _clampInt(index, 0, harmonicCount - 1);
    if (clamped == _selectedHarmonic) return;
    _selectedHarmonic = clamped;
    notifyListeners();
  }

  /// Sets harmonics by index to amplitudes 0..1, in one change, and selects
  /// [select] (default: the last index given). A change that would make every
  /// harmonic 0 is ignored, so the instrument can never go silent. Never
  /// plays sound by itself.
  void setHarmonics(Map<int, double> changes, {int? select}) {
    if (changes.isEmpty) return;
    final next = [..._draft.harmonics];
    for (final entry in changes.entries) {
      if (entry.key < 0 || entry.key >= next.length) continue;
      next[entry.key] = _clampDouble(entry.value, 0, 1);
    }
    if (!next.any((amplitude) => amplitude > 0)) return;
    _selectedHarmonic = _clampInt(
      select ?? changes.keys.last,
      0,
      next.length - 1,
    );
    _brightness = fitBrightness(next);
    _edit((i) => i.copyWith(harmonics: next));
  }

  void setHarmonic(int index, double amplitude) =>
      setHarmonics({index: amplitude});

  /// Redraws every bar with one of the quick shapes, for the current count.
  void applySpectrumShape(SpectrumShape shape) {
    final next = shape.amplitudes(harmonicCount);
    _brightness = fitBrightness(next);
    _edit((i) => i.copyWith(harmonics: next));
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

/// Quick shapes for the spectrum. Amplitudes are 1/n^k, the classic
/// waveforms of additive synthesis.
enum SpectrumShape {
  sine('Sine'),
  saw('Saw'),
  square('Square'),
  soft('Soft');

  const SpectrumShape(this.label);

  final String label;

  /// The amplitude of each of [count] harmonics for this shape.
  List<double> amplitudes(int count) => [
    for (var n = 1; n <= count; n++)
      switch (this) {
        SpectrumShape.sine => n == 1 ? 1.0 : 0.0,
        SpectrumShape.saw => 1 / n,
        SpectrumShape.square => n.isOdd ? 1 / n : 0.0,
        SpectrumShape.soft => 1 / (n * n),
      },
  ];
}
