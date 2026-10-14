import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../living_blobs/living_field.dart';
import '../living_blobs/living_surface.dart';
import '../theme/ambient_scope.dart';
import '../theme/design_scale.dart';
import '../theme/ground_palette.dart';
import '../theme/round_shapes.dart';
import '../theme/surfaces.dart';
import '../theme/synesterra_theme.dart';
import 'tap_glitch.dart';

// Visual language v2: round components for the blend of glass (floating
// layers), organic (shapes and figures) and tactile (things you press).
// Colours come from the AmbientScope's GroundPalette; every control is at
// least 48 dp and labelled for screen readers.

/// Body text in the visual language: [serif] for names and numbers.
TextStyle roundText(
  BuildContext context, {
  required Color color,
  double size = TypeScale.body,
  bool serif = false,
  FontWeight weight = FontWeight.w400,
  double spacing = 0,
}) {
  final platform = Theme.of(context).platform;
  return TextStyle(
    color: color,
    fontSize: size,
    fontWeight: weight,
    letterSpacing: spacing,
    fontFamily: serif
        ? SynesterraFonts.serif(platform)
        : SynesterraFonts.ui(platform),
    fontFamilyFallback: serif
        ? SynesterraFonts.serifFallback(platform)
        : SynesterraFonts.uiFallback(platform),
  );
}

/// A surface of [style] in [shape], behind [child]. Organic shapes breathe
/// with the scope's drift when [breathes] (never under reduce motion).
class RoundSurface extends StatelessWidget {
  const RoundSurface({
    super.key,
    required this.style,
    this.shape = RoundShape.capsule,
    this.pressed = false,
    this.breathes = false,
    this.padding = EdgeInsets.zero,
    this.child,
  });

  final SurfaceStyle style;
  final RoundShape shape;
  final bool pressed;
  final bool breathes;
  final EdgeInsetsGeometry padding;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: RoundSurfacePainter(
        surfaces: Surfaces(AmbientScope.paletteOf(context)),
        style: style,
        shape: shape,
        pressed: pressed,
        drift: breathes ? AmbientScope.driftOf(context) : null,
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

class RoundSurfacePainter extends CustomPainter {
  RoundSurfacePainter({
    required this.surfaces,
    required this.style,
    required this.shape,
    required this.pressed,
    this.drift,
  }) : super(repaint: drift);

  final Surfaces surfaces;
  final SurfaceStyle style;
  final RoundShape shape;
  final bool pressed;
  final Animation<double>? drift;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final path = shape.outline(rect, breath: breathPhase(drift));
    surfaces.paint(canvas, path, rect, style, pressed: pressed);
  }

  @override
  bool shouldRepaint(RoundSurfacePainter old) =>
      old.surfaces.palette != surfaces.palette ||
      old.style != style ||
      old.shape != shape ||
      old.pressed != pressed ||
      old.drift != drift;
}

/// A tappable element: at least 48 dp, one semantics node with [label], the
/// pressed state for the surface, and the [TapGlitch] in [shape] around the
/// visible part ([builder] gets the pressed state).
class _Pressable extends StatefulWidget {
  const _Pressable({
    super.key,
    required this.label,
    required this.onTap,
    required this.shape,
    required this.builder,
    this.selected,
    this.excludeSemantics = true,
  });

  final String label;
  final VoidCallback? onTap;
  final RoundShape shape;
  final bool? selected;
  final bool excludeSemantics;
  final Widget Function(BuildContext context, bool pressed) builder;

  @override
  State<_Pressable> createState() => _PressableState();
}

class _PressableState extends State<_Pressable> {
  bool _pressed = false;

  void _set(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    return Semantics(
      container: true,
      button: true,
      enabled: enabled,
      selected: widget.selected,
      label: widget.label,
      excludeSemantics: widget.excludeSemantics,
      onTap: widget.onTap,
      child: GestureDetector(
        // The Semantics above carries the label and the tap action.
        excludeFromSemantics: true,
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => _set(true) : null,
        onTapUp: enabled ? (_) => _set(false) : null,
        onTapCancel: enabled ? () => _set(false) : null,
        onTap: widget.onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          child: widget.builder(context, _pressed && enabled),
        ),
      ),
    );
  }
}

