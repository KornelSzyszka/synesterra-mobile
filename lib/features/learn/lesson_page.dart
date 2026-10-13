import 'package:flutter/material.dart';

import '../../data/repositories/loop.dart';
import '../../data/repositories/playback_repository.dart';
import '../../shared/loop_view/loop_view.dart';
import '../../shared/loop_view/loop_view_state.dart';
import '../../shared/loop_view/position_source.dart';
import '../../shared/theme/design_scale.dart';
import '../../shared/widgets/round_components.dart';
import '../../shared/widgets/round_screen.dart';
import 'learn_lessons.dart';
import 'section_clock.dart';

/// Opens the Loop panel on an unsaved copy of the lesson's loop.
typedef TryLesson = void Function(Loop loop);

/// One lesson: plain text, a live picture of its loop and "Try it".
///
/// The picture runs on a [TutorialClock]: nothing is playing, so it is the one
/// place where a UI ticker drives the visualizations. Tapping the picture (or
/// "Hear it") plays the loop through the playback repository instead.
class LessonPage extends StatefulWidget {
  const LessonPage({
    super.key,
    required this.lesson,
    required this.playback,
    required this.onTryIt,
  });

  final LearnLesson lesson;
  final PlaybackRepository playback;
  final TryLesson onTryIt;

  @override
  State<LessonPage> createState() => _LessonPageState();
}

class _LessonPageState extends State<LessonPage>
    with SingleTickerProviderStateMixin {
  TutorialClock? _clock;
  SectionClock? _sections;
  LoopViewState? _picture;
  bool _started = false;
  bool _running = false;
  bool _sound = false;

  Loop? get _loop => widget.lesson.loop;

  @override
  void initState() {
    super.initState();
    final loop = _loop;
    if (loop != null) {
      _picture = LoopViewState.fromDocument(loop.document);
      // One cycle at the loop's own tempo.
      final micros =
          (loop.cycleBeats * 60 / loop.bpm * Duration.microsecondsPerSecond)
              .round();
      _clock = TutorialClock(
        vsync: this,
        cycleDuration: Duration(microseconds: micros),
      );
    } else if (widget.lesson.sections.isNotEmpty) {
      // A small arrangement: two seconds a cycle is easy to follow.
      final clock = _clock = TutorialClock(
        vsync: this,
        cycleDuration: const Duration(seconds: 2),
      );
      _sections = SectionClock(source: clock, sections: widget.lesson.sections);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reduced motion: the picture starts still; the learner can run it.
    if (!_started && !MediaQuery.disableAnimationsOf(context)) {
      _started = true;
      _run(true);
    }
  }

  @override
  void dispose() {
    if (_sound) widget.playback.stop();
    _sections?.dispose();
    _clock?.dispose();
    super.dispose();
  }

  /// Runs or stops the picture. Does not rebuild on its own while the first
  /// frame is built.
  void _run(bool run) {
    final clock = _clock;
    if (clock == null) return;
    run ? clock.start() : clock.stop();
    _running = run;
  }

  void _toggleMotion() => setState(() => _run(!_running));

  void _say(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _toggleSound() async {
    final loop = _loop;
    if (loop == null) return;
    if (_sound) {
      setState(() => _sound = false);
      await widget.playback.stop();
      return;
    }
    try {
      await widget.playback.play(loop.document);
    } on Object {
      if (mounted) _say('Sound is not available on this device.');
      return;
    }
    if (!mounted) return;
    final status = widget.playback.status.value;
    if (status.state == PlaybackState.stopped &&
        status.stopReason == PlaybackStopReason.error) {
      _say('Sound is not available on this device.');
      return;
    }
    // The picture restarts with the sound; both begin at the cycle start.
    setState(() {
      _sound = true;
      _run(true);
    });
  }

  void _tryIt() {
    if (_sound) {
      _sound = false;
      widget.playback.stop();
    }
    widget.onTryIt(_loop!);
  }

  @override
  Widget build(BuildContext context) {
    final lesson = widget.lesson;
    final palette = groundOf(context);
    final clock = _clock;
    return RoundScreen(
      child: ListView(
        key: const Key('lesson-body'),
        padding: const EdgeInsets.fromLTRB(
          Space.xl,
          Space.md,
          Space.xl,
          Space.xl,
        ),
        children: [
          Semantics(
            header: true,
            child: Text(
              lesson.title,
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
            lesson.text,
            key: const Key('lesson-text'),
            style: roundText(
              context,
              color: palette.text,
              size: TypeScale.bodyLarge,
            ).copyWith(height: 1.45),
          ),
          for (final term in lesson.terms) ...[
            const SizedBox(height: Space.md),
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '${term.term}: ',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  TextSpan(text: term.meaning),
                ],
              ),
              style: roundText(context, color: palette.muted),
            ),
          ],
          if (clock != null) ...[
            const SizedBox(height: Space.xl),
            GestureDetector(
              key: const Key('lesson-picture'),
              excludeFromSemantics: true,
              onTap: _toggleSound,
              child: _picture == null
                  ? ArrangementStrip(
                      sections: lesson.sections,
                      source: _sections!,
                    )
                  : LoopView(
                      state: _picture!,
                      source: clock,
                      initialMode: lesson.viewMode,
                    ),
            ),
            const SizedBox(height: Space.lg),
            Wrap(
              spacing: Space.md,
              runSpacing: Space.sm,
              children: [
                if (_loop != null)
                  TactileChip(
                    key: const Key('lesson-hear'),
                    selected: _sound,
                    onPressed: _toggleSound,
                    label: _sound ? 'Stop sound' : 'Hear it',
                  ),
                TactileChip(
                  key: const Key('lesson-motion'),
                  selected: _running,
                  onPressed: _toggleMotion,
                  label: _running ? 'Pause picture' : 'Run picture',
                ),
              ],
            ),
            const SizedBox(height: Space.xl),
            if (_loop != null)
              Align(
                alignment: Alignment.centerLeft,
                child: TactileChip(
                  key: const Key('lesson-try-it'),
                  label: 'Try it',
                  primary: true,
                  onPressed: _tryIt,
                ),
              ),
          ],
        ],
      ),
    );
  }
}
