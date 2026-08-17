import 'package:flutter/material.dart';
import 'package:localsend_app/config/relay_brand.dart';
import 'package:localsend_app/config/relay_motion.dart';
import 'package:localsend_app/pages/relay_home_vm.dart';
import 'package:localsend_app/widget/relay/relay_desktop_metrics.dart';
import 'package:localsend_isolates/util/file_size_helper.dart';

/// The one control Home carries, docked below the nearby field.
///
/// It is a single pill that transforms in place — idle, loaded, then reporting
/// a transfer — rather than three different panels appearing and disappearing.
class PayloadDock extends StatelessWidget {
  final RelayPayloadVm selection;
  final RelayTransferVm? transfer;
  final bool compact;
  final VoidCallback onSelect;
  final VoidCallback? onClear;
  final VoidCallback? onCancelTransfer;
  final RelayResponsiveMetrics? metrics;

  const PayloadDock({
    required this.selection,
    required this.onSelect,
    this.transfer,
    this.compact = false,
    this.onClear,
    this.onCancelTransfer,
    this.metrics,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return _MobilePayloadDock(
        selection: selection,
        transfer: transfer,
        onSelect: onSelect,
        onClear: onClear,
        onCancelTransfer: onCancelTransfer,
      );
    }
    final palette = Theme.of(context).relayPalette;
    final children = <Widget>[];

    if (selection.isEmpty && transfer == null) {
      if (!compact) {
        children.addAll([
          const SizedBox(width: 20),
          // Flexible so a long translation ellipsizes instead of pushing the
          // dock past the content frame on a narrow desktop window.
          Flexible(
            child: Text(
              'Drop files or folders anywhere',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13.5, color: palette.textSecondary),
            ),
          ),
          const _Divider(),
        ]);
      } else {
        children.add(const SizedBox(width: 8));
      }
      children.add(Flexible(child: _ShareButton(onPressed: onSelect)));
    } else {
      children.add(const SizedBox(width: 8));
      // On a phone the readout already names the destination, so the chip is
      // dropped while a transfer runs rather than squeezing three blocks in.
      if (transfer == null || !compact) {
        children.add(Flexible(child: _PayloadChip(selection: selection)));
      }
      if (transfer != null) {
        children.addAll([
          const _Divider(),
          Flexible(
            child: _TransferReadout(transfer: transfer!, compact: compact),
          ),
          if (onCancelTransfer != null) ...[
            const _Divider(),
            Flexible(
              child: _GhostButton(label: 'Cancel', onPressed: onCancelTransfer!),
            ),
          ],
        ]);
      } else {
        if (!compact) {
          children.addAll([
            const _Divider(),
            Flexible(
              child: Text(
                'Choose a nearby device',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, color: palette.textSecondary),
              ),
            ),
          ]);
        }
        if (onClear != null) {
          children.add(
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: IconButton(
                tooltip: 'Clear selection',
                onPressed: onClear,
                iconSize: 18,
                style: IconButton.styleFrom(foregroundColor: palette.textSecondary),
                icon: const Icon(Icons.close_rounded),
              ),
            ),
          );
        }
        children.add(const SizedBox(width: 4));
      }
    }

    return AnimatedSize(
      duration: RelayMotion.deviceTransition,
      curve: RelayMotion.curve,
      child: Container(
        key: const ValueKey('relay-payload-dock'),
        constraints: BoxConstraints(minHeight: RelayDesktopMetrics.dockHeight, maxWidth: metrics?.payloadDockMaxWidth ?? double.infinity),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(RelayDesktopMetrics.dockHeight / 2),
          color: palette.elevated,
          border: Border.all(color: palette.hairline),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 34, offset: const Offset(0, 16), spreadRadius: -14),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: children,
        ),
      ),
    );
  }
}

class _MobilePayloadDock extends StatelessWidget {
  final RelayPayloadVm selection;
  final RelayTransferVm? transfer;
  final VoidCallback onSelect;
  final VoidCallback? onClear;
  final VoidCallback? onCancelTransfer;

