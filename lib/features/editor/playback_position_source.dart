import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import '../../data/repositories/playback_repository.dart';
import '../../shared/loop_view/position_source.dart';

/// The playback side's position in the visualizations' terms. The fields
/// mean the same on both sides (docs/modules/loop-view.md and playback.md):
/// `cycleIndex` counts whole cycles since the loop, or the current
/// arrangement section, began.
LoopPosition loopPositionOf(PlaybackPosition position) => LoopPosition(
  playing: position.playing,
  cyclePosition: position.cyclePosition,
  cycleIndex: position.cycleIndex,
  generation: position.generation,
  sectionIndex: position.sectionIndex,
);

/// A [PositionSource] over a [PlaybackRepository].
///
/// It follows the published position, and while the transport plays it also
/// takes a fresh audio clock reading ([PlaybackRepository.readPosition]) once
/// per frame, so the playhead moves smoothly. The frame only decides when to
/// read; the value always comes from the audio clock. It never sends a
/// transport command.
class PlaybackPositionSource extends ValueNotifier<LoopPosition>
    implements PositionSource {
  PlaybackPositionSource(this._playback)
    : super(loopPositionOf(_playback.position.value)) {
    _ticker = Ticker(_onFrame, debugLabel: 'PlaybackPositionSource');
    _playback.position.addListener(_onPublished);
    _follow(_playback.position.value);
  }

  final PlaybackRepository _playback;
  late final Ticker _ticker;

  void _onPublished() => _follow(_playback.position.value);

  void _onFrame(Duration _) => _follow(_playback.readPosition());

  void _follow(PlaybackPosition position) {
    value = loopPositionOf(position);
    if (position.playing) {
      if (!_ticker.isActive) _ticker.start();
    } else if (_ticker.isActive) {
      _ticker.stop();
    }
  }

  @override
  void dispose() {
    _playback.position.removeListener(_onPublished);
    _ticker.dispose();
    super.dispose();
  }
}
