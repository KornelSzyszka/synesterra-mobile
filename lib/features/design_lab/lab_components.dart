import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:synesterra_core/synesterra_core.dart';

import '../../shared/instrument_mist/instrument_mist.dart';
import '../../shared/instrument_mist/mist_spec.dart';
import '../../shared/theme/design_scale.dart';
import '../../shared/theme/synesterra_theme.dart';
import 'lab_motion.dart';
import 'lab_palette.dart';
import 'lab_skin.dart';
import 'skin_glass.dart';
import 'skin_material.dart';
import 'skin_organic.dart';

LabSkin skinFor(LabVariant variant, LabPalette palette) => switch (variant) {
  LabVariant.glass => GlassSkin(palette),
  LabVariant.organic => OrganicSkin(palette),
  LabVariant.material => MaterialSkin(palette),
};

/// What every lab component needs: the skin, the slow drift, reduce motion,
/// the tap flash strength and the one flash gate shared by the whole lab.
class LabScope extends InheritedWidget {
  const LabScope({
    super.key,
    required this.skin,
    required this.drift,
    required this.reduceMotion,
    required this.glitch,
    required this.gate,
    required super.child,
  });

  final LabSkin skin;

  /// 0..1 over [driftPeriod]; stands still under reduce motion.
  final Animation<double> drift;
  final bool reduceMotion;
  final GlitchStrength glitch;
  final FlashGate gate;

  GlitchMode get glitchMode =>
      glitchModeFor(glitch, reduceMotion: reduceMotion);

  static LabScope of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<LabScope>()!;

  /// The same scope around [child], for a route (a sheet) outside this tree.
  LabScope wrap(Widget child) => LabScope(
    skin: skin,
    drift: drift,
    reduceMotion: reduceMotion,
    glitch: glitch,
    gate: gate,
    child: child,
  );

  @override
  bool updateShouldNotify(LabScope oldWidget) =>
      skin.variant != oldWidget.skin.variant ||
      skin.palette != oldWidget.skin.palette ||
      drift != oldWidget.drift ||
      reduceMotion != oldWidget.reduceMotion ||
      glitch != oldWidget.glitch;
}

/// Drift (0..1) as a phase in radians.
double driftPhase(Animation<double>? drift) =>
    (drift?.value ?? 0) * 2 * math.pi;

/// The touch state handed to a surface: pressed, and the running flash.
@immutable
class LabPress {
  const LabPress({
    required this.pressed,
    required this.flash,
    required this.mode,
    required this.seed,
  });

  static const idle = LabPress(
    pressed: false,
    flash: kAlwaysDismissedAnimation,
    mode: GlitchMode.none,
    seed: 0,
  );

  final bool pressed;
  final Animation<double> flash;
  final GlitchMode mode;

  /// Changes with every flash, so jitter differs between taps.
  final int seed;
}

/// A tappable lab element: at least 48 dp, labelled for TalkBack, with the
/// press state and the tap flash (rate-limited by the scope's [FlashGate]).
class LabPressable extends StatefulWidget {
  const LabPressable({
    super.key,
    required this.label,
    required this.onTap,
    required this.builder,
    this.selected,
    this.excludeSemantics = true,
  });

  final String label;
  final VoidCallback onTap;
  final bool? selected;
  final bool excludeSemantics;
  final Widget Function(BuildContext context, LabPress press) builder;

  @override
  State<LabPressable> createState() => _LabPressableState();
}

