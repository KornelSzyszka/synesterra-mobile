/// How strongly a tap answers with the glitch / polarization flash. The
/// default lives in `SynesterraTokens.tapEffect`.
enum GlitchStrength {
  off('Off', 0),
  subtle('Subtle', .45),
  strong('Strong', 1);

  const GlitchStrength(this.label, this.amount);
  final String label;

  /// 0..1 scale of offsets and tint alpha.
  final double amount;
}

/// What a tap actually shows.
enum GlitchMode {
  /// Nothing.
  none,

  /// A plain, short fade of light over the element: the reduce-motion form.
  fade,

  /// The glitch itself (a sheen, a chromatic split or a slice jitter).
  full,
}

GlitchMode glitchModeFor(
  GlitchStrength strength, {
  required bool reduceMotion,
}) {
  if (strength == GlitchStrength.off) return GlitchMode.none;
  return reduceMotion ? GlitchMode.fade : GlitchMode.full;
}

/// Length of one flash; it snaps back well inside a quarter second.
const glitchDuration = Duration(milliseconds: 220);

/// No more than three flashes per second anywhere on screen (WCAG 2.3.1).
const maxFlashesPerSecond = 3;

/// The shortest gap between two flashes.
const minFlashInterval = Duration(microseconds: 1000000 ~/ maxFlashesPerSecond);

/// True when a flash may start at [now], given the start of the previous one.
/// A retrigger sooner than [minFlashInterval] is rejected: the tap still
/// works, it just does not flash.
bool flashAllowed({required Duration now, Duration? last}) =>
    last == null || now - last >= minFlashInterval;

final _monotonic = Stopwatch()..start();

Duration _monotonicNow() => _monotonic.elapsed;

/// Shared by every element on screen, so tapping two things quickly cannot
/// add up to more than [maxFlashesPerSecond].
class FlashGate {
  /// [clock] is a monotonic time source for [tryFlashNow]; tests pass a fake.
  FlashGate({Duration Function()? clock}) : _clock = clock ?? _monotonicNow;

  /// The gate of the whole app, used when no `AmbientScope` provides one.
  static final app = FlashGate();

  final Duration Function() _clock;
  Duration? _last;

  /// Records and allows a flash at [now], or rejects it.
  bool tryFlash(Duration now) {
    if (!flashAllowed(now: now, last: _last)) return false;
    _last = now;
    return true;
  }

  /// [tryFlash] at the gate's clock.
  bool tryFlashNow() => tryFlash(_clock());
}

/// Period of the slow drift (mist, breathing); slow on purpose.
const driftPeriod = Duration(seconds: 18);
