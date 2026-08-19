import 'package:flutter/material.dart';
import 'package:relay_app/config/relay_brand.dart';

/// Libadwaita Status Page / Empty State for GNOME.
///
/// Features a centered icon in a subtle circular container, bold title, descriptive
/// subtitle, and optional suggested action button.
class AdwStatusPage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final Widget? action;
  final double iconSize;

  const AdwStatusPage({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    this.action,
    this.iconSize = 48,
  });

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).relayPalette;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: iconSize + 32,
                height: iconSize + 32,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isDark ? const Color(0x1fffffff) : const Color(0x0f000000),
                ),
                alignment: Alignment.center,
                child: Icon(
                  icon,
                  size: iconSize,
                  color: palette.textSecondary,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                title,
                style: RelayTypography.title(palette.textPrimary, isGnome: true),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                description,
                style: RelayTypography.body(palette.textSecondary, isGnome: true),
                textAlign: TextAlign.center,
              ),
              if (action != null) ...[
                const SizedBox(height: 24),
                action!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}
