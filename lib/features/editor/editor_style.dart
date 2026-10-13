import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../shared/theme/ambient_scope.dart';
import '../../shared/theme/design_scale.dart';
import '../../shared/theme/ground_palette.dart';
import '../../shared/theme/round_shapes.dart';
import '../../shared/theme/surfaces.dart';
import '../../shared/theme/synesterra_theme.dart';
import '../../shared/widgets/design_components.dart';
import '../../shared/widgets/round_components.dart';
import '../../shared/widgets/tap_glitch.dart';

// Visual language v2 (Blend on the app palette) for the Editor shell and the
// Loop and Arrangement panels: the ground with its slow mist, the round
// theme for dialogs, sheets and fields, and the few pieces the panels share.
// The shared components live in `lib/shared/widgets/round_components.dart`.

/// The Editor's ground palette: the app palette on the dark ground. The mist
/// is the first layer colour, which is also what the round components fall
/// back to outside a scope, so sheets and dialogs match the panels.
GroundPalette editorPalette(SynesterraTokens tokens) =>
    GroundPalette.of(tokens, GroundTone.dark, tokens.layerColors.first);

/// The colour of a bottom sheet: glass over the plain ground, made opaque so
/// what lies under the sheet never shows through its text.
Color sheetColor(GroundPalette palette) => Color.alphaBlend(
  palette.light.withValues(alpha: palette.isDark ? .05 : .4),
  palette.ground,
);

/// The Editor's round theme for what Material draws itself: dialogs become
/// pebbles, sheets a glass lens, fields, buttons, snack bars and tooltips
/// capsules. Colours are unchanged; only shapes and the sheet's glass differ.
ThemeData editorRoundTheme(ThemeData base, GroundPalette palette) {
  final tokens = base.extension<SynesterraTokens>()!;
  final hairline = BorderSide(color: tokens.controlBorder);
  const capsule = StadiumBorder();
  OutlineInputBorder field(BorderSide side) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(999),
    borderSide: side,
  );
  final error = base.colorScheme.error;
  return base.copyWith(
    dialogTheme: base.dialogTheme.copyWith(shape: PebbleBorder(side: hairline)),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: sheetColor(palette),
      modalBackgroundColor: sheetColor(palette),
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      modalElevation: 0,
      shape: GlassLensBorder(Surfaces(palette)),
      modalBarrierColor: palette.shade.withValues(alpha: .45),
      dragHandleColor: palette.muted,
      dragHandleSize: const Size(36, 4),
    ),
    textButtonTheme: TextButtonThemeData(
      style: base.textButtonTheme.style?.copyWith(
        shape: const WidgetStatePropertyAll(capsule),
      ),
    ),
    snackBarTheme: base.snackBarTheme.copyWith(
      shape: StadiumBorder(side: hairline),
    ),
    tooltipTheme: base.tooltipTheme.copyWith(
      decoration: ShapeDecoration(
        color: tokens.surfaceHigh,
        shape: StadiumBorder(side: hairline),
      ),
    ),
    inputDecorationTheme: base.inputDecorationTheme.copyWith(
      contentPadding: const EdgeInsets.symmetric(
        horizontal: Space.xl,
        vertical: Space.md + 2,
      ),
      enabledBorder: field(hairline),
      border: field(hairline),
      focusedBorder: field(BorderSide(color: tokens.accent, width: 1.6)),
      errorBorder: field(BorderSide(color: error)),
      focusedErrorBorder: field(BorderSide(color: error, width: 1.6)),
    ),
  );
}

/// [dialog] in the Editor's round theme, whatever context opened it.
Widget roundDialog(BuildContext context, Widget dialog) => Theme(
  data: editorRoundTheme(
    Theme.of(context),
    editorPalette(SynesterraTokens.of(context)),
  ),
  child: dialog,
);

/// A pebble (a soft superellipse) as a [ShapeBorder]: the dialogs' shape.
class PebbleBorder extends ShapeBorder {
  const PebbleBorder({
    this.seed = 3,
    this.exponent = 5,
    this.side = BorderSide.none,
  });

