import 'dart:async';

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
    required LoopLibraryRepository library,
    required InstrumentLibraryRepository instruments,
    required PlaybackRepository playback,
    Loop? loop,
    bool existing = false,
  }) : _library = library,
       _instruments = instruments,
       _playback = playback {
    _load(loop ?? factoryLoops.first, existing: existing);
    _instruments.snapshot.addListener(notifyListeners);
    _playback.status.addListener(_onStatus);
    _playback.position.addListener(_onPosition);
  }

  final LoopLibraryRepository _library;
  final InstrumentLibraryRepository _instruments;
  final PlaybackRepository _playback;

  late Loop _baseline;
  late SessionDocument _document;
  late String _name;
  late bool _persisted;
  bool _saving = false;
  String? _saveError;

  /// True from this panel's Play until Stop, or until something else (the
  /// Arrangement panel's sequence, an engine stop) takes the transport.
  bool _owned = false;
  bool _disposed = false;

  void _load(Loop source, {required bool existing}) {
    final keep = existing && !isFactoryId(source.id);
    final loop = keep ? source : source.copyAsNew();
    _baseline = loop;
    _document = loop.document;
    _name = loop.name;
    _persisted = keep;
    _saveError = null;
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
  bool get saving => _saving;
  String? get saveError => _saveError;

  /// There is something to lose when leaving.
  bool get dirty =>
      _document != _baseline.document || _name.trim() != _baseline.name;

  /// A copy can be saved as it is; a saved loop only after a change.
  bool get canSave => nameValid && !_saving && (dirty || !_persisted);

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
    _saving = true;
    _saveError = null;
    notifyListeners();
    try {
      await _library.save(saved);
      _baseline = saved;
      _document = saved.document;
      _name = name;
      _persisted = true;
      return true;
    } catch (_) {
      _saveError = 'Could not save the loop. Try again.';
      return false;
    } finally {
      _saving = false;
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

  void setCycleBeats(int beats) {
    if (beats < edits.minLoopCycleBeats || beats > edits.maxLoopCycleBeats)
      return;
    _apply(edits.setCycleBeats(_document, beats));
  }

  void addLayer() {
    if (canAddLayer) _apply(edits.addLoopLayer(_document));
  }

  void removeLayer(int index) {
    if (canRemoveLayer) _apply(edits.removeLoopLayer(_document, index));
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
  bool get playing => _owned && _status.state != PlaybackState.stopped;

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
    await _playback.stop();
  }

  Future<void> togglePlay() => playing ? stop() : play();

  /// The app went to the background: nothing should keep playing there.
  void appHidden() {
    if (_owned) unawaited(stop());
  }

  Future<void> _send() async {
    try {
      await _playback.play(_document);
    } catch (_) {
      _owned = false;
      _failed = true;
      if (!_disposed) notifyListeners();
    }
  }

  /// A status change is shown; a stop, by the user elsewhere, at the end or
  /// on an error, ends this panel's playback. The repository may publish a
  /// stopped position while it restarts, so only the status decides that.
  void _onStatus() {
    if (_owned && _status.state == PlaybackState.stopped) {
      _owned = false;
      _failed = _status.stopReason == PlaybackStopReason.error;
    }
    notifyListeners();
  }

  /// A position inside a sequence means another panel took the transport.
  /// Other position updates (every frame or so) need no rebuild here.
  void _onPosition() {
    if (_owned && _playback.position.value.sectionIndex != null) {
      _owned = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _instruments.snapshot.removeListener(notifyListeners);
    _playback.status.removeListener(_onStatus);
    _playback.position.removeListener(_onPosition);
    if (_owned) unawaited(_playback.stop());
    super.dispose();
  }
}
