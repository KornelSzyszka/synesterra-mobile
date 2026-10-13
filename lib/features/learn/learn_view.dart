import 'package:flutter/material.dart';

import '../../data/repositories/playback_repository.dart';
import '../../shared/theme/design_scale.dart';
import '../../shared/theme/round_shapes.dart';
import '../../shared/theme/surfaces.dart';
import '../../shared/widgets/round_components.dart';
import '../../shared/widgets/round_screen.dart';
import 'learn_lessons.dart';
import 'lesson_page.dart';

/// The Learn tab: the list of lessons. "Try it" goes to [onTryIt], which the
/// app shell supplies (it opens the Loop panel), as it does for the Library.
class LearnView extends StatelessWidget {
  const LearnView({
    super.key,
    required this.playback,
    required this.onTryIt,
    this.lessons,
  });

  final PlaybackRepository playback;
  final TryLesson onTryIt;

  /// For tests; the app uses [learnLessons].
  final List<LearnLesson>? lessons;

  @override
  Widget build(BuildContext context) {
    final items = lessons ?? learnLessons;
    return RoundScreen(
      title: 'Learn',
      child: ListView(
        key: const Key('learn-list'),
        padding: const EdgeInsets.fromLTRB(
          Space.lg,
          Space.md,
          Space.lg,
          Space.xl,
        ),
        children: [
          for (var i = 0; i < items.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.md),
              child: OrganicCard(
                key: Key('lesson-${items[i].id}'),
                // Neighbouring lessons get different edges.
                seed: 3 + i * 5,
                label:
                    'Lesson ${i + 1} of ${items.length}. ${items[i].title}. '
                    '${items[i].teaser}',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => LessonPage(
                      lesson: items[i],
                      playback: playback,
                      onTryIt: onTryIt,
                    ),
                  ),
                ),
                child: ExcludeSemantics(
                  child: Row(
                    children: [
                      SizedBox.square(
                        dimension: 52,
                        child: RoundSurface(
                          style: SurfaceStyle.glass,
                          shape: RoundShape.circle,
                          child: Center(
                            child: Text(
                              '${i + 1}',
                              style: roundText(
                                context,
                                color: textOn(context, SurfaceStyle.glass),
                                size: TypeScale.title,
                                serif: true,
                              ),
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
                              items[i].title,
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
                              items[i].teaser,
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
