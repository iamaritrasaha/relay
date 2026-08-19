import 'package:flutter/material.dart';
import 'package:relay_app/config/relay_brand.dart';

/// Shared restrained frame for active Relay desktop dialogs.
class RelayDialog extends StatelessWidget {
  final String title;
  final String? description;
  final Widget child;
  final List<Widget> actions;
  final double maxWidth;

  const RelayDialog({
    super.key,
    required this.title,
    required this.child,
    this.description,
    this.actions = const [],
    this.maxWidth = 520,
  });

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).relayPalette;
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 28),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Material(
          color: palette.elevated,
          borderRadius: BorderRadius.circular(20),
          clipBehavior: Clip.antiAlias,
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: palette.hairline),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(26, 25, 26, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    title,
                    style: TextStyle(fontSize: 21, height: 1.2, fontWeight: FontWeight.w600, color: palette.textPrimary),
                  ),
                  if (description != null) ...[
                    const SizedBox(height: 7),
                    Text(description!, style: TextStyle(fontSize: 13.5, height: 1.45, color: palette.textSecondary)),
                  ],
                  const SizedBox(height: 22),
                  child,
                  if (actions.isNotEmpty) ...[
                    const SizedBox(height: 22),
                    Wrap(alignment: WrapAlignment.end, spacing: 8, runSpacing: 8, children: actions),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

ButtonStyle relayPrimaryButtonStyle(BuildContext context) {
  final palette = Theme.of(context).relayPalette;
  return FilledButton.styleFrom(
    backgroundColor: palette.accent,
    foregroundColor: RelayPalette.dark.canvas,
    elevation: 0,
    minimumSize: const Size(0, 42),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
  );
}

ButtonStyle relayQuietButtonStyle(BuildContext context) {
  final palette = Theme.of(context).relayPalette;
  return TextButton.styleFrom(foregroundColor: palette.textSecondary, minimumSize: const Size(0, 42));
}
