import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme/ambient_scope.dart';
import '../theme/ground_palette.dart';
import '../theme/round_shapes.dart';
import '../theme/surfaces.dart';
import 'living_field.dart';
import 'living_motion.dart';

/// The lights of a living blob, each as its largest alpha on the (dark,
/// light) ground. Public so the contrast test checks exactly what is drawn.
abstract final class LivingLight {
  /// The three drifting depth layers, front to back: the tint, white light,
  /// the tint again.
  static const layers = [(.12, .12), (.04, .2), (.07, .08)];

  /// The soft specular highlight that wanders over the top.
  static const highlight = (.07, .32);

  /// The inner glow along the edge at rest; pressed it doubles.
  static const innerGlow = (.16, .16);

  /// The most the inner glow grows when pressed.
  static const pressedGlow = 2.0;

  /// The faint fixed grain (1 px dots).
  static const grain = (.05, .05);

  static double of((double, double) alphas, bool dark) =>
      dark ? alphas.$1 : alphas.$2;
}

/// Every colour text on a living organic surface may sit on: the organic
/// fill with all the lights stacked at their strongest over it, in [tint].
List<Color> livingFillSamples(GroundPalette palette, Color tint) {
  final dark = palette.isDark;
  var samples = Surfaces(palette).fillSamples(SurfaceStyle.organic);
  void stack(Color color, (double, double) alphas, [double scale = 1]) {
    samples = [
      ...samples,
      ...veiled(color, LivingLight.of(alphas, dark) * scale, samples),
    ];
  }

  final colors = [tint, palette.light, tint];
  for (var i = 0; i < LivingLight.layers.length; i++) {
    stack(colors[i], LivingLight.layers[i]);
  }
  stack(palette.light, LivingLight.highlight);
  stack(tint, LivingLight.innerGlow, LivingLight.pressedGlow);
  stack(dark ? palette.text : palette.shade, LivingLight.grain);
  return samples;
}

/// How far the edge of a living blob moves, as shares of its half height.
abstract final class LivingReach {
  /// The slow morph of the outline.
  static const morph = .1;

  /// The swell while pressed.
  static const swell = .06;

  /// The bulge toward the finger.
  static const lean = .16;

  /// The whole blob's shift toward the finger.
  static const shift = .05;
}

final _sampleCache = <(int, double, int, int), _Samples>{};

typedef _Samples = ({List<Offset> points, List<Offset> normals});

_Samples _samplesFor(Size size, BlobShape shape) {
  final key = (
    shape.seed,
    shape.amount,
    size.width.round(),
    size.height.round(),
  );
  return _sampleCache.putIfAbsent(key, () {
    if (_sampleCache.length > 96) _sampleCache.clear();
    return blobSamples(
      Offset.zero & size,
      seed: shape.seed,
      amount: shape.amount,
      samples: 48,
    );
  });
}

/// The outline of a living blob in a box of [size]: [shape]'s still outline
/// with its edge moved by the morph noise ([morphSeed] at [time], scaled by
/// [life]), the press [swell] and the [lean] toward a finger (a direction in
/// half sizes, at most unit length). At rest (life, swell and lean all zero)
/// it is the still outline.
Path livingOutline(
  Size size,
  BlobShape shape, {
  required int morphSeed,
  required double time,
  required double life,
  required Offset lean,
  required double swell,
}) {
  final samples = _samplesFor(size, shape);
  final half = size.shortestSide / 2;
  final n = samples.points.length;
  final leanReach = lean.distance;
  final leanDirection = leanReach == 0 ? Offset.zero : lean / leanReach;
  final shift = lean * (half * LivingReach.shift);
  final points = <Offset>[];
  for (var i = 0; i < n; i++) {
    final normal = samples.normals[i];
    var push = swell * half * LivingReach.swell;
    if (life > 0) {
      push +=
          life * half * LivingReach.morph * morphNoise(morphSeed, i / n, time);
    }
    if (leanReach > 0) {
      final facing = math.max(
        0.0,
        normal.dx * leanDirection.dx + normal.dy * leanDirection.dy,
      );
      push += facing * facing * leanReach * half * LivingReach.lean;
    }
    points.add(samples.points[i] + normal * push + shift);
  }
  return smoothClosedPath(points);
}

