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

/// The inks of a living blob on one ground, in one tint: every colour it
/// paints inside the outline, with its alpha. Public so the contrast test
/// checks exactly what is drawn.
///
/// On the dark ground there is almost no room to lighten under text (the
/// secondary text is close to 4.5:1 already), so the depth there is colour
/// without light: the tint is darkened to the fill's own luminance, which
/// adds hue but never brightness, and a drifting shadow adds the depth. On
/// the light ground the layers are light and tint, as there is room.
@immutable
class LivingInk {
  const LivingInk._({
    required this.layers,
    required this.highlight,
    required this.innerGlow,
    required this.grain,
  });

  factory LivingInk.of(GroundPalette palette, Color tint) {
    if (!palette.isDark) {
      return LivingInk._(
        layers: [
          tint.withValues(alpha: .07),
          palette.light.withValues(alpha: .22),
          tint.withValues(alpha: .05),
        ],
        highlight: palette.light.withValues(alpha: .34),
        innerGlow: tint.withValues(alpha: .055),
        grain: palette.shade.withValues(alpha: .05),
      );
    }
    final fill = Surfaces(palette).fillSamples(SurfaceStyle.organic);
    final floor = fill.map((c) => c.computeLuminance()).reduce(math.min);
    final deep = _darkenedTo(tint, palette.shade, floor);
    return LivingInk._(
      layers: [
        deep.withValues(alpha: .55),
        palette.shade.withValues(alpha: .22),
        deep.withValues(alpha: .4),
      ],
      highlight: palette.light.withValues(alpha: .012),
      innerGlow: tint.withValues(alpha: .01),
      grain: palette.text.withValues(alpha: .015),
    );
  }

  /// The three drifting depth layers, front to back.
  final List<Color> layers;

  /// The soft specular highlight that wanders over the top.
  final Color highlight;

  /// The inner glow along the edge at rest; a press raises it up to
  /// [pressedGlow] times.
  final Color innerGlow;

  /// The faint fixed grain (1 px dots).
  final Color grain;

  static const pressedGlow = 2.0;

  @override
  bool operator ==(Object other) =>
      other is LivingInk &&
      _sameColors(other.layers, layers) &&
      other.highlight == highlight &&
      other.innerGlow == innerGlow &&
      other.grain == grain;

  @override
  int get hashCode =>
      Object.hash(Object.hashAll(layers), highlight, innerGlow, grain);
}

