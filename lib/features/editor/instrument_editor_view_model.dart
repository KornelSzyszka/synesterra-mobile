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
  /// [instrument] null starts a new instrument from the `neutral` trait
  /// preset (every trait in the middle). A factory preset or a copy is passed
  /// with [existing] false and gets a fresh id, so presets are never
  /// overwritten. A library instrument is passed with [existing] true and
  /// keeps its id. An opened instrument is never changed until the user moves
  /// the radar (and stored only on Save); the radar shows its approximate
  /// traits ([traitsForInstrument]).
  InstrumentEditorViewModel({
    required this._repository,
    required this._audition,
    Instrument? instrument,
    bool existing = false,
    String Function()? newId,
  }) : _newId = newId ?? _defaultId {
    final draft = instrument == null
        // A brand-new instrument starts untagged on the neutral shape.
        ? instrumentForTraits(
            InstrumentTraits.neutral(),
            id: _newId(),
            name: 'New instrument',
          )
        : existing
        ? instrument
        // A copy of a preset keeps the preset's tags.
        : instrument.copyWith(id: _newId());
    _draft = draft;
    _baseline = draft;
    _persisted = existing;
    _name = draft.name;
    _brightness = fitBrightness(draft.harmonics);
    _readTraits();
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
  late InstrumentTraits _traits;
  late bool _approximated;
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
    // A pitch where no harmonic is below Nyquist would audition silence.
    if (!hasRenderableHarmonic(_draft, fundamentalHz: sound.rootHz)) return;
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

  /// The radar shape: one value 0..1 per trait.
  InstrumentTraits get traits => _traits;

  /// The shape is only an approximation of the current sound: the instrument
  /// was made another way (a factory sound, an older pad sound) and has not
  /// been moved on the radar yet. Moving any trait replaces the whole recipe
  /// with the mapped one, which clears this.
  bool get approximated => _approximated;

  /// The preset whose shape is the current one, if any (named to screen
  /// readers; the presets are not offered in the panel).
  TraitPreset? get activePreset {
    for (final preset in traitPresets) {
      if (preset.traits == _traits) return preset;
    }
    return null;
  }

  /// Sets trait [id] to [value] (clamped to 0..1) and replaces the recipe with
  /// the mapped one, keeping id, name and tags. Never plays sound; the radar
  /// calls [releaseTraits] when the finger lifts.
  void setTrait(String id, double value) {
    final next = _traits.withValues({id: _clampDouble(value, 0, 1)});
    if (next == _traits && !_approximated) return;
    _traits = next;
    _approximated = false;
    final mapped = instrumentForTraits(
      next,
      id: _draft.id,
      name: _draft.name,
      tags: _draft.tags,
    );
    _brightness = fitBrightness(mapped.harmonics);
    _edit((_) => mapped);
  }

  /// The finger left the radar: plays the sound once.
  void releaseTraits() => audition();

  /// Reads the radar shape from the draft after it was replaced from outside
  /// the radar (opened, copied, or edited with the technical controls).
  ///
  /// The inverse is approximate, so an instrument that sounds like a preset
  /// shows that preset's exact shape.
  void _readTraits() {
    Instrument mapped(InstrumentTraits traits) =>
        instrumentForTraits(traits, id: _draft.id, name: _draft.name);
    for (final preset in traitPresets) {
      if (_sameSound(_draft, mapped(preset.traits))) {
        _traits = preset.traits;
        _approximated = false;
        return;
      }
    }
    _traits = traitsForInstrument(_draft);
    _approximated = !_sameSound(_draft, mapped(_traits));
  }

  /// [a] and [b] sound the same for the radar note: the harmonics agree
  /// within 0.01, the times within a millisecond and the EQ within 0.1 dB. An
  /// instrument made on the radar reads back this closely unless it is very
  /// thin (below about four harmonics its brightness cannot be read back, see
  /// `traitsForInstrument`).
  static bool _sameSound(Instrument a, Instrument b) {
    final count = math.max(a.harmonics.length, b.harmonics.length);
    for (var k = 0; k < count; k++) {
      final x = k < a.harmonics.length ? a.harmonics[k] : 0.0;
      final y = k < b.harmonics.length ? b.harmonics[k] : 0.0;
      if ((x - y).abs() > 0.01) return false;
    }
    return (a.attackMs - b.attackMs).abs() <= 1 &&
        (a.decayMs - b.decayMs).abs() <= 1 &&
        (a.eq.lowDb - b.eq.lowDb).abs() <= 0.1 &&
        (a.eq.midDb - b.eq.midDb).abs() <= 0.1 &&
        (a.eq.highDb - b.eq.highDb).abs() <= 0.1;
  }

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
    _editSound((i) => i.copyWith(harmonics: next));
  }

  void setBrightness(double value) {
    _brightness = _clampDouble(value, 0, 1);
    _editSound(
      (i) => i.copyWith(harmonics: spectrum(harmonicCount, _brightness)),
    );
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
    if (!next.any((amplitude) => amplitude > 0) ||
        !hasRenderableHarmonic(
          _draft.copyWith(harmonics: next),
          fundamentalHz: testHz,
        )) {
      return;
    }
    _selectedHarmonic = _clampInt(
      select ?? changes.keys.last,
      0,
      next.length - 1,
    );
    _brightness = fitBrightness(next);
    _editSound((i) => i.copyWith(harmonics: next));
  }

  void setHarmonic(int index, double amplitude) =>
      setHarmonics({index: amplitude});

  /// Redraws every bar with one of the quick shapes, for the current count.
  void applySpectrumShape(SpectrumShape shape) {
    final next = shape.amplitudes(harmonicCount);
    _brightness = fitBrightness(next);
    _editSound((i) => i.copyWith(harmonics: next));
  }

  /// Sets attack and decay in one change, for the envelope graph.
  void setEnvelope(int attackMs, int decayMs) => _editSound(
    (i) => i.copyWith(
      attackMs: _clampInt(attackMs, 0, Instrument.maxAttackMs),
      decayMs: _clampInt(decayMs, Instrument.minDecayMs, Instrument.maxDecayMs),
    ),
  );

  void setAttackMs(int ms) => _editSound(
    (i) => i.copyWith(attackMs: _clampInt(ms, 0, Instrument.maxAttackMs)),
  );

  void setDecayMs(int ms) => _editSound(
    (i) => i.copyWith(
      decayMs: _clampInt(ms, Instrument.minDecayMs, Instrument.maxDecayMs),
    ),
  );

  void setEq({double? lowDb, double? midDb, double? highDb}) {
    double gain(double value) =>
        _clampDouble(value, -InstrumentEq.maxGainDb, InstrumentEq.maxGainDb);
    _editSound(
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
    _readTraits();
    _saveError = null;
    notifyListeners();
  }

  void _edit(Instrument Function(Instrument) change) {
    _draft = change(_draft);
    _changed();
  }

  /// An edit from the technical controls: the radar follows the new recipe.
  void _editSound(Instrument Function(Instrument) change) {
    _draft = change(_draft);
    _readTraits();
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
