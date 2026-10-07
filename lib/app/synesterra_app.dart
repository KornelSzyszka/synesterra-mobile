import 'package:flutter/material.dart';
import 'package:synesterra_core/synesterra_core.dart';

import '../data/repositories/arrangement_library_repository.dart';
import '../data/repositories/impl/in_memory_arrangement_library_repository.dart';
import '../data/repositories/impl/in_memory_loop_library_repository.dart';
import '../data/repositories/instrument_audition_repository.dart';
import '../data/repositories/instrument_library_repository.dart';
import '../data/repositories/loop_library_repository.dart';
import '../data/repositories/audio_spike_repository.dart';
import '../features/editor/editor_view.dart';
import '../features/home/home_view.dart';
import '../features/library/library_item_placeholder_view.dart';
import '../features/library/library_view.dart';
import '../features/audio_spike/audio_spike_view.dart';
import '../shared/theme/synesterra_theme.dart';

class SynesterraApp extends StatefulWidget {
  const SynesterraApp({
    super.key,
    required this.instrumentLibrary,
    required this.instrumentAudition,
    this.audioSpikeRepositoryFactory,
    this.loopLibrary,
    this.arrangementLibrary,
  });

  final InstrumentLibraryRepository instrumentLibrary;
  final InstrumentAuditionRepository instrumentAudition;

  /// The bootstrap passes the file-backed libraries; when omitted (tests
  /// that do not care), an empty in-memory library is used.
  final LoopLibraryRepository? loopLibrary;
  final ArrangementLibraryRepository? arrangementLibrary;
  final AudioSpikeRepository Function()? audioSpikeRepositoryFactory;

  @override
  State<SynesterraApp> createState() => _SynesterraAppState();
}

class _SynesterraAppState extends State<SynesterraApp> {
  SynesterraPalette _palette = SynesterraPalette.forest;
  late final LoopLibraryRepository _loops =
      widget.loopLibrary ?? InMemoryLoopLibraryRepository();
  late final ArrangementLibraryRepository _arrangements =
      widget.arrangementLibrary ?? InMemoryArrangementLibraryRepository();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Synesterra',
      theme: synesterraTheme(_palette),
      home: Builder(
        builder: (context) {
          void openEditor([Instrument? instrument, bool existing = false]) =>
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => EditorView(
                    instrumentLibrary: widget.instrumentLibrary,
                    instrumentAudition: widget.instrumentAudition,
                    initialInstrument: instrument,
                    editsExisting: existing,
                  ),
                ),
              );
          // Until the Loop and Arrangement panels exist, opening an item from
          // the Library shows a placeholder.
          void openPlaceholder(String title, String message) =>
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => LibraryItemPlaceholderView(
                    title: title,
                    message: message,
                  ),
                ),
              );
          return HomeView(
            palette: _palette,
            onPaletteChanged: (palette) => setState(() => _palette = palette),
            onOpenEditor: openEditor,
            onOpenLibrary: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => LibraryView(
                  instrumentLibrary: widget.instrumentLibrary,
                  loopLibrary: _loops,
                  arrangementLibrary: _arrangements,
                  onOpenInstrument: openEditor,
                  onOpenLoop: (loop, _) => openPlaceholder(
                    loop.name,
                    'The Loop panel is not built yet. '
                    'This loop is kept in your library.',
                  ),
                  onOpenArrangement: (arrangement) => openPlaceholder(
                    arrangement.name,
                    'The Arrangement panel is not built yet. '
                    'This arrangement is kept in your library.',
                  ),
                ),
              ),
            ),
            onOpenAudioSpike: widget.audioSpikeRepositoryFactory == null
                ? null
                : () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => AudioSpikeView(
                        repository: widget.audioSpikeRepositoryFactory!(),
                      ),
                    ),
                  ),
          );
        },
      ),
    );
  }
}
