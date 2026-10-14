import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:synesterra_core/synesterra_core.dart';

import '../../data/repositories/instrument_library_repository.dart';
import '../../data/repositories/library_item.dart';
import '../../data/repositories/loop.dart';
import '../../data/repositories/loop_library_repository.dart';
import '../../data/repositories/playback_repository.dart';
import 'loop_edits.dart' as edits;

/// Edits one loop in the Loop panel, saves it to the loop library and plays
/// it through the playback repository.
///
/// Every edit is a pure function from `loop_edits.dart`, so scenes A and B
/// change together. While this panel's loop plays, each edit is sent with
/// [PlaybackRepository.play]; the repository decides what it means: a volume
/// or on/off change applies to the next planned hits, a tempo change keeps
/// the phase, anything else restarts from the start of the cycle. The view
/// model never touches the transport state itself.
class LoopEditorViewModel extends ChangeNotifier {
  /// [loop] null starts from a copy of the first factory loop. A factory loop
  /// or any loop with [existing] false is edited as an unsaved copy; one of
  /// the user's loops with [existing] true keeps its id and is saved in
  /// place.
  LoopEditorViewModel({
    required this._library,
    required this._instruments,
    required this._playback,
    Loop? loop,
    bool existing = false,
    int? firstRollSeed,
    Duration Function()? clock,
  }) : _nextRollSeed = firstRollSeed ?? math.Random().nextInt(1 << 32),
       _clock = clock ?? _stopwatchClock() {
    checkRandomSeed(_nextRollSeed, 'firstRollSeed');
    _load(loop ?? factoryLoops.first, existing: existing);
    _instruments.snapshot.addListener(notifyListeners);
    _playback.status.addListener(_onStatus);
  }

  final LoopLibraryRepository _library;
  final InstrumentLibraryRepository _instruments;
  final PlaybackRepository _playback;

  late Loop _baseline;
  late SessionDocument _document;
  late String _name;
  late bool _persisted;

  /// Increments whenever another loop is loaded. A save belongs to the
  /// session that started it; when it finishes after another loop was
  /// opened, it must not mark or rename the loop now being edited.
  int _session = 0;

  /// The session whose save is running, if any.
  int? _savingSession;
  String? _saveError;

  /// True from this panel's Play until Stop, or until something else (the
  /// Arrangement panel's sequence, an engine stop) takes the transport.
  bool _owned = false;
  bool _disposed = false;

  void _load(Loop source, {required bool existing}) {
    _session++;
    final keep = existing && !isFactoryId(source.id);
    final copy = keep ? source : source.copyAsNew();
    // The panel edits scene A and writes B as its copy. A stored loop whose
    // B differs (valid for the parser) is aligned here, so the picture, the
    // controls and playback all show the same scene. The file changes only
    // on the next save.
    final loop = copy.copyWith(
      document: edits.withTitle(copy.document, copy.document.title),
    );
    _baseline = loop;
    _document = loop.document;
    _name = loop.name;
    _persisted = keep;
    _saveError = null;
    _beforeRolls.clear();
    _tapTempo.reset();
  }

  /// The loop as edited, under the last valid name.
  Loop get loop => Loop(
    id: _baseline.id,
    name: nameValid ? _name.trim() : _baseline.name,
    document: _document,
  );

  SessionDocument get document => _document;

  /// The text in the name field, valid or not.
  String get name => _name;
  bool get nameValid => isValidLibraryName(_name.trim());

  /// Saved in the library (a copy is not, until its first save).
  bool get persisted => _persisted;
  bool get saving => _savingSession == _session;
  String? get saveError => _saveError;

  /// There is something to lose when leaving.
  bool get dirty =>
      _document != _baseline.document || _name.trim() != _baseline.name;

  /// A copy can be saved as it is; a saved loop only after a change.
  bool get canSave => nameValid && !saving && (dirty || !_persisted);

  void setName(String name) {
    if (name == _name) return;
    _name = name;
    notifyListeners();
  }

