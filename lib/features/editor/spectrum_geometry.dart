// Pure helpers for drawing a spectrum with a finger.

/// A touch below this height (as a fraction of the chart) sets the bar to 0,
/// so silence is easy to reach with the edge of the screen.
const bottomSnap = 0.03;

/// Which bar (0-based) a touch at [x] hits, for a chart [width] wide with
/// [count] bars. Touches outside the chart go to the nearest bar.
int barIndexAt(double x, double width, int count) {
  if (count <= 1 || width <= 0) return 0;
  final index = (x / width * count).floor();
  return index < 0 ? 0 : (index >= count ? count - 1 : index);
}

/// The amplitude 0..1 for a touch at [y] in a chart [height] tall. The top is
/// 1, the bottom 0, and a touch in the bottom 3 % snaps to exactly 0.
double amplitudeAt(double y, double height) {
  if (height <= 0) return 0;
  final amplitude = 1 - y / height;
  if (amplitude <= bottomSnap) return 0;
  return amplitude >= 1 ? 1 : amplitude;
}

/// The bars changed by a stroke from one touch to the next, both ends
/// included. A fast drag skips bars between two touch events, so the heights
/// in between are interpolated; the result is in order from the first bar to
/// the last touched.
Map<int, double> strokeBetween(
  int fromIndex,
  double fromAmplitude,
  int toIndex,
  double toAmplitude,
) {
  if (fromIndex == toIndex) return {toIndex: toAmplitude};
  final step = toIndex > fromIndex ? 1 : -1;
  final span = (toIndex - fromIndex).abs();
  return {
    for (var i = 0; i <= span; i++)
      fromIndex + i * step:
          fromAmplitude + (toAmplitude - fromAmplitude) * i / span,
  };
}
