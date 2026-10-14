import 'package:flutter/material.dart';
import 'package:synesterra_core/synesterra_core.dart';

import '../../data/repositories/playback_repository.dart';
import '../../shared/theme/design_scale.dart';
import '../../shared/theme/round_shapes.dart';
import '../../shared/theme/surfaces.dart';
import '../../shared/widgets/round_components.dart';
import '../../shared/widgets/round_screen.dart';
import 'tap_trainer_model.dart';

/// "12 ms early", "On the beat".
String tapErrorText(double ms) {
  final rounded = ms.round();
  if (rounded == 0) return 'On the beat';
  return '${rounded.abs()} ms ${rounded < 0 ? 'early' : 'late'}';
}

/// Tap in rhythm: choose an exercise, listen to the click, tap the pad.
/// Timing error is shown per tap and as a summary.
class TapTrainerView extends StatefulWidget {
  const TapTrainerView({
    super.key,
    required this.playback,
    required this.offset,
  });

  final PlaybackRepository playback;
  final ValueNotifier<int> offset;

  @override
  State<TapTrainerView> createState() => _TapTrainerViewState();
}

class _TapTrainerViewState extends State<TapTrainerView> {
  late final TapTrainerModel _model = TapTrainerModel(
    playback: widget.playback,
    offset: widget.offset,
  );

