import 'package:flutter_test/flutter_test.dart';
import 'package:synesterra/data/repositories/impl/noop_playback_repository.dart';
import 'package:synesterra/data/repositories/playback_repository.dart';

import 'playback_fakes.dart' show threeTwo;

void main() {
  test('reports transport state and generation without sound', () async {
    final repository = NoopPlaybackRepository();
    addTearDown(repository.dispose);
    await repository.play(threeTwo());
    expect(repository.status.value.state, PlaybackState.playing);
    expect(repository.status.value.bpm, 120);
    final playing = repository.readPosition();
    expect(playing.playing, isTrue);

    await repository.playSequence(const [], repeatAll: true);
    expect(
      repository.status.value.stopReason,
      PlaybackStopReason.emptySequence,
    );
    expect(repository.position.value.playing, isFalse);
    expect(
      repository.position.value.generation,
      greaterThan(playing.generation),
    );
  });
}
