import 'dart:convert';
import 'dart:io';

import 'package:synesterra_core/synesterra_core.dart';
import 'package:test/test.dart';

PatternStep step({
  bool enabled = true,
  num velocity = 1,
  bool accent = false,
  num probability = 1,
}) => PatternStep(
  enabled: enabled,
  velocity: velocity,
  accent: accent,
  probability: probability,
);

RhythmLayer layer(
  String id,
  int stepCount, {
  Rational? duration,
  List<PatternStep>? steps,
  int phase = 0,
  String swingGrid = 'off',
  num swingAmount = 0,
  num gain = 1,
  num pan = 0,
  bool muted = false,
  bool solo = false,
  String sound = 'wood',
}) => RhythmLayer(
  id: id,
  sound: sound,
  pattern: Pattern(
    durationBeats: duration ?? Rational(4, 1),
    steps: steps ?? List.generate(stepCount, (_) => step()),
  ),
  phaseSteps: phase,
  swing: Swing(grid: swingGrid, amount: swingAmount),
  mix: LayerMix(gain: gain, pan: pan, muted: muted, solo: solo),
);

SessionDocument document(
  List<RhythmLayer> layers, {
  int seed = 0,
  num master = 1,
}) {
  Scene scene(String id) => Scene(
    id: id,
    layers: layers,
    masterGain: master,
    drone: Drone(
      enabled: false,
      root: 0,
      octave: 1,
      mode: '',
      chord: 'root',
      gain: 0,
      filterHz: 100,
      spread: 0,
    ),
  );
  return SessionDocument(
    title: '',
    transport: SessionTransport(bpm: 120, practiceCycleBeats: Rational(4, 1)),
    referenceClick: ReferenceClick(0),
    randomSeed: seed,
    scenes: [scene('A'), scene('B')],
    defaultSceneId: 'A',
    presentation: Presentation('circle'),
  );
}

List<String> signatures(List<PlannedRhythmEvent> events) => [
  for (final event in events)
    '${event.beat}:${event.layerIndex}:${event.stepIndex}:${event.cycleIndex}:${event.eventId}',
];