  const _MobilePayloadDock({
    required this.selection,
    required this.transfer,
    required this.onSelect,
    required this.onClear,
    required this.onCancelTransfer,
  });

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).relayPalette;
    Widget child;
    if (selection.isEmpty && transfer == null) {
      child = SizedBox(
        width: double.infinity,
        child: _ShareButton(onPressed: onSelect),
      );
    } else if (transfer == null) {
      child = Row(
        children: [
          Expanded(child: _PayloadChip(selection: selection)),
          if (onClear != null) ...[
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Clear selection',
              onPressed: onClear,
              iconSize: 19,
              style: IconButton.styleFrom(foregroundColor: palette.textSecondary, backgroundColor: palette.softSurface),
              icon: const Icon(Icons.close_rounded),
            ),
          ],
        ],
      );
    } else {
      child = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(child: _PayloadChip(selection: selection)),
              if (onCancelTransfer != null) ...[
                const SizedBox(width: 8),
                _GhostButton(label: 'Cancel', onPressed: onCancelTransfer!),
              ],
            ],
          ),
          const SizedBox(height: 10),
          _TransferReadout(transfer: transfer!, compact: false),
        ],
      );
    }

    return AnimatedSize(
      duration: RelayMotion.deviceTransition,
      curve: RelayMotion.curve,
      child: Container(
        key: const ValueKey('relay-payload-dock'),
        width: double.infinity,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: palette.elevated,
          border: Border.all(color: palette.hairline),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 24, offset: const Offset(0, 12), spreadRadius: -12)],
        ),
        child: child,
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 24,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      color: Theme.of(context).relayPalette.hairline,
    );
  }
}

class _ShareButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _ShareButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).relayPalette;
    return FilledButton.icon(
      key: const ValueKey('relay-share-something'),
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 40),
        backgroundColor: palette.accent,
        foregroundColor: RelayPalette.dark.canvas,
        shape: const StadiumBorder(),
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 20),
      ),
      icon: const Icon(Icons.add_rounded, size: 18),
      // Styled on the label so the family still resolves from the text theme.
      label: const Text(
        'Share something',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _GhostButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;

  const _GhostButton({required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).relayPalette;
    return FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 40),
        backgroundColor: palette.softSurface,
        foregroundColor: palette.textPrimary,
        shape: const StadiumBorder(),
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 18),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500),
      ),
    );
  }
}

class _PayloadChip extends StatelessWidget {
  final RelayPayloadVm selection;

  const _PayloadChip({required this.selection});

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).relayPalette;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 7, 14, 7),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: palette.accent.withValues(alpha: 0.1),
        border: Border.all(color: palette.accent.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.description_outlined, size: 17, color: palette.accentSoft),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              '${selection.fileCount} ${selection.fileCount == 1 ? 'file' : 'files'} · ${selection.totalBytes.asReadableFileSize}',
              key: const ValueKey('relay-payload-summary'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500, color: palette.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

class _TransferReadout extends StatelessWidget {
  final RelayTransferVm transfer;
  final bool compact;

  const _TransferReadout({required this.transfer, required this.compact});

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).relayPalette;
    final progress = transfer.progress;
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: compact ? 130 : 200),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Flexible(
                child: Text(
                  'Sending to ${transfer.targetAlias}',
                  key: const ValueKey('relay-transfer-destination'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: palette.textPrimary),
                ),
              ),
              if (progress != null) ...[
                const SizedBox(width: 8),
                Text(
                  '${(progress * 100).round()}%',
                  style: TextStyle(fontSize: 12.5, color: palette.textTertiary),
                ),
              ],
            ],
          ),
          const SizedBox(height: 7),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 3,
              backgroundColor: palette.softSurface,
              valueColor: AlwaysStoppedAnimation(palette.accent),
            ),
          ),
        ],
      ),
    );
  }
}
