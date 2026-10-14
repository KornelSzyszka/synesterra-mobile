import '../sound/instrument_traits.dart';
import 'seeded_random.dart';

/// Lowest and highest value a random trait takes (the axes' extremes sound
/// thin or dull, so the dice stays off the very edge and centre).
const randomTraitMin = 0.05;
const randomTraitMax = 0.95;

/// Random trait values for the radar: each trait of [definitions] takes a
/// value in [randomTraitMin]..[randomTraitMax], rounded to hundredths, drawn
/// in the order of the definitions. The same [seed] gives the same traits on
/// every platform. [instrumentForTraits] turns them into the sound.
///
/// Throws [ArgumentError] when [seed] is not a uint32.
InstrumentTraits randomInstrumentTraits({
  required int seed,
  List<TraitDefinition> definitions = defaultTraitDefinitions,
}) {
  final random = SeededRandom(seed);
  const lowest = 5;
  const highest = 95;
  return InstrumentTraits({
    for (final definition in definitions)
      definition.id: (lowest + random.nextInt(highest - lowest + 1)) / 100,
  }, definitions: definitions);
}
