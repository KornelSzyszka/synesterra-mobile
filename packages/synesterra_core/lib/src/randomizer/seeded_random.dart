import 'dart:math' as math;

/// Largest seed: generator seeds are uint32, like `SessionDocument.randomSeed`.
const maxRandomSeed = 0xffffffff;

/// Throws [ArgumentError] unless [seed] is a uint32.
void checkRandomSeed(int seed, [String name = 'seed']) {
  if (seed < 0 || seed > maxRandomSeed) {
    throw ArgumentError.value(
      seed,
      name,
      'must be a uint32, 0..$maxRandomSeed',
    );
  }
}

/// One of [options] `(value, weight)`, in proportion to its weight: one
/// `random.nextInt(total weight)` walked through the options in order.
T weightedPick<T>(math.Random random, List<(T, int)> options) {
  var pick = random.nextInt(options.fold(0, (sum, option) => sum + option.$2));
  for (final (value, weight) in options) {
    if (pick < weight) return value;
    pick -= weight;
  }
  throw StateError('unreachable');
}

/// A shuffled copy of [items]: Fisher-Yates from the last index down, each
/// swap partner `random.nextInt(i + 1)`. Written out because `List.shuffle`
/// does not promise its algorithm, and a generator must not drift.
List<T> shuffled<T>(math.Random random, Iterable<T> items) {
  final list = [...items];
  for (var i = list.length - 1; i > 0; i--) {
    final j = random.nextInt(i + 1);
    final swap = list[i];
    list[i] = list[j];
    list[j] = swap;
  }
  return list;
}

/// A [math.Random] whose sequence is fixed by its uint32 seed forever.
///
/// `dart:math`'s seeded `Random` may change its algorithm between SDK
/// releases, which would silently change every generated loop for a stored
/// seed. This one is **mulberry32** (Tommy Ettinger, public domain): a 32-bit
/// state advanced by 0x6D2B79F5 and mixed by two multiply-xorshift rounds.
/// Its first outputs are pinned against the JavaScript reference in the
/// tests. Multiplication is split into 16-bit halves, so the result is the
/// same on every platform, the web included.
class SeededRandom implements math.Random {
  /// Throws [ArgumentError] unless [seed] is a uint32.
  SeededRandom(int seed) : _state = seed {
    checkRandomSeed(seed);
  }

  int _state;

  /// The next 32-bit output, 0..0xffffffff.
  int nextUint32() {
    _state = (_state + 0x6D2B79F5) & 0xffffffff;
    var t = _state;
    t = _imul(t ^ (t >>> 15), t | 1);
    t = ((t + _imul(t ^ (t >>> 7), t | 61)) & 0xffffffff) ^ t;
    return (t ^ (t >>> 14)) & 0xffffffff;
  }

  /// The low 32 bits of `a * b` for uint32 [a] and [b], with every
  /// intermediate below 2^53.
  static int _imul(int a, int b) {
    final low = (a & 0xffff) * b;
    final high = (((a >>> 16) * b) & 0xffff) << 16;
    return (low + high) & 0xffffffff;
  }

  /// Uniform in 0..max-1 by rejection, so no value is favoured.
  @override
  int nextInt(int max) {
    if (max < 1 || max > 0x100000000) {
      throw RangeError.range(max, 1, 0x100000000, 'max');
    }
    final limit = 0x100000000 - 0x100000000 % max;
    while (true) {
      final value = nextUint32();
      if (value < limit) return value % max;
    }
  }

  /// Uniform in [0, 1) with 53 random bits.
  @override
  double nextDouble() {
    final high = nextUint32() >>> 5; // 27 bits
    final low = nextUint32() >>> 6; // 26 bits
    return (high * 67108864 + low) / 9007199254740992;
  }

  @override
  bool nextBool() => nextUint32() & 1 == 1;
}
