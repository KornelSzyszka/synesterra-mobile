import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:synesterra/data/audio/playback_scheduler.dart';
import 'package:synesterra/data/audio/soloud_voice_sink.dart'
    show concurrentVoiceLimit;
import 'package:synesterra/data/repositories/impl/engine_playback_repository.dart';
import 'package:synesterra/data/repositories/playback_repository.dart';
import 'package:synesterra_core/synesterra_core.dart';

import 'playback_fakes.dart';

/// Play at clock 0 with minLead 10 ms and startPad 30 ms: beat 0 is here.
const anchor = 40000;

/// Unaccented, full velocity and gains: 1 * 0.7 * 0.6.
const fullGain = 0.42;

void main() {
  test('a 3:2 loop sounds each planned hit once, at its time', () async {
    final h = Harness();
    addTearDown(h.repository.dispose);
    await h.repository.play(threeTwo());
    expect(h.repository.status.value.state, PlaybackState.playing);
    expect(h.repository.status.value.bpm, 120);
    h.runTo(2100000);

    expect(h.times('playback-0'), [
      for (final tick in [0, 1280, 2560, 3840]) at(anchor, tick),
    ]);
    expect(h.times('playback-1'), [
      for (final tick in [0, 1920, 3840]) at(anchor, tick),
    ]);
    expect(h.sink.sounded.map((e) => e.event.gain).toSet(), {
      closeTo(fullGain, 1e-9),
    });
    // One buffer per (instrument, pitch), rendered at the pitch frequency.
    expect(h.renders.map((r) => r.hz), [440, closeTo(220, 1e-9)]);
  });

  test('the position follows the clock within the cycle', () async {
    final h = Harness();
    addTearDown(h.repository.dispose);
    await h.repository.play(threeTwo());
    final generation = h.repository.readPosition().generation;
    h.runTo(at(anchor, 960));
    var position = h.repository.readPosition();
    expect(position.playing, isTrue);
    expect(position.cyclePosition, closeTo(0.25, 1e-3));
    expect(position.cycleIndex, 0);
    expect(position.sectionIndex, isNull);
    expect(position.generation, generation);
    expect(h.repository.position.value, position);
    h.runTo(at(anchor, 3840 + 1920));
    position = h.repository.readPosition();
    expect(position.cycleIndex, 1);
    expect(position.cyclePosition, closeTo(0.5, 1e-3));
  });

  test('the heard position lags render time by the fallback latency', () async {
    final h = Harness();
    addTearDown(h.repository.dispose);
    h.clock.fallbackOutputLatency = const Duration(milliseconds: 50);
    await h.repository.play(threeTwo());
    h.runTo(at(anchor, 960) + 50000);
    expect(h.repository.readPosition().cyclePosition, closeTo(0.25, 1e-3));
  });

  test('stop silences pending hits and resets the position', () async {
    final h = Harness();
    addTearDown(h.repository.dispose);
    await h.repository.play(threeTwo());
    h.runTo(600000);
    expect(h.sink.pending, isNotEmpty);
    final before = h.repository.readPosition().generation;
    final scheduledBefore = h.sink.scheduled.length;

    await h.repository.stop();
    expect(h.sink.pending, isEmpty);
    expect(h.engine.log.last, 'stop');
    expect(h.repository.status.value.state, PlaybackState.stopped);
    expect(h.repository.status.value.stopReason, PlaybackStopReason.user);
    final position = h.repository.position.value;
    expect(position.playing, isFalse);
    expect(position.cyclePosition, 0);
    expect(position.generation, greaterThan(before));

    h.engine.clock.state = EngineState.running; // even if the clock ran on
    h.runTo(3000000);
    expect(h.sink.scheduled.length, scheduledBefore);
    expect(
      h.sink.sounded.where((e) => e.event.at.microseconds > 600000),
      isEmpty,
    );
  });

  test('a structural change drops stale hits and restarts the cycle', () async {
    final h = Harness();
    addTearDown(h.repository.dispose);
    await h.repository.play(threeTwo());
    h.runTo(600000);
    final stale = at(anchor, 1280);
    expect(h.sink.pending.map((e) => e.event.at.microseconds), [stale]);
    final old = h.sink.pending.single.generation;

    final changed = loopDocument([
      (id: 'three', instrumentId: 'factory-wood', pitch: 69, steps: 4),
      (id: 'two', instrumentId: 'factory-sine', pitch: 57, steps: 2),
    ]);
    await h.repository.play(changed);
    final generation = h.repository.readPosition().generation;
    expect(generation, greaterThan(old));
    expect(h.repository.readPosition().cyclePosition, 0);
    h.runTo(1700000);

    final after = h.sink.sounded.where((e) => e.event.at.microseconds > 600000);
    expect(after.map((e) => e.generation).toSet(), {generation});
    expect(h.times('playback-0'), isNot(contains(stale)));
    // The new structure starts from its own cycle start.
    const restart = 600000 + anchor;
    expect(h.times('playback-0').where((t) => t > 600000), [
      for (final tick in [0, 960, 1920]) at(restart, tick),
    ]);
  });

  test('a tempo change keeps the phase, cancels and replans', () async {
    final h = Harness();
    addTearDown(h.repository.dispose);
    await h.repository.play(threeTwo());
    h.runTo(1000000);
    final before = h.repository.readPosition();
    final staleTwo = at(anchor, 1920);
    expect(
      h.sink.pending.map((e) => e.event.at.microseconds),
      contains(staleTwo),
    );

    h.repository.setTempo(60);
    final after = h.repository.readPosition();
    expect(after.generation, greaterThan(before.generation));
    expect(after.cycleIndex, before.cycleIndex);
    expect(after.cyclePosition, closeTo(before.cyclePosition, 0.005));
    expect(h.engine.log.last, startsWith('schedule:'));
    expect(h.repository.status.value.bpm, 60);

    h.runTo(1200000);
    // Beat 1862 sits at 1.01 s; beat 1920 now follows 58 ticks at 60 BPM.
    expect(h.times('playback-1'), [at(anchor, 0), 1010000 + 60417]);
    expect(h.times('playback-1'), isNot(contains(staleTwo)));
  });

  test('a document that differs only in tempo is a tempo change', () async {
    final h = Harness();
    addTearDown(h.repository.dispose);
    await h.repository.play(threeTwo());
    h.runTo(1000000);
    final before = h.repository.readPosition();
    await h.repository.play(threeTwo(bpm: 60));
    final after = h.repository.readPosition();
    expect(after.generation, greaterThan(before.generation));
    expect(after.cyclePosition, closeTo(before.cyclePosition, 0.005));
    expect(h.renders, hasLength(2)); // no new buffers, no restart
  });

  test('volume changes apply without replanning', () async {
    final h = Harness();
    addTearDown(h.repository.dispose);
    await h.repository.play(threeTwo());
    h.runTo(600000);
    final generation = h.repository.readPosition().generation;
    final cancels = h.engine.log.where((l) => l.startsWith('cancel')).length;

    h.repository.setLayerGain('three', 0.5);
    await h.repository.play(threeTwo(gain: 1)); // identical: nothing changes
    h.runTo(1500000);
    expect(h.repository.readPosition().generation, generation);
    expect(
      h.engine.log.where((l) => l.startsWith('cancel')),
      hasLength(cancels),
    );
    final three = h.sink.sounded.where((e) => e.event.sound == 'playback-0');
    // The hit queued before the change keeps its gain; later ones follow.
    expect(three.map((e) => e.event.gain), [
      closeTo(fullGain, 1e-9),
      closeTo(fullGain, 1e-9),
      closeTo(fullGain / 2, 1e-9),
    ]);

    await h.repository.play(threeTwo(gain: 0.25));
    h.runTo(2700000);
    expect(h.repository.readPosition().generation, generation);
    expect(h.sink.sounded.last.event.gain, closeTo(fullGain / 4, 1e-9));
  });

  test('a missing instrument is a silent layer, reported in status', () async {
    final h = Harness();
    addTearDown(h.repository.dispose);
    await h.repository.play(
      loopDocument([
        (id: 'three', instrumentId: 'factory-wood', pitch: 69, steps: 3),
        (id: 'two', instrumentId: 'deleted-sound', pitch: 57, steps: 2),
      ]),
    );
    expect(h.repository.status.value.state, PlaybackState.playing);
    expect(h.repository.status.value.missingInstrumentIds, {'deleted-sound'});
    h.runTo(2100000);
    expect(h.sink.sounded.map((e) => e.event.sound).toSet(), {'playback-0'});
    expect(h.times('playback-0'), hasLength(4));
    expect(h.renders, hasLength(1));
  });

  test('library instruments resolve; buffers are shared and cached', () async {
    final bell = factoryInstruments[2].copyWith(
      id: 'my-bell',
      name: 'My bell',
      decayMs: 333,
    );
    final h = Harness(library: [bell]);
    addTearDown(h.repository.dispose);
    final document = loopDocument([
      (id: 'a', instrumentId: 'my-bell', pitch: 60, steps: 3),
      (id: 'b', instrumentId: 'my-bell', pitch: 60, steps: 2),
    ]);
    await h.repository.play(document);
    expect(h.renders.single.decayMs, 333);
    expect(h.renders.single.hz, closeTo(261.63, 0.01));
    final firstLoad = h.engine.log.indexWhere((l) => l.startsWith('load:'));
    final firstSchedule = h.engine.log.indexWhere(
      (l) => l.startsWith('schedule:'),
    );
    expect(firstLoad, lessThan(firstSchedule));

    await h.repository.stop();
    await h.repository.play(document);
    expect(h.renders, hasLength(1));
    expect(h.repository.status.value.missingInstrumentIds, isEmpty);
  });

  test('the voice cap is requested from the session and verified', () async {
    final h = Harness();
    addTearDown(h.repository.dispose);
    await h.repository.play(threeTwo());
    final ring = [
      for (final i in factoryInstruments.take(2)) i.attackMs + i.decayMs,
    ].reduce((a, b) => a > b ? a : b);
    final expected = concurrentVoiceLimit(
      layers: 2,
      bpm: 120,
      hitsPerQuarterPerLayer: 3 / 4,
      maxRing: Duration(milliseconds: ring),
      horizon: PlaybackScheduler.horizon,
      droneVoices: 0,
      auditionVoices: 8,
    );
    expect(h.engine.voiceLimits, [expected]);
    expect(h.repository.status.value.voiceLimit, expected);

    final refused = Harness();
    addTearDown(refused.repository.dispose);
    refused.engine.refuseVoiceLimit = true;
    await refused.repository.play(threeTwo());
    final status = refused.repository.status.value;
    expect(status.state, PlaybackState.stopped);
    expect(status.stopReason, PlaybackStopReason.error);
    expect(status.error, contains('voice limit refused'));
    expect(refused.sink.scheduled, isEmpty);
    expect(refused.engine.clock.state, EngineState.stopped);
    expect(refused.engine.log.last, 'stop');
  });

  test('stop during a slow engine start leaves the engine stopped', () async {
    final h = Harness();
    addTearDown(h.repository.dispose);
    h.engine.startGate = Completer<void>();
    final playing = h.repository.play(threeTwo());
    final stopping = h.repository.stop();
    h.engine.startGate!.complete();
    await playing;
    await stopping;
    expect(h.engine.clock.state, EngineState.stopped);
    expect(h.engine.log.where((l) => l == 'start' || l == 'stop').last, 'stop');
    expect(h.repository.status.value.state, PlaybackState.stopped);
    expect(h.sink.scheduled, isEmpty);
  });

  test('a render finishing after dispose loads nothing', () async {
    final h = Harness();
    h.renderGate = Completer<void>();
    final playing = h.repository.play(threeTwo());
    await Future<void>.delayed(Duration.zero);
    final disposing = h.repository.dispose();
    h.renderGate!.complete();
    await playing;
    await disposing;
    final disposedAt = h.engine.log.indexOf('dispose');
    expect(disposedAt, isNonNegative);
    expect(h.engine.log.skip(disposedAt + 1), isEmpty);
    expect(h.engine.buffers, isEmpty);
  });

  test('renders off the UI isolate the same samples as the core', () async {
    final instrument = factoryInstruments.first;
    final samples = await renderPlaybackBufferInIsolate(instrument, 440);
    expect(samples, renderInstrument(instrument, fundamentalHz: 440));
  });

  group('sequence', () {
    // Section 0: one-beat cycle, played twice (1920 ticks); section 1: once.
    final first = loopDocument([
      (id: 'a', instrumentId: 'factory-wood', pitch: 69, steps: 4),
      (id: 'b', instrumentId: 'factory-sine', pitch: 57, steps: 1),
    ], cycleBeats: 1);
    final second = loopDocument([
      (id: 'a', instrumentId: 'factory-wood', pitch: 81, steps: 2),
      (id: 'b', instrumentId: 'factory-sine', pitch: 57, steps: 1),
    ], cycleBeats: 1);
    List<PlaybackSection> sections() => [
      PlaybackSection(originalIndex: 2, document: first, repeats: 2),
      PlaybackSection(originalIndex: 5, document: second, repeats: 1),
    ];

    test('switches on the cycle boundary without cutting the tail', () async {
      final h = Harness();
      addTearDown(h.repository.dispose);
      await h.repository.playSequence(sections(), repeatAll: false);
      final generation = h.repository.readPosition().generation;

      h.runTo(at(anchor, 1900));
      var position = h.repository.readPosition();
      expect(position.sectionIndex, 2);
      expect(position.cycleIndex, 1);
      expect(position.cyclePosition, closeTo(940 / 960, 2e-3));
      expect(position.generation, generation);

      h.runTo(at(anchor, 1940));
      position = h.repository.readPosition();
      expect(position.sectionIndex, 5);
      expect(position.cycleIndex, 0);
      expect(position.cyclePosition, closeTo(20 / 960, 2e-3));
      expect(position.generation, generation + 1);

      h.runTo(at(anchor, 2880) + 100000);
      expect(h.times('playback-0'), [
        for (var tick = 0; tick < 1920; tick += 240) at(anchor, tick),
      ]);
      expect(h.times('playback-2'), [at(anchor, 1920), at(anchor, 2400)]);
      expect(h.times('playback-1'), [
        for (final tick in [0, 960, 1920]) at(anchor, tick),
      ]);
      final sectionOne = h.sink.sounded.where(
        (e) => e.event.at.microseconds >= at(anchor, 1920),
      );
      expect(sectionOne.map((e) => e.generation).toSet(), {generation + 1});
      // Only the start cancelled; the boundary was a handover.
      final cancels = h.engine.log.where((l) => l.startsWith('cancel'));
      expect(cancels, hasLength(2)); // start, then the final stop

      final status = h.repository.status.value;
      expect(status.state, PlaybackState.stopped);
      expect(status.stopReason, PlaybackStopReason.finished);
      expect(h.repository.position.value.playing, isFalse);
      await Future<void>.delayed(Duration.zero);
      expect(h.engine.clock.state, EngineState.stopped);
      expect(h.engine.log.last, 'stop');
    });

    test('a read on the boundary before the next planner tick', () async {
      final h = Harness();
      addTearDown(h.repository.dispose);
      await h.repository.playSequence(sections(), repeatAll: false);
      final generation = h.repository.readPosition().generation;
      // The clock moves on, but no scheduler wake has happened yet.
      h.clock.microseconds = at(anchor, 1930);
      final position = h.repository.readPosition();
      expect(position.sectionIndex, 5);
      expect(position.cycleIndex, 0);
      expect(position.cyclePosition, closeTo(10 / 960, 2e-3));
      expect(position.generation, generation + 1);
      // The planner then assigns the same generation to that section.
      h.runTo(at(anchor, 2000));
      expect(h.repository.readPosition().generation, generation + 1);
    });

    test('a newer start loads a buffer an abandoned start left', () async {
      final h = Harness();
      addTearDown(h.repository.dispose);
      h.renderGate = Completer<void>();
      final first = h.repository.play(threeTwo());
      await Future<void>.delayed(Duration.zero);
      final second = h.repository.play(threeTwo(gain: 0.5));
      h.renderGate!.complete();
      await first;
      await second;
      expect(h.repository.status.value.state, PlaybackState.playing);
      expect(h.engine.buffers, {'playback-0', 'playback-1'});
    });

    test('repeat all wraps to the first section', () async {
      final h = Harness();
      addTearDown(h.repository.dispose);
      await h.repository.playSequence(sections(), repeatAll: true);
      final generation = h.repository.readPosition().generation;
      h.runTo(at(anchor, 2880 + 100));
      final position = h.repository.readPosition();
      expect(h.repository.status.value.state, PlaybackState.playing);
      expect(position.sectionIndex, 2);
      expect(position.cycleIndex, 0);
      expect(position.generation, generation + 2);
      expect(h.times('playback-0'), contains(at(anchor, 2880)));
      expect(h.engine.log.where((l) => l.startsWith('cancel')), hasLength(1));
    });

    test('an empty list stops with a clear state', () async {
      final h = Harness();
      addTearDown(h.repository.dispose);
      await h.repository.play(threeTwo());
      h.runTo(600000);
      await h.repository.playSequence(const [], repeatAll: true);
      final status = h.repository.status.value;
      expect(status.state, PlaybackState.stopped);
      expect(status.stopReason, PlaybackStopReason.emptySequence);
      expect(h.sink.pending, isEmpty);
      // The engine is stopped too, like Stop: no device held open.
      expect(h.engine.clock.state, EngineState.stopped);
      expect(h.engine.log.last, 'stop');
      h.runTo(2000000);
      expect(
        h.sink.sounded.where((e) => e.event.at.microseconds > 600000),
        isEmpty,
      );
    });

    test('rejects invalid sections', () {
      expect(
        () => PlaybackSection(originalIndex: 0, document: first, repeats: 0),
        throwsArgumentError,
      );
      expect(
        () => PlaybackSection(originalIndex: -1, document: first, repeats: 1),
        throwsArgumentError,
      );
    });
  });
}
