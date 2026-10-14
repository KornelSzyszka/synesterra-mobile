import 'dart:math' as math;

/// How hard a tap exercise is: the timing error that still earns credit.
enum TapDifficulty {
  easy(toleranceMs: 120, label: 'Easy'),
  medium(toleranceMs: 80, label: 'Medium'),
  hard(toleranceMs: 50, label: 'Hard');

  const TapDifficulty({required this.toleranceMs, required this.label});

  /// A tap this far (or further) from its hit earns no credit.
  final double toleranceMs;
  final String label;
}

/// One tap exercise: a cycle with an audible [clickHits] pulse, and
/// [targetHits] evenly spaced hits the user taps. All hits are evenly spaced
/// over [cycleBeats] and start on the cycle start.
class TapPreset {
  const TapPreset({
    required this.id,
    required this.name,
    required this.description,
    required this.bpm,
    required this.cycleBeats,
    required this.clickHits,
    required this.targetHits,
    required this.playTarget,
  });

  final String id;
  final String name;
  final String description;
  final int bpm;
  final int cycleBeats;

  /// Hits per cycle of the reference click, always audible.
  final int clickHits;

  /// Hits per cycle the user is asked to tap.
  final int targetHits;

  /// True when the target hits are also sounded ("tap along"); false when the
  /// user has to keep them against the click alone.
  final bool playTarget;

  double get cycleMs => cycleBeats * 60000 / bpm;

  /// Target hit times within one cycle, in milliseconds.
  List<double> get targetTimesMs => [
    for (var i = 0; i < targetHits; i++) i * cycleMs / targetHits,
  ];
}

/// The built-in exercises, easiest first.
const List<TapPreset> tapPresets = [
  TapPreset(
    id: 'steady',
    name: 'Steady pulse',
    description: 'Tap on every click.',
    bpm: 80,
    cycleBeats: 4,
    clickHits: 4,
    targetHits: 4,
    playTarget: true,
  ),
  TapPreset(
    id: 'keep-it',
    name: 'Keep the pulse',
    description: 'Same pulse, but your taps are not sounded.',
    bpm: 80,
    cycleBeats: 4,
    clickHits: 4,
    targetHits: 4,
    playTarget: false,
  ),
  TapPreset(
    id: 'three-two',
    name: 'Three against two',
    description: 'Two clicks per cycle; tap three evenly.',
    bpm: 90,
    cycleBeats: 2,
    clickHits: 2,
    targetHits: 3,
    playTarget: false,
  ),
  TapPreset(
    id: 'four-three',
    name: 'Four against three',
    description: 'Three clicks per cycle; tap four evenly.',
    bpm: 80,
    cycleBeats: 3,
    clickHits: 3,
    targetHits: 4,
    playTarget: false,
  ),
];

/// Cycles played before scoring starts (a count-in, nothing is scored).
const tapCountInCycles = 1;

/// Cycles that are scored.
const tapScoredCycles = 4;

/// The calibration offset is limited to this many ms either way.
const tapOffsetLimitMs = 250;

/// Time in ms of a transport reading: whole cycles plus the position inside
/// the current cycle.
double tapTimeMs({
  required int cycleIndex,
  required double cyclePosition,
  required double cycleMs,
}) => (cycleIndex + cyclePosition) * cycleMs;

/// One tap and what it was matched to.
class TapResult {
  const TapResult({required this.tapMs, this.hitMs, this.errorMs});

  /// The tap time after the latency offset, in ms.
  final double tapMs;

  /// The hit it was matched to, or null for an extra tap.
  final double? hitMs;

  /// Tap minus hit: negative is early, positive late. Null for an extra tap.
  final double? errorMs;

  bool get matched => hitMs != null;
}

/// The outcome of a tap exercise.
class TapScore {
  const TapScore({
    required this.results,
    required this.expectedHits,
    required this.missed,
    required this.extraTaps,
    required this.meanAbsoluteErrorMs,
    required this.meanErrorMs,
    required this.score,
  });

