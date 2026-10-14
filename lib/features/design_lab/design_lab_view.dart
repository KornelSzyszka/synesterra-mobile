import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:synesterra_core/synesterra_core.dart';

import '../../shared/instrument_mist/mist_spec.dart';
import '../../shared/living_blobs/living_field.dart';
import '../../shared/theme/ambient_scope.dart';
import '../../shared/theme/design_scale.dart';
import '../../shared/theme/synesterra_theme.dart';
import 'blend_canvas.dart';
import 'lab_components.dart';
import 'lab_motion.dart';
import 'lab_palette.dart';
import 'lab_skin.dart';

/// Debug-only screen that renders the same components in three visual
/// directions (glass, organic, material), on a dark or a light ground, so the
/// Founder can compare them on a phone, and the Blend of the three (visual
/// language v2, the default tab) built from the shared round components.
/// Nothing here is product UI.
class DesignLabView extends StatefulWidget {
  const DesignLabView({super.key, @visibleForTesting this.debugGate});

  /// Tests only: the lab's flash gate, with a fake clock.
  final FlashGate? debugGate;

  @override
  State<DesignLabView> createState() => _DesignLabViewState();
}

class _DesignLabViewState extends State<DesignLabView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _drift = AnimationController(
    vsync: this,
    duration: driftPeriod,
  );

  /// One gate for every tab, on one (monotonic) clock.
  late final _gate = widget.debugGate ?? FlashGate();
  final _frames = ValueNotifier<String>('frame time: waiting for frames');

  /// True while the Blend tab is shown; otherwise [_variant] is.
  bool _blend = true;
  LabVariant _variant = LabVariant.glass;
  LabTone _tone = LabTone.dark;
  GlitchStrength _glitch = GlitchStrength.subtle;
  bool _reduceMotion = false;

  Offset _dot = const Offset(.25, -.2);
  String _view = 'Mist';
  double _level = .7;
  final Set<String> _tags = {'bell'};
  bool _playing = false;
  bool _looping = true;

  final Instrument _instrument = factoryInstruments.firstWhere(
    (instrument) => instrument.id == 'factory-bell',
  );

  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (_reduceMotion) {
      _drift.stop();
    } else if (!_drift.isAnimating) {
      _drift.repeat();
    }
  }

  @override
  void dispose() {
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
    _drift.dispose();
    _frames.dispose();
    super.dispose();
  }

  /// Average build and raster time of the last reported frames: a rough,
  /// on-device reading for the Founder (debug builds are slower than
  /// release).
  void _onTimings(List<FrameTiming> timings) {
    if (timings.isEmpty) return;
    double average(Duration Function(FrameTiming) of) =>
        timings.map((t) => of(t).inMicroseconds).reduce((a, b) => a + b) /
        timings.length /
        1000;
    final worst = timings
        .map((t) => t.rasterDuration.inMicroseconds)
        .reduce((a, b) => a > b ? a : b);
    _frames.value =
        'frame: build ${average((t) => t.buildDuration).toStringAsFixed(1)} ms'
        ' · raster ${average((t) => t.rasterDuration).toStringAsFixed(1)} ms'
        ' (worst ${(worst / 1000).toStringAsFixed(1)}) · ${timings.length} frames';
  }

  void _openBlendSheet(AmbientScope scope) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      elevation: 0,
      barrierColor: scope.palette.shade.withValues(alpha: .35),
      builder: (sheetContext) => AmbientScope(
        palette: scope.palette,
        drift: scope.drift,
        tapStrength: scope.tapStrength,
        gate: scope.gate,
        child: BlendSheet(
          onKeep: () => Navigator.of(sheetContext).pop(),
          onDismiss: () => Navigator.of(sheetContext).pop(),
        ),
      ),
    );
  }

  void _openSheet(LabScope scope) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      elevation: 0,
      barrierColor: scope.skin.palette.shade.withValues(alpha: .35),
      builder: (sheetContext) => scope.wrap(
        LabSheet(
          onKeep: () => Navigator.of(sheetContext).pop(),
          onDismiss: () => Navigator.of(sheetContext).pop(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = SynesterraTokens.of(context);
    final aura = tokens.layerColors[buildMistSpec(_instrument).colorIndex];
    final palette = LabPalette.of(tokens, _tone, aura);
    final skin = skinFor(_variant, palette);
    final scope = LabScope(
      skin: skin,
      drift: _drift,
      reduceMotion: _reduceMotion,
      glitch: _glitch,
      gate: _gate,
      child: const SizedBox.shrink(),
    );
    return Scaffold(
      key: const Key('design-lab'),
      backgroundColor: palette.ground,
      body: Stack(
        children: [
          Positioned.fill(
            child: RepaintBoundary(
              child: CustomPaint(
                painter: LabAuraPainter(
                  palette: palette,
                  drift: _reduceMotion ? null : _drift,
                ),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                _Chrome(
                  palette: palette,
                  blend: _blend,
                  variant: _variant,
                  tone: _tone,
                  glitch: _glitch,
                  frames: _frames,
                  onBlend: () => setState(() => _blend = true),
                  onVariant: (v) => setState(() {
                    _blend = false;
                    _variant = v;
                  }),
                  onTone: () => setState(
                    () => _tone = _tone == LabTone.dark
                        ? LabTone.light
                        : LabTone.dark,
                  ),
                  onGlitch: (g) => setState(() => _glitch = g),
                ),
                Expanded(
                  child: scope.wrap(
                    AnimatedSwitcher(
                      duration: _reduceMotion
                          ? Duration.zero
                          : const Duration(milliseconds: 280),
                      child: _blend
                          ? KeyedSubtree(
                              key: ValueKey('lab-canvas-blend-${_tone.name}'),
                              child: _blendCanvas(palette),
                            )
                          : KeyedSubtree(
                              key: ValueKey(
                                'lab-canvas-${_variant.name}-${_tone.name}',
                              ),
                              child: _canvas(context, skin, scope),
                            ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _blendCanvas(LabPalette palette) => AmbientScope(
    palette: palette,
    drift: _drift,
    tapStrength: _glitch,
    gate: _gate,
    child: Builder(
      builder: (context) => BlendCanvas(
        instrument: _instrument,
        dot: _dot,
        onDot: (dot) => setState(() => _dot = dot),
        view: _view,
        onView: (view) => setState(() => _view = view),
        level: _level,
        onLevel: (level) => setState(() => _level = level),
        tags: _tags,
        onTag: (tag) => setState(
          () => _tags.contains(tag) ? _tags.remove(tag) : _tags.add(tag),
        ),
        playing: _playing,
        looping: _looping,
        onPlay: () => setState(() => _playing = !_playing),
        onStop: () => setState(() => _playing = false),
        onLoop: () => setState(() => _looping = !_looping),
        onOpenSheet: () => _openBlendSheet(AmbientScope.maybeOf(context)!),
      ),
    ),
  );

  Widget _canvas(BuildContext context, LabSkin skin, LabScope scope) {
    final palette = skin.palette;
    const gap = SizedBox(height: Space.xxl);
    const small = SizedBox(height: Space.lg);
    return LayoutBuilder(
      builder: (context, constraints) {
        final padSize = (constraints.maxWidth - 2 * Space.xxl).clamp(
          160.0,
          300.0,
        );
        return ListView(
          key: const Key('lab-canvas'),
          padding: const EdgeInsets.fromLTRB(Space.xl, Space.lg, Space.xl, 0),
          children: [
            Text(
              skin.tagline,
              key: const Key('lab-tagline'),
              textAlign: TextAlign.center,
              style: labText(
                context,
                color: palette.muted,
                size: TypeScale.bodyLarge,
                serif: true,
              ),
            ),
            gap,
            const LabHeader('Instrument'),
            small,
            Center(
              child: LabPad(
                key: const Key('lab-pad'),
                instrument: _instrument,
                dot: _dot,
                size: padSize,
                onChanged: (dot) => setState(() => _dot = dot),
              ),
            ),
            const SizedBox(height: Space.xl),
            LabSegmented<String>(
              key: const Key('lab-segmented'),
              options: const [
                ('Mist', 'Mist'),
                ('Figure', 'Figure'),
                ('Wave', 'Wave'),
              ],
              value: _view,
              onChanged: (view) => setState(() => _view = view),
            ),
            small,
            LabSlider(
              key: const Key('lab-slider'),
              label: 'Level',
              value: _level,
              onChanged: (level) => setState(() => _level = level),
            ),
            small,
            Wrap(
              key: const Key('lab-chips'),
              spacing: Space.md,
              children: [
                for (final (i, tag) in const [
                  'bell',
                  'metal',
                  'bright',
                ].indexed)
                  LabChip(
                    key: ValueKey('lab-chip-$tag'),
                    label: tag,
                    seed: 40 + i,
                    selected: _tags.contains(tag),
                    onTap: () => setState(
                      () => _tags.contains(tag)
                          ? _tags.remove(tag)
                          : _tags.add(tag),
                    ),
                  ),
              ],
            ),
            gap,
            const LabHeader('Library'),
            small,
            LabCard(
              key: const Key('lab-card'),
              instrument: _instrument,
              subtitle: 'Instrument · 3 tags',
              onOpen: () {},
              onPlay: () {},
            ),
            gap,
            const LabHeader('Transport'),
            small,
            LabTransport(
              key: const Key('lab-transport'),
              playing: _playing,
              looping: _looping,
              bpm: 96,
              onPlay: () => setState(() => _playing = !_playing),
              onStop: () => setState(() => _playing = false),
              onLoop: () => setState(() => _looping = !_looping),
            ),
            gap,
            const LabHeader('Sheet'),
            Align(
              alignment: Alignment.centerLeft,
              child: Builder(
                builder: (context) => LabChip(
                  key: const Key('lab-open-sheet'),
                  label: 'Open as sheet',
                  seed: 50,
                  onTap: () => _openSheet(LabScope.of(context)),
                ),
              ),
            ),
            small,
            LabSheet(
              key: const Key('lab-sheet'),
              inline: true,
              onKeep: () {},
              onDismiss: () {},
            ),
          ],
        );
      },
    );
  }
}

/// The lab's own controls, kept plain so they are not part of the
/// comparison: back, Blend or variant, ground, tap flash and the frame-time
/// reading.
class _Chrome extends StatelessWidget {
  const _Chrome({
    required this.palette,
    required this.blend,
    required this.variant,
    required this.tone,
    required this.glitch,
    required this.frames,
    required this.onBlend,
    required this.onVariant,
    required this.onTone,
    required this.onGlitch,
  });

  final LabPalette palette;
  final bool blend;
  final LabVariant variant;
  final LabTone tone;
  final GlitchStrength glitch;
  final ValueNotifier<String> frames;
  final VoidCallback onBlend;
  final ValueChanged<LabVariant> onVariant;
  final VoidCallback onTone;
  final ValueChanged<GlitchStrength> onGlitch;

  @override
  Widget build(BuildContext context) {
    final platform = Theme.of(context).platform;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.sm),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                key: const Key('lab-back'),
                tooltip: 'Back',
                color: palette.text,
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
              Expanded(
                child: Text(
                  'Design lab',
                  style: labText(
                    context,
                    color: palette.text,
                    size: TypeScale.title,
                    serif: true,
                  ),
                ),
              ),
              IconButton(
                key: const Key('lab-tone'),
                tooltip: tone == LabTone.dark
                    ? 'Show on a light ground'
                    : 'Show on a dark ground',
                color: palette.text,
                icon: Icon(
                  tone == LabTone.dark
                      ? Icons.light_mode_outlined
                      : Icons.dark_mode_outlined,
                ),
                onPressed: onTone,
              ),
            ],
          ),
          Wrap(
            alignment: WrapAlignment.center,
            children: [
              _Tab(
                key: const ValueKey('lab-variant-blend'),
                label: 'Blend',
                semanticLabel: 'Blend variant',
                selected: blend,
                palette: palette,
                onTap: onBlend,
              ),
              for (final v in LabVariant.values)
                _Tab(
                  key: ValueKey('lab-variant-${v.name}'),
                  label: v.label,
                  semanticLabel: '${v.label} variant',
                  selected: !blend && v == variant,
                  palette: palette,
                  onTap: () => onVariant(v),
                ),
            ],
          ),
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'Tap flash',
                style: labText(
                  context,
                  color: palette.muted,
                  size: TypeScale.caption,
                ),
              ),
              const SizedBox(width: Space.sm),
              for (final g in GlitchStrength.values)
                _Tab(
                  key: ValueKey('lab-glitch-${g.name}'),
                  label: g.label,
                  semanticLabel: 'Tap flash ${g.label.toLowerCase()}',
                  selected: g == glitch,
                  palette: palette,
                  small: true,
                  onTap: () => onGlitch(g),
                ),
            ],
          ),
          // Living or flat blobs (UX-126): flips the lab's living gallery
          // and the library's cards, to compare them with the frame time.
          ValueListenableBuilder<bool>(
            valueListenable: livingBlobsEnabled,
            builder: (context, living, _) => Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  'Blobs',
                  style: labText(
                    context,
                    color: palette.muted,
                    size: TypeScale.caption,
                  ),
                ),
                const SizedBox(width: Space.sm),
                for (final (value, label) in const [
                  (false, 'Flat'),
                  (true, 'Living'),
                ])
                  _Tab(
                    key: ValueKey('lab-blobs-${label.toLowerCase()}'),
                    label: label,
                    semanticLabel: 'Blobs ${label.toLowerCase()}',
                    selected: living == value,
                    palette: palette,
                    small: true,
                    onTap: () => livingBlobsEnabled.value = value,
                  ),
              ],
            ),
          ),
          ValueListenableBuilder<String>(
            valueListenable: frames,
            builder: (context, text, _) => Text(
              text,
              key: const Key('lab-frame-timing'),
              style: TextStyle(
                color: palette.muted,
                fontSize: TypeScale.overline,
                fontFamily: SynesterraFonts.monospace(platform),
                fontFamilyFallback: SynesterraFonts.monospaceFallback(platform),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A plain text tab with a small gold dot under the chosen one.
class _Tab extends StatelessWidget {
  const _Tab({
    super.key,
    required this.label,
    required this.semanticLabel,
    required this.selected,
    required this.palette,
    required this.onTap,
    this.small = false,
  });

  final String label;
  final String semanticLabel;
  final bool selected;
  final LabPalette palette;
  final VoidCallback onTap;
  final bool small;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: semanticLabel,
      excludeSemantics: true,
      onTap: onTap,
      child: InkResponse(
        onTap: onTap,
        radius: 28,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: small ? Space.md : Space.lg,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  style: labText(
                    context,
                    color: selected ? palette.text : palette.muted,
                    size: small ? TypeScale.caption : TypeScale.bodyLarge,
                    weight: selected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
                const SizedBox(height: Space.xs),
                Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: selected ? palette.accent : Colors.transparent,
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
