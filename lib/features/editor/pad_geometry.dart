import 'dart:ui';

import 'package:synesterra_core/synesterra_core.dart';

// Pure helpers for the instrument pad: touch positions to pad points and back.

/// The margin between the edge of the field and the pad's corners, so the dot
/// is always fully inside the field, also at 0 and 1.
const padInset = 16.0;

/// How far one accessibility adjustment (increase or decrease) moves a
/// coordinate: 5 % of the pad.
const padStep = 0.05;

double _unit(double value) =>
    value.isNaN ? 0.5 : (value < 0 ? 0 : (value > 1 ? 1 : value));

/// The pad point under a touch at [local] in a field of [size]. Touches
/// outside the field clamp to the nearest edge, so the result is always valid.
PadPoint padPointAt(Offset local, Size size, {double inset = padInset}) {
  final width = size.width - 2 * inset;
  final height = size.height - 2 * inset;
  if (width <= 0 || height <= 0) return PadPoint(0.5, 0.5);
  return PadPoint(
    _unit((local.dx - inset) / width),
    _unit((local.dy - inset) / height),
  );
}

/// Where [point] is drawn in a field of [size]; the inverse of [padPointAt]
/// inside the field.
Offset padOffsetOf(PadPoint point, Size size, {double inset = padInset}) =>
    Offset(
      inset + point.x * (size.width - 2 * inset),
      inset + point.y * (size.height - 2 * inset),
    );

/// [from] moved by [dx] and [dy], clamped to the pad. With no point yet it
/// starts from the middle.
PadPoint stepPadPoint(PadPoint? from, {double dx = 0, double dy = 0}) {
  final x = from?.x ?? 0.5;
  final y = from?.y ?? 0.5;
  return PadPoint(_unit(x + dx), _unit(y + dy));
}

/// A coordinate as a whole percent, for spoken values.
int padPercent(double coordinate) => (coordinate * 100).round();