  /// Saves under the current name. Returns false when nothing was saved.
  Future<bool> save() async {
    if (!canSave) return false;
    final name = _name.trim();
    final saved = Loop(
      id: _baseline.id,
      name: name,
      document: edits.withTitle(_document, name),
    );
    final documentAtSave = _document;
    final session = _session;
    final rollsAtSave = _rolls;
    _savingSession = session;
    _saveError = null;
    notifyListeners();
    try {
      await _library.save(saved);
      // Another loop was opened meanwhile: the save stands for the loop
      // that started it, and the open loop keeps its own identity.
      if (session != _session) return true;
      _baseline = saved;
      // Edits made during the write are kept; they then differ from the
      // saved baseline, so the loop shows as changed and can be saved again.
      _document = _document == documentAtSave
          ? saved.document
          : edits.withTitle(_document, name);
      _persisted = true;
      // Only rolls made before the save began; a roll made while it ran is
      // not in the saved loop and stays undoable.
      _beforeRolls.removeWhere((entry) => entry.$1 <= rollsAtSave);
      return true;
    } catch (_) {
      if (session == _session) {
        _saveError = 'Could not save the loop. Try again.';
      }
      return false;
    } finally {
      if (_savingSession == session) _savingSession = null;
      if (!_disposed) notifyListeners();
    }
  }

  /// Replaces the loop being edited (see the constructor for [existing]).
  /// A loop that is playing switches to the new one.
  void open(Loop loop, {required bool existing}) {
    _load(loop, existing: existing);
    notifyListeners();
    if (playing) _send();
  }

  /// The user's saved loops, for opening another one.
  List<Loop> get savedLoops => _library.snapshot.value.items;

  // Layers.

  int get layerCount => edits.loopLayerCount(_document);
  RhythmLayer layer(int index) => edits.loopLayer(_document, index);
  int get cycleBeats => _document.transport.practiceCycleBeats.numerator;
  int get tempo => _document.transport.bpm.round();
  int get maxSteps => edits.maxStepsForCycle(cycleBeats);
  bool get canAddLayer => layerCount < edits.maxLoopLayers;
  bool get canRemoveLayer => layerCount > edits.minLoopLayers;

  /// Factory instruments first, then the user's.
  List<Instrument> get availableInstruments => [
    ...factoryInstruments,
    ..._instruments.snapshot.value.instruments,
  ];

  /// The instrument with [id], or null when it is missing (it then plays
  /// silence and the panel says "missing sound").
  Instrument? instrumentFor(String id) {
    for (final instrument in availableInstruments) {
      if (instrument.id == id) return instrument;
    }
    return null;
  }

  bool isMissing(int index) => instrumentFor(layer(index).instrumentId) == null;

  void setLayerOn(int index, bool on) =>
      _apply(edits.setLayerOn(_document, index, on));
  void setLayerInstrument(int index, String instrumentId) =>
      _apply(edits.setLayerInstrument(_document, index, instrumentId));
  void setLayerPitch(int index, int pitch) {
    if (pitch < minLayerPitch || pitch > maxLayerPitch) return;
    _apply(edits.setLayerPitch(_document, index, pitch));
  }

  void setLayerSteps(int index, int count) {
    if (count < 1 || count > maxSteps) return;
    _apply(edits.setLayerSteps(_document, index, count));
  }

  void toggleStep(int index, int step) =>
      _apply(edits.toggleStep(_document, index, step));

  /// [volume] 0..1, rounded to hundredths to keep files tidy.
  void setLayerVolume(int index, double volume) => _apply(
    edits.setLayerVolume(
      _document,
      index,
      (volume.clamp(0, 1) * 100).round() / 100,
    ),
  );

  void setTempo(int bpm) {
    if (bpm < edits.minLoopTempo || bpm > edits.maxLoopTempo) return;
    _apply(edits.setLoopTempo(_document, bpm));
  }

  // Tap tempo.

  /// The time of a tap. The core calculator reads no clock; this is the
  /// panel's (a stopwatch, so wall-clock changes cannot disturb it).
  final Duration Function() _clock;

  static Duration Function() _stopwatchClock() {
    final stopwatch = Stopwatch()..start();
    return () => stopwatch.elapsed;
  }

  final TapTempo _tapTempo = TapTempo(
    minBpm: edits.minLoopTempo,
    maxBpm: edits.maxLoopTempo,
  );

  /// One tap of the tempo button: from the third tap in a row (taps less
  /// than two seconds apart) the tempo follows the average interval.
  void tapTempo() {
    final bpm = _tapTempo.tap(_clock());
    if (bpm != null) setTempo(bpm);
  }

  void setCycleBeats(int beats) {
    if (beats < edits.minLoopCycleBeats || beats > edits.maxLoopCycleBeats) {
      return;
    }
    _apply(edits.setCycleBeats(_document, beats));
  }