  @override
  void dispose() {
    _model.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = groundOf(context);
    return RoundScreen(
      title: 'Tap in rhythm',
      child: ListenableBuilder(
        listenable: Listenable.merge([_model, _model.offsetMs]),
        builder: (context, _) {
          final model = _model;
          final done = model.phase == TapPhase.done;
          return ListView(
            key: const Key('tap-body'),
            padding: const EdgeInsets.fromLTRB(
              Space.lg,
              Space.md,
              Space.lg,
              Space.xl,
            ),
            children: [
              Text(
                model.preset.description,
                key: const Key('tap-description'),
                style: roundText(context, color: palette.muted),
              ),
              const SizedBox(height: Space.lg),
              Wrap(
                spacing: Space.md,
                runSpacing: Space.sm,
                children: [
                  for (final preset in tapPresets)
                    TactileChip(
                      key: Key('tap-preset-${preset.id}'),
                      label: preset.name,
                      selected: preset == model.preset,
                      onPressed: model.running
                          ? null
                          : () => model.selectPreset(preset),
                    ),
                ],
              ),
              const SizedBox(height: Space.lg),
              RoundSegmented<TapDifficulty>(
                key: const Key('tap-difficulty'),
                options: [for (final d in TapDifficulty.values) (d, d.label)],
                value: model.difficulty,
                onChanged: model.selectDifficulty,
              ),
              const SizedBox(height: Space.lg),
              _OffsetRow(model: model),
              const SizedBox(height: Space.xl),
              Center(child: _Pad(model: model)),
              const SizedBox(height: Space.lg),
              _Status(model: model),
              if (done) ...[
                const SizedBox(height: Space.xl),
                _Summary(score: model.score!),
              ],
              const SizedBox(height: Space.xl),
              Center(
                child: TactileChip(
                  key: const Key('tap-start'),
                  primary: true,
                  label: model.running
                      ? 'Stop'
                      : (done ? 'Try again' : 'Start'),
                  onPressed: model.phase == TapPhase.starting
                      ? null
                      : (model.running ? model.stop : model.start),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _OffsetRow extends StatelessWidget {
  const _OffsetRow({required this.model});

  final TapTrainerModel model;

  @override
  Widget build(BuildContext context) {
    final palette = groundOf(context);
    final value = model.offsetMs.value;
    final sign = value > 0 ? '+' : '';
    return Row(
      children: [
        Expanded(
          child: Semantics(
            container: true,
            label: 'Latency offset $value milliseconds',
            excludeSemantics: true,
            child: Text(
              'Latency offset: $sign$value ms\n'
              'A manual setting. Raise it if your taps land late.',
              key: const Key('tap-offset-text'),
              style: roundText(
                context,
                color: palette.muted,
                size: TypeScale.caption,
              ),
            ),
          ),
        ),
        RoundIconButton(
          key: const Key('tap-offset-down'),
          icon: Icons.remove_rounded,
          label: 'Decrease latency offset',
          onPressed: model.running ? null : () => model.setOffset(value - 10),
        ),
        const SizedBox(width: Space.sm),
        RoundIconButton(
          key: const Key('tap-offset-up'),
          icon: Icons.add_rounded,
          label: 'Increase latency offset',
          onPressed: model.running ? null : () => model.setOffset(value + 10),
        ),
      ],
    );
  }
}

/// The big round pad. It reacts to the pointer going down, not to a
/// completed tap, to add as little delay as possible.
class _Pad extends StatefulWidget {
  const _Pad({required this.model});

  final TapTrainerModel model;

  @override
  State<_Pad> createState() => _PadState();
}

class _PadState extends State<_Pad> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.model.running;
    final style = active ? SurfaceStyle.primary : SurfaceStyle.tactile;
    return Semantics(
      container: true,
      button: true,
      enabled: active,
      label: 'Tap pad',
      excludeSemantics: true,
      onTap: active ? widget.model.tap : null,
      child: Listener(
        key: const Key('tap-pad'),
        behavior: HitTestBehavior.opaque,
        onPointerDown: (_) {
          setState(() => _down = true);
          widget.model.tap();
        },
        onPointerUp: (_) => setState(() => _down = false),
        onPointerCancel: (_) => setState(() => _down = false),
        child: SizedBox.square(
          dimension: 220,
          child: RoundSurface(
            style: style,
            shape: RoundShape.circle,
            pressed: _down && active,
            child: Center(
              child: Text(
                active ? 'TAP' : 'Press Start',
                style: roundText(
                  context,
                  color: textOn(context, style),
                  size: TypeScale.title,
                  serif: true,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Status extends StatelessWidget {
  const _Status({required this.model});

  final TapTrainerModel model;

  @override
  Widget build(BuildContext context) {
    final palette = groundOf(context);
    final last = model.lastResult;
    final String text;
    switch (model.phase) {
      case TapPhase.idle:
        text = 'Listen to the click, then tap the pad.';
      case TapPhase.starting:
        text = 'Starting the sound...';
      case TapPhase.countIn:
        text = 'Count-in: listen, your taps are not scored yet.';
      case TapPhase.scoring:
        text = last == null
            ? 'Tap!'
            : last.matched
            ? tapErrorText(last.errorMs!)
            : 'Extra tap';
      case TapPhase.done:
        text = 'Finished.';
      case TapPhase.unavailable:
        text = 'Sound is not available on this device.';
    }
    return Semantics(
      liveRegion: true,
      container: true,
      child: Text(
        text,
        key: const Key('tap-status'),
        textAlign: TextAlign.center,
        style: roundText(
          context,
          color: palette.text,
          size: TypeScale.bodyLarge,
          serif: true,
        ),
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.score});

  final TapScore score;

  @override
  Widget build(BuildContext context) {
    final bias = score.meanErrorMs.round();
    final lines = <String>[
      '${score.matched} of ${score.expectedHits} hits, '
          '${score.extraTaps} extra',
      if (score.matched > 0)
        'Average error ${score.meanAbsoluteErrorMs.round()} ms'
            '${bias == 0 ? '' : ', mostly ${bias < 0 ? 'early' : 'late'}'}',
    ];
    final color = textOn(context, SurfaceStyle.glass);
    return GlassPanel(
      key: const Key('tap-summary'),
      shape: RoundShape.lens,
      padding: const EdgeInsets.all(Space.xl),
      child: Column(
        children: [
          Text(
            '${score.score}',
            key: const Key('tap-score'),
            style: roundText(
              context,
              color: color,
              size: TypeScale.display,
              serif: true,
            ),
          ),
          const SizedBox(height: Space.sm),
          for (final line in lines)
            Text(line, style: roundText(context, color: color)),
          if (score.results.isNotEmpty) ...[
            const SizedBox(height: Space.lg),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: Space.sm,
              runSpacing: Space.xs,
              children: [
                for (final r in score.results)
                  Text(
                    r.matched
                        ? '${r.errorMs! > 0 ? '+' : ''}${r.errorMs!.round()}'
                        : 'extra',
                    style: roundText(
                      context,
                      color: mutedTextOn(context, SurfaceStyle.glass),
                      size: TypeScale.caption,
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