/// The organic surface of a library card, alive: inside a [LivingField] it
/// morphs slowly, has depth (three translucent layers drifting at their own
/// speeds, a wandering highlight, an inner glow and a faint grain), leans
/// and swells toward a finger on a spring, glows brighter when [pressed],
/// and fades in with the field's staggered entrance. Under reduce motion,
/// or without a field, it keeps the depth and does not move. `OrganicCard`
/// shows it only in a living field; flat, it paints the plain surface.
class LivingBlob extends StatefulWidget {
  const LivingBlob({
    super.key,
    required this.shape,
    required this.morphSeed,
    required this.child,
    this.pressed = false,
    this.tint,
    this.padding = EdgeInsets.zero,
  });

  final BlobShape shape;

  /// Seeds the morph: the same item always moves the same way.
  final int morphSeed;
  final bool pressed;

  /// The colour of the depth and glow; the palette's aura when null.
  final Color? tint;
  final EdgeInsetsGeometry padding;
  final Widget child;

  @override
  State<LivingBlob> createState() => LivingBlobState();
}

@visibleForTesting
class LivingBlobState extends State<LivingBlob> implements LivingMember {
  LivingFieldState? _field;
  bool _living = false;
  bool _moving = false;
  bool _animated = false;
  bool _listening = false;
  int? _entranceIndex;

  double _time = 0;
  double _life = 0;
  SpringState _leanX = const SpringState(0);
  SpringState _leanY = const SpringState(0);
  SpringState _swell = const SpringState(0);
  Offset _leanTarget = Offset.zero;
  double _swellTarget = 0;

  final _frame = _Frame();
  final _entrance = ValueNotifier<double>(1);

  /// Tests: whether this blob follows the field's clock right now.
  @visibleForTesting
  bool get listening => _listening;

  /// Tests: whether this blob holds an animation slot.
  @visibleForTesting
  bool get animated => _animated;

  bool get _settled =>
      springSettled(_leanX, _leanTarget.dx) &&
      springSettled(_leanY, _leanTarget.dy) &&
      springSettled(_swell, _swellTarget);

  @override
  bool get busy => _moving && (!_settled || _entranceIndex != null);

  @override
  set animated(bool value) {
    if (_animated == value) return;
    _animated = value;
    _sync();
  }

  @override
  set entranceIndex(int? value) {
    _entranceIndex = value;
    _entrance.value = value == null ? 1 : 0;
  }