  final int seed;
  final double exponent;
  final BorderSide side;

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.all(side.width);

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) =>
      pebblePath(rect, seed: seed, exponent: exponent);

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      getOuterPath(rect.deflate(side.width));

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (side.style == BorderStyle.none) return;
    canvas.drawPath(
      getOuterPath(rect.deflate(side.width / 2)),
      side.toPaint()..isAntiAlias = true,
    );
  }

  @override
  ShapeBorder scale(double t) =>
      PebbleBorder(seed: seed, exponent: exponent, side: side.scale(t));

  @override
  bool operator ==(Object other) =>
      other is PebbleBorder &&
      other.seed == seed &&
      other.exponent == exponent &&
      other.side == side;

  @override
  int get hashCode => Object.hash(seed, exponent, side);
}

/// A sheet's lens-shaped top with the thin glass rim: the bottom sheets'
/// shape. The fill is the theme's opaque [sheetColor].
class GlassLensBorder extends ShapeBorder {
  const GlassLensBorder(this.surfaces);

  final Surfaces surfaces;

  static const rise = 22.0;

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.zero;

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) =>
      lensPath(rect, rise: rise);

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      getOuterPath(rect);

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) =>
      surfaces.paintRim(canvas, getOuterPath(rect), rect);

  @override
  ShapeBorder scale(double t) => this;

  @override
  bool operator ==(Object other) =>
      other is GlassLensBorder && other.surfaces.palette == surfaces.palette;

  @override
  int get hashCode => surfaces.palette.hashCode;
}

/// The ground behind the Editor: the palette's ground and two soft clouds of
/// mist that drift very slowly with [drift] (still without one). Sits behind
/// its own [RepaintBoundary], so the drift repaints nothing else.
class EditorAura extends StatelessWidget {
  const EditorAura({super.key, required this.palette, this.drift});

  final GroundPalette palette;
  final Animation<double>? drift;

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: CustomPaint(
      key: const Key('editor-aura'),
      painter: EditorAuraPainter(palette: palette, drift: drift),
      child: const SizedBox.expand(),
    ),
  );
}

class EditorAuraPainter extends CustomPainter {
  EditorAuraPainter({required this.palette, this.drift})
    : super(repaint: drift);

  final GroundPalette palette;
  final Animation<double>? drift;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = palette.ground);
    final phase = breathPhase(drift);
    final w = size.width;
    // No cloud is stronger than the palette's mist alpha: the contrast tests
    // check text over exactly that.
    void cloud(Color color, Offset centre, double radius, double strength) {
      final rect = Rect.fromCircle(center: centre, radius: radius);
      final alpha = palette.auraAlpha * strength;
      canvas.drawCircle(
        centre,
        radius,
        Paint()
          ..shader = RadialGradient(
            colors: [
              color.withValues(alpha: alpha),
              color.withValues(alpha: alpha * .4),
              color.withValues(alpha: 0),
            ],
            stops: const [0, .45, 1],
          ).createShader(rect),
      );
    }

    cloud(
      palette.aura,
      Offset(
        w * (.22 + .08 * math.sin(phase)),
        size.height * (.16 + .03 * math.cos(phase)),
      ),
      w * .9,
      .7,
    );
    cloud(
      palette.accent,
      Offset(
        w * (.86 - .06 * math.cos(phase)),
        size.height * (.78 + .04 * math.sin(phase)),
      ),
      w * .75,
      1,
    );
  }

  @override
  bool shouldRepaint(EditorAuraPainter old) =>
      old.palette != palette || old.drift != drift;
}

