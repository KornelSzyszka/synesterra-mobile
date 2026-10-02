import 'package:flutter/material.dart';

import '../theme/synesterra_theme.dart';

class PaletteMenuButton extends StatelessWidget {
  const PaletteMenuButton({
    super.key,
    required this.palette,
    required this.onPaletteChanged,
  });

  final SynesterraPalette palette;
  final ValueChanged<SynesterraPalette> onPaletteChanged;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<SynesterraPalette>(
      tooltip: 'Choose palette',
      icon: const Icon(Icons.palette_outlined),
      initialValue: palette,
      onSelected: onPaletteChanged,
      itemBuilder: (_) => const [
        PopupMenuItem(value: SynesterraPalette.forest, child: Text('Forest')),
        PopupMenuItem(value: SynesterraPalette.autumn, child: Text('Autumn')),
        PopupMenuItem(
          value: SynesterraPalette.highContrast,
          child: Text('High contrast'),
        ),
      ],
    );
  }
}
