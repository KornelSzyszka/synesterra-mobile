import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:synesterra_core/synesterra_core.dart';

import '../../shared/instrument_mist/mist_spec.dart';
import '../../shared/instrument_radar/radar_geometry.dart';
import '../../shared/instrument_radar/radar_painter.dart';
import '../../shared/theme/ambient_scope.dart';
import '../../shared/theme/design_scale.dart';
import '../../shared/theme/round_shapes.dart';
import '../../shared/theme/tap_effect.dart';
import '../../shared/widgets/round_components.dart';
import '../../shared/widgets/tap_glitch.dart';
import 'immediate_pan.dart';

/// Said after the description when the shape only approximates the sound.
const radarApproximateNote = 'The shape is an approximation of this sound.';

/// A plain sentence about a radar shape for screen readers: which traits are
/// high, which are low, the preset it matches, and whether it only
/// approximates the sound. [labels] and [values] are parallel.
String describeRadar(
  List<String> labels,
  List<double> values, {
  String? preset,
  bool approximate = false,
}) {
  final high = <String>[];
  final low = <String>[];
  for (var i = 0; i < labels.length; i++) {
    if (values[i] >= 2 / 3) {
      high.add(labels[i]);
    } else if (values[i] <= 1 / 3) {
      low.add(labels[i]);
    }
  }
  String list(List<String> items) => items.length == 1
      ? items.single
      : '${items.sublist(0, items.length - 1).join(', ')} and ${items.last}';
  final parts = [
    if (high.isNotEmpty) 'high ${list(high)}',
    if (low.isNotEmpty) 'low ${list(low)}',
    if (high.isEmpty && low.isEmpty)
      'everything in the middle'
    else if (high.length + low.length < labels.length)
      'the rest in the middle',
  ];
  final name = preset == null ? 'Sound shape' : 'Sound shape, $preset';
  final sentence = '$name: ${parts.join(', ')}';
  return approximate ? '$sentence. $radarApproximateNote' : sentence;
}

/// The stat wheel that shapes a sound: an outer ring with the trait names
/// written along it, and inside it one spoke per trait, graduated in ten
/// steps with the rank letters E (centre) to A (edge). Drag a vertex along
/// its spoke (only along it: the touch is projected onto the spoke); it snaps
/// to the steps, calling [onStep] on each new one (for a light haptic tick),
/// the shape follows live through
/// [onChanged] (always a snapped value) and [onRelease] is called once when
/// the finger lifts. It holds no trait state of its own: [traits] may be
/// continuous (an opened sound) and are shown snapped.
///
/// Touching it never scrolls the page. A change from outside (a
/// screen-reader step) glides to the new shape; a snap under the finger
/// glides in a blink; the shape breathes for a few slow breaths after it
/// appears and after each change, then rests (no breathing and no glide
/// under reduce motion). Letting go answers with the polarized tap accent on
/// the handle, through the shared [FlashGate], and the glow of the
/// instrument's mist ([glow]) swells once. Screen readers get one adjustable
/// control per trait, stepping by one rank step, and a description of the
/// whole shape.
class InstrumentRadar extends StatefulWidget {
  const InstrumentRadar({
    super.key,
    required this.traits,
    required this.color,
    required this.onChanged,
    required this.onRelease,
    this.onStep,
    this.glow,
    this.preset,
    this.approximated = false,
  });

  final InstrumentTraits traits;

  /// The instrument's identity colour, for the shape and the glow.
  final Color color;

  /// The instrument's mist, drawn as a soft glow behind the chart.
  final MistSpec? glow;

  /// The name of the preset the shape matches, for the description.
  final String? preset;

  /// The sound was not made on the wheel, so the shape approximates it. Said
  /// to screen readers only; a shape off the steps is said the same way.
  final bool approximated;
  final void Function(String id, double value) onChanged;
  final VoidCallback onRelease;

  /// Called each time the finger brings a vertex onto another step: the
  /// place for a light haptic tick. The UI never reaches the platform itself
  /// (decision 0001, R5), so the tick is given from outside.
  final VoidCallback? onStep;

  /// The glide to a new shape set from outside.
  static const glide = Duration(milliseconds: 320);