  /// Every tap in the scored window, in order.
  final List<TapResult> results;
  final int expectedHits;

  /// Hits nobody tapped.
  final int missed;

  /// Taps that matched no hit.
  final int extraTaps;

  /// Mean |error| of the matched taps; 0 when none matched.
  final double meanAbsoluteErrorMs;

  /// Mean signed error (negative: early on average); 0 when none matched.
  final double meanErrorMs;

  /// 0..100. Each hit earns `1 - |error| / tolerance` (never below 0); the
  /// sum is divided by the hits plus the extra taps.
  final int score;

  int get matched => expectedHits - missed;
}

/// Matches [tapsMs] to the hits of the scored cycles and scores them.
///
/// Pure: every time is a plain number. [targetTimesMs] are the hit times
/// within one cycle of [cycleMs]; hits of cycles [skipCycles] ..
/// [skipCycles] + [scoredCycles] - 1 are expected. [offsetMs] is the device's
/// systematic delay between a hit and the tap that answers it (positive: the
/// user taps late because of audio or touch latency); it is subtracted from
/// every tap. This is a manual setting, not a measurement.
///
/// A tap is matched to the nearest unmatched hit within half the shortest gap
/// between hits (at most 250 ms); otherwise it is an extra tap. Taps outside
/// the scored window (plus that margin) are ignored.
TapScore scoreTaps({
  required List<double> targetTimesMs,
  required double cycleMs,
  required List<double> tapsMs,
  required double toleranceMs,
  double offsetMs = 0,
  int skipCycles = tapCountInCycles,
  int scoredCycles = tapScoredCycles,
}) {
  if (targetTimesMs.isEmpty) {
    throw ArgumentError.value(targetTimesMs, 'targetTimesMs', 'is empty');
  }
  if (!(cycleMs > 0) || !(toleranceMs > 0)) {
    throw ArgumentError('cycleMs and toleranceMs must be positive');
  }
  final hits = <double>[
    for (var c = skipCycles; c < skipCycles + scoredCycles; c++)
      for (final t in targetTimesMs) c * cycleMs + t,
  ];
  var smallestGap = cycleMs;
  for (var i = 1; i < targetTimesMs.length; i++) {
    smallestGap = math.min(
      smallestGap,
      targetTimesMs[i] - targetTimesMs[i - 1],
    );
  }
  final window = math.min(250.0, smallestGap / 2);
  final start = hits.first - window;
  final end = hits.last + window;

  final taken = List<bool>.filled(hits.length, false);
  final results = <TapResult>[];
  for (final raw in tapsMs) {
    final tap = raw - offsetMs;
    if (tap < start || tap > end) continue;
    var best = -1;
    var bestDistance = double.infinity;
    for (var i = 0; i < hits.length; i++) {
      if (taken[i]) continue;
      final distance = (tap - hits[i]).abs();
      if (distance < bestDistance) {
        bestDistance = distance;
        best = i;
      }
    }
    if (best >= 0 && bestDistance <= window) {
      taken[best] = true;
      results.add(
        TapResult(tapMs: tap, hitMs: hits[best], errorMs: tap - hits[best]),
      );
    } else {
      results.add(TapResult(tapMs: tap));
    }
  }

  final matched = results.where((r) => r.matched).toList();
  final extra = results.length - matched.length;
  final credit = matched.fold<double>(
    0,
    (sum, r) => sum + math.max(0, 1 - r.errorMs!.abs() / toleranceMs),
  );
  return TapScore(
    results: List.unmodifiable(results),
    expectedHits: hits.length,
    missed: hits.length - matched.length,
    extraTaps: extra,
    meanAbsoluteErrorMs: matched.isEmpty
        ? 0
        : matched.fold<double>(0, (s, r) => s + r.errorMs!.abs()) /
              matched.length,
    meanErrorMs: matched.isEmpty
        ? 0
        : matched.fold<double>(0, (s, r) => s + r.errorMs!) / matched.length,
    score: (100 * credit / (hits.length + extra)).round().clamp(0, 100),
  );
}
