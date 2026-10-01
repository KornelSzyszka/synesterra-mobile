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
      style: TextStyle(color: color, fontFamily: 'monospace', fontSize: 11),
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
  });
  final int value;
  final int min;
  final int max;
  final ValueChanged<int>? onChanged;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final tokens = SynesterraTokens.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _button(
          Icons.remove,
          'Decrease $label',
          value > min ? () => onChanged?.call(value - 1) : null,
          tokens,
        ),
        SizedBox(
          width: 82,
          child: Column(
            children: [
              Text(
                '$value',
                style: TextStyle(
                  color: color,
                  fontFamily: 'serif',
                  fontSize: 36,
                  height: 1,
                ),
              ),
              Text(
                label,
                maxLines: 1,
                style: TextStyle(
                  color: tokens.muted,
                  fontFamily: 'monospace',
                  fontSize: 9,
                ),
              ),
            ],
          ),
        ),
        _button(
          Icons.add,
          'Increase $label',
          value < max ? () => onChanged?.call(value + 1) : null,
          tokens,
        ),
      ],
    );
  }

  Widget _button(
    IconData icon,
    String tooltip,
    VoidCallback? callback,
    SynesterraTokens tokens,
  ) => IconButton(
    tooltip: tooltip,
    constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
    icon: Icon(icon, size: 18),
    color: tokens.text,
    disabledColor: tokens.muted,
    onPressed: onChanged == null ? null : callback,
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
