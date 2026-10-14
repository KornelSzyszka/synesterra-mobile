import 'dart:math' as math;
import 'dart:typed_data';

import 'package:synesterra_core/synesterra_core.dart';
import 'package:test/test.dart';

const double sampleRate = 44100;
const int bufferSize = 4096;

Float32List sine(double hz, {double amplitude = 0.5, double phase = 0}) {
  return Float32List.fromList([
    for (var i = 0; i < bufferSize; i++)
      amplitude * math.sin(2 * math.pi * hz * i / sampleRate + phase),
  ]);
}

Float32List sawtooth(double hz, {double amplitude = 0.5}) {
  return Float32List.fromList([
    for (var i = 0; i < bufferSize; i++)
      amplitude * (2 * ((hz * i / sampleRate) % 1) - 1),
  ]);
}

double hzOffset(double cents) => 440 * math.pow(2, cents / 1200).toDouble();

double centsBetween(double measured, double expected) =>
    1200 * math.log(measured / expected) / math.ln2;

void main() {
  final detector = PitchDetector(sampleRate: sampleRate);

  group('PitchDetector', () {
    const frequencies = [
      41.2,
      55.0,
      82.41,
      110.0,
      196.0,
      261.63,
      440.0,
      659.26,
      1000.0,
      1318.5,
      1760.0,
      2000.0,
    ];

    for (final hz in frequencies) {
      test('finds a $hz Hz sine within 3 cents', () {
        final estimate = detector.detect(sine(hz));
        expect(estimate, isNotNull);
        expect(centsBetween(estimate!.frequencyHz, hz).abs(), lessThan(3));
        expect(estimate.clarity, greaterThan(0.9));
      });

      test('finds a $hz Hz sawtooth within 5 cents, not an octave off', () {
        final estimate = detector.detect(sawtooth(hz));
        expect(estimate, isNotNull);
        expect(centsBetween(estimate!.frequencyHz, hz).abs(), lessThan(5));
      });
    }

    test('does not depend on the phase', () {
      for (final phase in [0.0, 1.0, 2.5, 4.0]) {
        final estimate = detector.detect(sine(110, phase: phase));
        expect(centsBetween(estimate!.frequencyHz, 110).abs(), lessThan(3));
      }
    });

    test('works for a quiet signal above the silence floor', () {
      final estimate = detector.detect(sine(220, amplitude: 0.02));
      expect(estimate, isNotNull);
      expect(centsBetween(estimate!.frequencyHz, 220).abs(), lessThan(3));
    });

    test('returns no pitch for silence', () {
      expect(detector.detect(Float32List(bufferSize)), isNull);
    });

    test('returns no pitch for a very quiet signal', () {
      expect(detector.detect(sine(220, amplitude: 0.0005)), isNull);
    });

    test('returns no pitch for white noise', () {
      for (var seed = 0; seed < 5; seed++) {
        final random = math.Random(seed);
        final noise = Float32List.fromList([
          for (var i = 0; i < bufferSize; i++) random.nextDouble() * 2 - 1,
        ]);
        expect(detector.detect(noise), isNull, reason: 'seed $seed');
      }
    });

    test('returns no pitch for a constant offset', () {
      final dc = Float32List.fromList(List.filled(bufferSize, 0.4));
      expect(detector.detect(dc), isNull);
    });

    test('rejects a buffer shorter than minSamples', () {
      expect(
        () => detector.detect(Float32List(detector.minSamples - 1)),
        throwsArgumentError,
      );
    });

    test('rejects bad configuration', () {
      expect(() => PitchDetector(sampleRate: 100), throwsArgumentError);
      expect(
        () => PitchDetector(sampleRate: 8000, maxFrequencyHz: 5000),
        throwsArgumentError,
      );
      expect(
        () => PitchDetector(sampleRate: sampleRate, threshold: 1),
        throwsArgumentError,
      );
    });

    test('works at another sample rate', () {
      final d = PitchDetector(sampleRate: 16000, maxFrequencyHz: 1000);
      final samples = Float32List.fromList([
        for (var i = 0; i < 2048; i++)
          0.5 * math.sin(2 * math.pi * 330 * i / 16000),
      ]);
      expect(
        centsBetween(d.detect(samples)!.frequencyHz, 330).abs(),
        lessThan(3),
      );
    });
  });

  group('note and cents', () {
    test('A4 is 440 Hz exactly', () {
      final note = noteOfFrequency(440);
      expect(note.label, 'A4');
      expect(note.midi, 69);
      expect(note.cents.abs(), lessThan(1e-9));
      expect(note.inTune(), isTrue);
    });

    test('names the notes and octaves', () {
      expect(noteOfFrequency(261.6256).label, 'C4');
      expect(noteOfFrequency(41.2034).label, 'E1');
      expect(noteOfFrequency(466.1638).label, 'A#4');
      expect(noteOfFrequency(1975.533).label, 'B6');
    });

    test('reports sharp as positive and flat as negative cents', () {
      final sharp = noteOfFrequency(hzOffset(20));
      final flat = noteOfFrequency(hzOffset(-20));
      expect(sharp.cents, closeTo(20, 1e-6));
      expect(flat.cents, closeTo(-20, 1e-6));
      expect(sharp.inTune(), isFalse);
      expect(noteOfFrequency(hzOffset(4)).inTune(), isTrue);
    });

    test('rounds to the nearest note across the half-way point', () {
      final high = noteOfFrequency(hzOffset(51));
      expect(high.label, 'A#4');
      expect(high.cents, closeTo(-49, 1e-6));
    });

    test('honours a configurable reference', () {
      final note = noteOfFrequency(432, referenceA4: 432);
      expect(note.label, 'A4');
      expect(note.cents.abs(), lessThan(1e-9));
      expect(note.targetHz, closeTo(432, 1e-9));
      expect(noteOfFrequency(440, referenceA4: 432).cents, closeTo(31.8, 0.1));
      expect(frequencyOfMidi(60, referenceA4: 415), closeTo(246.76, 0.01));
    });

    test('rejects a bad reference or frequency', () {
      expect(() => noteOfFrequency(440, referenceA4: 300), throwsArgumentError);
      expect(() => noteOfFrequency(440, referenceA4: 500), throwsArgumentError);
      expect(() => noteOfFrequency(0), throwsArgumentError);
      expect(() => noteOfFrequency(double.nan), throwsArgumentError);
    });
  });

  group('PitchTracker', () {
    PitchTracker tracker() => PitchTracker(detector: detector);

    test('settles on the note and cents of a steady tone', () {
      final t = tracker();
      TunerNote? note;
      for (var i = 0; i < 4; i++) {
        note = t.process(sine(110));
      }
      expect(note!.label, 'A2');
      expect(note.cents.abs(), lessThan(3));
    });

    test('median smoothing ignores a single outlier', () {
      final t = tracker();
      for (var i = 0; i < 4; i++) {
        t.process(sine(440));
      }
      // 25 cents sharp for one buffer.
      final note = t.process(sine(hzOffset(25)));
      expect(note!.cents.abs(), lessThan(5));
    });

    test('a new note replaces the old one at once', () {
      final t = tracker();
      for (var i = 0; i < 4; i++) {
        t.process(sine(440));
      }
      final note = t.process(sine(659.26));
      expect(note!.label, 'E5');
    });

    test('holds the note briefly, then reports no pitch', () {
      final t = tracker();
      t.process(sine(440));
      final silence = Float32List(bufferSize);
      expect(t.process(silence)?.label, 'A4');
      expect(t.process(silence)?.label, 'A4');
      expect(t.process(silence)?.label, 'A4');
      expect(t.process(silence), isNull);
      expect(t.process(silence), isNull);
    });

    test('a changed reference moves the cents and starts over', () {
      final t = tracker();
      for (var i = 0; i < 3; i++) {
        t.process(sine(432));
      }
      t.referenceA4 = 432;
      final note = t.process(sine(432));
      expect(note!.label, 'A4');
      expect(note.cents.abs(), lessThan(3));
      expect(() => t.referenceA4 = 1000, throwsArgumentError);
    });

    test('noise never produces a note', () {
      final t = tracker();
      final random = math.Random(7);
      for (var n = 0; n < 6; n++) {
        final noise = Float32List.fromList([
          for (var i = 0; i < bufferSize; i++) random.nextDouble() * 2 - 1,
        ]);
        expect(t.process(noise), isNull);
      }
    });
  });
}
