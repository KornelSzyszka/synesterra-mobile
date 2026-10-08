import 'package:flutter/material.dart';

import '../../data/repositories/playback_repository.dart';
import '../../shared/theme/design_scale.dart';
import '../../shared/theme/synesterra_theme.dart';
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
    final tokens = SynesterraTokens.of(context);
    final items = lessons ?? learnLessons;
    return Scaffold(
      appBar: AppBar(title: const Text('Learn')),
      body: ListView(
        key: const Key('learn-list'),
        padding: const EdgeInsets.all(Space.lg),
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const SizedBox(height: Space.md),
            Semantics(
              button: true,
              label:
                  'Lesson ${i + 1} of ${items.length}. ${items[i].title}. '
                  '${items[i].teaser}',
              excludeSemantics: true,
              child: Material(
                color: tokens.surface,
                shape: RoundedRectangleBorder(
                  side: BorderSide(color: tokens.border),
                  borderRadius: BorderRadius.circular(Radii.sm),
                ),
                child: InkWell(
                  key: Key('lesson-${items[i].id}'),
                  borderRadius: BorderRadius.circular(Radii.sm),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => LessonPage(
                        lesson: items[i],
                        playback: playback,
                        onTryIt: onTryIt,
                      ),
                    ),
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 72),
                    child: Padding(
                      padding: const EdgeInsets.all(Space.lg),
                      child: Row(
                        children: [
                          Text(
                            '${i + 1}',
                            style: TextStyle(
                              color: tokens.accent,
                              fontSize: TypeScale.title,
                            ),
                          ),
                          const SizedBox(width: Space.lg),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  items[i].title,
                                  style: TextStyle(
                                    color: tokens.text,
                                    fontSize: TypeScale.bodyLarge,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: Space.xs),
                                Text(
                                  items[i].teaser,
                                  style: TextStyle(color: tokens.muted),
                                ),
                              ],
                            ),
                          ),
                          Icon(Icons.chevron_right, color: tokens.muted),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
