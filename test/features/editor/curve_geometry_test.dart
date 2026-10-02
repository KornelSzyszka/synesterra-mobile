import 'package:flutter_test/flutter_test.dart';
import 'package:synesterra/features/editor/curve_geometry.dart';

void main() {
  group('envelope time axis (square root)', () {
    test('0 is the left edge and the whole span is the right edge', () {
      expect(envelopeTimeToX(0, 300), 0);
      expect(envelopeTimeToX(envelopeSpanSeconds, 300), closeTo(300, 1e-9));
    });

    test('short times get far more room than a linear axis would give', () {
      // 10 ms is 0.18 % of the span on a linear axis, but about 4 % here.
      expect(envelopeTimeToX(0.01, 300), greaterThan(300 * 0.04));
      expect(envelopeTimeToX(0.1, 300), greaterThan(300 * 0.13));
    });

    test('it grows with time', () {
      var previous = -1.0;
      for (var ms = 0; ms <= 5500; ms += 50) {
        final x = envelopeTimeToX(ms / 1000, 300);
        expect(x, greaterThan(previous));
        previous = x;
      }
    });

    test('x and time convert back and forth', () {
      for (final seconds in [0.0, 0.002, 0.05, 0.4, 1.3, 5.0, 5.5]) {
        final x = envelopeTimeToX(seconds, 280);
        expect(envelopeXToTime(x, 280), closeTo(seconds, 1e-9));
      }
    });

    test('times beyond the span and touches off the graph are clamped', () {
      expect(envelopeTimeToX(99, 300), closeTo(300, 1e-9));
      expect(envelopeTimeToX(-1, 300), 0);
      expect(envelopeXToTime(-20, 300), 0);
      expect(envelopeXToTime(900, 300), closeTo(envelopeSpanSeconds, 1e-9));
      expect(envelopeXToTime(10, 0), 0);
    });
  });

  group('EQ frequency axis (logarithmic)', () {
    test('20 Hz is the left edge and 20 kHz the right edge', () {
      expect(hzToX(eqMinHz, 400), 0);
      expect(hzToX(eqMaxHz, 400), closeTo(400, 1e-9));
    });

    test('the geometric mean is in the middle', () {
      expect(hzToX(632.4555320336759, 400), closeTo(200, 1e-6));
    });

    test('every decade has the same width', () {
      final decade = hzToX(200, 300) - hzToX(20, 300);
      expect(hzToX(2000, 300) - hzToX(200, 300), closeTo(decade, 1e-9));
      expect(hzToX(20000, 300) - hzToX(2000, 300), closeTo(decade, 1e-9));
    });

    test('x and frequency convert back and forth', () {
      for (final hz in <double>[20, 55, 200, 1000, 4000, 12000, 20000]) {
        expect(xToHz(hzToX(hz, 333), 333), closeTo(hz, hz * 1e-9));
      }
    });

    test('frequencies and touches outside the range are clamped', () {
      expect(hzToX(5, 400), 0);
      expect(hzToX(90000, 400), closeTo(400, 1e-9));
      expect(xToHz(-50, 400), eqMinHz);
      expect(xToHz(900, 400), closeTo(eqMaxHz, 1e-6));
      expect(xToHz(10, 0), eqMinHz);
    });
  });

  group('EQ gain axis', () {
    test('+12 dB is the top, 0 the middle, -12 dB the bottom', () {
      expect(dbToY(12, 140), 0);
      expect(dbToY(0, 140), 70);
      expect(dbToY(-12, 140), 140);
    });

    test('gains beyond ±12 dB are clamped', () {
      expect(dbToY(40, 140), 0);
      expect(dbToY(-40, 140), 140);
    });

    test('a touch converts to a gain rounded to half a decibel', () {
      expect(yToDb(70, 140), 0);
      expect(yToDb(0, 140), 12);
      expect(yToDb(140, 140), -12);
      expect(yToDb(dbToY(3.2, 140), 140), 3);
      expect(yToDb(dbToY(3.3, 140), 140), 3.5);
      expect(yToDb(dbToY(-5.1, 140), 140), -5);
    });

    test('touches off the graph are clamped to ±12 dB', () {
      expect(yToDb(-80, 140), 12);
      expect(yToDb(400, 140), -12);
      expect(yToDb(10, 0), 0);
    });
  });

  group('nearestHandle', () {
    const handles = [Offset(50, 0), Offset(120, 130), Offset(200, 60)];

    test('picks the closest handle within reach', () {
      expect(nearestHandle(const Offset(55, 5), handles), 0);
      expect(nearestHandle(const Offset(130, 120), handles), 1);
      expect(nearestHandle(const Offset(190, 70), handles), 2);
    });

    test('picks the nearer one when two are in reach', () {
      const close = [Offset(100, 50), Offset(130, 50)];
      expect(nearestHandle(const Offset(110, 50), close), 0);
      expect(nearestHandle(const Offset(122, 50), close), 1);
    });

    test('returns null when nothing is within reach', () {
      expect(nearestHandle(const Offset(300, 300), handles), isNull);
      expect(nearestHandle(const Offset(50, 29), handles), isNull);
    });

    test('a touch exactly at the radius still grabs', () {
      expect(nearestHandle(const Offset(50, 28), handles), 0);
    });

    test('works with no handles and with a custom radius', () {
      expect(nearestHandle(const Offset(1, 1), const []), isNull);
      expect(nearestHandle(const Offset(60, 0), handles, radius: 5), isNull);
      expect(nearestHandle(const Offset(60, 0), handles, radius: 10), 0);
    });
  });
}
