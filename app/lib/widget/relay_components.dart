import 'package:flutter/material.dart';
import 'package:relay_app/config/relay_brand.dart';

/// Foundation primitives for future Relay surfaces. They are deliberately
/// small; existing screens can adopt them incrementally without a redesign.
abstract final class RelayButtonStyles {
  static ButtonStyle primary(BuildContext context) {
    final palette = Theme.of(context).relayPalette;
    return FilledButton.styleFrom(
      minimumSize: const Size(0, RelayComponentTokens.compactControlHeight),
      backgroundColor: palette.accent.withValues(alpha: 0.2),
      foregroundColor: palette.accentSoft,
      side: BorderSide(color: palette.accentSoft.withValues(alpha: 0.45)),
      shape: const StadiumBorder(),
      elevation: 0,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
    );
  }

  static ButtonStyle secondary(BuildContext context) {
    final palette = Theme.of(context).relayPalette;
    return OutlinedButton.styleFrom(
      minimumSize: const Size(0, RelayComponentTokens.compactControlHeight),
      foregroundColor: palette.textPrimary,
      side: BorderSide(color: palette.hairline),
      shape: const StadiumBorder(),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
    );
  }

  static ButtonStyle icon(BuildContext context) {
    final palette = Theme.of(context).relayPalette;
    return IconButton.styleFrom(
      foregroundColor: palette.textSecondary,
      backgroundColor: palette.softSurface,
      shape: const CircleBorder(),
    );
  }
}

class RelayGroupedSurface extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const RelayGroupedSurface({super.key, required this.child, this.padding = const EdgeInsets.all(16)});

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).relayPalette;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(RelayComponentTokens.groupedRadius),
        border: Border.all(color: palette.hairline),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [palette.topHighlight, palette.softSurface],
        ),
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

class RelaySectionHeading extends StatelessWidget {
  final String label;

  const RelaySectionHeading(this.label, {super.key});

  @override
  Widget build(BuildContext context) => Text(label.toUpperCase(), style: RelayTypography.section(Theme.of(context).relayPalette.textSecondary));
}

class RelaySettingsRow extends StatelessWidget {
  final String label;
  final String? value;
  final Widget? trailing;

  const RelaySettingsRow({super.key, required this.label, this.value, this.trailing});

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).relayPalette;
    return Row(
      children: [
        Expanded(child: Text(label, style: RelayTypography.row(palette.textPrimary))),
        if (value != null) Text(value!, style: RelayTypography.value(palette.textSecondary)),
        if (trailing != null) ...[const SizedBox(width: 12), trailing!],
      ],
    );
  }
}
