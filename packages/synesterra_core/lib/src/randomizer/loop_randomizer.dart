import 'dart:math' as math;

import '../harmony/drone.dart';
import '../rhythm/rhythm_values.dart';
import '../session/session_document.dart';
import '../sound/instrument.dart';
import 'seeded_random.dart';

/// Cycle lengths, in beats, a random loop chooses from.
const randomLoopCycleBeats = [2, 3, 4, 6, 8];

/// Tempo range of a random loop, BPM.
const randomLoopMinTempo = 70;
const randomLoopMaxTempo = 130;

/// Range of the root note a random loop's pitches are built on (MIDI).
const randomLoopMinRoot = 36;
const randomLoopMaxRoot = 72;

/// No generated pitch goes below C2: lower notes barely sound on a phone.
const _lowestPitch = 36;

/// Most steps a layer may have; the Loop panel offers 1..16.
const _maxSteps = 16;

/// Polyrhythm pairs and how often each one is chosen.
const _pairs = [
  (3, 2, 5),
  (4, 3, 4),
  (5, 4, 3),
  (7, 4, 2),
  (5, 3, 2),
  (5, 2, 1),
  (7, 3, 1),
];

/// Ratios (and their inverses) that relate a third or fourth layer to the
/// others: the pairs above plus the octave.
const _ratios = [(2, 1), (3, 2), (4, 3), (5, 4), (7, 4), (5, 3)];

const _majorPentatonic = [0, 2, 4, 7, 9];
const _minorPentatonic = [0, 3, 5, 7, 10];

/// A random, valid and (we hope) musical loop for [seed], a uint32.
///
/// The same seed and arguments always give the same document; the algorithm
/// is in docs/modules/randomizer.md. Layers use [instrumentIds] (deduplicated;
/// the factory instruments when empty). The result is a prototype-v0 loop:
/// whole-beat cycle, every layer one cycle long, scene B a copy of scene A,
/// and `randomSeed` set to [seed]. It is built through the core constructors,
/// so it is valid by construction.
///
/// Throws [ArgumentError] for a seed outside uint32 or an invalid id.
SessionDocument randomLoopDocument({
  required int seed,
  List<String> instrumentIds = const [],
  String title = '',
}) {
  checkRandomSeed(seed);
  final pool = _instrumentPool(instrumentIds);
  final random = SeededRandom(seed);

  final layerCount = weightedPick(random, const [(2, 35), (3, 40), (4, 25)]);
  final cycleBeats =
      randomLoopCycleBeats[random.nextInt(randomLoopCycleBeats.length)];
  final counts = _stepCounts(random, layerCount, cycleBeats);
  final cycle = Rational(cycleBeats, 1);
  final patterns = [
    for (final count in counts) _pattern(random, count, cycleBeats, cycle),
  ];
  final pitches = _pitches(random, counts);

  final instruments = shuffled(random, pool);
  // The densest layers play a little softer, so no layer buries the others.
  final base = switch (layerCount) {
    2 => 0.85,
    3 => 0.75,
    _ => 0.7,
  };
  final byCount = [...counts]..sort();

  final fastest = counts.reduce(math.max) / cycleBeats;
  final maxTempo = fastest > 3 ? 110 : randomLoopMaxTempo;
  final bpm =
      randomLoopMinTempo + random.nextInt(maxTempo - randomLoopMinTempo + 1);

  final layers = [
    for (var i = 0; i < layerCount; i++)
      RhythmLayer(
        id: 'layer-${i + 1}',
        instrumentId: instruments[i % instruments.length],
        pitch: pitches[i],
        pattern: patterns[i],
        phaseSteps: 0,
        swing: Swing(grid: 'off', amount: 0),
        mix: LayerMix(
          gain: _hundredths(
            base - 0.15 * byCount.indexOf(counts[i]) / (layerCount - 1),
          ),
          pan: 0,
          muted: false,
          solo: false,
        ),
      ),
  ];
  Scene scene(String id) => Scene(
    id: id,
    layers: layers,
    masterGain: 0.8,
    drone: Drone(
      enabled: false,
      root: 0,
      octave: 3,
      mode: '',
      chord: 'root',
      gain: 0,
      filterHz: 1000,
      spread: 0,
    ),
  );
  return SessionDocument(
    title: title,
    transport: SessionTransport(bpm: bpm, practiceCycleBeats: cycle),
    referenceClick: ReferenceClick(0),
    randomSeed: seed,
    scenes: [scene('A'), scene('B')],
    defaultSceneId: 'A',
    presentation: Presentation('circle'),
  );
}

final _idPattern = RegExp(r'^[A-Za-z0-9-]{1,64}$');

List<String> _instrumentPool(List<String> ids) {
  for (final id in ids) {
    if (!_idPattern.hasMatch(id)) {
      throw ArgumentError.value(id, 'instrumentIds');
    }
  }
  final pool = ids.toSet().toList();
  return pool.isEmpty
      ? [for (final instrument in factoryInstruments) instrument.id]
      : pool;
}

