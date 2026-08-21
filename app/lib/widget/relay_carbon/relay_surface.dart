import 'package:flutter/material.dart';
import 'package:relay_app/config/relay_brand.dart';

/// A major surface. There should only ever be two or three on a screen.
///
/// It is matte on purpose: one step of background tone and nothing else. No
/// border, no top highlight, no inner bevel — those are what made the previous
/// pass read as plastic. Anything smaller than a major region is separated by
/// space, tone or a hairline instead of being given its own box.
class RelaySurface extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double radius;

  /// Marks the surface that is the subject of the page with a faint warm wash
  /// rather than an outline.
  final bool accented;

  /// A region nested inside another surface: one tone quieter, no elevation.
  final bool inset;

  /// Opt in to a hairline. Only for surfaces that must read as interactive or
  /// as a true boundary.
  final bool outlined;

  final Color? fill;

  const RelaySurface({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.radius = RelayRadius.card,
    this.accented = false,
    this.inset = false,
    this.outlined = false,
    this.fill,
  });

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).relayPalette;

    final resolvedFill = fill ?? (inset ? palette.canvasTonalHigh : palette.elevated);

    return RepaintBoundary(
      child: Container(
        margin: margin,
        decoration: BoxDecoration(
          color: resolvedFill,
          borderRadius: BorderRadius.circular(radius),
          border: outlined ? Border.all(color: accented ? palette.accent.withValues(alpha: 0.3) : palette.hairline, width: 1) : null,
        ),
        child: Padding(
          padding: padding ?? EdgeInsets.zero,
          child: child,
        ),
      ),
    );
  }
}

/// A hairline. The main way one region is told from the next.
class RelayDivider extends StatelessWidget {
  final Axis axis;
  final double indent;

  const RelayDivider({super.key, this.axis = Axis.horizontal, this.indent = 0});

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).relayPalette;
    return axis == Axis.horizontal
        ? Divider(height: 1, thickness: 1, color: palette.hairline, indent: indent, endIndent: indent)
        : VerticalDivider(width: 1, thickness: 1, color: palette.hairline, indent: indent, endIndent: indent);
  }
}

/// The small tracked label that opens a section. No icon, no box: the label and
/// the space above it are the whole device.
class RelaySectionLabel extends StatelessWidget {
  final String label;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  const RelaySectionLabel({
    super.key,
    required this.label,
    this.trailing,
    this.padding = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).relayPalette;
    return Padding(
      padding: padding,
      child: Row(
        children: [
          Expanded(
            child: Text(
              label.toUpperCase(),
              style: RelayTypography.sectionHeader(palette.textTertiary, isGnome: true),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// Presence states a device or the app itself can be in.
///
/// Kept separate from any protocol state: this only says how the dot should
/// read, and every caller derives it from state the model already exposes.
enum RelayPresenceTone { online, busy, attention, offline }

extension RelayPresenceToneColor on RelayPresenceTone {
  Color color(RelayPalette palette) => switch (this) {
    RelayPresenceTone.online => palette.success,
    RelayPresenceTone.busy => palette.accent,
    RelayPresenceTone.attention => palette.warning,
    RelayPresenceTone.offline => palette.textTertiary,
  };
}

/// A status dot plus its label. Never colour alone — the word always ships
/// with the dot so the state survives a monochrome or colour-blind reading.
class RelayStatusPill extends StatelessWidget {
  final RelayPresenceTone tone;
  final String label;
  final bool compact;

  const RelayStatusPill({
    super.key,
    required this.tone,
    required this.label,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).relayPalette;
    final color = tone.color(palette);

    return Semantics(
      label: label,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              style: compact ? RelayTypography.caption(color, isGnome: true) : RelayTypography.body(color, isGnome: true),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// The window ground: a very subtle warm vertical tone, never flat black.
class RelayCanvas extends StatelessWidget {
  final Widget child;

  const RelayCanvas({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).relayPalette;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [palette.canvasTonalHigh, palette.canvasTonalLow],
        ),
      ),
      child: child,
    );
  }
}
