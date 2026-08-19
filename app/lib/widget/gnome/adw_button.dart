import 'package:flutter/material.dart';
import 'package:relay_app/config/relay_brand.dart';

enum AdwButtonStyle {
  normal,
  suggested,
  destructive,
  flat,
}

/// Libadwaita button for GNOME.
class AdwButton extends StatelessWidget {
  final Widget? child;
  final String? label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final AdwButtonStyle style;
  final bool isPill;
  final EdgeInsetsGeometry padding;

  const AdwButton({
    super.key,
    this.child,
    this.label,
    this.icon,
    this.onPressed,
    this.style = AdwButtonStyle.normal,
    this.isPill = false,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
  });

  const AdwButton.suggested({
    super.key,
    this.child,
    this.label,
    this.icon,
    this.onPressed,
    this.isPill = false,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
  }) : style = AdwButtonStyle.suggested;

  const AdwButton.destructive({
    super.key,
    this.child,
    this.label,
    this.icon,
    this.onPressed,
    this.isPill = false,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
  }) : style = AdwButtonStyle.destructive;

  const AdwButton.flat({
    super.key,
    this.child,
    this.label,
    this.icon,
    this.onPressed,
    this.isPill = false,
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
  }) : style = AdwButtonStyle.flat;

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).relayPalette;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    Color bg;
    Color fg;
    BorderSide? border;

    switch (style) {
      case AdwButtonStyle.suggested:
        bg = palette.accent;
        fg = Colors.white;
        border = null;
        break;
      case AdwButtonStyle.destructive:
        bg = palette.error;
        fg = Colors.white;
        border = null;
        break;
      case AdwButtonStyle.flat:
        bg = Colors.transparent;
        fg = palette.textPrimary;
        border = null;
        break;
      case AdwButtonStyle.normal:
        bg = isDark ? const Color(0x1fffffff) : const Color(0x0f000000);
        fg = palette.textPrimary;
        border = BorderSide(color: isDark ? const Color(0x18ffffff) : const Color(0x12000000), width: 1);
        break;
    }

    if (onPressed == null) {
      bg = isDark ? const Color(0x0affffff) : const Color(0x08000000);
      fg = palette.textTertiary;
      border = null;
    }

    final radius = isPill ? BorderRadius.circular(20) : BorderRadius.circular(8);

    Widget content =
        child ??
        Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 16, color: fg),
              if (label != null) const SizedBox(width: 8),
            ],
            if (label != null)
              Flexible(
                child: Text(
                  label!,
                  style: RelayTypography.body(fg, isGnome: true, bold: style == AdwButtonStyle.suggested),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
        );

    return Material(
      color: bg,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: border ?? BorderSide.none,
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        borderRadius: radius,
        child: Padding(
          padding: padding,
          child: content,
        ),
      ),
    );
  }
}
