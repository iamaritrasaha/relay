import 'package:flutter/material.dart';
import 'package:relay_app/config/relay_brand.dart';
import 'package:relay_app/config/relay_motion.dart';

/// One reading in a status section: a label on the left, the value on the
/// right, and a hairline between rows. No box, no icon chip — the alignment is
/// what makes it a table.
///
/// Every value is passed in from state the app already holds. The row animates
/// between the values it is given and never invents one.
class RelayStatRow extends StatelessWidget {
  final String label;
  final String value;

  /// 0..1, for readings that are genuinely a fraction (battery).
  final double? fraction;

  /// 0..4, for readings that are genuinely a level (signal).
  final int? level;

  /// Colours the value text and, unless [barColor] says otherwise, the bar.
  final Color? tint;

  /// The bar or level indicator, when it should stay quieter than the value.
  final Color? barColor;

  const RelayStatRow({
    super.key,
    required this.label,
    required this.value,
    this.fraction,
    this.level,
    this.tint,
    this.barColor,
  });

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).relayPalette;
    final reducedMotion = MediaQuery.disableAnimationsOf(context);

    return Semantics(
      label: '$label: $value',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 13),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: RelayTypography.body(palette.textSecondary, isGnome: true),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (fraction != null) ...[
              SizedBox(
                width: 44,
                child: RelayLevelBar(fraction: fraction!, color: tint ?? palette.textTertiary),
              ),
              const SizedBox(width: 12),
            ] else if (level != null) ...[
              RelaySignalBars(level: level!.clamp(0, 4), color: tint ?? palette.textTertiary),
              const SizedBox(width: 12),
            ],
            Flexible(
              child: AnimatedSwitcher(
                duration: reducedMotion ? Duration.zero : RelayMotion.state,
                child: Text(
                  value,
                  key: ValueKey(value),
                  textAlign: TextAlign.right,
                  style: RelayTypography.body(tint ?? palette.textPrimary, isGnome: true, bold: true),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A headline reading: a large number over a quiet label.
class RelayHeadlineStat extends StatelessWidget {
  final String value;
  final String label;
  final Color? tint;

  const RelayHeadlineStat({super.key, required this.value, required this.label, this.tint});

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).relayPalette;
    final reducedMotion = MediaQuery.disableAnimationsOf(context);

    return Semantics(
      label: '$label: $value',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedSwitcher(
            duration: reducedMotion ? Duration.zero : RelayMotion.state,
            child: Text(
              value,
              key: ValueKey(value),
              style: RelayTypography.metric(tint ?? palette.textPrimary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: RelayTypography.caption(palette.textTertiary, isGnome: true),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

/// A rounded fill bar that interpolates to whatever fraction it is handed.
class RelayLevelBar extends StatelessWidget {
  final double fraction;
  final Color color;
  final double height;

  const RelayLevelBar({super.key, required this.fraction, required this.color, this.height = 4});

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).relayPalette;
    final reducedMotion = MediaQuery.disableAnimationsOf(context);

    // A fraction of the track rather than a measured pixel width, so the bar
    // still reports intrinsic dimensions when it sits inside a column that
    // needs to size itself.
    return TweenAnimationBuilder<double>(
      tween: Tween(end: fraction.clamp(0.0, 1.0)),
      duration: reducedMotion ? Duration.zero : RelayMotion.state,
      curve: RelayMotion.curve,
      builder: (context, value, _) => Container(
        height: height,
        decoration: BoxDecoration(
          color: palette.softSurface,
          borderRadius: BorderRadius.circular(height),
        ),
        child: FractionallySizedBox(
          alignment: Alignment.centerLeft,
          widthFactor: value,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(height),
            ),
          ),
        ),
      ),
    );
  }
}

/// Four bars whose emphasis interpolates as the reported signal level changes.
class RelaySignalBars extends StatelessWidget {
  final int level;
  final Color color;

  const RelaySignalBars({super.key, required this.level, required this.color});

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).relayPalette;
    final reducedMotion = MediaQuery.disableAnimationsOf(context);

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (var i = 1; i <= 4; i++) ...[
          if (i > 1) const SizedBox(width: 3),
          AnimatedContainer(
            duration: reducedMotion ? Duration.zero : RelayMotion.state,
            curve: RelayMotion.curve,
            width: 3,
            height: 3.0 + i * 2.0,
            decoration: BoxDecoration(
              color: i <= level ? color : palette.softSurface,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ],
      ],
    );
  }
}
