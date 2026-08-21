import 'package:flutter/material.dart';
import 'package:relay_app/config/relay_brand.dart';

/// Libadwaita-inspired NavigationSplitView for GNOME.
///
/// On wide desktop viewports (>= 720px width), displays a fixed-width sidebar
/// alongside the detail content separated by an Adwaita hairline divider.
/// On narrow viewports (< 720px), collapses cleanly into a single view.
class AdwSplitView extends StatelessWidget {
  final Widget sidebar;
  final Widget content;
  final double sidebarWidth;
  final double breakpoint;
  final bool showSidebarOnNarrow;

  const AdwSplitView({
    super.key,
    required this.sidebar,
    required this.content,
    this.sidebarWidth = 270,
    this.breakpoint = 720,
    this.showSidebarOnNarrow = true,
  });

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).relayPalette;
    final dividerColor = palette.hairline;
    final sidebarBg = palette.canvas;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= breakpoint;

        if (isWide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: sidebarWidth,
                child: ColoredBox(
                  color: sidebarBg,
                  child: sidebar,
                ),
              ),
              VerticalDivider(
                width: 1,
                thickness: 1,
                color: dividerColor,
              ),
              Expanded(child: content),
            ],
          );
        }

        // Narrow mode: show either sidebar or content
        return showSidebarOnNarrow ? sidebar : content;
      },
    );
  }
}