/// [child] with the tap effect in [shape] when [enabled]; a disabled control
/// has no effect at all.
Widget _glitchIf(bool enabled, RoundShape shape, Widget child) =>
    enabled ? TapGlitch(shape: shape, child: child) : child;

/// A disc of [size] centred in a square of at least 48 dp, with the glitch.
Widget _orb({
  required double size,
  required SurfaceStyle style,
  required bool pressed,
  required Widget child,
  bool breathes = false,
  bool glitch = true,
}) {
  final surface = RepaintBoundary(
    child: RoundSurface(
      style: style,
      shape: RoundShape.circle,
      pressed: pressed,
      breathes: breathes,
      child: Center(child: child),
    ),
  );
  return SizedBox.square(
    dimension: math.max(48, size),
    child: Center(
      child: SizedBox.square(
        dimension: size,
        child: glitch ? TapGlitch(child: surface) : surface,
      ),
    ),
  );
}

/// The primary action: a round, glazed gold disc (Play, Record, Keep). Its
/// glow is the one place gold shines. [label] is read by screen readers.
class RoundActionButton extends StatelessWidget {
  const RoundActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.size = 64,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final double size;

  @override
  Widget build(BuildContext context) {
    final surfaces = Surfaces(AmbientScope.paletteOf(context));
    final style = onPressed == null
        ? SurfaceStyle.tactile
        : SurfaceStyle.primary;
    return _Pressable(
      label: label,
      onTap: onPressed,
      shape: RoundShape.circle,
      builder: (context, pressed) => _orb(
        size: size,
        style: style,
        pressed: pressed,
        glitch: onPressed != null,
        child: Icon(
          icon,
          size: size * .42,
          color: onPressed == null
              ? surfaces.mutedOn(style)
              : surfaces.textOn(style),
        ),
      ),
    );
  }
}

/// A quiet round button (Stop, Loop, a small Play). [selected] makes it a
/// toggle that is tinted gold while on.
class RoundIconButton extends StatelessWidget {
  const RoundIconButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.selected,
    this.size = 48,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  /// Null for a plain button; true or false for a toggle.
  final bool? selected;
  final double size;

  @override
  Widget build(BuildContext context) {
    final surfaces = Surfaces(AmbientScope.paletteOf(context));
    final style = selected ?? false
        ? SurfaceStyle.tactileSelected
        : SurfaceStyle.tactile;
    return _Pressable(
      label: label,
      selected: selected,
      onTap: onPressed,
      shape: RoundShape.circle,
      builder: (context, pressed) => _orb(
        size: size,
        style: style,
        pressed: pressed,
        glitch: onPressed != null,
        child: Icon(
          icon,
          size: size * .44,
          color: onPressed == null
              ? surfaces.mutedOn(style)
              : surfaces.textOn(style),
        ),
      ),
    );
  }
}

/// A tactile capsule with a label: a tag, a filter, an answer. [primary]
/// makes it the gold answer (Keep); otherwise [selected] tints it.
class TactileChip extends StatelessWidget {
  const TactileChip({
    super.key,
    required this.label,
    required this.onPressed,
    this.selected,
    this.primary = false,
  });

  final String label;
  final VoidCallback? onPressed;