/// Distinct step counts, one per layer. The first two are a polyrhythm pair
/// scaled by k; each further one is related to an earlier count by a small
/// ratio, or is the beat or the half beat. The slowest layer steps at most
/// every two beats, and no layer goes faster than four steps a beat.
List<int> _stepCounts(math.Random random, int layerCount, int cycleBeats) {
  final most = math.min(_maxSteps, cycleBeats * 4);
  bool calm(int count) => cycleBeats <= 2 * count;
  final pairs = [
    for (final (p, q, weight) in _pairs)
      if (p <= most) ((p, q), weight),
  ];
  final (p, q) = weightedPick(random, pairs);
  final scales = [
    for (var k = 1; k * p <= most; k++)
      if (calm(k * q)) k,
  ];
  final k = scales.isEmpty ? most ~/ p : scales[random.nextInt(scales.length)];
  final counts = shuffled(random, [k * p, k * q]);
  while (counts.length < layerCount) {
    final related = <int>{
      cycleBeats,
      cycleBeats * 2,
      for (final count in counts)
        for (final (a, b) in _ratios) ...[
          if (count * a % b == 0) count * a ~/ b,
          if (count * b % a == 0) count * b ~/ a,
        ],
    };
    var options = [
      for (final c in related)
        if (c >= 2 && c <= most && calm(c) && !counts.contains(c)) c,
    ]..sort();
    if (options.isEmpty) {
      options = [
        for (var c = 2; c <= most; c++)
          if (!counts.contains(c)) c,
      ];
    }
    counts.add(options[random.nextInt(options.length)]);
  }
  return counts;
}

/// [count] steps over one cycle: 30-70 % of them on, the first always on
/// (where the layers meet) and accented 60 % of the time; steps on a beat
/// are twice as likely to be chosen as steps between beats.
Pattern _pattern(
  math.Random random,
  int count,
  int cycleBeats,
  Rational cycle,
) {
  final density = 0.3 + 0.4 * random.nextDouble();
  // Integer bounds: ceil(0.3 n) and floor(0.7 n), never more than all.
  final least = (3 * count + 9) ~/ 10;
  final hits = (density * count).round().clamp(
    least,
    math.max(least, 7 * count ~/ 10),
  );
  final on = {0};
  final candidates = [for (var i = 1; i < count; i++) i];
  int weight(int step) => step * cycleBeats % count == 0 ? 2 : 1;
  while (on.length < hits) {
    final total = candidates.fold(0, (sum, step) => sum + weight(step));
    var pick = random.nextInt(total);
    for (final step in candidates) {
      if (pick < weight(step)) {
        on.add(step);
        candidates.remove(step);
        break;
      }
      pick -= weight(step);
    }
  }
  final accent = random.nextDouble() < 0.6;
  return Pattern(
    durationBeats: cycle,
    steps: [
      for (var i = 0; i < count; i++)
        if (i == 0)
          PatternStep(
            enabled: true,
            velocity: accent ? 1 : 0.9,
            accent: accent,
            probability: 1,
          )
        else if (on.contains(i))
          PatternStep(
            enabled: true,
            // 0.6..0.85 in steps of 0.05: a little life between the hits.
            velocity: _hundredths(0.6 + 0.05 * random.nextInt(6)),
            accent: false,
            probability: 1,
          )
        else
          PatternStep(
            enabled: false,
            velocity: 0.8,
            accent: false,
            probability: 1,
          ),
    ],
  );
}

/// One pitch per layer from a major or minor pentatonic on a root in
/// [randomLoopMinRoot]..[randomLoopMaxRoot], over the octave below and the
/// octave of the root (never below C2). The slowest layer takes the root, or
/// the root an octave down; faster layers take distinct notes above it, the
/// faster the higher.
List<int> _pitches(math.Random random, List<int> counts) {
  final root =
      randomLoopMinRoot +
      random.nextInt(randomLoopMaxRoot - randomLoopMinRoot + 1);
  final scale = random.nextBool() ? _majorPentatonic : _minorPentatonic;
  final notes = [
    for (final octave in const [-12, 0])
      for (final degree in scale)
        if (root + octave + degree >= _lowestPitch) root + octave + degree,
  ];
  final bass = root - 12 >= _lowestPitch && random.nextBool()
      ? root - 12
      : root;
  final above = shuffled(random, [
    for (final note in notes)
      if (note > bass) note,
  ]);
  final chosen = [bass, ...above.take(counts.length - 1)]..sort();
  final order = [for (var i = 0; i < counts.length; i++) i]
    ..sort((a, b) => counts[a].compareTo(counts[b]));
  final pitches = List.filled(counts.length, 0);
  for (var rank = 0; rank < order.length; rank++) {
    pitches[order[rank]] = chosen[rank];
  }
  return pitches;
}

double _hundredths(num value) => (value * 100).round() / 100;