  @override
  Rect? rectIn(RenderBox field) {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero, ancestor: field) & box.size;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final field = LivingField.maybeOf(context);
    final living = field?.living ?? false;
    if (field != _field || living != _living) {
      _leave();
      _field = field;
      _living = living;
      if (field != null && living) field.join(this);
    }
    _moving = field != null && field.moving;
    if (!_moving) _rest();
    _sync();
  }

  @override
  void dispose() {
    _leave();
    _frame.dispose();
    _entrance.dispose();
    super.dispose();
  }

  void _leave() {
    _unlisten();
    _field?.leave(this);
    _animated = false;
  }

  /// Back to the still shape at once (reduce motion, flat).
  void _rest() {
    _leanX = _leanY = _swell = const SpringState(0);
    _leanTarget = Offset.zero;
    _swellTarget = 0;
    _life = 0;
    entranceIndex = null;
  }

  void _sync() {
    final want = _moving && (_animated || busy);
    if (want && !_listening) {
      _field!.clock.addListener(_tick);
      _listening = true;
    } else if (!want && _listening) {
      _unlisten();
    }
  }

  void _unlisten() {
    if (!_listening) return;
    _field?.clock.removeListener(_tick);
    _listening = false;
  }

  void _tick() {
    final clock = _field!.clock;
    final dt = clock.dt;
    const spring = LivingSprings.touch;
    _leanX = springStep(_leanX, _leanTarget.dx, dt, spring);
    _leanY = springStep(_leanY, _leanTarget.dy, dt, spring);
    _swell = springStep(_swell, _swellTarget, dt, spring);
    if (_settled) {
      _leanX = SpringState(_leanTarget.dx);
      _leanY = SpringState(_leanTarget.dy);
      _swell = SpringState(_swellTarget);
    }
    final index = _entranceIndex;
    if (index != null) {
      final progress = entranceProgress(index, clock.sinceOpen);
      _entrance.value = progress;
      if (progress >= 1) _entranceIndex = null;
    }
    if (_animated) {
      _time += dt;
      _life = clock.life;
    }
    _frame.ping();
    _sync();
  }

  void _touch(Offset local, {required bool down}) {
    if (!_moving) return;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    final size = box.size;
    if (down) {
      var lean = Offset(
        (local.dx - size.width / 2) / math.max(1, size.width / 2),
        (local.dy - size.height / 2) / math.max(1, size.height / 2),
      );
      if (lean.distance > 1) lean = lean / lean.distance;
      _leanTarget = lean;
      _swellTarget = 1;
    } else {
      _leanTarget = Offset.zero;
      _swellTarget = 0;
    }
    _field?.wake();
    _sync();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AmbientScope.paletteOf(context);
    final surface = RepaintBoundary(
      child: CustomPaint(
        painter: LivingBlobPainter(
          blob: this,
          palette: palette,
          shape: widget.shape,
          tint: widget.tint ?? palette.aura,
          pressed: widget.pressed,
        ),
        child: Padding(
          padding: widget.padding,
          child: RepaintBoundary(child: widget.child),
        ),
      ),
    );
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (e) => _touch(e.localPosition, down: true),
      onPointerMove: (e) => _touch(e.localPosition, down: true),
      onPointerUp: (e) => _touch(e.localPosition, down: false),
      onPointerCancel: (e) => _touch(e.localPosition, down: false),
      child: ValueListenableBuilder<double>(
        valueListenable: _entrance,
        child: surface,
        builder: (context, progress, child) => Opacity(
          opacity: progress,
          alwaysIncludeSemantics: true,
          child: Transform.translate(
            offset: Offset(0, (1 - progress) * 14),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _Frame extends ChangeNotifier {
  void ping() => notifyListeners();
}

final _grainCache = <(int, int, int), Float32List>{};

/// Paints a [LivingBlob]: the organic surface on the living outline, then
/// its depth. Repaints only on the blob's own frames.
class LivingBlobPainter extends CustomPainter {
  LivingBlobPainter({
    required this.blob,
    required this.palette,
    required this.shape,
    required this.tint,
    required this.pressed,
  }) : super(repaint: blob._frame);

  final LivingBlobState blob;
  final GroundPalette palette;
  final BlobShape shape;
  final Color tint;
  final bool pressed;

  @override
  void paint(Canvas canvas, Size size) {
    final lean = Offset(blob._leanX.value, blob._leanY.value);
    final swell = blob._swell.value;
    final path = livingOutline(
      size,
      shape,
      morphSeed: blob.widget.morphSeed,
      time: blob._time,
      life: blob._life,
      lean: lean,
      swell: swell,
    );
    final rect = Offset.zero & size;
    final glow = (1 + swell.clamp(0.0, 1.0)) * (pressed ? 1.2 : 1);
    if (swell > .01) {
      // The press brightens the halo in the item's colour.
      canvas.drawPath(
        path,
        Paint()
          ..color = tint.withValues(alpha: .14 * swell.clamp(0.0, 1.0))
          ..maskFilter = MaskFilter.blur(
            BlurStyle.normal,
            math.min(Glow.haloBlur, rect.shortestSide / 4),
          ),
      );
    }
    Surfaces(palette)
        .paint(canvas, path, rect, SurfaceStyle.organic, pressed: pressed);
    paintLivingDepth(
      canvas,
      path,
      rect,
      palette: palette,
      tint: tint,
      seed: blob.widget.morphSeed,
      time: blob._time,
      life: blob._life,
      lean: lean,
      glow: math.min(glow, LivingLight.pressedGlow),
    );
  }

  @override
  bool shouldRepaint(LivingBlobPainter old) =>
      old.blob != blob ||
      old.palette != palette ||
      old.shape != shape ||
      old.tint != tint ||
      old.pressed != pressed;
}

/// The depth inside [path] (in [rect]): three translucent gradient layers
/// at their parallax offsets, a soft highlight, an inner glow ([glow] 1 at
/// rest, up to [LivingLight.pressedGlow]) and a fixed grain. With [life] 0
/// and no [lean] it is the still depth used under reduce motion.
void paintLivingDepth(
  Canvas canvas,
  Path path,
  Rect rect, {
  required GroundPalette palette,
  required Color tint,
  required int seed,
  required double time,
  required double life,
  required Offset lean,
  double glow = 1,
}) {
  final dark = palette.isDark;
  final w = rect.width;
  final h = rect.height;
  if (w <= 0 || h <= 0) return;
  canvas
    ..save()
    ..clipPath(path);
  final base = math.max(h, w * .35);
  const anchors = [Offset(-.5, -.3), Offset(.45, .35), Offset(.1, 0)];
  const radii = [.75, 1.0, 1.4];
  final colors = [tint, palette.light, tint];
  for (var layer = 0; layer < LivingDepth.layers; layer++) {
    final drift = parallaxOffset(
      layer: layer,
      time: time,
      seed: seed,
      lean: Offset.zero,
    );
    final follow = parallaxOffset(
      layer: layer,
      time: 0,
      seed: seed,
      lean: lean,
    );
    final unit = drift * life + follow;
    final centre =
        rect.center +
        Offset(anchors[layer].dx * w / 2, anchors[layer].dy * h / 2) +
        Offset(unit.dx * w * .2, unit.dy * h * .4);
    final radius = base * radii[layer];
    final alpha = LivingLight.of(LivingLight.layers[layer], dark);
    canvas.drawCircle(
      centre,
      radius,
      Paint()
        ..shader = RadialGradient(
          colors: [
            colors[layer].withValues(alpha: alpha),
            colors[layer].withValues(alpha: 0),
          ],
        ).createShader(Rect.fromCircle(center: centre, radius: radius)),
    );
  }

  // The highlight wanders slowly and slides away from the finger, as if the
  // surface tilted toward it under a fixed light.
  final phase = (seed % 97) / 97 * 2 * math.pi;
  final spot = Offset(
    rect.left +
        w * (.3 + .08 * math.sin(.17 * time + phase) * life - .1 * lean.dx),
    rect.top +
        h * (.2 + .1 * math.cos(.13 * time + phase) * life - .15 * lean.dy),
  );
  canvas
    ..save()
    ..translate(spot.dx, spot.dy)
    ..scale(w * .26, h * .3)
    ..drawCircle(
      Offset.zero,
      1,
      Paint()
        ..shader = RadialGradient(
          colors: [
            palette.light.withValues(
              alpha: LivingLight.of(LivingLight.highlight, dark),
            ),
            palette.light.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromCircle(center: Offset.zero, radius: 1)),
    )
    ..restore();

  // The inner glow: a blurred rim of the tint just inside the edge.
  canvas.drawPath(
    path,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..color = tint.withValues(
        alpha: LivingLight.of(LivingLight.innerGlow, dark) * glow,
      )
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
  );

  _paintGrain(
    canvas,
    rect,
    seed,
    dark ? palette.text : palette.shade,
    LivingLight.of(LivingLight.grain, dark),
  );
  canvas.restore();
}

/// A faint, fixed grain: about one 1 px dot per 40 square pixels, computed
/// once per size and seed, so a repaint only draws.
void _paintGrain(
  Canvas canvas,
  Rect rect,
  int seed,
  Color color,
  double alpha,
) {
  final key = (seed % 64, rect.width.round(), rect.height.round());
  final points = _grainCache.putIfAbsent(key, () {
    if (_grainCache.length > 64) _grainCache.clear();
    final random = math.Random(key.$1 * 7919 + key.$2);
    final count = (rect.width * rect.height / 40).clamp(0, 1600).round();
    final list = Float32List(count * 2);
    for (var i = 0; i < count; i++) {
      list[2 * i] = random.nextDouble() * rect.width;
      list[2 * i + 1] = random.nextDouble() * rect.height;
    }
    return list;
  });
  canvas.drawRawPoints(
    ui.PointMode.points,
    rect.topLeft == Offset.zero ? points : _shifted(points, rect.topLeft),
    Paint()
      ..color = color.withValues(alpha: alpha)
      ..strokeWidth = 1,
  );
}

Float32List _shifted(Float32List points, Offset by) {
  final out = Float32List(points.length);
  for (var i = 0; i < points.length; i += 2) {
    out[i] = points[i] + by.dx;
    out[i + 1] = points[i + 1] + by.dy;
  }
  return out;
}
