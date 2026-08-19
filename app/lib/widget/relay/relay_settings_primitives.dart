import 'package:flutter/material.dart';
import 'package:relay_app/config/relay_brand.dart';
import 'package:relay_app/widget/relay/relay_desktop_metrics.dart';

/// The row/group vocabulary Relay's Settings is built from.
///
/// Groups are defined by typography and hairlines rather than by cards, and a
/// control is sized to its own content instead of claiming a fixed slab of the
/// row. Kept here so Settings and its tests measure the same thing.

/// A settings group: a tracked label over a hairline, then its rows.
class RelaySettingsGroup extends StatelessWidget {
  final String title;
  final List<Widget> children;

  /// Full-width notices (restart hints, non-default warnings) that belong to
  /// the group but are not rows, so they carry no hairline.
  final List<Widget> notes;

  const RelaySettingsGroup({super.key, required this.title, required this.children, this.notes = const []});

  bool get isEmpty => children.isEmpty;

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).relayPalette;
    final rows = children;
    if (rows.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 38),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 11),
            child: Text(title.toUpperCase(), style: RelayTypography.section(palette.textTertiary)),
          ),
          Container(height: 1, color: palette.textTertiary.withValues(alpha: 0.22)),
          ...notes,
          for (final (index, row) in rows.indexed)
            DecoratedBox(
              decoration: BoxDecoration(
                border: index == rows.length - 1 ? null : Border(bottom: BorderSide(color: palette.hairline)),
              ),
              child: row,
            ),
        ],
      ),
    );
  }
}

/// One settings row. The label leads, the control follows at its own size.
class RelaySettingsEntry extends StatelessWidget {
  final String label;

  /// Optional second line, used only where the existing copy genuinely helps.
  final String? description;
  final Widget child;

  /// Caps the control so it stays sized to its content rather than stretching.
  final double controlMaxWidth;

  const RelaySettingsEntry({super.key, required this.label, required this.child, this.description, this.controlMaxWidth = 230});

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).relayPalette;
    return LayoutBuilder(
      builder: (context, constraints) {
        final mobile = constraints.maxWidth < 420;
        return ConstrainedBox(
          constraints: const BoxConstraints(minHeight: RelayDesktopMetrics.settingsRowMinHeight),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label,
                        style: TextStyle(fontSize: 14, height: 1.35, fontWeight: FontWeight.w500, color: palette.textPrimary),
                      ),
                      if (description != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Text(description!, style: TextStyle(fontSize: 12.5, height: 1.45, color: palette.textTertiary)),
                        ),
                    ],
                  ),
                ),
                SizedBox(width: mobile ? 14 : 24),
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: mobile ? controlMaxWidth.clamp(0, 148) : controlMaxWidth),
                  child: child,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// A row whose control is Relay's compact switch.
class RelayBooleanEntry extends StatelessWidget {
  final String label;
  final String? description;
  final bool value;
  final ValueChanged<bool> onChanged;

  const RelayBooleanEntry({super.key, required this.label, required this.value, required this.onChanged, this.description});

  @override
  Widget build(BuildContext context) {
    // The whole row is the target, so the switch itself can stay small without
    // costing reach.
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(8),
      child: RelaySettingsEntry(
        label: label,
        description: description,
        child: Align(
          alignment: Alignment.centerRight,
          child: RelaySwitch(value: value, onChanged: onChanged, semanticLabel: label),
        ),
      ),
    );
  }
}

/// A row that reads as navigable: a value and a chevron, the whole row tappable.
class RelayNavigationEntry extends StatelessWidget {
  final String label;
  final String? description;
  final String value;
  final VoidCallback onTap;

  const RelayNavigationEntry({super.key, required this.label, required this.value, required this.onTap, this.description});

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).relayPalette;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: RelaySettingsEntry(
        label: label,
        description: description,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                value,
                textAlign: TextAlign.end,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, height: 1.35, color: palette.textSecondary),
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right_rounded, size: 18, color: palette.textTertiary),
          ],
        ),
      ),
    );
  }
}

/// Relay's compact switch: 38x21, no pill wrapper, still a 48px hit target.
class RelaySwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  final String? semanticLabel;

  const RelaySwitch({super.key, required this.value, required this.onChanged, this.semanticLabel});

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).relayPalette;
    return Semantics(
      label: semanticLabel,
      toggled: value,
      child: Tooltip(
        message: value ? 'On' : 'Off',
        child: InkWell(
          onTap: () => onChanged(!value),
          borderRadius: BorderRadius.circular(24),
          child: Padding(
            // Small enough to keep every row on the same 52px rhythm; the row
            // around it carries the comfortable target.
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 5),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              curve: Curves.easeOutCubic,
              width: 38,
              height: 21,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(11),
                color: value ? palette.accent : palette.softSurface,
              ),
              child: AnimatedAlign(
                duration: const Duration(milliseconds: 140),
                curve: Curves.easeOutCubic,
                alignment: value ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  width: 15,
                  height: 15,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: value ? palette.textPrimary : palette.textSecondary,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Lays settings groups out in two balanced columns only when this surface has
/// enough usable width. Narrow desktop windows retain desktop-sized rows in a
/// centered single column instead of inheriting Home's desktop breakpoint.
///
/// Groups are dealt into the column that is currently shorter, measured in
/// rows, so neither side runs far past the other as advanced options appear.
class RelaySettingsColumns extends StatelessWidget {
  final List<RelaySettingsGroup> groups;

  const RelaySettingsColumns({super.key, required this.groups});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final present = groups.where((group) => !group.isEmpty).toList();
        final layout = RelayDesktopMetrics.settingsLayout(constraints.maxWidth);
        if (layout == RelaySettingsLayout.singleColumn) {
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: RelayDesktopMetrics.settingsSingleColumnWidth),
              child: Column(
                key: const ValueKey('relay-settings-one-column'),
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: present,
              ),
            ),
          );
        }

        final left = <Widget>[];
        final right = <Widget>[];
        var leftWeight = 0;
        var rightWeight = 0;
        for (final group in present) {
          final weight = group.children.length;
          if (leftWeight <= rightWeight) {
            left.add(group);
            leftWeight += weight;
          } else {
            right.add(group);
            rightWeight += weight;
          }
        }

        return Row(
          key: ValueKey(
            layout == RelaySettingsLayout.twoColumnWide ? 'relay-settings-two-columns-wide' : 'relay-settings-two-columns-standard',
          ),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: left),
            ),
            const SizedBox(width: RelayDesktopMetrics.settingsColumnGap),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: right),
            ),
          ],
        );
      },
    );
  }
}
