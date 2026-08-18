import 'package:flutter/material.dart';
import 'package:localsend_app/config/relay_brand.dart';

/// Libadwaita-styled Action Row for GNOME.
class AdwActionRow extends StatelessWidget {
  final Widget? leading;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool isDestructive;
  final EdgeInsetsGeometry padding;

  const AdwActionRow({
    super.key,
    this.leading,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.isDestructive = false,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
  });

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).relayPalette;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final titleColor = isDestructive ? palette.error : palette.textPrimary;
    final subtitleColor = palette.textSecondary;

    Widget content = Padding(
      padding: padding,
      child: Row(
        children: [
          if (leading != null) ...[
            IconTheme(
              data: IconThemeData(
                size: 20,
                color: isDestructive ? palette.error : palette.textSecondary,
              ),
              child: leading!,
            ),
            const SizedBox(width: 14),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: RelayTypography.body(titleColor, isGnome: true, bold: true),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: RelayTypography.caption(subtitleColor, isGnome: true),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 12),
            trailing!,
          ],
        ],
      ),
    );

    if (onTap != null) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          hoverColor: isDark ? const Color(0x12ffffff) : const Color(0x0a000000),
          highlightColor: isDark ? const Color(0x1fffffff) : const Color(0x14000000),
          child: content,
        ),
      );
    }

    return content;
  }
}

/// Libadwaita Navigation Row that displays a chevron and navigates on tap.
class AdwNavigationRow extends StatelessWidget {
  final Widget? leading;
  final String title;
  final String? subtitle;
  final String? valueText;
  final VoidCallback onTap;

  const AdwNavigationRow({
    super.key,
    this.leading,
    required this.title,
    this.subtitle,
    this.valueText,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).relayPalette;

    return AdwActionRow(
      leading: leading,
      title: title,
      subtitle: subtitle,
      onTap: onTap,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (valueText != null) ...[
            Text(
              valueText!,
              style: RelayTypography.body(palette.textSecondary, isGnome: true),
            ),
            const SizedBox(width: 8),
          ],
          Icon(
            Icons.chevron_right_rounded,
            size: 18,
            color: palette.textTertiary,
          ),
        ],
      ),
    );
  }
}

/// Libadwaita Switch Row with an active switch toggle.
class AdwSwitchRow extends StatelessWidget {
  final Widget? leading;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  const AdwSwitchRow({
    super.key,
    this.leading,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).relayPalette;

    return AdwActionRow(
      leading: leading,
      title: title,
      subtitle: subtitle,
      onTap: onChanged == null ? null : () => onChanged!(!value),
      trailing: Transform.scale(
        scale: 0.85,
        alignment: Alignment.centerRight,
        child: Switch(
          value: value,
          onChanged: onChanged,
          activeTrackColor: palette.accent,
        ),
      ),
    );
  }
}
