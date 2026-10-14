import 'package:flutter_test/flutter_test.dart';
import 'package:synesterra/shared/living_blobs/living_mist.dart';
import 'package:synesterra/shared/living_blobs/living_motion.dart';

const _frame = Duration(milliseconds: 16);

void _run(LivingMist mist, Duration duration) {
  for (var t = Duration.zero; t < duration; t += _frame) {
    mist.tick(_frame);
  }
}

void main() {
  test('rests until woken, then lives for a while and rests again', () {
    final mist = LivingMist();
    expect(mist.resting, isTrue);
    expect(mist.life, 0);
    mist.wake();
    expect(mist.resting, isFalse);
    expect(mist.life, 1);
    _run(mist, LivingTiming.awake + LivingTiming.settle + _frame);
    expect(mist.life, 0);
    expect(mist.resting, isTrue);
  });

  test('pulses with the envelope of the audition', () {
    final mist = LivingMist()
      ..pulseWith(
        const Duration(milliseconds: 32),
        const Duration(milliseconds: 320),
      );
    expect(mist.pulse, 0);
    mist.tick(_frame);
    expect(mist.pulse, closeTo(.5, 1e-9));
    mist.tick(_frame);
    expect(mist.pulse, closeTo(1, 1e-9));
    _run(mist, const Duration(milliseconds: 160));
    expect(mist.pulse, inExclusiveRange(0, 1));
    _run(mist, const Duration(milliseconds: 400));
    expect(mist.pulse, 0);
  });

  test('leans toward the finger and swells, then springs back', () {
    final mist = LivingMist()..touch(const Offset(2, 0));
    _run(mist, const Duration(milliseconds: 600));
    // The lean is clamped to one reach.
    expect(mist.lean.dx, closeTo(1, .05));
    expect(mist.hold, closeTo(1, .05));
    mist.release();
    var overshoot = 0.0;
    for (var i = 0; i < 90; i++) {
      mist.tick(_frame);
      if (mist.lean.dx < overshoot) overshoot = mist.lean.dx;
    }
    expect(overshoot, lessThan(0), reason: 'a soft wobble past the rest');
    expect(mist.lean, Offset.zero);
    expect(mist.hold, 0);
  });
}
