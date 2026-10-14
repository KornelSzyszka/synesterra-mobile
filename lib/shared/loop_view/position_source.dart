import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// Where a loop is in time, as the visualizations need it.
///
/// An immutable snapshot. The playback side exposes its own position type and
/// never imports UI code; the Loop panel writes the adapter to this one.
@immutable
class LoopPosition {
  LoopPosition({
    this.playing = false,
    this.cyclePosition = 0,
    this.cycleIndex = 0,
    this.generation = 0,
    this.sectionIndex,
  }) {
    // Checked at runtime, not by assert: a bad position from an adapter must
    // fail the same way in release builds. The cycle boundary is 0 of the
    // next cycle, so 1 is invalid.
    if (cycleIndex < 0 || generation < 0 || (sectionIndex ?? 0) < 0) {
      throw ArgumentError(
        'cycleIndex, generation and sectionIndex must not be negative',
      );
    }
    if (!(cyclePosition >= 0 && cyclePosition < 1)) {
      throw ArgumentError.value(
        cyclePosition,
        'cyclePosition',
        'must be finite and in [0, 1)',
      );
    }
  }

  /// Stopped at the start of the cycle.
  static final stopped = LoopPosition();

  /// Whether the transport is running. A stopped view shows no pulses.
  final bool playing;

  /// Position inside the current cycle, in [0, 1) (half-open).
  final double cyclePosition;

  /// Number of whole cycles played since the current section began (since
  /// play began outside an arrangement).
  final int cycleIndex;

  /// Increments whenever the playback side discards its plan (stop, edit,
  /// tempo change). A view may use it to drop animations tied to the past.
  final int generation;

  /// The arrangement section being played, as its index in the arrangement;
  /// null outside an arrangement.
  final int? sectionIndex;

  @override
  bool operator ==(Object other) =>
      other is LoopPosition &&
      playing == other.playing &&
      cyclePosition == other.cyclePosition &&
      cycleIndex == other.cycleIndex &&
      generation == other.generation &&
      sectionIndex == other.sectionIndex;

  @override
  int get hashCode =>
      Object.hash(playing, cyclePosition, cycleIndex, generation, sectionIndex);

  @override
  String toString() =>
      'LoopPosition(playing: $playing, cyclePosition: $cyclePosition, '
      'cycleIndex: $cycleIndex, generation: $generation, '
      'sectionIndex: $sectionIndex)';
}

/// The only thing the loop views read to know where to draw.
///
/// Views listen to it and never drive it: transport belongs to the playback
/// side. Implementations: [FakePositionSource] (tests, demos),
/// [TutorialClock] (no audio) and, later, an adapter over the real transport.
abstract interface class PositionSource
    implements ValueListenable<LoopPosition> {}

/// A position that tests and demos set by hand.
class FakePositionSource extends ValueNotifier<LoopPosition>
    implements PositionSource {
  FakePositionSource([LoopPosition? initial])
    : super(initial ?? LoopPosition.stopped);

  /// Replaces the position and notifies listeners.
  void set({
    bool playing = true,
    double cyclePosition = 0,
    int cycleIndex = 0,
    int generation = 0,
    int? sectionIndex,
  }) {
    value = LoopPosition(
      playing: playing,
      cyclePosition: cyclePosition,
      cycleIndex: cycleIndex,
      generation: generation,
      sectionIndex: sectionIndex,
    );
  }
}

/// A deterministic, ticker-driven position with no audio and no transport,
/// for demos. Nothing is being played, which is why this is
/// the one allowed exception to "views are never driven by a UI timer".
///
/// The position is a pure function of the ticker's elapsed time
/// ([positionAt]); a frame only samples it.
class TutorialClock extends ValueNotifier<LoopPosition>
    implements PositionSource {
  TutorialClock({required TickerProvider vsync, required this.cycleDuration})
    : super(LoopPosition.stopped) {
    if (cycleDuration <= Duration.zero) {
      throw ArgumentError.value(
        cycleDuration,
        'cycleDuration',
        'must be positive',
      );
    }
    _ticker = vsync.createTicker(_onTick);
  }

  /// Wall time of one cycle.
  final Duration cycleDuration;

  late final Ticker _ticker;
  int _generation = 0;

  /// The cycle position and cycle index after [elapsed] time. Integer
  /// microseconds keep the cycle boundary exact: a whole cycle is position 0
  /// of the next one.
  static (double, int) positionAt(Duration elapsed, Duration cycleDuration) {
    final cycle = cycleDuration.inMicroseconds;
    final micros = elapsed.inMicroseconds;
    return ((micros % cycle) / cycle, micros ~/ cycle);
  }

  bool get isRunning => _ticker.isActive;

  /// Starts from the beginning of the cycle.
  void start() {
    _ticker.stop();
    _generation++;
    value = LoopPosition(playing: true, generation: _generation);
    _ticker.start();
  }

  /// Stops and resets to the start of the cycle.
  void stop() {
    _ticker.stop();
    _generation++;
    value = LoopPosition(generation: _generation);
  }

  void _onTick(Duration elapsed) {
    final (position, index) = positionAt(elapsed, cycleDuration);
    value = LoopPosition(
      playing: true,
      cyclePosition: position,
      cycleIndex: index,
      generation: _generation,
    );
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }
}
