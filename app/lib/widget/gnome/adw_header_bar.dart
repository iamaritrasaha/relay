import 'package:flutter/material.dart';
import 'package:localsend_app/config/relay_brand.dart';

/// Libadwaita-styled HeaderBar for GNOME desktop.
///
/// Features standard Adwaita height (48px), clean title/subtitle centering,
/// flat icon actions with hover and focus states, and seamless window integration.
class AdwHeaderBar extends StatelessWidget implements PreferredSizeWidget {
  final Widget? title;
  final String? titleText;
  final String? subtitleText;
  final Widget? leading;
  final List<Widget>? actions;
  final bool showBorder;
  final Color? backgroundColor;

  const AdwHeaderBar({
    super.key,
    this.title,
    this.titleText,
    this.subtitleText,
    this.leading,
    this.actions,
    this.showBorder = true,
    this.backgroundColor,
  });

  @override
  Size get preferredSize => const Size.fromHeight(48);

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).relayPalette;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final bgColor = backgroundColor ?? (isDark ? const Color(0xff181a20) : const Color(0xfff0f1f6));
    final borderColor = isDark ? const Color(0x1fffffff) : const Color(0x18000000);

    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: bgColor,
        border: showBorder
            ? Border(bottom: BorderSide(color: borderColor, width: 1))
            : null,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: NavigationToolbar(
        leading: leading,
        middle: title ??
            (titleText != null
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        titleText!,
                        style: RelayTypography.heading(palette.textPrimary, isGnome: true),
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (subtitleText != null)
                        Text(
                          subtitleText!,
                          style: RelayTypography.caption(palette.textSecondary, isGnome: true),
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  )
                : null),
        trailing: actions != null
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: actions!,
              )
            : null,
        centerMiddle: true,
      ),
    );
  }
}

/// Libadwaita flat icon button used in HeaderBars and Action Rows.
class AdwIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final bool isPrimary;
  final bool isDestructive;

  const AdwIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.tooltip,
    this.isPrimary = false,
    this.isDestructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).relayPalette;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    Color iconColor;
    if (onPressed == null) {
      iconColor = palette.textTertiary;
    } else if (isPrimary) {
      iconColor = palette.accent;
    } else if (isDestructive) {
      iconColor = palette.error;
    } else {
      iconColor = palette.textPrimary;
    }

    final button = Material(
      color: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(6),
        hoverColor: isDark ? const Color(0x1fffffff) : const Color(0x0f000000),
        highlightColor: isDark ? const Color(0x2fffffff) : const Color(0x1a000000),
        child: Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          child: Icon(icon, size: 18, color: iconColor),
        ),
      ),
    );

    if (tooltip != null) {
      return Tooltip(message: tooltip!, child: button);
    }
    return button;
  }
}
