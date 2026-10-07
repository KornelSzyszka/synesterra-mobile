import 'dart:math';

import 'package:synesterra_core/synesterra_core.dart';
import 'package:test/test.dart';

Instrument at(double x, double y) =>
    instrumentForPad(PadPoint(x, y), id: 'pad-test', name: 'Pad test');

List<double> padded(List<double> harmonics, int length) => [
  ...harmonics,
  ...List.filled(length - harmonics.length, 0.0),
];

double centroid(Instrument instrument) {
  var weighted = 0.0;
  var total = 0.0;
  for (final (i, amplitude) in instrument.harmonics.indexed) {
    weighted += (i + 1) * amplitude;
    total += amplitude;
  }
  return weighted / total;
}

/// Largest change of any recipe field, each scaled to a comparable 0..1 span.
/// Attack is linear in ms (a 1 ms rounding step is inaudible); decay is
/// compared in the log domain, where it is blended.
double distance(Instrument a, Instrument b) {
  var worst = 0.0;
  for (var i = 0; i < a.harmonics.length; i++) {
    worst = max(worst, (a.harmonics[i] - b.harmonics[i]).abs());
  }
  worst = max(worst, (a.attackMs - b.attackMs).abs() / 500);
  worst = max(worst, (log(a.decayMs) - log(b.decayMs)).abs() / log(250));
  worst = max(worst, (a.eq.lowDb - b.eq.lowDb).abs() / 24);
  worst = max(worst, (a.eq.midDb - b.eq.midDb).abs() / 24);
  worst = max(worst, (a.eq.highDb - b.eq.highDb).abs() / 24);
  return worst;
}

