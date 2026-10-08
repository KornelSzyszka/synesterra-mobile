import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:synesterra_core/synesterra_core.dart';

import '../../data/repositories/arrangement_library_repository.dart';
import '../../data/repositories/library_item.dart';
import '../../data/repositories/loop.dart';
import '../../data/repositories/loop_library_repository.dart';
import '../../data/repositories/playback_repository.dart';
import '../../shared/loop_view/arrangement_strip.dart';

/// Edits and plays one arrangement: an ordered list of sections, each a loop
/// from the library and a number of repeats (cycles).
///
/// The draft may be empty while editing (an [Arrangement] needs at least one
/// section, so an empty draft cannot be saved). Whether a section's loop
/// exists is read from the loop library on every use, so a loop deleted
/// elsewhere becomes "missing" at once. A missing section is shown, marked
/// and skipped when playing; the sections that do play keep their original
/// index, which is what the playback repository reports back as
/// `sectionIndex`.
class ArrangementPanelViewModel extends ChangeNotifier {
  /// [initial] is an arrangement opened from the library; it keeps its id, so
  /// saving replaces it. Null starts a new, empty arrangement.
  ArrangementPanelViewModel({
    required this._loops,
    required this._arrangements,
    required this._playback,
    Arrangement? initial,
    String Function()? newId,
  }) : _newId = newId ?? (() => newLibraryId('arrangement')) {
    if (initial == null) {
      startNew();
    } else {
      _load(initial);
    }
    _loops.snapshot.addListener(_onLoopsChanged);
    _playback.status.addListener(_onStatus);
  }

  static const newName = 'New arrangement';

  /// Repeats a newly added section starts with.
  static const defaultRepeats = 2;

  final LoopLibraryRepository _loops;
  final ArrangementLibraryRepository _arrangements;
  final PlaybackRepository _playback;
  final String Function() _newId;

  late String _id;
  late String _name;
  late List<ArrangementSection> _sections;
  Arrangement? _baseline;
  bool _repeatAll = false;

  /// This panel owned the playback at the last status change.
  bool _wasOwner = false;

  /// This panel's playback ended on an engine error.
  bool _failed = false;
  bool _saving = false;
  String? _saveError;
  bool _disposed = false;

  String get id => _id;

  /// The text of the name field, valid or not.
  String get name => _name;
  List<ArrangementSection> get sections => List.unmodifiable(_sections);
  bool get repeatAll => _repeatAll;
  bool get saving => _saving;
  String? get saveError => _saveError;

  bool get canAddSection => _sections.length < Arrangement.maxSections;

  /// Factory loops first, then the user's loops by name.
  List<Loop> get loopChoices => [
    ...factoryLoops,
    ..._loops.snapshot.value.items,
  ];

  /// The loop of section [index], or null when it is missing.
  Loop? loopAt(int index) =>
      findLoop(_loops.snapshot.value, _sections[index].loopId);

  bool isMissing(int index) => loopAt(index) == null;

  /// The sections that can play, in order, each with its index in the
  /// arrangement.
  List<PlaybackSection> get playableSections => [
    for (var i = 0; i < _sections.length; i++)
      if (loopAt(i) case final loop?)
        PlaybackSection(
          originalIndex: i,
          document: loop.document,
          repeats: _sections[i].repeats,
        ),
  ];

  /// Why Play is disabled, in plain words; null when it is enabled.
  String? get playBlockedReason {
    if (_sections.isEmpty) return 'Add a loop to play.';
    if (playableSections.isEmpty) {
      return 'Nothing to play: the loops of every section are missing. '
          'Pick a loop for a section.';
    }
    return null;
  }

  bool get canPlay => playBlockedReason == null;

  /// True while a sequence started here is preparing or playing: this
  /// panel is the playback's owner. Playback started elsewhere (the Loop
  /// panel) does not count and is never stopped from here.
  bool get isPlaying {
    final status = _playback.status.value;
    return identical(status.owner, this) &&
        status.state != PlaybackState.stopped;
  }

  /// A short note about playback for the user, or null.
  String? get playbackNote {
    final status = _playback.status.value;
    if (_failed) {
      return 'Playback stopped because of a problem.';
    }
    if (isPlaying && status.missingInstrumentIds.isNotEmpty) {
      return 'Some sounds are missing and play silence.';
    }
    return null;
  }

  /// What the arrangement strip draws: one entry per section, missing ones
  /// marked.
  List<StripSection> get stripSections => [
    for (var i = 0; i < _sections.length; i++)
      StripSection(
        label: loopAt(i)?.name ?? 'Missing loop',
        repeats: _sections[i].repeats,
        missing: isMissing(i),
      ),
  ];

  bool get nameValid => isValidLibraryName(_name);

