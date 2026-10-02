import 'package:flutter/material.dart';

import '../data/repositories/impl/in_memory_rhythm_settings_repository.dart';
import '../features/rhythm/rhythm_view.dart';
import '../features/rhythm/rhythm_view_model.dart';
import '../shared/theme/synesterra_theme.dart';

class SynesterraApp extends StatefulWidget {
  const SynesterraApp({super.key});

  @override
  State<SynesterraApp> createState() => _SynesterraAppState();
}

class _SynesterraAppState extends State<SynesterraApp> {
  SynesterraPalette _palette = SynesterraPalette.forest;
  late final RhythmViewModel _viewModel = RhythmViewModel(
    repository: InMemoryRhythmSettingsRepository(),
  );

  @override
  void dispose() {
    _viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Synesterra',
      theme: synesterraTheme(_palette),
      home: RhythmView(
        viewModel: _viewModel,
        palette: _palette,
        onPaletteChanged: (palette) => setState(() => _palette = palette),
      ),
    );
  }
}