class _LabPressableState extends State<LabPressable>
    with SingleTickerProviderStateMixin {
  late final AnimationController _flash = AnimationController(
    vsync: this,
    duration: glitchDuration,
  );
  bool _pressed = false;
  int _seed = 0;

  @override
  void dispose() {
    _flash.dispose();
    super.dispose();
  }

  void _tap() {
    final scope = LabScope.of(context);
    if (scope.glitchMode != GlitchMode.none &&
        scope.gate.tryFlash(
          Duration(microseconds: DateTime.now().microsecondsSinceEpoch),
        )) {
      _seed++;
      _flash.forward(from: 0);
    }
    widget.onTap();
  }

  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final mode = LabScope.of(context).glitchMode;
    return Semantics(
      container: true,
      button: true,
      selected: widget.selected,
      label: widget.label,
      excludeSemantics: widget.excludeSemantics,
      onTap: _tap,
      child: GestureDetector(
        // The Semantics above carries the label and the tap action.
        excludeFromSemantics: true,
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _setPressed(true),
        onTapUp: (_) => _setPressed(false),
        onTapCancel: () => _setPressed(false),
        onTap: _tap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          child: widget.builder(
            context,
            LabPress(pressed: _pressed, flash: _flash, mode: mode, seed: _seed),
          ),
        ),
      ),
    );
  }
}

/// A surface painted by the scope's skin, with the tap flash on top.
class LabSurface extends StatelessWidget {
  const LabSurface({
    super.key,
    required this.form,
    required this.kind,
    this.seed = 0,
    this.breathes = false,
    this.press = LabPress.idle,
    this.padding = EdgeInsets.zero,
    this.child,
  });

  final LabForm form;
  final LabKind kind;
  final int seed;
  final bool breathes;
  final LabPress press;
  final EdgeInsets padding;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final scope = LabScope.of(context);
    final drift = breathes && !scope.reduceMotion ? scope.drift : null;
    return CustomPaint(
      painter: LabSurfacePainter(
        skin: scope.skin,
        form: form,
        kind: kind,
        seed: seed,
        pressed: press.pressed,
        drift: drift,
      ),
      foregroundPainter: press.mode == GlitchMode.none
          ? null
          : LabFlashPainter(
              skin: scope.skin,
              form: form,
              seed: seed,
              flash: press.flash,
              mode: press.mode,
              amount: scope.glitch.amount,
              flashSeed: press.seed,
            ),
      child: Padding(padding: padding, child: child),
    );
  }
}

class LabSurfacePainter extends CustomPainter {
  LabSurfacePainter({
    required this.skin,
    required this.form,
    required this.kind,
    required this.seed,
    required this.pressed,
    this.drift,
  }) : super(repaint: drift);

  final LabSkin skin;
  final LabForm form;
  final LabKind kind;
  final int seed;
  final bool pressed;
  final Animation<double>? drift;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final path = skin.outline(
      rect,
      form,
      seed: seed,
      breath: driftPhase(drift),
    );
    skin.paintSurface(canvas, path, rect, kind, pressed: pressed, seed: seed);
  }

  @override
  bool shouldRepaint(LabSurfacePainter old) =>
      old.skin.variant != skin.variant ||
      old.skin.palette != skin.palette ||
      old.form != form ||
      old.kind != kind ||
      old.seed != seed ||
      old.pressed != pressed ||
      old.drift != drift;
}

/// The tap flash over an element's outline: the variant's glitch, or a plain
/// fade under reduce motion. Paints nothing when idle.
class LabFlashPainter extends CustomPainter {
  LabFlashPainter({
    required this.skin,
    required this.form,
    required this.seed,
    required this.flash,
    required this.mode,
    required this.amount,
    required this.flashSeed,
  }) : super(repaint: flash);

  final LabSkin skin;
  final LabForm form;
  final int seed;
  final Animation<double> flash;
  final GlitchMode mode;
  final double amount;
  final int flashSeed;

  @override
  void paint(Canvas canvas, Size size) {
    final t = flash.value;
    if (!flash.isAnimating || t <= 0 || t >= 1) return;
    final rect = Offset.zero & size;
    final path = skin.outline(rect, form, seed: seed);
    switch (mode) {
      case GlitchMode.none:
        return;
      case GlitchMode.fade:
        skin.paintFade(canvas, path, t, amount);
      case GlitchMode.full:
        skin.paintGlitch(canvas, path, rect, t, amount, flashSeed);
    }
  }

