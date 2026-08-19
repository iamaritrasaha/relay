import 'package:flutter/material.dart';
import 'package:relay_app/config/relay_brand.dart';
import 'package:relay_app/pages/relay_home_vm.dart';
import 'package:relay_app/widget/relay/nearby_stage.dart';
import 'package:relay_app/widget/relay/payload_dock.dart';
import 'package:relay_app/widget/relay/relay_desktop_metrics.dart';
import 'package:relay_app/widget/relay/relay_top_bar.dart';
import 'package:relay_app/widget/relay/self_identity_block.dart';
import 'package:relay_app/widget/relay_symbol.dart';

/// Relay's Home surface.
///
/// Desktop is composed as three regions with fixed jobs — a quiet identity bar,
/// the nearby field which owns all the vertical slack, and the payload dock
/// anchored at the bottom. Narrow windows (and therefore phones) fall back to
/// the scrolling column composition through the same width breakpoint the rest
/// of the app uses.
class RelayShell extends StatelessWidget {
  final RelayHomeVm vm;
  final bool animationsEnabled;
  final ValueChanged<String>? onDeviceTap;
  final VoidCallback onSelectPayload;
  final VoidCallback? onClearPayload;
  final VoidCallback? onCancelTransfer;
  final VoidCallback? onOpenHistory;
  final VoidCallback? onOpenSettings;
  final VoidCallback? onPairDevice;

  const RelayShell({
    required this.vm,
    required this.animationsEnabled,
    required this.onSelectPayload,
    this.onClearPayload,
    this.onCancelTransfer,
    this.onDeviceTap,
    this.onOpenHistory,
    this.onOpenSettings,
    this.onPairDevice,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final desktop = RelayDesktopMetrics.isDesktopWidth(constraints.maxWidth);
            final metrics = RelayDesktopMetrics.resolve(constraints.biggest);
            return Column(
              children: [
                RelayTopBar.brand(
                  horizontalInset: desktop ? metrics.topBarInset : 12,
                  wordmark: const _Wordmark(),
                  presence: SelfIdentityBlock(alias: vm.selfAlias, presence: vm.presence),
                  actions: [
                    RelayTopBarAction(
                      key: const ValueKey('relay-pair-device-button'),
                      icon: Icons.add_link_rounded,
                      tooltip: 'Add Relay device',
                      onPressed: onPairDevice,
                    ),
                    RelayTopBarAction(
                      key: const ValueKey('relay-history-button'),
                      icon: Icons.history_rounded,
                      tooltip: 'History',
                      onPressed: onOpenHistory,
                    ),
                    RelayTopBarAction(
                      key: const ValueKey('relay-settings-button'),
                      icon: Icons.tune_rounded,
                      tooltip: 'Settings',
                      onPressed: onOpenSettings,
                    ),
                  ],
                ),
                Expanded(
                  child: desktop ? _DesktopBody(shell: this, metrics: metrics) : _MobileBody(shell: this),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  String get _fieldMeta {
    final transfer = vm.activeTransfer;
    if (transfer != null) {
      return 'Sending to ${transfer.targetAlias}';
    }
    if (vm.devices.isEmpty) {
      return switch (vm.presence) {
        RelayPresence.offline => 'Not listening',
        RelayPresence.discovering => 'Looking for devices',
        RelayPresence.ready => 'Listening on this network',
      };
    }
    return '${vm.devices.length} ${vm.devices.length == 1 ? 'device' : 'devices'}';
  }

  Widget _stage({required bool compact, RelayResponsiveMetrics? metrics}) => NearbyStage(
    devices: vm.devices,
    selfDeviceType: vm.selfDeviceType,
    animationsEnabled: animationsEnabled,
    payloadSelected: !vm.selection.isEmpty,
    compact: compact,
    metrics: metrics,
    onDeviceTap: vm.intents.canChooseTarget ? (device) => onDeviceTap?.call(device.key) : null,
  );

  Widget _dock({required bool compact, RelayResponsiveMetrics? metrics}) => PayloadDock(
    selection: vm.selection,
    transfer: vm.activeTransfer,
    compact: compact,
    metrics: metrics,
    onSelect: onSelectPayload,
    onClear: vm.selection.isEmpty ? null : onClearPayload,
    onCancelTransfer: vm.activeTransfer == null ? null : onCancelTransfer,
  );
}

class _Wordmark extends StatelessWidget {
  const _Wordmark();

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).relayPalette;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const RelaySymbol(size: 22),
        const SizedBox(width: 11),
        Flexible(
          child: Text(
            RelayProduct.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 16, height: 1.2, fontWeight: FontWeight.w600, color: palette.textPrimary),
          ),
        ),
      ],
    );
  }
}

class _DesktopBody extends StatelessWidget {
  final RelayShell shell;
  final RelayResponsiveMetrics metrics;

  const _DesktopBody({required this.shell, required this.metrics});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final frameWidth = constraints.maxWidth - metrics.horizontalGutter * 2;
        return Center(
          child: SizedBox(
            width: frameWidth.clamp(0, metrics.maxContentWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(0, metrics.headingTopSpacing, 0, metrics.headingBottomSpacing),
                  child: _FieldHeading(meta: shell._fieldMeta),
                ),
                Expanded(child: shell._stage(compact: false, metrics: metrics)),
                Padding(
                  padding: EdgeInsets.only(top: 20, bottom: metrics.dockBottomSpacing),
                  child: Align(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: metrics.payloadDockMaxWidth),
                      child: shell._dock(compact: false, metrics: metrics),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Mobile-native composition: the nearby field owns the scrollable space and
/// the transforming payload control stays in the lower thumb zone.
class _MobileBody extends StatelessWidget {
  final RelayShell shell;

  const _MobileBody({required this.shell});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(RelayDesktopMetrics.compactGutter, 18, RelayDesktopMetrics.compactGutter, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 6, bottom: 12),
                  child: _FieldHeading(meta: shell._fieldMeta),
                ),
                Expanded(child: shell._stage(compact: true)),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(RelayDesktopMetrics.compactGutter, 8, RelayDesktopMetrics.compactGutter, 14),
          child: SizedBox(width: double.infinity, child: shell._dock(compact: true)),
        ),
      ],
    );
  }
}

class _FieldHeading extends StatelessWidget {
  final String meta;

  const _FieldHeading({required this.meta});

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).relayPalette;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text('NEARBY', style: RelayTypography.section(palette.textSecondary)),
        const SizedBox(width: 24),
        Expanded(
          child: Text(
            meta,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.end,
            style: TextStyle(fontSize: 12.5, color: palette.textTertiary),
          ),
        ),
      ],
    );
  }
}
