import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:synesterra_core/synesterra_core.dart';

import '../../shared/instrument_radar/radar_geometry.dart';
import '../../shared/instrument_radar/radar_painter.dart';
import '../../shared/theme/ambient_scope.dart';
import '../../shared/theme/design_scale.dart';
import '../../shared/theme/round_shapes.dart';
import '../../shared/theme/tap_effect.dart';
import '../../shared/widgets/round_components.dart';
import '../../shared/widgets/tap_glitch.dart';
import 'immediate_pan.dart';

/// A plain sentence about a radar shape for screen readers: which traits are
/// high, which are low, and the preset it matches. [labels] and [values] are
/// parallel.
String describeRadar(
  List<String> labels,
  List<double> values, {
  String? preset,
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
  return '$name: ${parts.join(', ')}';
}

/// The radar that shapes a sound: one axis per trait, the centre is low and
/// the edge high. Drag a vertex along its axis (only along it: the touch is
/// projected onto the axis and clamped); the shape follows live through
/// [onChanged] and [onRelease] is called once when the finger lifts. It holds
/// no trait state of its own.
///
/// Touching it never scrolls the page. A change from outside (a preset, a
/// screen-reader step) glides to the new shape with a short ease; the shape
/// breathes for a few slow breaths after it appears and after each change,
/// then rests (no breathing and no glide under reduce motion). Letting go
/// answers with the polarized tap accent on the handle, through the shared
/// [FlashGate]. Screen readers get one adjustable control per trait and a
/// description of the whole shape.
class InstrumentRadar extends StatefulWidget {
  const InstrumentRadar({
    super.key,
    required this.traits,
    required this.color,
    required this.onChanged,
    required this.onRelease,
    this.preset,
  });

  final InstrumentTraits traits;

  /// The instrument's identity colour, for the shape.
  final Color color;

  /// The name of the preset the shape matches, for the description.
  final String? preset;
  final void Function(String id, double value) onChanged;
  final VoidCallback onRelease;

  /// The glide to a new shape set from outside.
  static const glide = Duration(milliseconds: 320);

  /// One slow breath; a bout is [radarBreaths] of them.
  static const breath = Duration(seconds: 5);

  /// Width over height of the field.
  static const aspect = 1.16;

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

  late List<double> _from = _valuesOf(widget.traits);
  late List<double> _to = _from;
  bool _reduceMotion = false;

  /// The axis being dragged, and the difference between its value and the
  /// projected touch when a handle was grabbed (so it does not jump).
  int? _active;
  double _grab = 0;

  Offset? _flashAt;
  int _flashSeed = 0;

  static List<double> _valuesOf(InstrumentTraits traits) => [
    for (final definition in traits.definitions) traits[definition.id],
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
      _glide.value = 1;
    } else {
      _breathe();
    }
  }

  @override
  void didUpdateWidget(InstrumentRadar old) {
    super.didUpdateWidget(old);
    final next = _valuesOf(widget.traits);
    if (listEquals(next, _to)) return;
    if (_active != null || _reduceMotion || next.length != _to.length) {
      _from = _to = next;
      _glide.value = 1;
      return;
    }
    _from = _shown;
    _to = next;
    _glide.forward(from: 0);
    _breathe();
  }

  @override
  void dispose() {
    _glide.dispose();
    _breath.dispose();
    _flash.dispose();
    super.dispose();
  }

  /// Starts a bout of breathing unless one is running (restarting would
  /// make the shape jump) or motion is reduced.
  void _breathe() {
    if (_reduceMotion || _breath.isAnimating) return;
    _breath.forward(from: 0);
  }

  String _id(int index) => widget.traits.definitions[index].id;

  void _down(Offset local, Size size, double reach) {
    final values = _to;
    final axis = radarHitAxis(local, values, size, reach);
    if (axis == null) return;
    final count = values.length;
    final projected = radarProject(local, axis, count, size, reach);
    final handle = radarPoint(axis, count, values[axis], size, reach);
    final onHandle = (local - handle).distance <= radarHandleTarget / 2;
    setState(() {
      _active = axis;
      _grab = onHandle ? values[axis] - projected : 0;
    });
    if (!onHandle) widget.onChanged(_id(axis), projected);
  }

  void _move(Offset local, Size size, double reach) {
    final axis = _active;
    if (axis == null) return;
    final projected = radarProject(local, axis, _to.length, size, reach);
    widget.onChanged(_id(axis), (projected + _grab).clamp(0.0, 1.0));
  }

  void _up(Size size, double reach) {
    final axis = _active;
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
    if (_active == null) return;
    setState(() => _active = null);
    _breathe();
  }

  /// The polarized accent on the released handle, within the shared limits.
  void _accent(Offset at) {
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
    widget.onChanged(_id(index), radarStep(_to[index], direction));
    widget.onRelease();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AmbientScope.paletteOf(context);
    final definitions = widget.traits.definitions;
    final labels = [for (final d in definitions) d.label];
    final count = definitions.length;
    final labelStyle = roundText(
      context,
      color: palette.muted,
      size: TypeScale.caption,
      weight: FontWeight.w500,
      spacing: .3,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final size = Size(width, width / InstrumentRadar.aspect);
        final reach = radarReach(size, count);
        final flashAt = _flashAt;
        return Semantics(
          container: true,
          label: describeRadar(labels, _to, preset: widget.preset),
          child: SizedBox.fromSize(
            size: size,
            child: Stack(
              children: [
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
                                labelStyle: labelStyle,
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
                                ),
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
                    rect: _semanticsRect(i, count, size, reach),
                    child: _axisSemantics(i, labels[i]),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// The screen-reader target of axis [index]: its label box, at least
  /// 48 dp in both directions, inside the field.
  Rect _semanticsRect(int index, int count, Size size, double reach) {
    final box = radarLabelRect(index, count, size, reach);
    final width = math.max(box.width, radarHandleTarget);
    final height = math.max(box.height, radarHandleTarget);
    final left = (box.center.dx - width / 2)
        .clamp(0.0, math.max(0.0, size.width - width))
        .toDouble();
    final top = (box.center.dy - height / 2)
        .clamp(0.0, math.max(0.0, size.height - height))
        .toDouble();
    return Rect.fromLTWH(left, top, width, height);
  }

  Widget _axisSemantics(int index, String label) {
    String level(double value) => '${radarPercent(value)} percent';
    final value = _to[index];
    return Semantics(
      key: ValueKey('radar-axis-${_id(index)}'),
      container: true,
      slider: true,
      label: label,
      value: level(value),
      increasedValue: level(radarStep(value, 1)),
      decreasedValue: level(radarStep(value, -1)),
      onIncrease: () => _step(index, 1),
      onDecrease: () => _step(index, -1),
      child: const SizedBox.expand(),
    );
  }
}
