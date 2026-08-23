import 'package:flutter/material.dart';
import 'package:relay_app/config/relay_brand.dart';
import 'package:relay_app/widget/gnome/adw_action_row.dart';

/// Libadwaita Boxed List / Preferences Group for GNOME.
///
/// Contains child rows inside a single rounded container with internal hairline
/// dividers. Includes optional title and description text above the group.
class AdwPreferencesGroup extends StatelessWidget {
  final String? title;
  final String? description;
  final List<Widget> children;
  final EdgeInsetsGeometry margin;
  final bool uppercaseTitle;
  final EdgeInsetsGeometry? rowPadding;
  final double? rowMinHeight;

  /// Overrides the group's own surface tone. Left null, a group matches the
  /// page canvas (the common case); a group nested inside another elevated
  /// surface -- a dialog card, say -- passes `palette.canvasTonalHigh` so it
  /// reads as one tonal step *into* that surface rather than the same flat
  /// grey repeated twice.
  final Color? surfaceColor;

  const AdwPreferencesGroup({
    super.key,
    this.title,
    this.description,
    required this.children,
    this.margin = const EdgeInsets.only(bottom: 24),
    this.uppercaseTitle = true,
    this.rowPadding,
    this.rowMinHeight,
    this.surfaceColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
                uppercaseTitle ? title!.toUpperCase() : title!,
                style: uppercaseTitle
                    ? RelayTypography.sectionHeader(palette.textSecondary, isGnome: true)
                    : theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant, fontWeight: FontWeight.w600),
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
          if (rowPadding != null && rowMinHeight != null)
            AdwRowGeometry(
              padding: rowPadding!,
              minHeight: rowMinHeight!,
              child: AdwBoxedList(surfaceColor: surfaceColor, children: children),
            )
          else
            AdwBoxedList(surfaceColor: surfaceColor, children: children),
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
  final Color? surfaceColor;

  const AdwBoxedList({
    super.key,
    required this.children,
    this.borderRadius = RelayRadius.panel,
    this.surfaceColor,
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

    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(borderRadius));

    // The Material is the single visual and clipping boundary for the group:
    // rows stay contiguous, dividers finish inside the rounded outer edge, and
    // InkWell feedback from actionable rows cannot paint square corners.
    return Material(
      color: surfaceColor ?? palette.elevated,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: separated,
      ),
    );
  }
}
