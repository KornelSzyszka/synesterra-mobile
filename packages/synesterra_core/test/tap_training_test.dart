import 'package:synesterra_core/synesterra_core.dart';
import 'package:test/test.dart';

void main() {
  const steady = TapPreset(
    id: 't',
    name: 't',
    description: '',
    bpm: 60,
    cycleBeats: 4,
    clickHits: 4,
    targetHits: 4,
    playTarget: true,
  );
  // 60 bpm, 4 beats: cycle 4000 ms, hits at 0, 1000, 2000, 3000.

  List<double> perfect() => [
    for (var c = 1; c <= 4; c++)
      for (final t in steady.targetTimesMs) c * steady.cycleMs + t,
  ];

  TapScore score(List<double> taps, {double offset = 0, double tol = 100}) =>
      scoreTaps(
        targetTimesMs: steady.targetTimesMs,
        cycleMs: steady.cycleMs,
        tapsMs: taps,
        toleranceMs: tol,
        offsetMs: offset,
      );

  test('presets are valid and polyrhythms have unequal pulse and target', () {
    for (final p in tapPresets) {
      expect(p.cycleMs, greaterThan(0));
      expect(p.targetTimesMs, hasLength(p.targetHits));
    }
    final three = tapPresets.firstWhere((p) => p.id == 'three-two');
    expect(three.targetTimesMs[1], closeTo(three.cycleMs / 3, 1e-9));
    expect(three.clickHits, 2);
  });

  test('perfect taps score 100 with zero error', () {
    final s = score(perfect());
    expect(s.score, 100);
    expect(s.missed, 0);
    expect(s.extraTaps, 0);
    expect(s.meanAbsoluteErrorMs, 0);
  });

  test('early and late errors are signed', () {
    final taps = perfect();
    taps[0] -= 30;
    taps[1] += 50;
    final s = score(taps);
    expect(s.results[0].errorMs, closeTo(-30, 1e-9));
    expect(s.results[1].errorMs, closeTo(50, 1e-9));
    expect(s.meanErrorMs, closeTo(20 / 16, 1e-9));
    expect(s.score, lessThan(100));
  });

  test('count-in taps are ignored, no taps scores 0', () {
    final s = score([0, 1000, 2000, 3000]);
    expect(s.results, isEmpty);
    expect(s.missed, 16);
    expect(s.score, 0);
  });

  test('an offset removes a constant device delay', () {
    final late = [for (final t in perfect()) t + 80];
    expect(score(late).score, lessThan(100));
    expect(score(late, offset: 80).score, 100);
  });

  test('a tap past the tolerance matches but earns nothing', () {
    final taps = perfect();
    taps[3] += 150; // window is 500 ms, tolerance 100 ms
    final s = score(taps);
    expect(s.results[3].matched, isTrue);
    expect(s.score, closeTo(100 * 15 / 16, 0.51));
  });

  test('extra and doubled taps are counted and cost score', () {
    final taps = perfect()..insert(1, perfect()[0] + 10);
    final s = score(taps);
    expect(s.extraTaps, 1);
    expect(s.missed, 0);
    expect(s.score, lessThan(100));
  });

  test('a missed hit lowers the score', () {
    final s = score(perfect()..removeAt(5));
    expect(s.missed, 1);
    expect(s.score, 94);
  });

  test('invalid input throws', () {
    expect(
      () => scoreTaps(
        targetTimesMs: const [],
        cycleMs: 1,
        tapsMs: const [],
        toleranceMs: 1,
      ),
      throwsArgumentError,
    );
    expect(
      () => scoreTaps(
        targetTimesMs: const [0],
        cycleMs: 0,
        tapsMs: const [],
        toleranceMs: 1,
      ),
      throwsArgumentError,
    );
  });

  test('tapTimeMs combines cycle index and position', () {
    expect(tapTimeMs(cycleIndex: 2, cyclePosition: .25, cycleMs: 4000), 9000);
  });
}
