import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../shared/theme/design_scale.dart';
import '../../shared/theme/round_shapes.dart';
import '../../shared/theme/surfaces.dart';
import '../../shared/theme/synesterra_theme.dart';
import '../../shared/widgets/palette_menu_button.dart';
import '../../shared/widgets/round_components.dart';
import '../../shared/widgets/round_screen.dart';
import '../../shared/widgets/tap_glitch.dart';

/// The first screen: the title and three round entries, Editor, Library and
/// Learn. The Editor is the large gold light; Library and Learn are two
/// softer forms below it, one a little lower than the other.
class HomeView extends StatelessWidget {
  const HomeView({
    super.key,
    required this.onOpenEditor,
    required this.onOpenLibrary,
    required this.onOpenLearn,
    this.onOpenAudioSpike,
    this.onOpenDesignLab,
    this.palette = SynesterraPalette.graphite,
    this.onPaletteChanged,
  });

  final VoidCallback onOpenEditor;
  final VoidCallback onOpenLibrary;
  final VoidCallback onOpenLearn;
  final VoidCallback? onOpenAudioSpike;

  /// Debug builds only: a long press on the title opens the design lab.
  final VoidCallback? onOpenDesignLab;
  final SynesterraPalette palette;
  final ValueChanged<SynesterraPalette>? onPaletteChanged;

  @override
  Widget build(BuildContext context) {
    return RoundScreen(
      showHeader: false,
      drifts: true,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final big = math.min(width * .62, 252.0);
          final small = math.min(width * .39, 164.0);
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              Space.lg,
              Space.sm,
              Space.lg,
              Space.xl,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: constraints.maxHeight - 40,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    children: [
                      const SizedBox(width: 48),
                      Expanded(child: _Title(onLongPress: onOpenDesignLab)),
                      SizedBox(
                        width: 48,
                        child: onPaletteChanged == null
                            ? null
                            : PaletteMenuButton(
                                palette: palette,
                                onPaletteChanged: onPaletteChanged!,
                              ),
                      ),
                    ],
                  ),
                  const SizedBox(height: Space.xl),
                  _Entry(
                    key: const Key('home-editor'),
                    icon: Icons.tune_rounded,
                    title: 'Editor',
                    description:
                        'Shape an instrument, build a loop, arrange a track.',
                    onTap: onOpenEditor,
                    size: big,
                    style: SurfaceStyle.primary,
                    shape: const BlobShape(seed: 3, amount: BlobAmount.round),
                    breathes: true,
                  ),
                  const SizedBox(height: Space.xl),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _Entry(
                        key: const Key('home-library'),
                        icon: Icons.library_music_outlined,
                        title: 'Library',
                        description: 'Your saved instruments and loops.',
                        onTap: onOpenLibrary,
                        size: small,
                        style: SurfaceStyle.organic,
                        shape: const BlobShape(
                          seed: 11,
                          amount: BlobAmount.round,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: Space.xxl),
                        child: _Entry(
                          key: const Key('home-learn'),
                          icon: Icons.school_outlined,
                          title: 'Learn',
                          description:
                              'Short lessons on rhythm, with live pictures.',
                          onTap: onOpenLearn,
                          size: small,
                          style: SurfaceStyle.organic,
                          shape: const BlobShape(
                            seed: 5,
                            amount: BlobAmount.round,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (onOpenAudioSpike != null) ...[
                    const SizedBox(height: Space.xl),
                    TactileChip(
                      key: const Key('home-audio-spike'),
                      label: 'Audio spike',
                      onPressed: onOpenAudioSpike,
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// The title with a soft gold glow. A long press opens the design lab in a
/// debug build.
class _Title extends StatelessWidget {
  const _Title({required this.onLongPress});

  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final palette = groundOf(context);
    return Semantics(
      onLongPressHint: onLongPress == null ? null : 'open design lab',
      child: GestureDetector(
        key: const Key('home-title'),
        behavior: HitTestBehavior.opaque,
        onLongPress: onLongPress,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Center(
            child: Text(
              '◉  synesterra',
              maxLines: 1,
              style:
                  roundText(
                    context,
                    color: palette.text,
                    size: TypeScale.headline,
                    serif: true,
                    weight: FontWeight.bold,
                  ).copyWith(
                    shadows: [
                      Shadow(
                        color: palette.accent.withValues(alpha: .45),
                        blurRadius: 18,
                      ),
                    ],
                  ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One round entry: a form with an icon and a name, and what it opens in a
/// line under it. One semantics node, "Title. Description".
class _Entry extends StatefulWidget {
  const _Entry({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
    required this.size,
    required this.style,
    required this.shape,
    this.breathes = false,
  });

  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onTap;
  final double size;
  final SurfaceStyle style;
  final RoundShape shape;
  final bool breathes;

  @override
  State<_Entry> createState() => _EntryState();
}

class _EntryState extends State<_Entry> {
  bool _pressed = false;

  void _set(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final style = widget.style;
    final large = widget.style == SurfaceStyle.primary;
    return Semantics(
      container: true,
      button: true,
      label: '${widget.title}. ${widget.description}',
      excludeSemantics: true,
      onTap: widget.onTap,
      child: GestureDetector(
        excludeFromSemantics: true,
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _set(true),
        onTapUp: (_) => _set(false),
        onTapCancel: () => _set(false),
        onTap: widget.onTap,
        child: SizedBox(
          width: widget.size,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox.square(
                dimension: widget.size,
                child: TapGlitch(
                  shape: widget.shape,
                  child: RepaintBoundary(
                    child: RoundSurface(
                      style: style,
                      shape: widget.shape,
                      pressed: _pressed,
                      breathes: widget.breathes,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            widget.icon,
                            size: large ? 44 : 30,
                            color: textOn(context, style),
                          ),
                          SizedBox(height: large ? Space.md : Space.sm),
                          Text(
                            widget.title,
                            style: roundText(
                              context,
                              color: textOn(context, style),
                              size: large
                                  ? TypeScale.headline
                                  : TypeScale.title,
                              serif: true,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: Space.md),
              Text(
                widget.description,
                textAlign: TextAlign.center,
                style: roundText(
                  context,
                  color: groundOf(context).muted,
                  size: TypeScale.caption,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