bool _sameColors(List<Color> a, List<Color> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// [color] pulled toward [shade] until its luminance is at most [luminance]:
/// the same hue, no brighter than the surface it tints.
Color _darkenedTo(Color color, Color shade, double luminance) {
  if (color.computeLuminance() <= luminance) return color;
  var lo = 0.0; // share of the colour that is known to be dark enough
  var hi = 1.0;
  for (var i = 0; i < 14; i++) {
    final mid = (lo + hi) / 2;
    if (Color.lerp(shade, color, mid)!.computeLuminance() <= luminance) {
      lo = mid;
    } else {
      hi = mid;
    }
  }
  return Color.lerp(shade, color, lo)!;
}

/// Every colour text on a living organic surface may sit on: the organic
/// fill with every ink of [LivingInk] stacked over it at its strongest.
List<Color> livingFillSamples(GroundPalette palette, Color tint) {
  final ink = LivingInk.of(palette, tint);
  var samples = Surfaces(palette).fillSamples(SurfaceStyle.organic);
  void stack(Color color) =>
      samples = [...samples, ...veiled(color, color.a, samples)];
  for (final layer in ink.layers) {
    stack(layer);
  }
  stack(ink.highlight);
  stack(
    ink.innerGlow.withValues(alpha: ink.innerGlow.a * LivingInk.pressedGlow),
  );
  stack(ink.grain);
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

  /// Tests: the spring-driven lean toward the finger (in half sizes).
  @visibleForTesting
  Offset get debugLean => Offset(_leanX.value, _leanY.value);

  /// Tests: the spring-driven swell of a press.
  @visibleForTesting
  double get debugSwell => _swell.value;

  /// Tests: the lean and swell of the last painted frame.
  @visibleForTesting
  (Offset, double)? get debugPainted => _painted;
  (Offset, double)? _painted;

  bool get _settled =>
      springSettled(_leanX, _leanTarget.dx) &&
      springSettled(_leanY, _leanTarget.dy) &&
      springSettled(_swell, _swellTarget);

  @override
  bool get busy =>
      _moving && _animated && (!_settled || _entranceIndex != null);

  @override
  void finishEntrance() {
    if (_entranceIndex == null) return;
    entranceIndex = null;
    _sync();
  }

  @override
  set animated(bool value) {
    if (_animated == value) return;
    _animated = value;
    // Only slot holders follow the clock: a card losing its slot drops its
    // springs to rest at once instead of ticking them out.
    if (!value) {
      _settleSprings();
      // Nothing else repaints the card: show the still shape now.
      _frame.ping();
    }
    _sync();
  }

  void _settleSprings() {
    _leanTarget = Offset.zero;
    _swellTarget = 0;
    _leanX = _leanY = _swell = const SpringState(0);
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
    _frame.ping();
  }

  void _sync() {
    final want = _moving && _animated;
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
    _field?.wake();
    // A card without a slot answers a press only with its static pressed
    // glow; the spring is for slot holders, so the cap always holds.
    if (!_animated) return;
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
  }) : ink = LivingInk.of(palette, tint),
       super(repaint: blob._frame);

  final LivingBlobState blob;
  final GroundPalette palette;
  final BlobShape shape;
  final Color tint;
  final bool pressed;
  final LivingInk ink;

  @override
  void paint(Canvas canvas, Size size) {
    final lean = Offset(blob._leanX.value, blob._leanY.value);
    final swell = blob._swell.value;
    blob._painted = (lean, swell);
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
      ink: ink,
      seed: blob.widget.morphSeed,
      time: blob._time,
      life: blob._life,
      lean: lean,
      glow: math.min(glow, LivingInk.pressedGlow),
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
/// rest, up to [LivingInk.pressedGlow]) and a fixed grain, in [ink]. With [life] 0
/// and no [lean] it is the still depth used under reduce motion.
void paintLivingDepth(
  Canvas canvas,
  Path path,
  Rect rect, {
  required LivingInk ink,
  required int seed,
  required double time,
  required double life,
  required Offset lean,
  double glow = 1,
}) {
  final w = rect.width;
  final h = rect.height;
  if (w <= 0 || h <= 0) return;
  canvas
    ..save()
    ..clipPath(path);
  final base = math.max(h, w * .35);
  const anchors = [Offset(-.5, -.3), Offset(.45, .35), Offset(.1, 0)];
  const radii = [.75, 1.0, 1.4];
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
    final color = ink.layers[layer];
    canvas.drawCircle(
      centre,
      radius,
      Paint()
        ..shader = RadialGradient(colors: [color, color.withValues(alpha: 0)])
            .createShader(Rect.fromCircle(center: centre, radius: radius)),
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
          colors: [ink.highlight, ink.highlight.withValues(alpha: 0)],
        ).createShader(Rect.fromCircle(center: Offset.zero, radius: 1)),
    )
    ..restore();

  // The inner glow: a blurred rim of the tint just inside the edge.
  canvas.drawPath(
    path,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..color = ink.innerGlow.withValues(alpha: ink.innerGlow.a * glow)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
  );

  _paintGrain(canvas, rect, seed, ink.grain);
  canvas.restore();
}

/// A faint, fixed grain: about one 1 px dot per 40 square pixels, computed
/// once per size and seed, so a repaint only draws.
void _paintGrain(Canvas canvas, Rect rect, int seed, Color color) {
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
      ..color = color
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
