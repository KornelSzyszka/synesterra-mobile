import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'living_motion.dart';

/// Living (true, the production default) or flat blobs. Only the debug
/// design lab flips it, to compare both on the phone.
final livingBlobsEnabled = ValueNotifier<bool>(true);

/// At most this many blobs of one field animate at the same time.
const maxAnimatedBlobs = 6;

/// A tick later than this after the previous one ends a pause.
const _resumeGap = Duration(milliseconds: 250);

/// The motion step taken for the first tick after a pause.
const _frame = Duration(milliseconds: 16);

/// The shared clock of a [LivingField]: one ticker for every blob in it.
/// Blobs listen to it only while they animate.
class LivingClock extends ChangeNotifier {
  /// Seconds of motion so far; it does not advance while the field pauses,
  /// so a paused blob resumes without a jump.
  double get time => _time;
  double _time = 0;

  /// Seconds since the previous tick (0 on the first tick after a pause).
  double get dt => _dt;
  double _dt = 0;

  /// 0..1: how much the blobs move ([lifeAmount] of the last wake).
  double get life => _life;
  double _life = 1;

  /// Time since the field first ticked: drives the staggered entrance.
  Duration get sinceOpen => _sinceOpen;
  Duration _sinceOpen = Duration.zero;

  void _advance(Duration motion, Duration wall, double life) {
    _dt = motion.inMicroseconds / Duration.microsecondsPerSecond;
    _time += _dt;
    _sinceOpen += wall;
    _life = life;
    notifyListeners();
  }
}

/// One blob in a field (implemented by the living surface).
abstract interface class LivingMember {
  /// Where the blob is, in the coordinates of [field]; null when it is not
  /// laid out.
  Rect? rectIn(RenderBox field);

  /// Whether the blob holds one of the field's animation slots.
  set animated(bool value);

  /// True while the blob needs ticks for something besides its slot (a
  /// spring still moving, the entrance still running).
  bool get busy;

  /// Its place in the staggered entrance, given when it joins.
  set entranceIndex(int? value);

  /// Ends the entrance at once: a blob without a slot (offscreen, or beyond
  /// the cap) shows its full card and never ticks for the entrance.
  void finishEntrance();
}

/// Runs the living blobs below it (library cards): one ticker for all of
/// them, the cap on how many animate ([cap], the visible ones first), the
/// staggered entrance when it opens, and the pauses.
///
/// The blobs move fully for [LivingTiming.awake] after the field appears,
/// a touch or a scroll, then settle to their still shape and the ticker
/// stops: a gallery at rest schedules no frames. It also stops while its
/// route is covered (the ticker is muted by `TickerMode`), while the app is
/// not in the foreground, under reduce motion (the blobs keep their static
/// depth) and when [livingBlobsEnabled] is false (the blobs are flat).
class LivingField extends StatefulWidget {
  const LivingField({
    super.key,
    required this.child,
    this.cap = maxAnimatedBlobs,
    this.keepAwake = false,
  });

  final Widget child;

  /// How many blobs may animate at once.
  final int cap;

  /// Never settle (the design lab, to read the frame time of the motion).
  final bool keepAwake;

  /// The field around [context] that blobs join, or null.
  static LivingFieldState? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_LivingFieldScope>()?.state;

  @override
  State<LivingField> createState() => LivingFieldState();
}