void main() {
  group('PadPoint', () {
    test('accepts the whole unit square including the corners', () {
      for (final x in [0.0, 0.5, 1.0]) {
        for (final y in [0.0, 0.5, 1.0]) {
          final point = PadPoint(x, y);
          expect(point.x, x);
          expect(point.y, y);
        }
      }
    });

    test('rejects values outside 0..1 and non-finite values', () {
      for (final bad in [-0.001, 1.001, double.nan, double.infinity]) {
        expect(() => PadPoint(bad, 0.5), throwsArgumentError);
        expect(() => PadPoint(0.5, bad), throwsArgumentError);
      }
    });

    test('the error names the offending field and the range', () {
      expect(
        () => PadPoint(2, 0.5),
        throwsA(
          isA<ArgumentError>()
              .having((e) => e.name, 'name', 'x')
              .having((e) => e.message, 'message', contains('0..1')),
        ),
      );
      expect(
        () => PadPoint(0.5, -1),
        throwsA(isA<ArgumentError>().having((e) => e.name, 'name', 'y')),
      );
    });

    test('has value equality', () {
      expect(PadPoint(0.25, 0.75), PadPoint(0.25, 0.75));
      expect(PadPoint(0.25, 0.75).hashCode, PadPoint(0.25, 0.75).hashCode);
      expect(PadPoint(0.25, 0.75), isNot(PadPoint(0.75, 0.25)));
    });
  });

  group('anchors', () {
    test('the five Founder names exist at the documented places', () {
      final byName = {for (final a in padAnchors) a.name: a};
      expect(byName.keys.toSet(), {
        'warm drone',
        'airy pad',
        'bass',
        'guitar',
        'click',
      });
      expect((byName['warm drone']!.x, byName['warm drone']!.y), (0.0, 0.0));
      expect((byName['airy pad']!.x, byName['airy pad']!.y), (1.0, 0.0));
      expect((byName['bass']!.x, byName['bass']!.y), (0.0, 1.0));
      expect((byName['guitar']!.x, byName['guitar']!.y), (1.0, 1.0));
      expect((byName['click']!.x, byName['click']!.y), (0.5, 1.0));
    });

    test('every anchor is a valid recipe on its own', () {
      for (final anchor in padAnchors) {
        expect(anchor.harmonics.any((h) => h > 0), isTrue, reason: anchor.name);
        expect(at(anchor.x, anchor.y), isA<Instrument>());
      }
    });

    test('each anchor point reproduces its anchor recipe exactly', () {
      final length = padAnchors.map((a) => a.harmonics.length).reduce(max);
      for (final anchor in padAnchors) {
        final result = at(anchor.x, anchor.y);
        expect(
          result.harmonics,
          padded(anchor.harmonics, length),
          reason: anchor.name,
        );
        expect(result.attackMs, anchor.attackMs, reason: anchor.name);
        expect(result.decayMs, anchor.decayMs, reason: anchor.name);
        expect(result.eq, anchor.eq, reason: anchor.name);
      }
    });

    test('the anchors keep the intended character relative to each other', () {
      Instrument named(String name) {
        final a = padAnchors.firstWhere((a) => a.name == name);
        return at(a.x, a.y);
      }

      expect(named('click').decayMs, lessThan(named('bass').decayMs));
      expect(named('click').decayMs, lessThan(named('guitar').decayMs));
      expect(named('warm drone').attackMs, greaterThan(100));
      expect(named('airy pad').attackMs, greaterThan(100));
      expect(
        centroid(named('airy pad')),
        greaterThan(centroid(named('warm drone'))),
      );
      expect(centroid(named('guitar')), greaterThan(centroid(named('bass'))));
    });
  });

  group('instrumentForPad', () {
    test('passes id, name and tags through', () {
      final result = instrumentForPad(
        PadPoint(0.3, 0.6),
        id: 'my-sound',
        name: 'My sound',
        tags: ['dark', 'soft'],
      );
      expect(result.id, 'my-sound');
      expect(result.name, 'My sound');
      expect(result.tags, ['dark', 'soft']);
    });

    test('a bad id or name is rejected by the Instrument rules', () {
      expect(
        () => instrumentForPad(PadPoint(0.5, 0.5), id: 'no spaces', name: 'x'),
        throwsArgumentError,
      );
      expect(
        () => instrumentForPad(PadPoint(0.5, 0.5), id: 'ok', name: ' '),
        throwsArgumentError,
      );
    });

    test('is deterministic', () {
      expect(at(0.37, 0.81), at(0.37, 0.81));
    });

    test('a 21x21 grid always gives a valid, audible instrument at 48 kHz', () {
      for (var i = 0; i <= 20; i++) {
        for (var j = 0; j <= 20; j++) {
          final instrument = at(i / 20, j / 20);
          // Round-trips through the validating parser.
          expect(Instrument.fromJson(instrument.toJson()), instrument);
          final samples = renderInstrument(
            instrument,
            fundamentalHz: 220,
            sampleRate: 48000,
          );
          final peak = samples.fold<double>(0, (m, s) => max(m, s.abs()));
          expect(peak, greaterThan(0.1), reason: '($i, $j)');
        }
      }
    });

    test('is continuous: a small step changes the recipe a bounded amount', () {
      const step = 0.01;
      var worst = 0.0;
      for (var i = 0; i <= 100; i++) {
        for (var j = 0; j <= 100; j++) {
          final here = at(i * step, j * step);
          if (i < 100) {
            worst = max(worst, distance(here, at((i + 1) * step, j * step)));
          }
          if (j < 100) {
            worst = max(worst, distance(here, at(i * step, (j + 1) * step)));
          }
        }
      }
      // Integer rounding of attack and decay is included in this bound.
      expect(worst, lessThan(0.06));
    });

    test('brightness never decreases with x along any row', () {
      for (var j = 0; j <= 20; j++) {
        var previous = -1.0;
        for (var i = 0; i <= 100; i++) {
          final value = centroid(at(i / 100, j / 20));
          expect(
            value,
            greaterThanOrEqualTo(previous - 1e-9),
            reason: 'row $j, x ${i / 100}',
          );
          previous = value;
        }
      }
    });

    test('toward the bottom, attack and decay do not increase on average', () {
      for (var i = 0; i <= 20; i++) {
        double mean(Iterable<int> rows, int Function(Instrument) pick) =>
            rows.map((j) => pick(at(i / 20, j / 20))).reduce((a, b) => a + b) /
            rows.length;
        final upper = List.generate(10, (j) => j);
        final lower = List.generate(10, (j) => j + 11);
        expect(
          mean(lower, (v) => v.decayMs),
          lessThanOrEqualTo(mean(upper, (v) => v.decayMs)),
          reason: 'decay, column $i',
        );
        expect(
          mean(lower, (v) => v.attackMs),
          lessThanOrEqualTo(mean(upper, (v) => v.attackMs)),
          reason: 'attack, column $i',
        );
      }
    });
  });
}
