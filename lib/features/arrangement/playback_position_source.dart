import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import '../../data/repositories/playback_repository.dart';
import '../../shared/loop_view/position_source.dart';

/// The playback repository's position as the loop views read it. Every
/// field is copied; `sectionIndex` stays the arrangement's original index.
LoopPosition loopPositionOf(PlaybackPosition position) => LoopPosition(
  playing: position.playing,
  cyclePosition: position.cyclePosition,
  cycleIndex: position.cycleIndex,
  generation: position.generation,
  sectionIndex: position.sectionIndex,
);

/// Adapts [PlaybackRepository.position] to a [PositionSource].
///
/// It follows the repository's notifications (about every 25 ms). With a
/// [vsync] it also reads a fresh position once per frame while playing, so
/// progress moves smoothly; the value always comes from the audio clock, the
/// frame only decides when to read it. It never drives transport.
class PlaybackPositionSource extends ValueNotifier<LoopPosition>
    implements PositionSource {
  PlaybackPositionSource(this._playback, {TickerProvider? vsync})
    : super(loopPositionOf(_playback.position.value)) {
    _ticker = vsync?.createTicker((_) => _read(_playback.readPosition()));
    _playback.position.addListener(_onPosition);
    _onPosition();
  }

  final PlaybackRepository _playback;
  Ticker? _ticker;

  void _onPosition() {
    final position = _playback.position.value;
    _read(position);
    final ticker = _ticker;
    if (ticker == null) return;
    if (position.playing && !ticker.isActive) ticker.start();
    if (!position.playing && ticker.isActive) ticker.stop();
  }

  void _read(PlaybackPosition position) => value = loopPositionOf(position);

  @override
  void dispose() {
    _playback.position.removeListener(_onPosition);
    _ticker?.dispose();
    super.dispose();
  }
}
