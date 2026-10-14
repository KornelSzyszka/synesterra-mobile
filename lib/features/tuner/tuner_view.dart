import 'package:flutter/material.dart';
import 'package:synesterra_core/synesterra_core.dart';

import '../../data/repositories/microphone_repository.dart';
import '../../data/repositories/playback_repository.dart';
import '../../shared/theme/design_scale.dart';
import '../../shared/widgets/round_components.dart';
import '../../shared/widgets/round_screen.dart';
import 'tuner_dial.dart';
import 'tuner_model.dart';

/// "+3 cents", "-12 cents", "In tune".
String centsText(double cents) {
  if (cents.abs() <= inTuneCents) return 'In tune';
  final rounded = cents.round();
  return '${rounded > 0 ? '+' : ''}$rounded cents';
}

/// The Tuner: listens to the microphone and shows the note and how far it is
/// from being in tune. Starts listening when opened; stops when closed or
/// when the app leaves the foreground.
class TunerView extends StatefulWidget {
  const TunerView({
    super.key,
    required this.microphone,
    required this.playback,
    this.model,
  });

  final MicrophoneRepository microphone;
  final PlaybackRepository playback;

  /// For tests; the view owns and disposes its own model otherwise.
  final TunerModel? model;

  @override
  State<TunerView> createState() => _TunerViewState();
}

class _TunerViewState extends State<TunerView> with WidgetsBindingObserver {
  late final TunerModel _model =
      widget.model ??
      TunerModel(microphone: widget.microphone, playback: widget.playback);
  bool _resume = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _model.start();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_resume) _model.start();
      _resume = false;
    } else if (_model.listening) {
      _resume = true;
      _model.stop();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _model.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RoundScreen(
      title: 'Tuner',
      child: ListenableBuilder(
        listenable: _model,
        builder: (context, _) => LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            key: const Key('tuner-body'),
            padding: const EdgeInsets.fromLTRB(
              Space.lg,
              Space.md,
              Space.lg,
              Space.xl,
            ),
            child: Column(
              children: [
                _Dial(
                  model: _model,
                  maxSide: constraints.maxWidth - 2 * Space.lg,
                ),
                const SizedBox(height: Space.lg),
                _Message(model: _model),
                const SizedBox(height: Space.lg),
                _Controls(model: _model),
                const SizedBox(height: Space.xl),
                _ReferenceRow(model: _model),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Dial extends StatelessWidget {
  const _Dial({required this.model, required this.maxSide});

  final TunerModel model;
  final double maxSide;

  @override
  Widget build(BuildContext context) {
    final palette = groundOf(context);
    final note = model.note;
    final inTune = note != null && note.inTune(inTuneCents);
    final reduce = MediaQuery.disableAnimationsOf(context);
    final side = maxSide.clamp(200.0, 320.0);
    final big = note?.label ?? '--';
    final detail = note == null
        ? (model.listening ? 'Play a note' : ' ')
        : centsText(note.cents);
    final label = note == null
        ? 'Tuner. ${model.listening ? 'Listening, no note heard.' : 'Not listening.'}'
        : 'Tuner. ${note.label}, ${centsText(note.cents)}';
    return Semantics(
      container: true,
      liveRegion: true,
      label: label,
      child: ExcludeSemantics(
        child: Center(
          child: SizedBox.square(
            dimension: side,
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: note?.cents ?? 0),
              duration: reduce
                  ? Duration.zero
                  : const Duration(milliseconds: 120),
              builder: (context, cents, _) => TweenAnimationBuilder<double>(
                tween: Tween(end: inTune ? 1.0 : 0.0),
                duration: reduce
                    ? Duration.zero
                    : const Duration(milliseconds: 260),
                builder: (context, glow, _) => CustomPaint(
                  key: const Key('tuner-dial'),
                  painter: TunerDialPainter(
                    palette: palette,
                    cents: note == null ? null : cents,
                    glow: glow,
                  ),
                  child: Center(
                    child: Padding(
                      padding: EdgeInsets.all(side * .2),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              big,
                              key: const Key('tuner-note'),
                              style: roundText(
                                context,
                                color: inTune
                                    ? palette.accentText
                                    : palette.text,
                                size: TypeScale.display * 1.5,
                                serif: true,
                                weight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              detail,
                              key: const Key('tuner-cents'),
                              style: roundText(
                                context,
                                color: palette.muted,
                                size: TypeScale.bodyLarge,
                              ),
                            ),
                            if (note != null)
                              Text(
                                '${note.frequencyHz.toStringAsFixed(1)} Hz',
                                key: const Key('tuner-hz'),
                                style: roundText(
                                  context,
                                  color: palette.muted,
                                  size: TypeScale.caption,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.model});

  final TunerModel model;

  @override
  Widget build(BuildContext context) {
    final palette = groundOf(context);
    final text = switch (model.phase) {
      TunerPhase.denied =>
        'Microphone access is off. The tuner needs it to hear your '
            'instrument. Allow it when asked, or in the system settings for '
            'Synesterra, then try again.',
      TunerPhase.failed =>
        'The microphone could not be opened. Close other apps that use it '
            'and try again.',
      TunerPhase.starting => 'Opening the microphone...',
      TunerPhase.listening => 'Play one note at a time.',
      TunerPhase.idle =>
        model.toneOn
            ? 'Reference tone: A4 = 440 Hz.'
            : 'Press the microphone to listen.',
    };
    return Text(
      text,
      key: const Key('tuner-message'),
      textAlign: TextAlign.center,
      style: roundText(context, color: palette.muted),
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({required this.model});

  final TunerModel model;

  @override
  Widget build(BuildContext context) {
    final busy = model.phase == TunerPhase.starting;
    final denied = model.phase == TunerPhase.denied;
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: Space.lg,
      runSpacing: Space.md,
      children: [
        RoundActionButton(
          key: const Key('tuner-listen'),
          icon: model.listening ? Icons.stop_rounded : Icons.mic_rounded,
          label: model.listening
              ? 'Stop listening'
              : (denied ? 'Try again' : 'Start listening'),
          onPressed: busy ? null : (model.listening ? model.stop : model.start),
        ),
        if (model.toneAvailable)
          TactileChip(
            key: const Key('tuner-tone'),
            label: model.toneOn ? 'Stop tone' : 'Play A4',
            selected: model.toneOn,
            onPressed: busy ? null : model.toggleTone,
          ),
      ],
    );
  }
}

class _ReferenceRow extends StatelessWidget {
  const _ReferenceRow({required this.model});

  final TunerModel model;

  @override
  Widget build(BuildContext context) {
    final palette = groundOf(context);
    final hz = model.referenceA4;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        RoundIconButton(
          key: const Key('tuner-ref-down'),
          icon: Icons.remove_rounded,
          label: 'Lower reference pitch',
          onPressed: hz > minReferenceA4
              ? () => model.setReference(hz - 1)
              : null,
        ),
        Flexible(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.lg),
            child: Semantics(
              label: 'Reference pitch, A4 equals ${hz.round()} hertz',
              child: ExcludeSemantics(
                child: Text(
                  'A4 = ${hz.round()} Hz',
                  key: const Key('tuner-ref'),
                  textAlign: TextAlign.center,
                  style: roundText(
                    context,
                    color: palette.text,
                    size: TypeScale.bodyLarge,
                    weight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ),
        ),
        RoundIconButton(
          key: const Key('tuner-ref-up'),
          icon: Icons.add_rounded,
          label: 'Raise reference pitch',
          onPressed: hz < maxReferenceA4
              ? () => model.setReference(hz + 1)
              : null,
        ),
      ],
    );
  }
}
