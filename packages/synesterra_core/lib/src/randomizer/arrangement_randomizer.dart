import '../arrangement/arrangement.dart';
import 'seeded_random.dart';

/// Range of sections and repeats in a random arrangement.
const randomArrangementMinSections = 2;
const randomArrangementMaxSections = 6;
const randomArrangementMaxRepeats = 4;

final _idPattern = RegExp(r'^[A-Za-z0-9-]{1,64}$');

/// A random arrangement of [loopIds] for [seed], a uint32, or null when
/// [loopIds] is empty (there is nothing to arrange; not an error).
///
/// 2..6 sections with 1..4 repeats each (2 and 4 favoured, like phrases).
/// A section never repeats the loop right before it unless there is only one
/// loop; with three or more sections the last one returns to the first loop
/// 40 % of the time. Duplicate ids count once. The same arguments always give
/// the same arrangement (docs/modules/randomizer.md).
///
/// Throws [ArgumentError] for a seed outside uint32, an invalid loop id, or
/// an [id] or [name] that [Arrangement] rejects.
Arrangement? randomArrangement({
  required int seed,
  required List<String> loopIds,
  required String id,
  required String name,
}) {
  checkRandomSeed(seed);
  for (final loopId in loopIds) {
    if (!_idPattern.hasMatch(loopId)) {
      throw ArgumentError.value(loopId, 'loopIds');
    }
  }
  final pool = loopIds.toSet().toList();
  if (pool.isEmpty) return null;
  final random = SeededRandom(seed);

  final count = weightedPick(random, const [
    (2, 2),
    (3, 3),
    (4, 3),
    (5, 2),
    (6, 1),
  ]);
  final chosen = <String>[];
  for (var i = 0; i < count; i++) {
    final previous = chosen.isEmpty ? null : chosen.last;
    final last = i == count - 1;
    if (last &&
        count >= 3 &&
        chosen.first != previous &&
        random.nextDouble() < 0.4) {
      chosen.add(chosen.first);
      continue;
    }
    final options = [
      for (final loopId in pool)
        if (pool.length == 1 || loopId != previous) loopId,
    ];
    chosen.add(options[random.nextInt(options.length)]);
  }
  return Arrangement(
    id: id,
    name: name,
    sections: [
      for (final loopId in chosen)
        ArrangementSection(
          loopId: loopId,
          repeats: weightedPick(random, const [(1, 2), (2, 4), (3, 1), (4, 3)]),
        ),
    ],
  );
}