  /// Null for a plain chip; true or false for a toggle.
  final bool? selected;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final surfaces = Surfaces(AmbientScope.paletteOf(context));
    final style = primary
        ? SurfaceStyle.primary
        : (selected ?? false
              ? SurfaceStyle.tactileSelected
              : SurfaceStyle.tactile);
    return _Pressable(
      label: label,
      selected: primary ? null : selected,
      onTap: onPressed,
      shape: RoundShape.capsule,
      builder: (context, pressed) => SizedBox(
        height: 48,
        child: Center(
          widthFactor: 1,
          child: _glitchIf(
            onPressed != null,
            RoundShape.capsule,
            RoundSurface(
              style: style,
              pressed: pressed,
              padding: const EdgeInsets.symmetric(
                horizontal: Space.lg + 2,
                vertical: Space.md,
              ),
              child: Text(
                label,
                style: roundText(
                  context,
                  color: surfaces.textOn(style),
                  weight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One of a few options: a concave tray with the chosen option raised and
/// tinted gold.
class RoundSegmented<T> extends StatelessWidget {
  const RoundSegmented({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
  });

  /// Values and their labels.
  final List<(T, String)> options;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final surfaces = Surfaces(AmbientScope.paletteOf(context));
    return SizedBox(
      height: 52,
      child: RoundSurface(
        style: SurfaceStyle.tray,
        padding: const EdgeInsets.all(2),
        child: Row(
          children: [
            for (final (option, label) in options)
              Expanded(
                child: _Pressable(
                  key: ValueKey('round-segment-$label'),
                  label: label,
                  selected: option == value,
                  onTap: () => onChanged(option),
                  shape: RoundShape.capsule,
                  builder: (context, pressed) {
                    final selected = option == value;
                    final text = Text(
                      label,
                      style: roundText(
                        context,
                        color: selected
                            ? surfaces.textOn(SurfaceStyle.tactileSelected)
                            : surfaces.mutedOn(SurfaceStyle.tray),
                        weight: FontWeight.w500,
                      ),
                    );
                    return TapGlitch(
                      shape: RoundShape.capsule,
                      child: selected
                          ? RoundSurface(
                              style: SurfaceStyle.tactileSelected,
                              pressed: pressed,
                              child: Center(child: text),
                            )
                          : Center(child: text),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A slider: its label and value above a 48 dp groove filled with gold, and
/// a tactile thumb. [value] is 0..1; screen readers step it by a tenth.
class RoundSlider extends StatelessWidget {
  const RoundSlider({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.valueText = _percent,
  });

  final String label;
  final double value;
  final ValueChanged<double> onChanged;

  /// How the value is shown and announced.
  final String Function(double value) valueText;

  static String _percent(double v) => '${(v * 100).round()} %';

  @override
  Widget build(BuildContext context) {
    final palette = AmbientScope.paletteOf(context);
    double clamp(double v) => v.clamp(0.0, 1.0);
    return Semantics(
      slider: true,
      label: label,
      value: valueText(value),
      increasedValue: valueText(clamp(value + .1)),
      decreasedValue: valueText(clamp(value - .1)),
      onIncrease: () => onChanged(clamp(value + .1)),
      onDecrease: () => onChanged(clamp(value - .1)),
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(label, style: roundText(context, color: palette.text)),
              const Spacer(),
              Text(
                valueText(value),
                style: roundText(context, color: palette.muted),
              ),
            ],
          ),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              void set(Offset local) =>
                  onChanged(clamp((local.dx - 24) / math.max(1, width - 48)));
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (details) => set(details.localPosition),
                onHorizontalDragUpdate: (details) => set(details.localPosition),
                child: SizedBox(
                  height: 48,
                  width: width,
                  child: RepaintBoundary(
                    child: CustomPaint(
                      painter: _SliderPainter(Surfaces(palette), value),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _SliderPainter extends CustomPainter {
  const _SliderPainter(this.surfaces, this.value);

  final Surfaces surfaces;
  final double value;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final palette = surfaces.palette;
    final groove = Rect.fromCenter(
      center: rect.center,
      width: rect.width - rect.height + 14,
      height: 12,
    );
    surfaces.paint(canvas, capsulePath(groove), groove, SurfaceStyle.tray);
    final inner = groove.deflate(3);
    final at =
        inner.left + (inner.width - inner.height) * value + inner.height / 2;
    final fill = Rect.fromLTRB(inner.left, inner.top, at, inner.bottom);
    canvas
      ..drawRRect(
        RRect.fromRectAndRadius(
          fill.inflate(2),
          Radius.circular(inner.height / 2 + 2),
        ),
        Paint()
          ..color = palette.accent.withValues(alpha: .35)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      )
      ..drawRRect(
        RRect.fromRectAndRadius(fill, Radius.circular(inner.height / 2)),
        Paint()..color = palette.accent,
      );
    final thumb = Rect.fromCircle(
      center: Offset(at, rect.center.dy),
      radius: 14,
    );
    surfaces.paint(canvas, circlePath(thumb), thumb, SurfaceStyle.tactile);
    canvas.drawCircle(thumb.center, 3.5, Paint()..color = palette.accent);
  }

  @override
  bool shouldRepaint(_SliderPainter old) =>
      old.value != value || old.surfaces.palette != surfaces.palette;
}

/// A floating glass layer over the mist: a transport bar ([RoundShape.capsule],
/// the default) or a sheet ([RoundShape.lens]). Static; it never breathes.
class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.shape = RoundShape.capsule,
    this.padding = const EdgeInsets.symmetric(
      horizontal: Space.lg,
      vertical: Space.md,
    ),
  });

  final Widget child;
  final RoundShape shape;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => RoundSurface(
    style: SurfaceStyle.glass,
    shape: shape,
    padding: padding,
    child: child,
  );
}

/// An organic card: a soft blob that holds an item (a library entry). With
/// [onTap] it is one button read as [label]; its children stay reachable
/// for screen readers. [breathes] lets the edge move with the drift; keep
/// that to one card on screen.
///
/// A [living] card inside a `LivingField` is a `LivingBlob` (UX-126): it
/// morphs, has depth, leans toward the finger and glows when pressed, in
/// [tint]; [morphSeed] gives it its own motion. Elsewhere, or with the flat
/// comparison on, it is the still card.
class OrganicCard extends StatelessWidget {
  const OrganicCard({
    super.key,
    required this.child,
    this.label,
    this.onTap,
    this.seed = 7,
    this.breathes = false,
    this.living = false,
    this.morphSeed,
    this.tint,
    this.padding = const EdgeInsets.fromLTRB(
      Space.xl,
      Space.lg,
      Space.lg,
      Space.lg,
    ),
  }) : assert(onTap == null || label != null, 'a tappable card needs a label');

  final Widget child;
  final String? label;
  final VoidCallback? onTap;
  final int seed;
  final bool breathes;
  final bool living;

  /// Seeds a living card's motion; [seed] when null.
  final int? morphSeed;

  /// The colour of a living card's depth and glow; the aura when null.
  final Color? tint;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final shape = BlobShape(seed: seed, amount: BlobAmount.wide);
    final alive = living && (LivingField.maybeOf(context)?.living ?? false);
    Widget surface(bool pressed) => alive
        ? LivingBlob(
            shape: shape,
            morphSeed: morphSeed ?? seed,
            tint: tint,
            pressed: pressed,
            padding: padding,
            child: child,
          )
        : RoundSurface(
            style: SurfaceStyle.organic,
            shape: shape,
            pressed: pressed,
            breathes: breathes,
            padding: padding,
            child: child,
          );
    final onTap = this.onTap;
    if (onTap == null) return surface(false);
    return _Pressable(
      label: label!,
      onTap: onTap,
      shape: shape,
      excludeSemantics: false,
      builder: (context, pressed) =>
          TapGlitch(shape: shape, child: surface(pressed)),
    );
  }
}

/// The colour of secondary text on [style] in the current scope; a helper
/// for content placed on round surfaces.
Color mutedTextOn(BuildContext context, SurfaceStyle style) =>
    Surfaces(AmbientScope.paletteOf(context)).mutedOn(style);

/// The colour of body text on [style] in the current scope.
Color textOn(BuildContext context, SurfaceStyle style) =>
    Surfaces(AmbientScope.paletteOf(context)).textOn(style);

/// The ground palette in scope (a shortcut for content).
GroundPalette groundOf(BuildContext context) => AmbientScope.paletteOf(context);
