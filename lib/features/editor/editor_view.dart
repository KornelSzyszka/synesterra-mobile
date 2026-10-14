import 'dart:async';

import 'package:flutter/material.dart';
import 'package:synesterra_core/synesterra_core.dart';

import '../../data/repositories/instrument_audition_repository.dart';
import '../../data/repositories/instrument_library_repository.dart';
import '../../data/repositories/loop.dart';
import '../../data/repositories/loop_library_repository.dart';
import '../../data/repositories/playback_repository.dart';
import '../../shared/loop_view/position_source.dart';
import '../../shared/theme/ambient_scope.dart';
import '../../shared/theme/ground_palette.dart';
import '../../shared/theme/round_shapes.dart';
import '../../shared/theme/synesterra_theme.dart';
import '../../shared/widgets/round_components.dart';
import '../../shared/widgets/round_screen.dart';
import '../../shared/widgets/tap_glitch.dart';
import 'arrangement_tab_placeholder.dart';
import 'editor_style.dart';
import 'instrument_editor_view_model.dart';
import 'instrument_panel.dart';
import 'loop_editor_view_model.dart';
import 'loop_panel.dart';
import 'playback_position_source.dart';

/// The Editor's panels, in tab order.
enum EditorTab { instrument, loop, arrangement }

/// What the Editor offers a panel built outside this feature. A feature never
/// imports another one (R4), so `lib/app/` builds such a panel and passes it
/// in through an [EditorPanelBuilder].
abstract interface class EditorShell {
  /// The transport position of the shared playback repository, for loop
  /// views. Read-only: it never drives transport.
  PositionSource get position;

  /// Loads [loop] into the Loop panel and shows that panel. [existing] true
  /// edits one of the user's loops in place; false edits a copy. When the
  /// loop being edited has unsaved changes, the user is asked first.
  Future<void> openLoop(Loop loop, {required bool existing});

  /// Lets a panel built outside take part in the exit protection: leaving
  /// the Editor while [EditorPanelGuard.dirty] holds asks first, the same
  /// way as for the instrument and the loop. Null removes the guard.
  void guardPanel(EditorPanelGuard? guard);
}

/// Unsaved work of a panel built outside the Editor (see
/// [EditorShell.guardPanel]).
final class EditorPanelGuard {
  const EditorPanelGuard({
    required this.what,
    required this.changes,
    required this.dirty,
    required this.canSave,
    required this.save,
  });

  /// How the leave dialog names it, such as "this arrangement".
  final String what;

  /// Notifies when [dirty] or [canSave] may have changed.
  final Listenable changes;
  final bool Function() dirty;
  final bool Function() canSave;

  /// Saves; true when it was stored.
  final Future<bool> Function() save;
}

typedef EditorPanelBuilder = Widget Function(
  BuildContext context,
  EditorShell shell,
);

/// Editor with three panels: Instrument, Loop and Arrangement.
///
/// Visual language v2: the shared [RoundScreen] frame (the ground and its
/// still mist, a round Back and the title) with the panels as quiet tabs. The
/// Loop and Arrangement panels get the round theme ([editorRoundTheme]); the
/// Instrument panel keeps its own look.
class EditorView extends StatefulWidget {
  const EditorView({
    super.key,
    required this.instrumentLibrary,
    required this.instrumentAudition,
    required this.loopLibrary,
    required this.playback,
    this.initialInstrument,
    this.editsExisting = false,
    this.initialLoop,
    this.loopExisting = false,
    this.initialTab = EditorTab.instrument,
    this.arrangementPanel,
    this.showArrangement = true,
    this.stepFeedback,
  });

  final InstrumentLibraryRepository instrumentLibrary;
  final InstrumentAuditionRepository instrumentAudition;
  final LoopLibraryRepository loopLibrary;

  /// Shared by the Loop and Arrangement panels.
  final PlaybackRepository playback;

  /// Null starts a new instrument.
  final Instrument? initialInstrument;

  /// True when [initialInstrument] comes from the library and is edited in
  /// place; false makes a copy (a factory preset).
  final bool editsExisting;

  /// Null starts the Loop panel from a copy of the first factory loop.
  final Loop? initialLoop;

  /// True when [initialLoop] is one of the user's loops, edited in place;
  /// false edits a copy (a factory loop, a lesson's loop).
  final bool loopExisting;

  final EditorTab initialTab;

  /// Builds the Arrangement tab; null shows [ArrangementTabPlaceholder].
  final EditorPanelBuilder? arrangementPanel;

