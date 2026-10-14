import 'package:flutter/material.dart';
import 'package:synesterra_core/synesterra_core.dart';

import '../../data/repositories/playback_repository.dart';
import '../../shared/theme/design_scale.dart';
import '../../shared/theme/round_shapes.dart';
import '../../shared/theme/surfaces.dart';
import '../../shared/widgets/round_components.dart';
import '../../shared/widgets/round_screen.dart';
import 'ear_trainer_model.dart';

/// Ear training for one [EarMode]: the app plays a note, a chord or a
/// progression; the user picks one of four answers.
class EarTrainerView extends StatefulWidget {
  const EarTrainerView({
    super.key,
    required this.playback,
    required this.mode,
    required this.score,
    required this.seed,
  });

  final PlaybackRepository playback;
  final EarMode mode;
  final ValueNotifier<EarScore> score;
  final int seed;

  @override
  State<EarTrainerView> createState() => _EarTrainerViewState();
}

class _EarTrainerViewState extends State<EarTrainerView> {
  late final EarTrainerModel _model = EarTrainerModel(
    playback: widget.playback,
    mode: widget.mode,
    seed: widget.seed,
    score: widget.score,
  );

  @override
  void initState() {
    super.initState();
    // The first question sounds when the screen opens.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _model.play();
    });
  }

  @override
  void dispose() {
    _model.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = groundOf(context);
    return RoundScreen(
      title: '${widget.mode.label} training',
      child: ListenableBuilder(
        listenable: Listenable.merge([_model, widget.score]),
        builder: (context, _) {
          final model = _model;
          final question = model.question;
          final score = widget.score.value;
          return ListView(
            key: const Key('ear-body'),
            padding: const EdgeInsets.fromLTRB(
              Space.lg,
              Space.md,
              Space.lg,
              Space.xl,
            ),
            children: [
              Semantics(
                header: true,
                child: Text(
                  question.prompt,
                  key: const Key('ear-prompt'),
                  style: roundText(
                    context,
                    color: palette.text,
                    size: TypeScale.headline,
                    serif: true,
                  ),
                ),
              ),
              const SizedBox(height: Space.lg),
              Text(
                'Streak ${score.streak}   Best ${score.bestStreak}   '
                '${score.correct} of ${score.answered} right',
                key: const Key('ear-score'),
                style: roundText(context, color: palette.muted),
              ),
              const SizedBox(height: Space.xl),
              Center(
                child: RoundActionButton(
                  key: const Key('ear-replay'),
                  icon: Icons.replay_rounded,
                  label: 'Play again',
                  size: 84,
                  onPressed: model.play,
                ),
              ),
              if (model.unavailable) ...[
                const SizedBox(height: Space.md),
                Text(
                  'Sound is not available on this device.',
                  key: const Key('ear-unavailable'),
                  textAlign: TextAlign.center,
                  style: roundText(context, color: palette.muted),
                ),
              ],
              const SizedBox(height: Space.xl),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: Space.md,
                runSpacing: Space.md,
                children: [
                  for (var i = 0; i < question.options.length; i++)
                    TactileChip(
                      key: Key('ear-option-${question.options[i].id}'),
                      label: question.options[i].label,
                      primary: model.answered && i == question.correctIndex,
                      selected: model.answered && i == model.chosen,
                      onPressed: model.answered ? null : () => model.answer(i),
                    ),
                ],
              ),
              const SizedBox(height: Space.xl),
              if (model.answered) ...[
                _Verdict(model: model),
                const SizedBox(height: Space.lg),
                Center(
                  child: TactileChip(
                    key: const Key('ear-next'),
                    primary: true,
                    label: 'Next',
                    onPressed: model.next,
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _Verdict extends StatelessWidget {
  const _Verdict({required this.model});

  final EarTrainerModel model;

  @override
  Widget build(BuildContext context) {
    final color = textOn(context, SurfaceStyle.glass);
    return Semantics(
      liveRegion: true,
      container: true,
      child: GlassPanel(
        key: const Key('ear-verdict'),
        shape: RoundShape.lens,
        padding: const EdgeInsets.all(Space.lg),
        child: Center(
          child: Text(
            model.right
                ? 'Right! It was ${model.question.correct.label}.'
                : 'Not quite. It was ${model.question.correct.label}.',
            textAlign: TextAlign.center,
            style: roundText(
              context,
              color: color,
              size: TypeScale.bodyLarge,
              serif: true,
            ),
          ),
        ),
      ),
    );
  }
}
