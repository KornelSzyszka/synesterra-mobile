import 'package:flutter_test/flutter_test.dart';
import 'package:synesterra/data/repositories/playback_repository.dart';
import 'package:synesterra/features/arrangement/playback_position_source.dart';
import 'package:synesterra/shared/loop_view/position_source.dart';

import 'arrangement_fakes.dart';

void main() {
  test('maps every field, keeping the original section index', () {
    expect(
      loopPositionOf(
        PlaybackPosition(
          playing: true,
          cyclePosition: .25,
          cycleIndex: 3,
          generation: 7,
          sectionIndex: 2,
        ),
      ),
      LoopPosition(
        playing: true,
        cyclePosition: .25,
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

  test('follows the repository position and stops following on dispose', () {
    final playback = RecordingPlayback();
    final source = PlaybackPositionSource(playback);
    var notified = 0;
    source.addListener(() => notified++);
    playback.positionNotifier.value = PlaybackPosition(
      playing: true,
      cyclePosition: .5,
      cycleIndex: 1,
      generation: 2,
      sectionIndex: 0,
    );
    expect(notified, 1);
    expect(source.value.sectionIndex, 0);
    expect(source.value.cyclePosition, .5);
    source.dispose();
    playback.positionNotifier.value = PlaybackPosition.stopped(3);
  });
}
