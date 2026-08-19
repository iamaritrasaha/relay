import 'package:flutter/material.dart';
import 'package:localsend_app/config/relay_brand.dart';

/// Libadwaita Boxed List / Preferences Group for GNOME.
///
/// Contains child rows inside a single rounded container with internal hairline
/// dividers. Includes optional title and description text above the group.
class AdwPreferencesGroup extends StatelessWidget {
  final String? title;
  final String? description;
  final List<Widget> children;
  final EdgeInsetsGeometry margin;

  const AdwPreferencesGroup({
    super.key,
    this.title,
    this.description,
    required this.children,
    this.margin = const EdgeInsets.only(bottom: 24),
  });

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).relayPalette;

    return Padding(
      padding: margin,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (title != null) ...[
            Padding(
              padding: const EdgeInsets.only(left: 16, bottom: 6),
              child: Text(
                title!.toUpperCase(),
                style: RelayTypography.sectionHeader(palette.textSecondary, isGnome: true),
              ),
            ),
          ],
          if (description != null) ...[
            Padding(
              padding: const EdgeInsets.only(left: 16, bottom: 8),
              child: Text(
                description!,
                style: RelayTypography.caption(palette.textTertiary, isGnome: true),
              ),
            ),
          ],
          AdwBoxedList(children: children),
        ],
      ),
    );
  }
}

/// Libadwaita Boxed List container.
class AdwBoxedList extends StatelessWidget {
  final List<Widget> children;
  final double borderRadius;

  const AdwBoxedList({
    super.key,
    required this.children,
    this.borderRadius = 10,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final bgColor = isDark ? const Color(0xff1e2028) : const Color(0xffffffff);
    final borderColor = isDark ? const Color(0x1fffffff) : const Color(0x14000000);
    final dividerColor = isDark ? const Color(0x14ffffff) : const Color(0x0f000000);

    if (children.isEmpty) {
      return const SizedBox.shrink();
    }

    final separated = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) {
        separated.add(Divider(height: 1, thickness: 1, color: dividerColor, indent: 16, endIndent: 16));
      }
      separated.add(children[i]);
    }

    return Container(
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: borderColor, width: 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: separated,
      ),
    );
  }
}
