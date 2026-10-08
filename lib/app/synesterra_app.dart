import 'package:flutter/material.dart';
import 'package:synesterra_core/synesterra_core.dart';

import '../data/repositories/arrangement_library_repository.dart';
import '../data/repositories/impl/in_memory_arrangement_library_repository.dart';
import '../data/repositories/impl/in_memory_loop_library_repository.dart';
import '../data/repositories/impl/noop_playback_repository.dart';
import '../data/repositories/instrument_audition_repository.dart';
import '../data/repositories/instrument_library_repository.dart';
import '../data/repositories/loop.dart';
import '../data/repositories/loop_library_repository.dart';
import '../data/repositories/playback_repository.dart';
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
    this.playback,
  });

  final InstrumentLibraryRepository instrumentLibrary;
  final InstrumentAuditionRepository instrumentAudition;

  /// The bootstrap passes the file-backed libraries; when omitted (tests
  /// that do not care), an empty in-memory library is used.
  final LoopLibraryRepository? loopLibrary;
  final ArrangementLibraryRepository? arrangementLibrary;
  final AudioSpikeRepository Function()? audioSpikeRepositoryFactory;

  /// The bootstrap passes the engine; when omitted, a silent stand-in.
  final PlaybackRepository? playback;

  @override
  State<SynesterraApp> createState() => _SynesterraAppState();
}

class _SynesterraAppState extends State<SynesterraApp> {
  SynesterraPalette _palette = SynesterraPalette.forest;
  late final LoopLibraryRepository _loops =
      widget.loopLibrary ?? InMemoryLoopLibraryRepository();
  late final ArrangementLibraryRepository _arrangements =
      widget.arrangementLibrary ?? InMemoryArrangementLibraryRepository();
  late final PlaybackRepository _playback =
      widget.playback ?? NoopPlaybackRepository();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Synesterra',
      theme: synesterraTheme(_palette),
      home: Builder(
        builder: (context) {
          void openEditor({
            Instrument? instrument,
            bool existing = false,
            Loop? loop,
            bool loopExisting = false,
            EditorTab tab = EditorTab.instrument,
          }) => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => EditorView(
                instrumentLibrary: widget.instrumentLibrary,
                instrumentAudition: widget.instrumentAudition,
                loopLibrary: _loops,
                playback: _playback,
                initialInstrument: instrument,
                editsExisting: existing,
                initialLoop: loop,
                loopExisting: loopExisting,
                initialTab: tab,
              ),
            ),
          );
          // Opens the Loop panel with [loop]; Learn's "Try it" can use it too.
          void openLoop(Loop loop, bool existing) => openEditor(
            loop: loop,
            loopExisting: existing,
            tab: EditorTab.loop,
          );
          // Until the Arrangement panel exists, opening an arrangement from
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
                  onOpenInstrument: (instrument, existing) =>
                      openEditor(instrument: instrument, existing: existing),
                  onOpenLoop: openLoop,
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