  /// The glide from one step to the next under the finger.
  static const snapGlide = Duration(milliseconds: 90);

  /// One slow breath; a bout is [radarBreaths] of them.
  static const breath = Duration(seconds: 5);

  /// The swell of the glow after a release.
  static const swell = Duration(milliseconds: 900);

  /// The largest text scale the wheel follows; beyond it the names would
  /// leave no room for the chart.
  static const maxTextScale = 2.0;

  /// How far a touch on stacked handles moves before it picks a spoke.
  static const pickSlop = 4.0;

  @override
  State<InstrumentRadar> createState() => _InstrumentRadarState();
}

class _InstrumentRadarState extends State<InstrumentRadar>
    with TickerProviderStateMixin {
  late final AnimationController _glide = AnimationController(
    vsync: this,
    duration: InstrumentRadar.glide,
    value: 1,
  );
  late final Animation<double> _eased = CurvedAnimation(
    parent: _glide,
    curve: Curves.easeOutCubic,
  );
  late final AnimationController _breath = AnimationController(
    vsync: this,
    duration: InstrumentRadar.breath * radarBreaths,
  );
  late final AnimationController _flash = AnimationController(
    vsync: this,
    duration: glitchDuration,
  );
  late final AnimationController _swell = AnimationController(
    vsync: this,
    duration: InstrumentRadar.swell,
  );

  late List<double> _from = _snapped(widget.traits);
  late List<double> _to = _from;
  bool _reduceMotion = false;

  /// The spoke being dragged, and the difference between its value and the
  /// projected touch when a handle was grabbed (so it does not jump).
  int? _active;
  double _grab = 0;

  /// Stacked handles under a touch that has not moved yet, and where it
  /// went down; the first move picks one of them.
  List<int>? _stacked;
  Offset _downAt = Offset.zero;

  /// Handles closer than this to each other count as stacked.
  static const _stackedWithin = 6.0;

  Offset? _flashAt;
  int _flashSeed = 0;

  static List<double> _raw(InstrumentTraits traits) => [
    for (final definition in traits.definitions) traits[definition.id],
  ];

  static List<double> _snapped(InstrumentTraits traits) => [
    for (final value in _raw(traits)) snapToRank(value),
  ];

  List<double> get _shown {
    final t = _eased.value;
    if (t >= 1) return _to;
    return [
      for (var i = 0; i < _to.length; i++)
        i < _from.length ? _from[i] + (_to[i] - _from[i]) * t : _to[i],
    ];
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (_reduceMotion) {
      _breath
        ..stop()
        ..value = 0;
      _swell
        ..stop()
        ..value = 0;
      _glide.value = 1;
    } else {
      _breathe();
    }
  }

  @override
  void didUpdateWidget(InstrumentRadar old) {
    super.didUpdateWidget(old);
    final next = _snapped(widget.traits);
    if (listEquals(next, _to)) return;
    if (_reduceMotion || next.length != _to.length) {
      _from = _to = next;
      _glide.value = 1;
      return;
    }
    _from = _shown;
    _to = next;
    _glide
      ..duration = _active == null
          ? InstrumentRadar.glide
          : InstrumentRadar.snapGlide
      ..forward(from: 0);
    _breathe();
  }

  @override
  void dispose() {
    _glide.dispose();
    _breath.dispose();
    _flash.dispose();
    _swell.dispose();
    super.dispose();
  }

  /// Starts a bout of breathing unless one is running (restarting would
  /// make the shape jump) or motion is reduced.
  void _breathe() {
    if (_reduceMotion || _breath.isAnimating) return;
    _breath.forward(from: 0);
  }

  String _id(int index) => widget.traits.definitions[index].id;

  /// Sends [value] snapped for spoke [axis] when it lands on another step,
  /// with a tick ([InstrumentRadar.onStep]).
  void _send(int axis, double value) {
    final snapped = snapToRank(value);
    if (rankStep(snapped) == rankStep(_to[axis])) return;
    widget.onStep?.call();
    widget.onChanged(_id(axis), snapped);
  }

  void _grabHandle(int axis, Offset at, Size size, double reach) {
    setState(() {
      _active = axis;
      _grab = _to[axis] - radarProject(at, axis, _to.length, size, reach);
    });
  }

  void _down(Offset local, Size size, double reach) {
    final values = _to;
    final handles = radarHandlesAt(local, values, size, reach);
    if (handles.isNotEmpty) {
      Offset point(int i) =>
          radarPoint(i, values.length, values[i], size, reach);
      final nearest = point(handles.first);
      final stacked = [
        for (final i in handles)
          if ((point(i) - nearest).distance < _stackedWithin) i,
      ];
      if (stacked.length > 1) {
        // Handles on top of each other (all at the centre, say): the first
        // move picks the spoke it points along.
        _stacked = stacked;
        _downAt = local;
        return;
      }
    }
    if (handles.isNotEmpty) {
      _grabHandle(handles.first, local, size, reach);
      return;
    }
    final axis = radarHitAxis(local, values, size, reach);
    if (axis == null) return;
    setState(() {
      _active = axis;
      _grab = 0;
    });
    _send(axis, radarProject(local, axis, values.length, size, reach));
  }

  void _move(Offset local, Size size, double reach) {
    final stacked = _stacked;
    if (stacked != null) {
      final delta = local - _downAt;
      if (delta.distance < InstrumentRadar.pickSlop) return;
      _stacked = null;
      _grabHandle(
        radarPickByDirection(stacked, delta, _to.length),
        _downAt,
        size,
        reach,
      );
    }
    final axis = _active;
    if (axis == null) return;
    final projected = radarProject(local, axis, _to.length, size, reach);
    _send(axis, (projected + _grab).clamp(0.0, 1.0));
  }

  void _up(Size size, double reach) {
    final stacked = _stacked;
    _stacked = null;
    final axis = _active ?? stacked?.first;
    if (axis == null) return;
    final at = radarPoint(axis, _to.length, _to[axis], size, reach);
    setState(() => _active = null);
    widget.onRelease();
    _accent(at);
    _breathe();
  }

  /// The system cancelled the drag (a call, a system gesture): stop it
  /// without a sound and without the accent; the shape keeps the last value.
  void _cancel() {
    _stacked = null;
    if (_active == null) return;
    setState(() => _active = null);
    _breathe();
  }

  /// The polarized accent on the released handle, within the shared limits,
  /// and a swell of the glow.
  void _accent(Offset at) {
    if (!_reduceMotion) _swell.forward(from: 0);
    final mode = glitchModeFor(
      AmbientScope.tapStrengthOf(context),
      reduceMotion: _reduceMotion,
    );
    if (mode == GlitchMode.none) return;
    if (!AmbientScope.gateOf(context).tryFlashNow()) return;
    setState(() {
      _flashAt = at;
      _flashSeed++;
    });
    _flash.forward(from: 0);
  }

  void _step(int index, int direction) {
    final next = rankStepFrom(_to[index], direction);
    if (next != _to[index]) widget.onChanged(_id(index), next);
    widget.onRelease();
    if (!_reduceMotion) _swell.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final palette = AmbientScope.paletteOf(context);
    final definitions = widget.traits.definitions;
    final labels = [for (final d in definitions) d.label];
    final count = definitions.length;
    final raw = _raw(widget.traits);
    final offSteps = [
      for (final value in raw) (value - snapToRank(value)).abs() > 1e-9,
    ].any((off) => off);
    final nameStyle = roundText(
      context,
      color: palette.muted,
      size: TypeScale.overline + 1,
      weight: FontWeight.w600,
      spacing: 1.6,
    );
    // The user's text size scales the names and the letters; the name band
    // widens and the chart makes room (up to twice the normal size).
    final fontSize = nameStyle.fontSize!;
    final textScale =
        (MediaQuery.textScalerOf(context).scale(fontSize) / fontSize).clamp(
          1.0,
          InstrumentRadar.maxTextScale,
        );
    final glow = widget.glow;
    return LayoutBuilder(
      builder: (context, constraints) {
        // Square: as wide as it may be, and no taller than it may be.
        final side = constraints.hasBoundedHeight
            ? math.min(constraints.maxWidth, constraints.maxHeight)
            : constraints.maxWidth;
        final size = Size.square(side);
        final layout = WheelLayout.of(size, textScale: textScale);
        final reach = layout.reach;
        final flashAt = _flashAt;
        return Semantics(
          container: true,
          label: describeRadar(
            labels,
            _to,
            preset: widget.preset,
            approximate: widget.approximated || offSteps,
          ),
          child: SizedBox.fromSize(
            size: size,
            child: Stack(
              children: [
                if (glow != null)
                  Positioned.fill(
                    child: ExcludeSemantics(
                      child: IgnorePointer(
                        child: RepaintBoundary(
                          child: CustomPaint(
                            painter: RadarGlowPainter(
                              spec: glow,
                              color: widget.color,
                              swell: _reduceMotion ? null : _swell,
                              textScale: textScale,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                Positioned.fill(
                  child: ExcludeSemantics(
                    child: ImmediatePanDetector(
                      onDown: (local) => _down(local, size, reach),
                      onUpdate: (local) => _move(local, size, reach),
                      onEnd: () => _up(size, reach),
                      onCancel: _cancel,
                      child: Stack(
                        children: [
                          RepaintBoundary(
                            child: CustomPaint(
                              size: size,
                              painter: RadarFieldPainter(
                                palette: palette,
                                count: count,
                                labels: labels,
                                labelStyle: nameStyle,
                                textScale: textScale,
                              ),
                            ),
                          ),
                          RepaintBoundary(
                            child: AnimatedBuilder(
                              animation: _eased,
                              builder: (context, _) => CustomPaint(
                                size: size,
                                painter: RadarShapePainter(
                                  values: _shown,
                                  palette: palette,
                                  color: widget.color,
                                  breath: _reduceMotion ? null : _breath,
                                  active: _active,
                                  textScale: textScale,
                                ),
                              ),
                            ),
                          ),
                          RepaintBoundary(
                            child: CustomPaint(
                              size: size,
                              painter: RadarRankPainter(
                                palette: palette,
                                count: count,
                                style: nameStyle,
                                textScale: textScale,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (flashAt != null)
                  Positioned(
                    left: flashAt.dx - radarHandleTarget / 2,
                    top: flashAt.dy - radarHandleTarget / 2,
                    width: radarHandleTarget,
                    height: radarHandleTarget,
                    child: IgnorePointer(
                      child: RepaintBoundary(
                        child: CustomPaint(
                          painter: TapGlitchPainter(
                            palette: palette,
                            shape: RoundShape.circle,
                            flash: _flash,
                            mode: glitchModeFor(
                              AmbientScope.tapStrengthOf(context),
                              reduceMotion: _reduceMotion,
                            ),
                            amount: AmbientScope.tapStrengthOf(context).amount,
                            seed: _flashSeed,
                          ),
                        ),
                      ),
                    ),
                  ),
                for (var i = 0; i < count; i++)
                  Positioned.fromRect(
                    rect: _semanticsRect(i, count, size, layout),
                    child: _axisSemantics(i, labels[i]),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// The screen-reader target of spoke [index]: over its name on the ring,
  /// at least 48 dp in both directions, inside the field.
  Rect _semanticsRect(int index, int count, Size size, WheelLayout layout) {
    final at =
        layout.centre + radarAxisDirection(index, count) * layout.nameRadius;
    const width = radarHandleTarget + 16;
    const height = radarHandleTarget;
    final left = (at.dx - width / 2)
        .clamp(0.0, math.max(0.0, size.width - width))
        .toDouble();
    final top = (at.dy - height / 2)
        .clamp(0.0, math.max(0.0, size.height - height))
        .toDouble();
    return Rect.fromLTWH(left, top, width, height);
  }

  Widget _axisSemantics(int index, String label) {
    final step = rankStep(_to[index]);
    return Semantics(
      key: ValueKey('radar-axis-${_id(index)}'),
      container: true,
      slider: true,
      label: label,
      value: rankSpoken(step),
      increasedValue: rankSpoken(math.min(step + 1, rankSteps)),
      decreasedValue: rankSpoken(math.max(step - 1, 0)),
      onIncrease: () => _step(index, 1),
      onDecrease: () => _step(index, -1),
      child: const SizedBox.expand(),
    );
  }
}