/// A quiet section header: a small gold light and a tracked-out label.
class SoftHeader extends StatelessWidget {
  const SoftHeader(this.title, {super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    final palette = AmbientScope.paletteOf(context);
    return Semantics(
      header: true,
      label: title,
      excludeSemantics: true,
      child: Row(
        children: [
          CustomPaint(
            size: const Size.square(12),
            painter: GoldMarkPainter(palette.accent),
          ),
          const SizedBox(width: Space.md),
          Flexible(
            child: Text(
              title.toUpperCase(),
              style: roundText(
                context,
                color: palette.muted,
                size: TypeScale.caption,
                weight: FontWeight.w600,
                spacing: 2.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A small gold light with a soft glow.
class GoldMarkPainter extends CustomPainter {
  const GoldMarkPainter(this.accent);

  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    canvas
      ..drawCircle(
        c,
        size.shortestSide / 2,
        Paint()
          ..color = accent.withValues(alpha: .4)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.5),
      )
      ..drawCircle(c, size.shortestSide / 4.5, Paint()..color = accent);
  }

  @override
  bool shouldRepaint(GoldMarkPainter old) => old.accent != accent;
}

/// A [NumberStepper] in a concave tactile tray: the value sits in a groove
/// between its two 48 dp buttons.
class TrayStepper extends StatelessWidget {
  const TrayStepper({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    required this.label,
    required this.color,
    this.repeatOnHold = false,
  });

  final int value;
  final int min;
  final int max;
  final ValueChanged<int>? onChanged;
  final String label;
  final Color color;
  final bool repeatOnHold;

  @override
  Widget build(BuildContext context) => RoundSurface(
    style: SurfaceStyle.tray,
    child: NumberStepper(
      value: value,
      min: min,
      max: max,
      onChanged: onChanged,
      label: label,
      color: color,
      repeatOnHold: repeatOnHold,
    ),
  );
}

/// Play or Stop: the round gold disc with its word under it (the word is for
/// the eye; screen readers hear the button's label once).
class PlayDisc extends StatelessWidget {
  const PlayDisc({
    super.key,
    required this.playing,
    required this.onPressed,
    this.size = 56,
  });

  final bool playing;
  final VoidCallback? onPressed;
  final double size;

  @override
  Widget build(BuildContext context) {
    final palette = AmbientScope.paletteOf(context);
    final label = playing ? 'Stop' : 'Play';
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        RoundActionButton(
          icon: playing ? Icons.stop_rounded : Icons.play_arrow_rounded,
          label: label,
          size: size,
          onPressed: onPressed,
        ),
        ExcludeSemantics(
          child: Text(
            label,
            style: roundText(
              context,
              color: Surfaces(palette).mutedOn(SurfaceStyle.glass),
              size: TypeScale.caption,
              weight: FontWeight.w500,
              spacing: .6,
            ),
          ),
        ),
      ],
    );
  }
}

/// A tactile capsule that holds any content: one button for screen readers
/// ([semanticsLabel]), at least 48 dp tall, with the tap glitch.
class TactileCapsule extends StatefulWidget {
  const TactileCapsule({
    super.key,
    required this.semanticsLabel,
    required this.onPressed,
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: Space.lg),
    this.hint,
  });

  final String semanticsLabel;
  final String? hint;
  final VoidCallback? onPressed;
  final EdgeInsetsGeometry padding;
  final Widget child;

  @override
  State<TactileCapsule> createState() => _TactileCapsuleState();
}

class _TactileCapsuleState extends State<TactileCapsule> {
  bool _pressed = false;

  void _set(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final surface = RoundSurface(
      style: SurfaceStyle.tactile,
      pressed: _pressed && enabled,
      padding: widget.padding,
      child: SizedBox(
        height: 48,
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          widthFactor: 1,
          child: widget.child,
        ),
      ),
    );
    return Semantics(
      container: true,
      button: true,
      enabled: enabled,
      label: widget.semanticsLabel,
      hint: widget.hint,
      excludeSemantics: true,
      onTap: widget.onPressed,
      child: GestureDetector(
        excludeFromSemantics: true,
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => _set(true) : null,
        onTapUp: enabled ? (_) => _set(false) : null,
        onTapCancel: enabled ? () => _set(false) : null,
        onTap: widget.onPressed,
        child: enabled
            ? TapGlitch(shape: RoundShape.capsule, child: surface)
            : surface,
      ),
    );
  }
}

/// A layer's number in a small round badge of its colour (identity is never
/// colour alone). The number is in the text colour: in the layer's own colour
/// it fell below 4.5:1 on the lit organic card for some layer colours.
class NumberBadge extends StatelessWidget {
  const NumberBadge({super.key, required this.number, required this.color});

  final int number;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final platform = Theme.of(context).platform;
    return SizedBox.square(
      dimension: 34,
      child: CustomPaint(
        painter: _BadgePainter(color),
        child: Center(
          child: Text(
            number.toString().padLeft(2, '0'),
            style: TextStyle(
              color: textOn(context, SurfaceStyle.organic),
              fontFamily: SynesterraFonts.monospace(platform),
              fontFamilyFallback: SynesterraFonts.monospaceFallback(platform),
              fontSize: TypeScale.caption,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _BadgePainter extends CustomPainter {
  const _BadgePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    canvas
      ..drawCircle(c, r, Paint()..color = color.withValues(alpha: .1))
      ..drawCircle(
        c,
        r - .75,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = color.withValues(alpha: .55),
      );
  }

  @override
  bool shouldRepaint(_BadgePainter old) => old.color != color;
}

/// A pair of a text colour and what it is drawn on, with the contrast it
/// needs: 4.5:1 for body text, 3:1 for large numbers.
typedef ContrastRule = ({TextContrastPair pair, double minimum});

/// Every text colour the Editor shell and the Loop panel draw, with the
/// opaque colours under it, for [palette] and the layer colours of [tokens].
List<ContrastRule> editorTextRules(SynesterraTokens tokens, Color error) {
  final ground = editorPalette(tokens);
  final s = Surfaces(ground);
  final rules = <ContrastRule>[];
  void add(String name, Color text, List<Color> on, {double minimum = 4.5}) =>
      rules.add((pair: TextContrastPair(name, text, on), minimum: minimum));

  final grounds = ground.groundSamples;
  final tray = s.fillSamples(SurfaceStyle.tray);
  final glass = s.fillSamples(SurfaceStyle.glass);
  final tactile = s.fillSamples(SurfaceStyle.tactile);
  final selected = s.fillSamples(SurfaceStyle.tactileSelected);
  final sheet = [sheetColor(ground)];

  // Shell: title, tabs.
  add('title on ground', ground.text, grounds);
  add('tab on ground', ground.text, grounds);
  add('quiet tab on ground', ground.muted, grounds);
  // Panel text on the ground (status, captions, headers, notes).
  add('muted on ground', ground.muted, grounds);
  add('error on ground', error, grounds);
  // Steppers in a tray: the value, its unit, the +/- icons.
  add('stepper text on tray', tokens.text, tray);
  add('stepper unit on tray', tokens.muted, tray);
  add('tempo on tray', tokens.accent, tray, minimum: 3);
  // Transport: the note above it, the word under Play.
  add('play word on glass', s.mutedOn(SurfaceStyle.glass), glass);
  // A missing sound's icon in its glass vessel: a graphic, so 3:1.
  add('missing-sound icon on glass', error, glass, minimum: 3);
  // Chips and capsules.
  add('chip on tactile', s.textOn(SurfaceStyle.tactile), tactile);
  add('error on tactile', error, tactile);
  add('chip on selected', s.textOn(SurfaceStyle.tactileSelected), selected);
  // Sheets and their lists.
  add('text on sheet', ground.text, sheet);
  add('muted on sheet', s.mutedOn(SurfaceStyle.glass), sheet);
  add('accent text on sheet', ground.accentText, sheet);
  // Layer cards: organic, with the layer's own halo.
  for (var i = 0; i < tokens.layerColors.length; i++) {
    final color = tokens.layerColors[i];
    final card = Surfaces(GroundPalette.of(tokens, GroundTone.dark, color));
    final organic = card.fillSamples(SurfaceStyle.organic);
    add('text on layer card ${i + 1}', card.textOn(SurfaceStyle.organic), [
      ...organic,
    ]);
    add(
      'muted on layer card ${i + 1}',
      card.mutedOn(SurfaceStyle.organic),
      organic,
    );
    add('number on badge ${i + 1}', card.textOn(SurfaceStyle.organic), [
      for (final c in organic) Color.alphaBlend(color.withValues(alpha: .1), c),
    ]);
    add('legend ${i + 1} on ground', color, grounds);
    add('hits ${i + 1} on tray', color, tray, minimum: 3);
  }
  return rules;
}