  /// Why Save is disabled, in plain words; null when it is enabled.
  String? get saveBlockedReason {
    if (_sections.isEmpty) return 'Add a loop to save.';
    if (!nameValid) return 'Give the arrangement a name.';
    return null;
  }

  bool get canSave => saveBlockedReason == null && !_saving;

  /// The draft differs from what is stored (a new arrangement with sections
  /// counts as unsaved).
  bool get hasUnsavedChanges {
    final baseline = _baseline;
    if (baseline == null) return _sections.isNotEmpty;
    return baseline.name != _name || !listEquals(baseline.sections, _sections);
  }

  // Editing.

  /// Appends a section playing [loopId] for [defaultRepeats] cycles.
  /// Throws [StateError] when there are already 16 sections.
  void addSection(String loopId) {
    if (!canAddSection) {
      throw StateError('at most ${Arrangement.maxSections} sections');
    }
    _sections.add(ArrangementSection(loopId: loopId, repeats: defaultRepeats));
    _edited();
  }

  void removeSection(int index) {
    _sections.removeAt(index);
    _edited();
  }

  /// Moves the section at [from] so that it ends up at index [to].
  void moveSection(int from, int to) {
    if (from == to) return;
    _sections.insert(to, _sections.removeAt(from));
    _edited();
  }

  /// Throws [ArgumentError] outside 1..32.
  void setRepeats(int index, int repeats) {
    _sections[index] = ArrangementSection(
      loopId: _sections[index].loopId,
      repeats: repeats,
    );
    _edited();
  }

  void replaceLoop(int index, String loopId) {
    _sections[index] = ArrangementSection(
      loopId: loopId,
      repeats: _sections[index].repeats,
    );
    _edited();
  }

  void setRepeatAll(bool value) {
    if (value == _repeatAll) return;
    _repeatAll = value;
    _edited();
  }

  void setName(String name) {
    _name = name;
    _saveError = null;
    notifyListeners();
  }

  // Playback.

  Future<void> play() async {
    final sections = playableSections;
    if (sections.isEmpty) return;
    _failed = false;
    await _playback.playSequence(sections, repeatAll: _repeatAll, owner: this);
  }

  /// Stops this panel's playback; playback another panel started is left
  /// alone.
  Future<void> stop() => _playback.stop(owner: this);

  /// A playing sequence follows the edit: it restarts from the first
  /// playable section with the new sections, or stops if none is left.
  void _edited() {
    _saveError = null;
    notifyListeners();
    if (!isPlaying) return;
    unawaited(canPlay ? play() : stop());
  }

  void _onLoopsChanged() {
    notifyListeners();
    if (isPlaying && !canPlay) unawaited(stop());
  }

  void _onStatus() {
    final status = _playback.status.value;
    if (_wasOwner &&
        status.state == PlaybackState.stopped &&
        status.stopReason == PlaybackStopReason.error) {
      _failed = true;
    }
    _wasOwner = isPlaying;
    notifyListeners();
  }

  // Library.

  /// Saves the draft to the arrangement library. Returns the saved
  /// arrangement, or null when it cannot be saved or saving failed (then
  /// [saveError] says so and the draft is kept).
  Future<Arrangement?> save() async {
    if (!canSave) return null;
    final arrangement = Arrangement(
      id: _id,
      name: _name,
      sections: List.of(_sections),
    );
    _saving = true;
    _saveError = null;
    notifyListeners();
    try {
      await _arrangements.save(arrangement);
      _baseline = arrangement;
      return arrangement;
    } on Object {
      _saveError = 'Could not save. Try again.';
      return null;
    } finally {
      _saving = false;
      if (!_disposed) notifyListeners();
    }
  }

  /// Replaces the draft with [arrangement] (it keeps its id). Stops a
  /// sequence this panel was playing.
  void open(Arrangement arrangement) {
    _stopOwnSequence();
    _load(arrangement);
    notifyListeners();
  }

  /// Replaces the draft with a new, empty arrangement under a fresh id.
  void startNew() {
    _stopOwnSequence();
    _id = _newId();
    _name = newName;
    _sections = [];
    _baseline = null;
    _saveError = null;
    if (hasListeners) notifyListeners();
  }

  void _load(Arrangement arrangement) {
    _id = arrangement.id;
    _name = arrangement.name;
    _sections = List.of(arrangement.sections);
    _baseline = arrangement;
    _saveError = null;
  }

  void _stopOwnSequence() {
    if (isPlaying) unawaited(stop());
  }

  @override
  void dispose() {
    _disposed = true;
    _loops.snapshot.removeListener(_onLoopsChanged);
    _playback.status.removeListener(_onStatus);
    _stopOwnSequence();
    super.dispose();
  }
}
