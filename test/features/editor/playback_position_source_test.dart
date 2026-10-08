import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synesterra/data/repositories/playback_repository.dart';
import 'package:synesterra/features/editor/playback_position_source.dart';
import 'package:synesterra/shared/loop_view/position_source.dart';

/// Only the position side of a playback repository, under test control.
class PositionOnlyPlayback implements PlaybackRepository {
  final positionNotifier = ValueNotifier(PlaybackPosition.stopped(0));

  /// What a fresh audio clock reading returns.
  PlaybackPosition clock = PlaybackPosition.stopped(0);
  int reads = 0;

  @override
  ValueListenable<PlaybackPosition> get position => positionNotifier;

  @override
  PlaybackPosition readPosition() {
    reads++;
    return clock;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

PlaybackPosition at(
  double position, {
  bool playing = true,
  int cycle = 0,
  int generation = 1,
  int? section,
}) => PlaybackPosition(
  playing: playing,
  cyclePosition: position,
  cycleIndex: cycle,
  generation: generation,
  sectionIndex: section,
);

void main() {
  test('maps every field of the playback position one to one', () {
    expect(
      loopPositionOf(at(0.25, cycle: 3, generation: 7, section: 2)),
      LoopPosition(
        playing: true,
        cyclePosition: 0.25,
        cycleIndex: 3,
        generation: 7,
        sectionIndex: 2,
      ),
    );
    expect(
      loopPositionOf(PlaybackPosition.stopped(4)),
      LoopPosition(generation: 4),
    );
  });

  testWidgets('follows the published position and reads the clock per frame '
      'only while playing', (tester) async {
    final playback = PositionOnlyPlayback();
    final source = PlaybackPositionSource(playback);
    addTearDown(source.dispose);
    expect(source, isA<PositionSource>());
    expect(source.value, LoopPosition());

    await tester.pump(const Duration(milliseconds: 16));
    expect(playback.reads, 0, reason: 'stopped: no frame reads');

    playback.clock = at(0.1);
    playback.positionNotifier.value = at(0.05);
    expect(source.value.cyclePosition, 0.05);

    await tester.pump(const Duration(milliseconds: 16));
    expect(playback.reads, greaterThan(0));
    expect(source.value.cyclePosition, 0.1);

    playback.clock = at(0.6, cycle: 1);
    await tester.pump(const Duration(milliseconds: 16));
    expect(source.value, loopPositionOf(at(0.6, cycle: 1)));

    // Stop: the published stop wins and frame reads end.
    playback.clock = PlaybackPosition.stopped(2);
    playback.positionNotifier.value = PlaybackPosition.stopped(2);
    expect(source.value, LoopPosition(generation: 2));
    final reads = playback.reads;
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));
    expect(playback.reads, reads);
  });

  testWidgets('a frame read that finds the transport stopped ends the frame '
      'reads', (tester) async {
    final playback = PositionOnlyPlayback();
    final source = PlaybackPositionSource(playback);
    addTearDown(source.dispose);
    playback.clock = at(0.2);
    playback.positionNotifier.value = at(0.2);
    await tester.pump(const Duration(milliseconds: 16));
    playback.clock = PlaybackPosition.stopped(3);
    await tester.pump(const Duration(milliseconds: 16));
    expect(source.value.playing, isFalse);
    final reads = playback.reads;
    await tester.pump(const Duration(milliseconds: 16));
    expect(playback.reads, reads);
  });

  testWidgets('starts reading when created while already playing', (
    tester,
  ) async {
    final playback = PositionOnlyPlayback();
    playback.positionNotifier.value = at(0.3);
    playback.clock = at(0.4);
    final source = PlaybackPositionSource(playback);
    expect(source.value.cyclePosition, 0.3);
    await tester.pump(const Duration(milliseconds: 16));
    expect(source.value.cyclePosition, 0.4);
    // Disposing while playing cancels the pending frame read.
    source.dispose();
  });

  testWidgets('dispose stops listening', (tester) async {
    final playback = PositionOnlyPlayback();
    PlaybackPositionSource(playback).dispose();
    playback.positionNotifier.value = at(0.5);
    await tester.pump(const Duration(milliseconds: 16));
    expect(playback.reads, 0);
  });
}
