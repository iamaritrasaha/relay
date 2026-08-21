import 'package:flutter/material.dart';
import 'package:relay_app/config/relay_brand.dart';
import 'package:relay_app/config/relay_motion.dart';

/// A Relay action button.
///
/// One filled warm primary per group; everything else is a low-contrast flat
/// button that only picks up a tone on hover. These are controls, not cards —
/// they carry no border and no elevation.
class RelayAction extends StatefulWidget {
  final IconData icon;
  final String label;
  final String? hint;
  final VoidCallback? onPressed;
  final bool primary;
  final bool enabled;
  final bool expand;

  const RelayAction({
    super.key,
    required this.icon,
    required this.label,
    this.hint,
    this.onPressed,
    this.primary = false,
    this.enabled = true,
    this.expand = true,
  });

  @override
  State<RelayAction> createState() => _RelayActionState();
}

class _RelayActionState extends State<RelayAction> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).relayPalette;
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    final enabled = widget.enabled && widget.onPressed != null;

    final Color fill;
    final Color foreground;
    if (!enabled) {
      fill = palette.softSurface;
      foreground = palette.textTertiary;
    } else if (widget.primary) {
      fill = _hovered ? palette.accentSoft : palette.accent;
      foreground = const Color(0xff1a0e08);
    } else {
      fill = _hovered ? palette.hoverSurface : palette.softSurface;
      foreground = palette.textPrimary;
    }

    final scale = reducedMotion || !enabled ? 1.0 : (_pressed ? 0.98 : 1.0);
    final translateY = reducedMotion || !enabled ? 0.0 : (_pressed ? 0.0 : (_hovered ? -1.0 : 0.0));

    Widget tile = AnimatedContainer(
      duration: reducedMotion ? Duration.zero : RelayMotion.hover,
      curve: RelayMotion.curve,
      transform: Matrix4.identity()
        ..translateByDouble(0.0, translateY, 0.0, 1.0)
        ..scaleByDouble(scale, scale, 1.0, 1.0),
      transformAlignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(RelayRadius.button),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(widget.icon, size: 17, color: widget.primary && enabled ? foreground : (enabled ? palette.textSecondary : foreground)),
          const SizedBox(width: 9),
          Flexible(
            child: Text(
              widget.label,
              style: RelayTypography.body(foreground, isGnome: true, bold: widget.primary),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );

    tile = Semantics(
      button: true,
      enabled: enabled,
      label: widget.hint == null ? widget.label : '${widget.label}. ${widget.hint}',
      child: tile,
    );

    if (widget.hint != null) {
      tile = Tooltip(message: widget.hint!, child: tile);
    }

    return RepaintBoundary(
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() {
          _hovered = false;
          _pressed = false;
        }),
        child: GestureDetector(
          onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
          onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
          onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
          onTap: enabled ? widget.onPressed : null,
          child: widget.expand ? SizedBox(width: double.infinity, child: tile) : tile,
        ),
      ),
    );
  }
}
