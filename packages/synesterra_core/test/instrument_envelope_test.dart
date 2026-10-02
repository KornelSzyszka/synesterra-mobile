import 'package:synesterra_core/synesterra_core.dart';
import 'package:test/test.dart';

double level(int attackMs, int decayMs, double seconds) =>
    envelopeLevel(attackMs: attackMs, decayMs: decayMs, seconds: seconds);

void main() {
  test('the attack rises linearly from 0 to full level', () {
    expect(level(100, 500, 0), 0);
    expect(level(100, 500, 0.025), closeTo(0.25, 1e-12));
    expect(level(100, 500, 0.05), closeTo(0.5, 1e-12));
    expect(level(100, 500, 0.1), closeTo(1, 1e-12));
  });

  test('with no attack the sound starts at full level', () {
    expect(level(0, 200, 0), 1);
  });

  test('the decay reaches -60 dB exactly when the decay time is over', () {
    expect(level(100, 500, 0.6), closeTo(envelopeFloor, 1e-12));
    expect(level(0, 200, 0.2), closeTo(0.001, 1e-12));
  });

  test('halfway through the decay the level is -30 dB', () {
    expect(level(0, 400, 0.2), closeTo(0.0316227766, 1e-9));
  });

  test('after the decay the level stays at the floor', () {
    expect(level(10, 100, 5), closeTo(envelopeFloor, 1e-12));
    expect(level(10, 100, 1000), closeTo(envelopeFloor, 1e-12));
  });

  test('after the peak the level only goes down', () {
    var previous = 1.0;
    for (var ms = 100; ms <= 700; ms += 10) {
      final now = level(100, 500, ms / 1000);
      expect(now, lessThanOrEqualTo(previous + 1e-12));
      previous = now;
    }
  });

  test('the floor is -60 dB', () {
    expect(envelopeFloor, closeTo(0.001, 1e-15));
  });
}
