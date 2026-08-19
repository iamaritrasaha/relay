import 'package:flutter/material.dart';
import 'package:relay_app/config/relay_brand.dart';
import 'package:relay_app/widget/relay/relay_desktop_metrics.dart';

/// The quiet bar that sits at the top of every Relay surface.
///
/// It is deliberately not an [AppBar]: the OS already draws window chrome, so
/// this only carries identity (or a title plus a way back) and the secondary
/// actions. The full-bleed hairline underneath is what binds it to the content
/// instead of letting it float.
class RelayTopBar extends StatelessWidget {
  /// Leading identity/title block.
  final Widget leading;

  /// Secondary actions, rendered at the trailing edge.
  final List<Widget> actions;
  final double horizontalInset;

  const RelayTopBar({super.key, required this.leading, this.actions = const [], this.horizontalInset = 16});

  /// Home's variant: the Relay mark and wordmark.
  factory RelayTopBar.brand({
    required Widget wordmark,
    required Widget presence,
    List<Widget> actions = const [],
    double horizontalInset = 16,
  }) {
    return RelayTopBar(
      leading: _BrandLeading(wordmark: wordmark, presence: presence),
      actions: actions,
      horizontalInset: horizontalInset,
    );
  }

  /// Settings' and About's variant: a back affordance and the surface name.
  factory RelayTopBar.titled({
    required String title,
    VoidCallback? onBack,
    String? backTooltip,
    List<Widget> actions = const [],
    double horizontalInset = 16,
  }) {
    return RelayTopBar(
      leading: _TitledLeading(title: title, onBack: onBack, backTooltip: backTooltip),
      actions: actions,
      horizontalInset: horizontalInset,
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).relayPalette;
    return DecoratedBox(
      // Full bleed: the hairline spans the window, not the content frame.
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: palette.hairline)),
      ),
      child: SizedBox(
        height: RelayDesktopMetrics.topBarHeight,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: horizontalInset),
          child: Row(
            children: [
              Flexible(child: leading),
              const Spacer(),
              ...actions,
            ],
          ),
        ),
      ),
    );
  }
}

class _BrandLeading extends StatelessWidget {
  final Widget wordmark;
  final Widget presence;

  const _BrandLeading({required this.wordmark, required this.presence});

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).relayPalette;
    return LayoutBuilder(
      builder: (context, constraints) {
        // Narrow windows drop the inline presence rather than truncating the
        // alias; Home still shows it under the field label.
        if (constraints.maxWidth < 360) {
          return Align(alignment: Alignment.centerLeft, child: wordmark);
        }
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            wordmark,
            Container(
              width: 1,
              height: 14,
              margin: const EdgeInsets.symmetric(horizontal: 14),
              color: palette.hairline,
            ),
            Flexible(child: presence),
          ],
        );
      },
    );
  }
}

class _TitledLeading extends StatelessWidget {
  final String title;
  final VoidCallback? onBack;
  final String? backTooltip;

  const _TitledLeading({required this.title, this.onBack, this.backTooltip});

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).relayPalette;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (onBack != null) ...[
          IconButton(
            tooltip: backTooltip ?? MaterialLocalizations.of(context).backButtonTooltip,
            onPressed: onBack,
            iconSize: 18,
            visualDensity: VisualDensity.compact,
            style: IconButton.styleFrom(
              foregroundColor: palette.textSecondary,
              backgroundColor: palette.softSurface,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            icon: const Icon(Icons.chevron_left_rounded),
          ),
          const SizedBox(width: 11),
        ] else
          const SizedBox(width: 8),
        Flexible(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 16, height: 1.2, fontWeight: FontWeight.w600, color: palette.textPrimary),
          ),
        ),
      ],
    );
  }
}

/// The quiet 32px square actions used at the trailing edge of [RelayTopBar].
class RelayTopBarAction extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool selected;

  const RelayTopBarAction({
    super.key,
    required this.icon,
    required this.tooltip,
    this.onPressed,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).relayPalette;
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        iconSize: 18,
        style: IconButton.styleFrom(
          minimumSize: const Size(36, 36),
          foregroundColor: selected ? palette.textPrimary : palette.textSecondary,
          backgroundColor: selected ? palette.softSurface : Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        icon: Icon(icon),
      ),
    );
  }
}