  /// False hides the Arrangement tab (shelved by the Founder); the code stays.
  final bool showArrangement;

  /// The light haptic tick of the Instrument wheel, given by the app (the
  /// UI may not reach the platform, decision 0001 R5). Null: no tick.
  final VoidCallback? stepFeedback;

  @override
  State<EditorView> createState() => _EditorViewState();
}

class _EditorViewState extends State<EditorView>
    with SingleTickerProviderStateMixin
    implements EditorShell {
  late final InstrumentEditorViewModel _instrument = InstrumentEditorViewModel(
    repository: widget.instrumentLibrary,
    audition: widget.instrumentAudition,
    instrument: widget.initialInstrument,
    existing: widget.editsExisting,
  );
  late final LoopEditorViewModel _loop = LoopEditorViewModel(
    library: widget.loopLibrary,
    instruments: widget.instrumentLibrary,
    playback: widget.playback,
    loop: widget.initialLoop,
    existing: widget.loopExisting,
  );
  late final PlaybackPositionSource _position = PlaybackPositionSource(
    widget.playback,
  );
  int get _tabCount => widget.showArrangement ? 3 : 2;

  late final TabController _tabs = TabController(
    length: _tabCount,
    initialIndex: widget.initialTab.index.clamp(0, _tabCount - 1),
    vsync: this,
  );

  /// Nothing keeps playing when the app goes to the background.
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onHide: _appHidden);
  }

  /// Stops whatever plays, the loop or an arrangement started in the
  /// Arrangement tab.
  void _appHidden() {
    _loop.appHidden();
    unawaited(widget.playback.stop());
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _guard?.changes.removeListener(_onGuard);
    _guardChanges.dispose();
    _tabs.dispose();
    _loop.dispose();
    _position.dispose();
    _instrument.dispose();
    super.dispose();
  }

  @override
  PositionSource get position => _position;

  @override
  Future<void> openLoop(Loop loop, {required bool existing}) async {
    if (_loop.dirty && !await confirmDiscardLoop(context)) return;
    _loop.open(loop, existing: existing);
    _tabs.animateTo(EditorTab.loop.index);
  }

  EditorPanelGuard? _guard;
  final _guardChanges = ValueNotifier(0);

  void _onGuard() => _guardChanges.value++;

  @override
  void guardPanel(EditorPanelGuard? guard) {
    _guard?.changes.removeListener(_onGuard);
    _guard = guard;
    guard?.changes.addListener(_onGuard);
  }

  bool get _panelDirty => _guard?.dirty() ?? false;

  bool get _dirty => _instrument.dirty || _loop.dirty || _panelDirty;

  /// Leaving with unsaved changes asks first; the safe answer is Cancel.
  Future<void> _confirmLeave() async {
    final navigator = Navigator.of(context);
    final instrument = _instrument.dirty;
    final loop = _loop.dirty;
    final guard = _panelDirty ? _guard : null;
    final parts = [
      if (instrument) 'this instrument',
      if (loop) 'this loop',
      ?guard?.what,
    ];
    final what = parts.length == 1
        ? parts.single
        : '${parts.sublist(0, parts.length - 1).join(', ')} and ${parts.last}';
    final canSave =
        (!instrument || _instrument.canSave) &&
        (!loop || _loop.canSave) &&
        (guard == null || guard.canSave());
    final choice = await showDialog<_LeaveChoice>(
      context: context,
      builder: (context) => roundDialog(
        context,
        AlertDialog(
          title: const Text('Unsaved changes'),
          content: Text('Save $what before leaving?'),
          actions: [
            TextButton(
              key: const Key('leave-discard'),
              onPressed: () => Navigator.pop(context, _LeaveChoice.discard),
              child: const Text('Discard'),
            ),
            TextButton(
              key: const Key('leave-cancel'),
              autofocus: true,
              onPressed: () => Navigator.pop(context, _LeaveChoice.cancel),
              child: const Text('Cancel'),
            ),
            TextButton(
              key: const Key('leave-save'),
              onPressed: canSave
                  ? () => Navigator.pop(context, _LeaveChoice.save)
                  : null,
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    switch (choice) {
      case _LeaveChoice.discard:
        navigator.pop();
      case _LeaveChoice.save:
        final savedInstrument = !instrument || await _instrument.save();
        final savedLoop = !loop || await _loop.save();
        final savedPanel = guard == null || await guard.save();
        if (savedInstrument && savedLoop && savedPanel) navigator.pop();
      case _LeaveChoice.cancel || null:
        break;
    }
  }

  ThemeData? _themeBase;
  GroundPalette? _themePalette;
  ThemeData? _roundTheme;

  /// The round theme for the Loop and Arrangement panels, made once per app
  /// theme rather than on every rebuild.
  ThemeData _roundThemeFor(ThemeData base, GroundPalette palette) {
    if (!identical(base, _themeBase) || palette != _themePalette) {
      _themeBase = base;
      _themePalette = palette;
      _roundTheme = editorRoundTheme(base, palette);
    }
    return _roundTheme!;
  }

  @override
  Widget build(BuildContext context) {
    final palette = editorPalette(SynesterraTokens.of(context));
    final round = _roundThemeFor(Theme.of(context), palette);
    final outer = AmbientScope.maybeOf(context);
    return ListenableBuilder(
      listenable: Listenable.merge([_instrument, _loop, _guardChanges]),
      builder: (context, _) => PopScope(
        canPop: !_dirty,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _confirmLeave();
        },
        child: RoundScreen(
          title: 'Editor',
          below: _EditorTabs(
            controller: _tabs,
            palette: palette,
            showArrangement: widget.showArrangement,
          ),
          // Passes on a flash gate and tap strength given from outside.
          child: AmbientScope(
            palette: palette,
            tapStrength: outer?.tapStrength,
            gate: outer?.gate,
            child: TabBarView(
              controller: _tabs,
              children: [
                _KeepAlive(
                  child: InstrumentPanel(
                    viewModel: _instrument,
                    stepFeedback: widget.stepFeedback,
                  ),
                ),
                _KeepAlive(
                  child: Theme(
                    data: round,
                    child: LoopPanel(viewModel: _loop, position: _position),
                  ),
                ),
                if (widget.showArrangement)
                  _KeepAlive(
                    child: Theme(
                      data: round,
                      child: Builder(
                        builder: (context) =>
                            widget.arrangementPanel?.call(context, this) ??
                            const ArrangementTabPlaceholder(),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The three panels as quiet words on the ground; a small gold light under
/// the current one follows the swipe. Each word answers a tap with the glitch.
class _EditorTabs extends StatelessWidget {
  const _EditorTabs({
    required this.controller,
    required this.palette,
    required this.showArrangement,
  });

  final bool showArrangement;
  final TabController controller;
  final GroundPalette palette;

  @override
  Widget build(BuildContext context) {
    Tab tab(String key, String label) => Tab(
      key: Key(key),
      height: 48,
      child: TapGlitch(
        shape: RoundShape.capsule,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Text(label),
        ),
      ),
    );
    return TabBar(
      controller: controller,
      dividerColor: Colors.transparent,
      indicator: _GlowDot(palette.accent),
      indicatorSize: TabBarIndicatorSize.label,
      labelPadding: EdgeInsets.zero,
      labelColor: palette.text,
      unselectedLabelColor: palette.muted,
      labelStyle: roundText(
        context,
        color: palette.text,
        weight: FontWeight.w600,
      ),
      unselectedLabelStyle: roundText(context, color: palette.muted),
      overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      splashFactory: NoSplash.splashFactory,
      tabs: [
        tab('editor-tab-instrument', 'Instrument'),
        tab('editor-tab-loop', 'Loop'),
        if (showArrangement) tab('editor-tab-arrangement', 'Arrangement'),
      ],
    );
  }
}

/// The tab indicator: a small gold light with a soft glow.
class _GlowDot extends Decoration {
  const _GlowDot(this.color);

  final Color color;

  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) =>
      _GlowDotPainter(color);
}

class _GlowDotPainter extends BoxPainter {
  _GlowDotPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration configuration) {
    final rect = offset & (configuration.size ?? Size.zero);
    final at = Offset(rect.center.dx, rect.bottom - 4);
    canvas
      ..drawCircle(
        at,
        5,
        Paint()
          ..color = color.withValues(alpha: .45)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.5),
      )
      ..drawCircle(at, 2.2, Paint()..color = color);
  }
}

enum _LeaveChoice { save, discard, cancel }

/// Keeps a panel's state when the user switches to another panel.
class _KeepAlive extends StatefulWidget {
  const _KeepAlive({required this.child});

  final Widget child;

  @override
  State<_KeepAlive> createState() => _KeepAliveState();
}

class _KeepAliveState extends State<_KeepAlive>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
