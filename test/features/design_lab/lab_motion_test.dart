import 'package:flutter_test/flutter_test.dart';
import 'package:synesterra/features/design_lab/lab_motion.dart';

void main() {
  group('flash-rate guard', () {
    test('the first flash is always allowed', () {
      expect(flashAllowed(now: Duration.zero), isTrue);
    });

    test('a retrigger faster than three per second is rejected', () {
      const last = Duration(seconds: 10);
      expect(
        flashAllowed(now: last + const Duration(milliseconds: 100), last: last),
        isFalse,
      );
      expect(
        flashAllowed(now: last + const Duration(milliseconds: 333), last: last),
        isFalse,
      );
      expect(
        flashAllowed(now: last + const Duration(milliseconds: 334), last: last),
        isTrue,
      );
    });

    test('the gate never allows more than three flashes in any second', () {
      final gate = FlashGate();
      final starts = <Duration>[];
      // A tap every 50 ms for three seconds.
      for (var ms = 0; ms < 3000; ms += 50) {
        final now = Duration(milliseconds: ms);
        if (gate.tryFlash(now)) starts.add(now);
      }
      for (final start in starts) {
        final inWindow = starts.where(
          (s) => s >= start && s < start + const Duration(seconds: 1),
        );
        expect(inWindow.length, lessThanOrEqualTo(maxFlashesPerSecond));
      }
      expect(starts, isNotEmpty);
    });

    test('a rejected tap does not push the next allowed flash back', () {
      final gate = FlashGate();
      expect(gate.tryFlash(Duration.zero), isTrue);
      expect(gate.tryFlash(const Duration(milliseconds: 200)), isFalse);
      expect(gate.tryFlash(const Duration(milliseconds: 340)), isTrue);
    });
  });

  test('a flash is shorter than a quarter second', () {
    expect(glitchDuration, lessThan(const Duration(milliseconds: 250)));
  });

  test('reduce motion turns the glitch into a plain fade; off is off', () {
    for (final strength in [GlitchStrength.subtle, GlitchStrength.strong]) {
      expect(glitchModeFor(strength, reduceMotion: false), GlitchMode.full);
      expect(glitchModeFor(strength, reduceMotion: true), GlitchMode.fade);
    }
    for (final reduce in [true, false]) {
      expect(
        glitchModeFor(GlitchStrength.off, reduceMotion: reduce),
        GlitchMode.none,
      );
    }
  });
}
