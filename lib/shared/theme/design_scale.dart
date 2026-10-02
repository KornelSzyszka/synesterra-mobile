import 'dart:math' as math;

/// The golden ratio, φ.
const phi = 1.618033988749895;

/// Spacing, in logical pixels: steps of about φ from a base of 16
/// (6 ≈ 10 / φ, 10 ≈ 16 / φ, 26 ≈ 16 φ, 42 ≈ 16 φ², 68 ≈ 16 φ³).
abstract final class Space {
  static const xs = 4.0;
  static const sm = 6.0;
  static const md = 10.0;
  static const lg = 16.0;
  static const xl = 26.0;
  static const xxl = 42.0;
  static const huge = 68.0;
}

/// Corner radii: about φ apart.
abstract final class Radii {
  static const xs = 4.0;
  static const sm = 7.0;
  static const md = 10.0;
  static const lg = 17.0;
}

/// Type sizes on the scale `16 · φ^(n/4)`, rounded to half a point.
abstract final class TypeScale {
  /// Section labels (uppercase, tracked out).
  static const overline = 10.0;
  static const caption = 12.5;
  static const body = 14.0;
  static const bodyLarge = 16.0;
  static const title = 20.5;
  static const headline = 26.0;
  static const display = 42.0;
}

/// The size of step [n] of the type scale: 16 · φ^(n/4).
double typeStep(int n) => 16 * math.pow(phi, n / 4).toDouble();

/// The height of a golden rectangle that is [width] wide (wider than tall):
/// `width / φ`. Used for drawing surfaces such as the spectrum and the EQ.
double goldenHeight(double width) => width / phi;

/// A flatter golden proportion, `width / φ²`, for graphs that need less
/// height (the envelope).
double flatGoldenHeight(double width) => width / (phi * phi);
