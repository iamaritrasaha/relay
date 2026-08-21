import 'package:flutter/material.dart';
import 'package:relay_app/config/relay_brand.dart';

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
              padding: const EdgeInsets.only(left: 4, bottom: 10),
              child: Text(
                title!.toUpperCase(),
                style: RelayTypography.sectionHeader(palette.textSecondary, isGnome: true),
              ),
            ),
          ],
          if (description != null) ...[
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 8),
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

/// A grouped list of rows.
///
/// Deliberately borderless: the rows are separated by hairlines and the group
/// by space, so a page of these reads as sections of one document rather than
/// as a stack of boxes.
class AdwBoxedList extends StatelessWidget {
  final List<Widget> children;
  final double borderRadius;

  const AdwBoxedList({
    super.key,
    required this.children,
    this.borderRadius = RelayRadius.panel,
  });

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).relayPalette;
    final dividerColor = palette.hairline;

    if (children.isEmpty) {
      return const SizedBox.shrink();
    }

    final separated = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) {
        separated.add(Divider(height: 1, thickness: 1, color: dividerColor, indent: 4, endIndent: 4));
      }
      separated.add(children[i]);
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: separated,
    );
  }
}
