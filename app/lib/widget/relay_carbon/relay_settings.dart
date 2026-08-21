import 'package:flutter/material.dart';
import 'package:relay_app/config/relay_brand.dart';
import 'package:relay_app/config/relay_motion.dart';
import 'package:relay_app/widget/relay_carbon/relay_surface.dart';

/// A group of settings.
///
/// A section is a heading, a rule and a run of rows — never a rounded box. That
/// is what lets Settings read as the same document as the rest of Relay instead
/// of as a preferences dialog dropped inside it.
class RelaySettingsSection extends StatelessWidget {
  final String title;
  final String? description;
  final List<Widget> children;

  const RelaySettingsSection({
    super.key,
    required this.title,
    this.description,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).relayPalette;

    return Padding(
      padding: const EdgeInsets.only(bottom: 30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: RelayTypography.heading(palette.textPrimary, isGnome: true).copyWith(fontWeight: RelayTypography.semiBold),
          ),
          if (description != null) ...[
            const SizedBox(height: 4),
            Text(description!, style: RelayTypography.caption(palette.textTertiary, isGnome: true)),
          ],
          const SizedBox(height: 10),
          const RelayDivider(),
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const RelayDivider(),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// The shared body of every settings row: a title, an optional explanation and
/// whatever control belongs on the right.
class RelaySettingsRow extends StatefulWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool destructive;

  const RelaySettingsRow({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.destructive = false,
  });

  @override
  State<RelaySettingsRow> createState() => _RelaySettingsRowState();
}

class _RelaySettingsRowState extends State<RelaySettingsRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).relayPalette;
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    final interactive = widget.onTap != null;
    final titleColor = widget.destructive ? palette.error : palette.textPrimary;

    final row = AnimatedContainer(
      duration: reducedMotion ? Duration.zero : RelayMotion.hover,
      curve: RelayMotion.curve,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
      decoration: BoxDecoration(
        color: interactive && _hovered ? palette.softSurface : Colors.transparent,
        borderRadius: BorderRadius.circular(RelayRadius.button),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(widget.title, style: RelayTypography.body(titleColor, isGnome: true)),
                if (widget.subtitle != null) ...[
                  const SizedBox(height: 3),
                  Text(widget.subtitle!, style: RelayTypography.caption(palette.textTertiary, isGnome: true)),
                ],
              ],
            ),
          ),
          if (widget.trailing != null) ...[
            const SizedBox(width: 18),
            widget.trailing!,
          ],
        ],
      ),
    );

    if (!interactive) {
      return row;
    }

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Semantics(
        button: true,
        label: widget.subtitle == null ? widget.title : '${widget.title}. ${widget.subtitle}',
        child: GestureDetector(onTap: widget.onTap, child: row),
      ),
    );
  }
}

/// A settings row whose control is a switch.
class RelaySettingsSwitchRow extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  const RelaySettingsSwitchRow({
    super.key,
    required this.title,
    this.subtitle,
    required this.value,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      toggled: value,
      label: subtitle == null ? title : '$title. $subtitle',
      child: RelaySettingsRow(
        title: title,
        subtitle: subtitle,
        onTap: onChanged == null ? null : () => onChanged!(!value),
        trailing: ExcludeSemantics(
          child: Switch(
            value: value,
            onChanged: onChanged,
          ),
        ),
      ),
    );
  }
}

/// A settings row that opens something else, showing its current value.
class RelaySettingsNavRow extends StatelessWidget {
  final String title;
  final String? subtitle;
  final String? valueText;
  final VoidCallback onTap;

  const RelaySettingsNavRow({
    super.key,
    required this.title,
    this.subtitle,
    this.valueText,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).relayPalette;

    return RelaySettingsRow(
      title: title,
      subtitle: subtitle,
      onTap: onTap,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (valueText != null)
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 240),
              child: Text(
                valueText!,
                style: RelayTypography.body(palette.textSecondary, isGnome: true),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
              ),
            ),
          const SizedBox(width: 8),
          Icon(Icons.chevron_right_rounded, size: 18, color: palette.textTertiary),
        ],
      ),
    );
  }
}

/// A settings row that only reports state Relay already knows.
class RelaySettingsValueRow extends StatelessWidget {
  final String title;
  final String? subtitle;
  final String value;
  final Color? tint;

  const RelaySettingsValueRow({
    super.key,
    required this.title,
    this.subtitle,
    required this.value,
    this.tint,
  });

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).relayPalette;

    return RelaySettingsRow(
      title: title,
      subtitle: subtitle,
      trailing: Text(
        value,
        style: RelayTypography.body(tint ?? palette.textSecondary, isGnome: true, bold: true),
      ),
    );
  }
}

/// A settings row that houses a quiet dropdown picker.
class RelaySettingsDropdownRow<T> extends StatelessWidget {
  final String title;
  final String? subtitle;
  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?>? onChanged;

  const RelaySettingsDropdownRow({
    super.key,
    required this.title,
    this.subtitle,
    required this.value,
    required this.items,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).relayPalette;

    return RelaySettingsRow(
      title: title,
      subtitle: subtitle,
      trailing: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          items: items,
          onChanged: onChanged,
          dropdownColor: palette.elevated,
          icon: Icon(Icons.keyboard_arrow_down_rounded, color: palette.textSecondary, size: 20),
          style: RelayTypography.body(palette.textPrimary, isGnome: true),
        ),
      ),
    );
  }
}
