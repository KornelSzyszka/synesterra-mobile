import 'dart:typed_data';

import 'pitch_detector.dart';
import 'tuner_note.dart';

/// Turns a stream of sample buffers into a steady [TunerNote].
///
/// Per buffer the [PitchDetector] gives a frequency or none. The tracker
/// smooths with the median of the last [window] readings (in semitones, so
/// the median is musical), starts over when the pitch jumps more than
/// [jumpSemitones] (a new note, so the needle does not crawl), and keeps the
/// last note for up to [holdFrames] silent buffers before it reports `null`.
/// Readings with a clarity under [minClarity] count as none.
class PitchTracker {
  PitchTracker({
    required this.detector,
    double referenceA4 = defaultReferenceA4,
    this.window = 5,
    this.jumpSemitones = 0.7,
    this.holdFrames = 3,
    this.minClarity = 0.8,
  }) : _referenceA4 = referenceA4 {
    if (window < 1) throw ArgumentError.value(window, 'window', 'at least 1');
    if (holdFrames < 0) {
      throw ArgumentError.value(holdFrames, 'holdFrames', 'not negative');
    }
    midiOfFrequency(440, referenceA4: referenceA4); // validates
  }

  final PitchDetector detector;
  final int window;
  final double jumpSemitones;
  final int holdFrames;
  final double minClarity;

  double _referenceA4;
  final List<double> _recent = [];
  int _missed = 0;
  TunerNote? _last;

  double get referenceA4 => _referenceA4;

  /// Changes the reference pitch and starts a fresh reading.
  set referenceA4(double hz) {
    midiOfFrequency(440, referenceA4: hz); // validates
    _referenceA4 = hz;
    reset();
  }

  /// Forgets everything; the next buffer starts a fresh reading.
  void reset() {
    _recent.clear();
    _missed = 0;
    _last = null;
  }

  /// Feeds one buffer; returns the smoothed note, or `null` for no pitch.
  TunerNote? process(Float32List samples) {
    final estimate = detector.detect(samples);
    if (estimate == null || estimate.clarity < minClarity) {
      _missed++;
      if (_missed > holdFrames) {
        reset();
        return null;
      }
      return _last;
    }
    _missed = 0;
    final midi = midiOfFrequency(
      estimate.frequencyHz,
      referenceA4: _referenceA4,
    );
    if (_recent.isNotEmpty && (midi - _median()).abs() > jumpSemitones) {
      _recent.clear();
    }
    _recent.add(midi);
    if (_recent.length > window) _recent.removeAt(0);
    return _last = noteOfMidi(_median(), referenceA4: _referenceA4);
  }

  double _median() {
    final sorted = [..._recent]..sort();
    final mid = sorted.length ~/ 2;
    return sorted.length.isOdd
        ? sorted[mid]
        : (sorted[mid - 1] + sorted[mid]) / 2;
  }
}