class LivingFieldState extends State<LivingField>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final Ticker _ticker = createTicker(_onTick);
  final LivingClock clock = LivingClock();

  final Set<LivingMember> _members = {};
  Set<LivingMember> _animated = {};
  int _joined = 0;

  Duration _lastElapsed = Duration.zero;
  Duration _sinceWake = Duration.zero;
  bool _foreground = true;
  bool _reduceMotion = false;
  bool _visibilityScheduled = false;

  /// True when the blobs show motion at all (living, motion allowed).
  bool get moving => livingBlobsEnabled.value && !_reduceMotion;

  /// True while the blobs are living (not the flat comparison).
  bool get living => livingBlobsEnabled.value;

  /// Tests: whether the shared ticker is running and not muted.
  @visibleForTesting
  bool get isTicking => _ticker.isTicking;

  /// Tests: the blobs that hold an animation slot.
  @visibleForTesting
  Set<LivingMember> get animatedMembers => Set.unmodifiable(_animated);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    livingBlobsEnabled.addListener(_onEnabled);
    final state = WidgetsBinding.instance.lifecycleState;
    _foreground = state == null || state == AppLifecycleState.resumed;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (moving) {
      wake();
    } else {
      _stop();
    }
  }

  @override
  void didUpdateWidget(LivingField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cap != widget.cap) _scheduleVisibility();
    if (oldWidget.keepAwake != widget.keepAwake) wake();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    livingBlobsEnabled.removeListener(_onEnabled);
    _ticker.dispose();
    clock.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) {
      wake();
    } else {
      _stop();
    }
  }

  void _onEnabled() {
    if (!mounted) return;
    setState(() {});
    if (moving) {
      wake();
    } else {
      _stop();
    }
  }

  /// Full motion again for [LivingTiming.awake] (a touch, a scroll).
  void wake() {
    _sinceWake = Duration.zero;
    if (!moving || !_foreground || _ticker.isActive) return;
    _lastElapsed = Duration.zero;
    _ticker.start();
  }

  void _stop() {
    if (_ticker.isActive) _ticker.stop();
  }

  void _onTick(Duration elapsed) {
    final step = elapsed - _lastElapsed;
    _lastElapsed = elapsed;
    // A muted ticker (the route was covered) keeps its start time, so the
    // first tick after it comes back spans the whole pause: the gallery
    // wakes again and its motion goes on from where it paused.
    final resumed = step > _resumeGap;
    if (resumed) _sinceWake = Duration.zero;
    _sinceWake += resumed ? Duration.zero : step;
    final life = widget.keepAwake ? 1.0 : lifeAmount(_sinceWake);
    clock._advance(resumed ? _frame : step, step, life);
    if (life == 0 && !_members.any((m) => m.busy)) _stop();
  }

  /// Adds a blob; it gets an entrance place while the field is opening.
  void join(LivingMember member) {
    if (!_members.add(member)) return;
    final opening =
        moving &&
        clock.sinceOpen <
            LivingTiming.stagger * LivingTiming.maxStaggered +
                LivingTiming.entrance;
    member.entranceIndex = opening ? _joined++ : null;
    _scheduleVisibility();
  }

  void leave(LivingMember member) {
    _members.remove(member);
    _animated.remove(member);
    _scheduleVisibility();
  }

  /// Decides after the frame which blobs animate: the visible ones, at most
  /// [LivingField.cap].
  void _scheduleVisibility() {
    if (_visibilityScheduled) return;
    _visibilityScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _visibilityScheduled = false;
      if (mounted) _updateVisibility();
    });
    SchedulerBinding.instance.ensureVisualUpdate();
  }

  void _updateVisibility() {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    final rects = <LivingMember, Rect>{};
    for (final member in _members) {
      final rect = member.rectIn(box);
      if (rect != null) rects[member] = rect;
    }
    final chosen = chooseAnimated(
      rects,
      Offset.zero & box.size,
      cap: widget.cap,
    );
    for (final member in _members) {
      final slot = chosen.contains(member);
      if (!slot) member.finishEntrance();
      member.animated = slot;
    }
    _animated = chosen;
  }

  bool _onScroll(ScrollNotification notification) {
    _scheduleVisibility();
    if (notification is ScrollStartNotification ||
        notification is ScrollUpdateNotification &&
            notification.dragDetails != null) {
      wake();
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return _LivingFieldScope(
      state: this,
      living: living,
      moving: moving,
      child: NotificationListener<ScrollNotification>(
        onNotification: _onScroll,
        child: NotificationListener<SizeChangedLayoutNotification>(
          onNotification: (_) {
            _scheduleVisibility();
            return false;
          },
          child: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (_) => wake(),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

class _LivingFieldScope extends InheritedWidget {
  const _LivingFieldScope({
    required this.state,
    required this.living,
    required this.moving,
    required super.child,
  });

  final LivingFieldState state;
  final bool living;
  final bool moving;

  @override
  bool updateShouldNotify(_LivingFieldScope old) =>
      old.state != state || old.living != living || old.moving != moving;
}
