import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'position_source.dart';

/// Pure geometry for the arrangement ring: numbers in, numbers out, so it is
/// unit-tested directly.
///
/// Angles are radians in canvas space, as in `loop_geometry.dart`: 0 points
/// right, positive turns clockwise, and the ring starts at 12 o'clock.

/// The gap between two neighbouring arcs. The first gap sits at 12 o'clock,
/// so the start of the arrangement is visible.
const double ringGap = 0.06;

/// The shortest arc, so a 1-repeat section next to 32-repeat ones stays
/// visible (about 8 degrees). Sixteen of them plus the gaps take about half
/// the ring.
const double ringMinSweep = 0.14;

/// One section's arc.
@immutable
class RingArc {
  const RingArc({required this.start, required this.sweep});

  final double start;
  final double sweep;

  double get end => start + sweep;
  double get mid => start + sweep / 2;
}

/// The arcs of sections that play [repeats] cycles each, in order, clockwise
/// from 12 o'clock. A sweep is proportional to the repeats, except that no
/// arc is shorter than [minSweep]; the arcs that would be are held at it and
/// the rest of the ring is shared by the others in proportion. One [gap]
/// separates neighbours, so the sweeps and gaps add up to the whole ring.
///
/// Throws [ArgumentError] outside the arrangement's limits (1..16 sections,
/// 1..32 repeats).
List<RingArc> ringArcs(
  List<int> repeats, {
  double gap = ringGap,
  double minSweep = ringMinSweep,
}) {
  final n = repeats.length;
  if (n < 1 || n > 16) {
    throw ArgumentError.value(n, 'repeats.length', 'must be in 1..16');
  }
  for (final r in repeats) {
    if (r < 1 || r > 32) {
      throw ArgumentError.value(r, 'repeats', 'must be in 1..32');
    }
  }
  final room = 2 * math.pi - n * gap;
  // Water filling: hold the arcs that fall below the minimum, share the rest
  // again, until none falls below. Each pass holds at least one more arc, so
  // it ends after at most n passes; holding the shortest first keeps the
  // order of sweeps the order of repeats.
  final held = List.filled(n, false);
  final sweeps = List.filled(n, 0.0);
  while (true) {
    final heldCount = held.where((h) => h).length;
    final free = room - heldCount * minSweep;
    var freeRepeats = 0;
    for (var i = 0; i < n; i++) {
      if (!held[i]) freeRepeats += repeats[i];
    }
    var changed = false;
    for (var i = 0; i < n; i++) {
      if (held[i]) {
        sweeps[i] = minSweep;
      } else {
        sweeps[i] = free * repeats[i] / freeRepeats;
        if (sweeps[i] < minSweep) {
          held[i] = true;
          changed = true;
        }
      }
    }
    if (!changed || held.every((h) => h)) break;
  }
  final arcs = <RingArc>[];
  var start = -math.pi / 2 + gap / 2;
  for (final sweep in sweeps) {
    arcs.add(RingArc(start: start, sweep: sweep));
    start += sweep + gap;
  }
  return arcs;
}

/// How far through a section of [repeats] cycles the position is, in [0, 1).
/// [continuous] is the strip's fill (`sectionProgress`); without it (reduce
/// motion) only whole cycles count, so the playhead moves once a cycle.
double ringProgress(
  LoopPosition position,
  int repeats, {
  bool continuous = true,
}) {
  if (!position.playing || repeats < 1) return 0;
  final whole = position.cycleIndex % repeats;
  return (whole + (continuous ? position.cyclePosition : 0)) / repeats;
}

/// The playhead's angle on [arc] at [progress] in [0, 1). Half-open: the end
/// of a section is the start of the next one.
double ringPlayheadAngle(RingArc arc, double progress) {
  if (!(progress >= 0 && progress < 1)) {
    throw ArgumentError.value(progress, 'progress', 'must be in [0, 1)');
  }
  return arc.start + arc.sweep * progress;
}

/// Whether something [length] long fits along [arc] at [radius].
bool arcFits(RingArc arc, double radius, double length) =>
    arc.sweep * radius >= length;

/// A colour index per section: one per distinct loop, in order of first
/// appearance, so sections that play the same loop share a colour. Wraps
/// after [colorCount].
List<int> loopColorIndexes(List<String> loopIds, {int colorCount = 12}) {
  final seen = <String, int>{};
  return [
    for (final id in loopIds)
      seen.putIfAbsent(id, () => seen.length) % colorCount,
  ];
}
