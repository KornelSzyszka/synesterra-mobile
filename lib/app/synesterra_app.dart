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
import '../features/editor/editor_view.dart';
import '../features/home/home_view.dart';
import '../features/arrangement/arrangement_panel.dart';
import '../features/training/training_view.dart';
import '../features/library/library_view.dart';
import '../shared/theme/synesterra_theme.dart';
import 'step_feedback.dart';

class SynesterraApp extends StatefulWidget {
  const SynesterraApp({
    super.key,
    required this.instrumentLibrary,
    required this.instrumentAudition,
    this.loopLibrary,
    this.arrangementLibrary,
    this.playback,
    this.stepFeedback = hapticStepFeedback,
    @visibleForTesting this.showArrangement = false,
  });

  final InstrumentLibraryRepository instrumentLibrary;
  final InstrumentAuditionRepository instrumentAudition;

  /// The bootstrap passes the file-backed libraries; when omitted (tests
  /// that do not care), an empty in-memory library is used.
  final LoopLibraryRepository? loopLibrary;
  final ArrangementLibraryRepository? arrangementLibrary;

  /// The bootstrap passes the engine; when omitted, a silent stand-in.
  final PlaybackRepository? playback;

  /// The light tick of the Instrument wheel on each snapped step: the
  /// platform's selection click unless a test gives its own.
  final VoidCallback stepFeedback;

  /// Arrangements are shelved (Founder, 2026-10-14); only tests turn them on.
  final bool showArrangement;

  @override
  State<SynesterraApp> createState() => _SynesterraAppState();
}

class _SynesterraAppState extends State<SynesterraApp> {
  SynesterraPalette _palette = SynesterraPalette.graphite;
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
            Arrangement? arrangement,
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
                showArrangement: widget.showArrangement,
                stepFeedback: widget.stepFeedback,
                // The Arrangement panel is its own feature (R4), so it is built
                // here; it shares the one playback repository and the
                // Editor's position adapter with the Loop panel.
                arrangementPanel: (context, shell) => ArrangementPanel(
                  loops: _loops,
                  arrangements: _arrangements,
                  playback: _playback,
                  position: shell.position,
                  initial: arrangement,
                  onModel: (model) => shell.guardPanel(
                    model == null
                        ? null
                        : EditorPanelGuard(
                            what: 'this arrangement',
                            changes: model,
                            dirty: () => model.hasUnsavedChanges,
                            canSave: () => model.canSave,
                            save: () async => await model.save() != null,
                          ),
                  ),
                ),
              ),
            ),
          );
          // Opens the Loop panel with [loop] (Library).
          void openLoop(Loop loop, bool existing) => openEditor(
            loop: loop,
            loopExisting: existing,
            tab: EditorTab.loop,
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
                  showArrangements: widget.showArrangement,
                  onOpenArrangement: (arrangement) => openEditor(
                    arrangement: arrangement,
                    tab: EditorTab.arrangement,
                  ),
                ),
              ),
            ),
            onOpenTraining: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => TrainingView(playback: _playback),
              ),
            ),
          );
        },
      ),
    );
  }
}