void main() {
  test('SessionProject resolves a selected scene and rejects unknown IDs', () {
    final source = document([layer('one', 2), layer('two', 3)]);
    final project = SessionProject(source, sceneId: 'B');
    expect(project.sceneId, 'B');
    expect(project.transport, source.transport);
    expect(project.randomSeed, source.randomSeed);
    expect(project.layers, source.scenes[1].layers);
    expect(() => SessionProject(source, sceneId: 'C'), throwsArgumentError);
  });

  test('3:2 and 5:4 match the C0 beat/order fixtures', () {
    final fixture = jsonDecode(
      File('../../test/data/audio/fixtures/polyrhythms.json')
          .readAsStringSync(),
    ) as Map<String, dynamic>;
    for (final (name, counts) in <(String, List<int>)>[
      ('3:2', [3, 2]),
      ('5:4', [5, 4]),
    ]) {
      final planned = EventPlanner(
        SessionProject(
          document([
            layer('first', counts[0]),
            layer('second', counts[1], sound: 'sine'),
          ]),
        ),
      ).plan(0, 3840);
      final expected = fixture[name] as List<dynamic>;
      expect(planned.map((event) => event.beat).toList(), [
        for (final row in expected) (row as Map<String, dynamic>)['beat'],
      ]);
      expect(planned.map((event) => event.layerIndex).toList(), [
        for (final row in expected)
          (row as Map<String, dynamic>)['sound'] ==
                  (name == '3:2' ? 'three' : 'five')
              ? 0
              : 1,
      ]);
    }
  });

  test('half-open windows partition every event and keep IDs stable', () {
    final planner = EventPlanner(
      SessionProject(
        document([
          layer('seven', 7, duration: Rational(5, 1)),
          layer('five', 5, duration: Rational(7, 1)),
        ]),
      ),
    );
    final whole = planner.plan(0, 20000);
    for (var split = 0; split <= 20000; split += 137) {
      expect(
        signatures([...planner.plan(0, split), ...planner.plan(split, 20000)]),
        signatures(whole),
        reason: 'split at $split',
      );
    }
    final boundaryPlanner = EventPlanner(
      SessionProject(
        document([layer('quarters', 4), layer('silent', 2, muted: true)]),
      ),
    );
    expect(
      boundaryPlanner.plan(0, 960).any((event) => event.beat == 960),
      false,
    );
    expect(
      boundaryPlanner.plan(960, 1920).any((event) => event.beat == 960),
      true,
    );
    expect(() => planner.plan(-1, 10), throwsRangeError);
    expect(() => planner.plan(2, 1), throwsRangeError);
  });

  test('phase wraps step positions within each period', () {
    final planner = EventPlanner(
      SessionProject(
        document([
          layer('phased', 4, phase: 3),
          layer('plain', 4, muted: true),
        ]),
      ),
    );
    expect(planner.plan(0, 3840).map((e) => e.beat).toList(), [
      0,
      960,
      1920,
      2880,
    ]);
    expect(planner.plan(0, 960).single.stepIndex, 1);
  });

  test('eighth and sixteenth swing delay alternate grid points', () {
    final eighth = EventPlanner(
      SessionProject(
        document([
          layer('swing', 8, swingGrid: 'eighth', swingAmount: 1),
          layer('silent', 2, muted: true),
        ]),
      ),
    );
    expect(eighth.plan(0, 3840).map((e) => e.beat).toList(), [
      0,
      720,
      960,
      1680,
      1920,
      2640,
      2880,
      3600,
    ]);
    final sixteenth = EventPlanner(
      SessionProject(
        document([
          layer('swing', 16, swingGrid: 'sixteenth', swingAmount: 0.5),
          layer('silent', 2, muted: true),
        ]),
      ),
    );
    expect(sixteenth.plan(0, 500).map((e) => e.beat).toList(), [0, 300, 480]);
  });

  test(
    'step intent and mix stay separate; muted and solo layers are silent',
    () {
      final planner = EventPlanner(
        SessionProject(
          document([
            layer(
              'lead',
              2,
              steps: [step(velocity: 0.25, accent: true), step(enabled: false)],
              gain: 0.4,
              pan: -0.5,
              solo: true,
              sound: 'bell',
            ),
            layer('other', 2),
          ], master: 0.7),
        ),
      );
      final events = planner.plan(0, 3840);
      expect(events, hasLength(1));
      final event = events.single;
      expect(
        (event.layerId, event.sound, event.velocity, event.accent),
        ('lead', 'bell', 0.25, true),
      );
      expect((event.layerGain, event.masterGain, event.pan), (0.4, 0.7, -0.5));
      expect(event.eventId, 0);
      expect(planner.plan(3840, 7680).single.eventId, 128);
    },
  );

  test('a muted solo does not silence an otherwise audible layer', () {
    final planner = EventPlanner(
      SessionProject(
        document([
          layer('muted-solo', 2, muted: true, solo: true),
          layer('audible', 2),
        ]),
      ),
    );
    expect(planner.plan(0, 3840).map((event) => event.layerId).toList(), [
      'audible',
      'audible',
    ]);
  });

  test('probability is seed-based, stable, and independent of windows', () {
    EventPlanner seeded(int seed) => EventPlanner(
      SessionProject(
        document([
          layer(
            'chance',
            4,
            steps: List.generate(4, (_) => step(probability: 0.5)),
          ),
          layer('always', 4, muted: true),
        ], seed: seed),
      ),
    );
    final planner = seeded(1234);
    final whole = planner.plan(0, 38400);
    expect(signatures(whole), signatures(planner.plan(0, 38400)));
    expect(
      signatures([...planner.plan(0, 19000), ...planner.plan(19000, 38400)]),
      signatures(whole),
    );
    expect(signatures(whole), isNot(signatures(seeded(1235).plan(0, 38400))));
    expect(whole.take(5).map((e) => (e.beat, e.eventId)).toList(), [
      (0, 0),
      (960, 4),
      (2880, 12),
      (3840, 128),
      (4800, 132),
    ]);
  });

  test('probability zero rejects and one always plays', () {
    final planner = EventPlanner(
      SessionProject(
        document([
          layer(
            'mixed',
            2,
            steps: [step(probability: 0), step(probability: 1)],
          ),
          layer('silent', 2, muted: true),
        ], seed: 0xffffffff),
      ),
    );
    expect(planner.plan(0, 7680).map((event) => event.beat).toList(), [
      1920,
      5760,
    ]);
  });

  test('non-grid periods are rounded once with at most half-tick error', () {
    for (final (steps, period) in <(int, Rational)>[
      (7, Rational(5, 1)),
      (5, Rational(7, 1)),
    ]) {
      final planned = EventPlanner(
        SessionProject(
          document([
            layer('fractional', steps, duration: period),
            layer('silent', 2, muted: true),
          ]),
        ),
      ).plan(0, 960 * period.numerator);
      for (final event in planned) {
        final exactNumerator =
            (event.cycleIndex * steps + event.stepIndex) *
            period.numerator *
            ticksPerQuarter;
        final exactDenominator = period.denominator * steps;
        expect(
          (event.beat * exactDenominator - exactNumerator).abs() * 2,
          lessThanOrEqualTo(exactDenominator),
        );
      }
    }
  });

  test('a distant window expands only nearby cycles', () {
    final planner = EventPlanner(
      SessionProject(
        document([
          layer('fractional', 7, duration: Rational(7, 3)),
          layer('silent', 2, muted: true),
        ]),
      ),
    );
    final from = 100000000;
    final events = planner.plan(from, from + 960);
    expect(events, isNotEmpty);
    expect(
      events.every((event) => event.beat >= from && event.beat < from + 960),
      true,
    );
    expect(
      signatures([
        ...planner.plan(from, from + 480),
        ...planner.plan(from + 480, from + 960),
      ]),
      signatures(events),
    );
  });
}
