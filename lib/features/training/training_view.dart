import 'package:flutter/material.dart';

import '../../data/repositories/playback_repository.dart';
import '../../shared/theme/design_scale.dart';
import '../../shared/theme/round_shapes.dart';
import '../../shared/theme/surfaces.dart';
import '../../shared/widgets/round_components.dart';
import '../../shared/widgets/round_screen.dart';
import 'tap_trainer_view.dart';

/// The Training tab: one round card per exercise.
class TrainingView extends StatefulWidget {
  const TrainingView({super.key, required this.playback});

  final PlaybackRepository playback;

  @override
  State<TrainingView> createState() => _TrainingViewState();
}

class _TrainingViewState extends State<TrainingView> {
  /// The latency offset of the tap trainer, kept while this tab is open.
  final _tapOffset = ValueNotifier<int>(0);

  @override
  void dispose() {
    _tapOffset.dispose();
    super.dispose();
  }

  void _open(Widget page) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));

  @override
  Widget build(BuildContext context) {
    final sections = <_Section>[
      _Section(
        id: 'tap',
        title: 'Tap in rhythm',
        teaser: 'Tap along with a click and see how early or late you are.',
        icon: Icons.touch_app_rounded,
        onTap: () => _open(
          TapTrainerView(playback: widget.playback, offset: _tapOffset),
        ),
      ),
    ];
    return RoundScreen(
      title: 'Training',
      child: ListView(
        key: const Key('training-list'),
        padding: const EdgeInsets.fromLTRB(
          Space.lg,
          Space.md,
          Space.lg,
          Space.xl,
        ),
        children: [
          for (var i = 0; i < sections.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.md),
              child: OrganicCard(
                key: Key('training-${sections[i].id}'),
                seed: 3 + i * 5,
                label: '${sections[i].title}. ${sections[i].teaser}',
                onTap: sections[i].onTap,
                child: ExcludeSemantics(
                  child: Row(
                    children: [
                      SizedBox.square(
                        dimension: 52,
                        child: RoundSurface(
                          style: SurfaceStyle.glass,
                          shape: RoundShape.circle,
                          child: Center(
                            child: Icon(
                              sections[i].icon,
                              color: textOn(context, SurfaceStyle.glass),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: Space.lg),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              sections[i].title,
                              style: roundText(
                                context,
                                color: textOn(context, SurfaceStyle.organic),
                                size: TypeScale.bodyLarge,
                                serif: true,
                                weight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: Space.xs),
                            Text(
                              sections[i].teaser,
                              style: roundText(
                                context,
                                color: mutedTextOn(
                                  context,
                                  SurfaceStyle.organic,
                                ),
                                size: TypeScale.caption,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Section {
  const _Section({
    required this.id,
    required this.title,
    required this.teaser,
    required this.icon,
    required this.onTap,
  });

  final String id;
  final String title;
  final String teaser;
  final IconData icon;
  final VoidCallback onTap;
}
