import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/synesterra_theme.dart';

class DesignPanel extends StatelessWidget {
  const DesignPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final tokens = SynesterraTokens.of(context);
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: tokens.surface,
        border: Border.all(color: tokens.border),
        borderRadius: BorderRadius.circular(7),
      ),
      child: child,
    );
  }
}

class SectionLabel extends StatelessWidget {
  const SectionLabel(this.label, {super.key});
  final String label;

  @override
  Widget build(BuildContext context) => Text(
    label.toUpperCase(),
    style: TextStyle(
      color: SynesterraTokens.of(context).muted,
      fontSize: 10,
      fontWeight: FontWeight.w600,
      letterSpacing: 1.7,
    ),
  );
}

class LayerChip extends StatelessWidget {
  const LayerChip({super.key, required this.number, required this.color});
  final int number;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .12),
      border: Border.all(color: color.withValues(alpha: .32)),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text(
      number.toString().padLeft(2, '0'),
      style: TextStyle(
        color: color,
        fontFamily: SynesterraFonts.monospace(Theme.of(context).platform),
        fontFamilyFallback: SynesterraFonts.monospaceFallback(
          Theme.of(context).platform,
        ),
        fontSize: 11,
      ),
    ),
  );
}

class NumberStepper extends StatelessWidget {
  const NumberStepper({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    required this.label,
    required this.color,
    this.repeatOnHold = false,
  });
  final int value;
  final int min;
  final int max;
  final ValueChanged<int>? onChanged;
  final String label;
  final Color color;
  final bool repeatOnHold;

  @override
  Widget build(BuildContext context) {
    final tokens = SynesterraTokens.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _StepperButton(
          icon: Icons.remove,
          tooltip: 'Decrease $label',
          onPressed: onChanged != null && value > min
              ? () => onChanged!(value - 1)
              : null,
          repeatOnHold: repeatOnHold,
          tokens: tokens,
        ),
        SizedBox(
          width: 82,
          child: Column(
            children: [
              Text(
                '$value',
                style: TextStyle(
                  color: color,
                  fontFamily: SynesterraFonts.serif(Theme.of(context).platform),
                  fontFamilyFallback: SynesterraFonts.serifFallback(
                    Theme.of(context).platform,
                  ),
                  fontSize: 36,
                  height: 1,
                ),
              ),
              Text(
                label,
                maxLines: 1,
                style: TextStyle(
                  color: tokens.muted,
                  fontFamily: SynesterraFonts.monospace(
                    Theme.of(context).platform,
                  ),
                  fontFamilyFallback: SynesterraFonts.monospaceFallback(
                    Theme.of(context).platform,
                  ),
                  fontSize: 9,
                ),
              ),
            ],
          ),
        ),
        _StepperButton(
          icon: Icons.add,
          tooltip: 'Increase $label',
          onPressed: onChanged != null && value < max
              ? () => onChanged!(value + 1)
              : null,
          repeatOnHold: repeatOnHold,
          tokens: tokens,
        ),
      ],
    );
  }
}

class _StepperButton extends StatefulWidget {
  const _StepperButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    required this.repeatOnHold,
    required this.tokens,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool repeatOnHold;
  final SynesterraTokens tokens;

  @override
  State<_StepperButton> createState() => _StepperButtonState();
}

class _StepperButtonState extends State<_StepperButton> {
  Timer? _timer;
  int _repeatCount = 0;

  void _stop() {
    _timer?.cancel();
    _timer = null;
    _repeatCount = 0;
  }

  void _repeat() {
    if (widget.onPressed == null) {
      _stop();
      return;
    }
    widget.onPressed!();
    _repeatCount++;
    // A long press begins after Flutter's gesture timeout. Then a user can
    // cross the full BPM range quickly without making short taps jump values.
    final interval = _repeatCount < 10 ? 140 : (_repeatCount < 25 ? 90 : 50);
    _timer = Timer(Duration(milliseconds: interval), _repeat);
  }

  @override
  void didUpdateWidget(covariant _StepperButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.onPressed == null || !widget.repeatOnHold) _stop();
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Tooltip(
    message: widget.tooltip,
    child: Semantics(
      label: widget.tooltip,
      button: true,
      enabled: widget.onPressed != null,
      onTap: widget.onPressed,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        excludeFromSemantics: true,
        onTap: widget.onPressed,
        onLongPressStart: widget.repeatOnHold && widget.onPressed != null
            ? (_) => _repeat()
            : null,
        onLongPressEnd: widget.repeatOnHold ? (_) => _stop() : null,
        onLongPressCancel: widget.repeatOnHold ? _stop : null,
        child: SizedBox.square(
          dimension: 48,
          child: Icon(
            widget.icon,
            size: 18,
            color: widget.onPressed == null
                ? widget.tokens.muted
                : widget.tokens.text,
          ),
        ),
      ),
    ),
  );
}

class LayerToggle extends StatelessWidget {
  const LayerToggle({
    super.key,
    required this.value,
    required this.color,
    required this.onChanged,
  });
  final bool value;
  final Color color;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = SynesterraTokens.of(context);
    return Switch(
      value: value,
      onChanged: onChanged,
      activeThumbColor: tokens.background,
      activeTrackColor: color,
      inactiveThumbColor: tokens.muted,
      inactiveTrackColor: tokens.controlBackground,
      trackOutlineColor: WidgetStatePropertyAll(tokens.border),
      materialTapTargetSize: MaterialTapTargetSize.padded,
    );
  }
}

class GoldPrimaryButton extends StatelessWidget {
  const GoldPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
  });
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final tokens = SynesterraTokens.of(context);
    return FilledButton(
      style: FilledButton.styleFrom(
        backgroundColor: tokens.accent,
        foregroundColor: tokens.onAccent,
        minimumSize: const Size(116, 48),
      ),
      onPressed: onPressed,
      child: Text(label),
    );
  }
}
