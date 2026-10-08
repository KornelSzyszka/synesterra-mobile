import 'package:flutter/material.dart';

import '../../shared/theme/synesterra_theme.dart';
import '../../shared/widgets/palette_menu_button.dart';
import '../../shared/theme/design_scale.dart';

/// The first screen: Editor, Library and Learn.
class HomeView extends StatelessWidget {
  const HomeView({
    super.key,
    required this.onOpenEditor,
    required this.onOpenLibrary,
    required this.onOpenLearn,
    this.onOpenAudioSpike,
    this.palette = SynesterraPalette.forest,
    this.onPaletteChanged,
  });

  final VoidCallback onOpenEditor;
  final VoidCallback onOpenLibrary;
  final VoidCallback onOpenLearn;
  final VoidCallback? onOpenAudioSpike;
  final SynesterraPalette palette;
  final ValueChanged<SynesterraPalette>? onPaletteChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = SynesterraTokens.of(context);
    final platform = Theme.of(context).platform;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          '◉  synesterra',
          style: TextStyle(
            color: tokens.text,
            fontFamily: SynesterraFonts.serif(platform),
            fontFamilyFallback: SynesterraFonts.serifFallback(platform),
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          if (onPaletteChanged != null)
            PaletteMenuButton(
              palette: palette,
              onPaletteChanged: onPaletteChanged!,
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(Space.lg),
        children: [
          _EntryCard(
            key: const Key('home-editor'),
            icon: Icons.tune,
            title: 'Editor',
            description: 'Shape an instrument, build a loop, arrange a track.',
            onTap: onOpenEditor,
          ),
          const SizedBox(height: Space.lg),
          _EntryCard(
            key: const Key('home-library'),
            icon: Icons.library_music_outlined,
            title: 'Library',
            description: 'Your saved instruments, loops and arrangements.',
            onTap: onOpenLibrary,
          ),
          const SizedBox(height: Space.lg),
          _EntryCard(
            key: const Key('home-learn'),
            icon: Icons.school_outlined,
            title: 'Learn',
            description: 'Short lessons on rhythm, with live pictures.',
            onTap: onOpenLearn,
          ),
          if (onOpenAudioSpike != null) ...[
            const SizedBox(height: 16),
            _EntryCard(
              key: const Key('home-audio-spike'),
              icon: Icons.graphic_eq,
              title: 'Audio spike',
              description: 'Run rhythm and instrument-buffer measurements.',
              onTap: onOpenAudioSpike!,
            ),
          ],
        ],
      ),
    );
  }
}

class _EntryCard extends StatelessWidget {
  const _EntryCard({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = SynesterraTokens.of(context);
    final platform = Theme.of(context).platform;
    return Semantics(
      button: true,
      label: '$title. $description',
      excludeSemantics: true,
      onTap: onTap,
      child: Material(
        color: tokens.surface,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: tokens.border),
          borderRadius: BorderRadius.circular(Radii.sm),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(Radii.sm),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 140),
            child: Padding(
              padding: const EdgeInsets.all(Space.lg),
              child: Row(
                children: [
                  Icon(icon, size: 36, color: tokens.accent),
                  const SizedBox(width: Space.lg),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            color: tokens.text,
                            fontFamily: SynesterraFonts.serif(platform),
                            fontFamilyFallback: SynesterraFonts.serifFallback(
                              platform,
                            ),
                            fontSize: TypeScale.headline,
                          ),
                        ),
                        const SizedBox(height: Space.sm),
                        Text(
                          description,
                          style: TextStyle(color: tokens.muted),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, color: tokens.muted),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