  @override
  bool shouldRepaint(LabFlashPainter old) =>
      old.skin.variant != skin.variant ||
      old.skin.palette != skin.palette ||
      old.mode != mode ||
      old.amount != amount ||
      old.flash != flash ||
      old.flashSeed != flashSeed;
}

TextStyle labText(
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

/// A circular button: the primary action (gold) or a quiet secondary one.
class LabOrb extends StatelessWidget {
  const LabOrb({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.primary = false,
    this.selected = false,
    this.size = 52,
    this.seed = 0,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool primary;
  final bool selected;
  final double size;
  final int seed;

  @override
  Widget build(BuildContext context) {
    final skin = LabScope.of(context).skin;
    final kind = primary
        ? LabKind.accent
        : (selected ? LabKind.selected : LabKind.plain);
    return LabPressable(
      label: label,
      selected: primary ? null : selected,
      onTap: onTap,
      builder: (context, press) => SizedBox.square(
        dimension: math.max(48, size),
        child: Center(
          child: SizedBox.square(
            dimension: size,
            child: RepaintBoundary(
              child: LabSurface(
                form: LabForm.round,
                kind: kind,
                seed: seed,
                breathes: primary && skin.primaryBreathes,
                press: press,
                child: Center(
                  child: Icon(icon, size: size * .42, color: skin.textOn(kind)),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A tag: a small wide form, 48 dp tall to touch.
class LabChip extends StatelessWidget {
  const LabChip({
    super.key,
    required this.label,
    required this.onTap,
    this.selected = false,
    this.seed = 0,
    this.accent = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool selected;
  final int seed;

  /// The primary action in chip form (the sheet's Keep).
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final skin = LabScope.of(context).skin;
    final kind = accent
        ? LabKind.accent
        : (selected ? LabKind.selected : LabKind.plain);
    return LabPressable(
      label: label,
      selected: accent ? null : selected,
      onTap: onTap,
      builder: (context, press) => SizedBox(
        height: 48,
        child: Center(
          child: LabSurface(
            form: LabForm.wide,
            kind: kind,
            seed: seed,
            press: press,
            padding: const EdgeInsets.symmetric(
              horizontal: Space.lg + 2,
              vertical: Space.md,
            ),
            child: Text(
              label,
              style: labText(
                context,
                color: skin.textOn(kind),
                weight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A choice of one of a few options.
class LabSegmented<T> extends StatelessWidget {
  const LabSegmented({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
  });

  final List<(T, String)> options;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final skin = LabScope.of(context).skin;
    if (skin.separateSegments) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (final (i, (option, label)) in options.indexed) ...[
            if (i > 0) const SizedBox(width: Space.md),
            LabChip(
              key: ValueKey('lab-segment-$label'),
              label: label,
              selected: option == value,
              seed: 20 + i,
              onTap: () => onChanged(option),
            ),
          ],
        ],
      );
    }
    return SizedBox(
      height: 52,
      child: LabSurface(
        form: LabForm.wide,
        kind: skin.segmentTrackKind,
        seed: 19,
        padding: const EdgeInsets.all(2),
        child: Row(
          children: [
            for (final (option, label) in options)
              Expanded(
                child: LabPressable(
                  key: ValueKey('lab-segment-$label'),
                  label: label,
                  selected: option == value,
                  onTap: () => onChanged(option),
                  builder: (context, press) {
                    final selected = option == value;
                    final kind = selected ? LabKind.selected : LabKind.plain;
                    final text = Text(
                      label,
                      style: labText(
                        context,
                        color: selected
                            ? skin.textOn(LabKind.selected)
                            : skin.mutedOn(skin.segmentTrackKind),
                        weight: FontWeight.w500,
                      ),
                    );
                    if (!selected) return Center(child: text);
                    return LabSurface(
                      form: LabForm.wide,
                      kind: kind,
                      seed: 29,
                      press: press,
                      child: Center(child: text),
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

/// A slider with its label and value above a 48 dp track.
class LabSlider extends StatelessWidget {
  const LabSlider({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;

  /// 0..1.
  final double value;
  final ValueChanged<double> onChanged;

  String _percent(double v) => '${(v * 100).round()} %';

  @override
  Widget build(BuildContext context) {
    final skin = LabScope.of(context).skin;
    final palette = skin.palette;
    double clamp(double v) => v.clamp(0.0, 1.0);
    return Semantics(
      slider: true,
      label: label,
      value: _percent(value),
      increasedValue: _percent(clamp(value + .1)),
      decreasedValue: _percent(clamp(value - .1)),
      onIncrease: () => onChanged(clamp(value + .1)),
      onDecrease: () => onChanged(clamp(value - .1)),
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(label, style: labText(context, color: palette.text)),
              const Spacer(),
              Text(
                _percent(value),
                style: labText(context, color: palette.muted),
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
                      painter: _TrackPainter(skin: skin, value: value),
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

class _TrackPainter extends CustomPainter {
  const _TrackPainter({required this.skin, required this.value});

  final LabSkin skin;
  final double value;

  @override
  void paint(Canvas canvas, Size size) =>
      skin.paintTrack(canvas, Offset.zero & size, value);

  @override
  bool shouldRepaint(_TrackPainter old) =>
      old.value != value ||
      old.skin.variant != skin.variant ||
      old.skin.palette != skin.palette;
}

/// The circular instrument pad of the lab (its own painter, not the real
/// pad): the instrument mist inside, the light at [dot].
class LabPad extends StatelessWidget {
  const LabPad({
    super.key,
    required this.instrument,
    required this.dot,
    required this.onChanged,
    this.size = 280,
  });

  final Instrument instrument;

  /// -1..1 in both axes, inside the unit circle.
  final Offset dot;
  final ValueChanged<Offset> onChanged;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scope = LabScope.of(context);
    final tokens = SynesterraTokens.of(context);
    final spec = buildMistSpec(instrument);
    final color = tokens.layerColors[spec.colorIndex];
    void set(Offset local) {
      var p = (local - Offset(size / 2, size / 2)) / (size / 2 * .82);
      if (p.distance > 1) p = p / p.distance;
      onChanged(p);
    }

    final brightness = ((dot.dx + 1) / 2 * 100).round();
    final hardness = ((1 - dot.dy) / 2 * 100).round();
    return Semantics(
      label: 'Sound pad',
      value: 'Brightness $brightness %, hardness $hardness %',
      hint: 'Drag the light to shape the sound',
      excludeSemantics: true,
      child: GestureDetector(
        onPanDown: (details) => set(details.localPosition),
        onPanUpdate: (details) => set(details.localPosition),
        child: RepaintBoundary(
          child: CustomPaint(
            size: Size.square(size),
            painter: _PadPainter(
              skin: scope.skin,
              dot: dot,
              drift: scope.reduceMotion ? null : scope.drift,
              mist: MistPainter(spec: spec, color: color),
            ),
          ),
        ),
      ),
    );
  }
}

class _PadPainter extends CustomPainter {
  _PadPainter({
    required this.skin,
    required this.dot,
    required this.mist,
    this.drift,
  }) : super(repaint: drift);

  final LabSkin skin;
  final Offset dot;
  final MistPainter mist;
  final Animation<double>? drift;

  @override
  void paint(Canvas canvas, Size size) {
    skin.paintPad(
      canvas,
      Offset.zero & size,
      dot: dot,
      breath: driftPhase(drift),
      paintMist: (canvas, square) {
        canvas
          ..save()
          ..translate(square.left, square.top);
        mist.paint(canvas, square.size);
        canvas.restore();
      },
    );
  }

  @override
  bool shouldRepaint(_PadPainter old) =>
      old.dot != dot ||
      old.drift != drift ||
      old.skin.variant != skin.variant ||
      old.skin.palette != skin.palette ||
      old.mist.spec != mist.spec ||
      old.mist.color != mist.color;
}

/// A section header: the variant's small mark and a tracked-out label.
class LabHeader extends StatelessWidget {
  const LabHeader(this.title, {super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    final skin = LabScope.of(context).skin;
    return Semantics(
      header: true,
      label: title,
      excludeSemantics: true,
      child: Row(
        children: [
          CustomPaint(size: const Size.square(14), painter: _MarkPainter(skin)),
          const SizedBox(width: Space.md),
          Text(
            title.toUpperCase(),
            style: labText(
              context,
              color: skin.palette.muted,
              size: TypeScale.caption,
              weight: FontWeight.w600,
              spacing: 2.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _MarkPainter extends CustomPainter {
  const _MarkPainter(this.skin);

  final LabSkin skin;

  @override
  void paint(Canvas canvas, Size size) =>
      skin.paintMark(canvas, Offset.zero & size);

  @override
  bool shouldRepaint(_MarkPainter old) =>
      old.skin.variant != skin.variant || old.skin.palette != skin.palette;
}

/// A library item: the instrument's mist in a round vessel, its name and
/// kind, and a small play button.
class LabCard extends StatelessWidget {
  const LabCard({
    super.key,
    required this.instrument,
    required this.subtitle,
    required this.onOpen,
    required this.onPlay,
  });

  final Instrument instrument;
  final String subtitle;
  final VoidCallback onOpen;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    final skin = LabScope.of(context).skin;
    return LabPressable(
      label: 'Open ${instrument.name}. $subtitle',
      excludeSemantics: false,
      onTap: onOpen,
      builder: (context, press) => LabSurface(
        form: LabForm.wide,
        kind: LabKind.plain,
        seed: 7,
        press: press,
        padding: const EdgeInsets.fromLTRB(
          Space.xl,
          Space.lg,
          Space.lg,
          Space.lg,
        ),
        child: Row(
          children: [
            SizedBox.square(
              dimension: 64,
              child: LabSurface(
                form: LabForm.round,
                kind: LabKind.raised,
                seed: 8,
                child: Center(
                  child: InstrumentMist(instrument: instrument, size: 52),
                ),
              ),
            ),
            const SizedBox(width: Space.lg),
            Expanded(
              child: ExcludeSemantics(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      instrument.name,
                      style: labText(
                        context,
                        color: skin.textOn(LabKind.plain),
                        size: TypeScale.title,
                        serif: true,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: labText(
                        context,
                        color: skin.mutedOn(LabKind.plain),
                        size: TypeScale.caption,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            LabOrb(
              key: const Key('lab-card-play'),
              icon: Icons.play_arrow_rounded,
              label: 'Play ${instrument.name}',
              size: 44,
              seed: 9,
              onTap: onPlay,
            ),
          ],
        ),
      ),
    );
  }
}

/// Loop, Play and Stop around the tempo.
class LabTransport extends StatelessWidget {
  const LabTransport({
    super.key,
    required this.playing,
    required this.looping,
    required this.bpm,
    required this.onPlay,
    required this.onStop,
    required this.onLoop,
  });

  final bool playing;
  final bool looping;
  final int bpm;
  final VoidCallback onPlay;
  final VoidCallback onStop;
  final VoidCallback onLoop;

  @override
  Widget build(BuildContext context) {
    final skin = LabScope.of(context).skin;
    return LabSurface(
      form: LabForm.wide,
      kind: LabKind.plain,
      seed: 11,
      padding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: 10),
      child: Row(
        children: [
          LabOrb(
            key: const Key('lab-loop'),
            icon: Icons.repeat_rounded,
            label: 'Loop',
            selected: looping,
            seed: 12,
            onTap: onLoop,
          ),
          const SizedBox(width: Space.md),
          LabOrb(
            key: const Key('lab-play'),
            icon: playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
            label: playing ? 'Pause' : 'Play',
            primary: true,
            size: 72,
            seed: 13,
            onTap: onPlay,
          ),
          const SizedBox(width: Space.md),
          LabOrb(
            key: const Key('lab-stop'),
            icon: Icons.stop_rounded,
            label: 'Stop',
            seed: 14,
            onTap: onStop,
          ),
          const Spacer(),
          ExcludeSemantics(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '$bpm',
                  style: labText(
                    context,
                    color: skin.textOn(LabKind.plain),
                    size: TypeScale.headline,
                    serif: true,
                  ),
                ),
                Text(
                  'bpm',
                  style: labText(
                    context,
                    color: skin.mutedOn(LabKind.plain),
                    size: TypeScale.caption,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: Space.sm),
        ],
      ),
    );
  }
}

/// The bottom sheet sample: a question with a quiet and a primary answer.
class LabSheet extends StatelessWidget {
  const LabSheet({super.key, required this.onKeep, required this.onDismiss});

  final VoidCallback onKeep;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final skin = LabScope.of(context).skin;
    return CustomPaint(
      painter: _SheetPainter(skin),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          Space.xl,
          Space.huge - Space.sm,
          Space.xl,
          Space.xl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Keep this sound?',
              style: labText(
                context,
                color: skin.textOn(LabKind.raised),
                size: TypeScale.title,
                serif: true,
              ),
            ),
            const SizedBox(height: Space.sm),
            Text(
              'Bell goes to your library. You can shape it again later.',
              style: labText(context, color: skin.mutedOn(LabKind.raised)),
            ),
            const SizedBox(height: Space.lg),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                LabChip(
                  key: const Key('lab-sheet-dismiss'),
                  label: 'Not now',
                  seed: 15,
                  onTap: onDismiss,
                ),
                const SizedBox(width: Space.md),
                LabChip(
                  key: const Key('lab-sheet-keep'),
                  label: 'Keep',
                  accent: true,
                  seed: 16,
                  onTap: onKeep,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SheetPainter extends CustomPainter {
  const _SheetPainter(this.skin);

  final LabSkin skin;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    skin.paintSurface(canvas, skin.sheetOutline(rect), rect, LabKind.raised);
  }

  @override
  bool shouldRepaint(_SheetPainter old) =>
      old.skin.variant != skin.variant || old.skin.palette != skin.palette;
}

/// The instrument mist behind everything: two very soft lights (the
/// instrument's colour and the gold) that drift slowly. The strongest alpha
/// is [LabPalette.auraAlpha], which the contrast test includes.
class LabAuraPainter extends CustomPainter {
  LabAuraPainter({required this.palette, this.drift}) : super(repaint: drift);

  final LabPalette palette;
  final Animation<double>? drift;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = palette.ground);
    final phase = driftPhase(drift);
    final w = size.width;
    void light(Color color, Offset centre, double radius) {
      final rect = Rect.fromCircle(center: centre, radius: radius);
      canvas.drawCircle(
        centre,
        radius,
        Paint()
          ..shader = RadialGradient(
            colors: [
              color.withValues(alpha: palette.auraAlpha),
              color.withValues(alpha: palette.auraAlpha * .4),
              color.withValues(alpha: 0),
            ],
            stops: const [0, .45, 1],
          ).createShader(rect),
      );
    }

    light(
      palette.aura,
      Offset(
        w * (.42 + .07 * math.sin(phase)),
        size.height * (.24 + .03 * math.cos(phase)),
      ),
      w * .95,
    );
    light(
      palette.accent,
      Offset(
        w * (.8 - .06 * math.cos(phase)),
        size.height * (.7 + .04 * math.sin(phase)),
      ),
      w * .7,
    );
  }

  @override
  bool shouldRepaint(LabAuraPainter old) =>
      old.palette != palette || old.drift != drift;
}