  void addLayer() {
    if (canAddLayer) _apply(edits.addLoopLayer(_document));
  }

  void removeLayer(int index) {
    if (canRemoveLayer) _apply(edits.removeLoopLayer(_document, index));
  }

  // Randomize.

  /// The seed of the next roll; each roll takes the next one (uint32, so it
  /// wraps). Random per panel unless given, which makes tests exact.
  int _nextRollSeed;

  /// The document just before each roll, the last roll last. Kept through
  /// other edits, so a roll never loses unsaved work; cleared on save and
  /// when another loop is opened (a save clears only the rolls made before
  /// it began). Each entry is numbered by [_rolls].
  final List<(int, SessionDocument)> _beforeRolls = [];

  /// How many rolls this panel has made.
  int _rolls = 0;

  bool get canUndoRandomize => _beforeRolls.isNotEmpty;

  /// Replaces the loop with a random one from the core generator
  /// (docs/modules/randomizer.md), drawn from the factory instruments and
  /// mine. It is an unsaved change like any edit: the id and the name stay,
  /// nothing starts playing, and a loop that plays restarts with it.
  void randomize() {
    final seed = _nextRollSeed;
    _nextRollSeed = (seed + 1) & maxRandomSeed;
    _beforeRolls.add((++_rolls, _document));
    final next = randomLoopDocument(
      seed: seed,
      instrumentIds: [
        for (final instrument in availableInstruments) instrument.id,
      ],
      title: _document.title,
    );
    if (next == _document) {
      notifyListeners();
    } else {
      _apply(next);
    }
  }

  /// Back to the exact document from just before the last roll (edits made
  /// after it are undone with it). Repeated, it steps back through every
  /// roll to the loop as it was before the first one.
  void undoRandomize() {
    if (_beforeRolls.isEmpty) return;
    // The title follows the loop as it is now: a save that finished after
    // the roll renamed it, and the snapshot must not bring the old name back
    // (then a restored saved loop is not "changed").
    final (_, snapshot) = _beforeRolls.removeLast();
    final before = edits.withTitle(snapshot, _document.title);
    if (before == _document) {
      notifyListeners();
    } else {
      _apply(before);
    }
  }

  void _apply(SessionDocument next) {
    if (next == _document) return;
    _document = next;
    notifyListeners();
    if (playing) _send();
  }

  // Transport.

  PlaybackStatus get _status => _playback.status.value;

  /// This panel's loop is playing or getting ready to.
  bool get playing =>
      _owned &&
      identical(_status.owner, this) &&
      _status.state != PlaybackState.stopped;

  /// Sounds are being prepared; nothing is heard yet.
  bool get preparing => playing && _status.state == PlaybackState.preparing;

  /// A plain explanation when playback stopped on an error.
  String? get playbackProblem =>
      !_owned && _failed ? 'The sound could not start. Try Play again.' : null;

  /// This panel's playback ended on an engine error.
  bool _failed = false;

  Future<void> play() async {
    _owned = true;
    _failed = false;
    notifyListeners();
    await _send();
  }

  Future<void> stop() async {
    _owned = false;
    notifyListeners();
    await _playback.stop(owner: this);
  }

  Future<void> togglePlay() => playing ? stop() : play();

  /// The app went to the background: nothing should keep playing there.
  void appHidden() {
    if (_owned) unawaited(stop());
  }

  Future<void> _send() async {
    try {
      await _playback.play(_document, owner: this);
    } catch (_) {
      _owned = false;
      _failed = true;
      if (!_disposed) notifyListeners();
    }
  }

  /// A status change is shown; a stop, by the user elsewhere, at the end or
  /// on an error, ends this panel's playback, and so does playback that
  /// another owner (the Arrangement panel) started. The repository may
  /// publish a stopped position while it restarts, so only the status
  /// decides that.
  void _onStatus() {
    if (_owned && _status.state == PlaybackState.stopped) {
      _owned = false;
      _failed = _status.stopReason == PlaybackStopReason.error;
    } else if (_owned && !identical(_status.owner, this)) {
      _owned = false;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _instruments.snapshot.removeListener(notifyListeners);
    _playback.status.removeListener(_onStatus);
    if (_owned) unawaited(_playback.stop(owner: this));
    super.dispose();
  }
}
