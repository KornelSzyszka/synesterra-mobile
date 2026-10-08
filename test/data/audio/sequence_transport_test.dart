import 'package:flutter_test/flutter_test.dart';
import 'package:synesterra/data/audio/sequence_transport.dart';
import 'package:synesterra/data/repositories/loop.dart';
import 'package:synesterra_core/synesterra_core.dart';

import '../playback_fakes.dart';

TransportSection section(int originalIndex) => TransportSection(
  document: simpleLoopDocument(
    bpm: 120,
    cycleBeats: 1,
    layers: const [
      LoopLayerSpec(instrumentId: 'factory-wood', pitch: 69, hits: 3),
      LoopLayerSpec(instrumentId: 'factory-bell', pitch: 76, hits: 2),
    ],
  ),
  soundIds: const {'layer-1': 'a', 'layer-2': 'b'},
  originalIndex: originalIndex,
  repeats: 1,
);

void main() {
  test('repeat all keeps a bounded timeline over many passes', () {
    final clock = FakeClock()..state = EngineState.running;
    final transport = SequenceTransport(clock)
      ..start(
        [section(0), section(1)],
        repeatAll: true,
        bpm: 120,
        anchorTime: AudioTime(0),
      );
    // 120 BPM, one-beat cycles: a section lasts 500 ms. Like the scheduler,
    // wake every 25 ms and plan a 200 ms horizon ahead.
    const cycles = 2000;
    int? plannedTo;
    var maxSegments = 0;
    var maxMarks = 0;
    for (var t = 0; t <= cycles * 500000; t += 25000) {
      clock.microseconds = t;
      final snapshot = transport.snapshot;
      final from = plannedTo ?? snapshot.tempoMap.beatAt(AudioTime(t + 10000));
      var to = snapshot.tempoMap.beatAt(AudioTime(t + 210000));
      final limit = snapshot.planUntilBeat;
      if (limit != null && to > limit) to = limit;
      if (to > from) {
        transport.plan(from, to);
        plannedTo = to;
      }
      if (transport.retainedSegments > maxSegments) {
        maxSegments = transport.retainedSegments;
      }
      if (transport.retainedMarks > maxMarks) {
        maxMarks = transport.retainedMarks;
      }
    }
    expect(maxSegments, lessThanOrEqualTo(4));
    expect(maxMarks, lessThanOrEqualTo(4));

    // Still right after the pruning: cycle 2000.25 is section 0 again.
    clock.microseconds = cycles * 500000 + 125000;
    final position = transport.positionAt(clock.now());
    expect(position.sectionIndex, 0);
    expect(position.cyclePosition, closeTo(.25, 1e-9));
  });
}
