import 'package:flutter/material.dart';

import '../data/repositories/instrument_library_repository.dart';
import '../features/editor/editor_view.dart';
import '../features/home/home_view.dart';
import '../features/library/library_view.dart';
import '../shared/theme/synesterra_theme.dart';

class SynesterraApp extends StatefulWidget {
  const SynesterraApp({super.key, required this.instrumentLibrary});

  final InstrumentLibraryRepository instrumentLibrary;

  @override
  State<SynesterraApp> createState() => _SynesterraAppState();
}

class _SynesterraAppState extends State<SynesterraApp> {
  SynesterraPalette _palette = SynesterraPalette.forest;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Synesterra',
      theme: synesterraTheme(_palette),
      home: Builder(
        builder: (context) => HomeView(
          palette: _palette,
          onPaletteChanged: (palette) => setState(() => _palette = palette),
          onOpenEditor: () => Navigator.of(
            context,
          ).push(MaterialPageRoute<void>(builder: (_) => const EditorView())),
          onOpenLibrary: () => Navigator.of(
            context,
          ).push(MaterialPageRoute<void>(builder: (_) => const LibraryView())),
        ),
      ),
    );
  }
}
