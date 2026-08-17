import 'package:flutter/material.dart';
import 'package:localsend_app/pages/relay_home_vm.dart';
import 'package:localsend_app/widget/relay/nearby_stage.dart';
import 'package:localsend_app/widget/relay/payload_dock.dart';
import 'package:localsend_app/widget/relay/self_identity_block.dart';
import 'package:localsend_app/widget/relay_symbol.dart';

class RelayShell extends StatelessWidget {
  final RelayHomeVm vm;
  final bool animationsEnabled;
  final ValueChanged<String>? onDeviceTap;
  final VoidCallback onSelectPayload;
  final VoidCallback? onClearPayload;
  final VoidCallback? onOpenHistory;
  final VoidCallback? onOpenSettings;

  const RelayShell({
    required this.vm,
    required this.animationsEnabled,
    required this.onSelectPayload,
    this.onClearPayload,
    this.onDeviceTap,
    this.onOpenHistory,
    this.onOpenSettings,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxHeight < 720 || constraints.maxWidth < 600;
            final mobile = constraints.maxWidth < 600;
            return Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 980),
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(mobile ? 22 : 40, mobile ? 20 : 32, mobile ? 22 : 40, mobile ? 28 : 42),
                  child: Column(
                    children: [
                      _RelayHeader(
                        alias: vm.selfAlias,
                        presence: vm.presence,
                        onOpenHistory: onOpenHistory,
                        onOpenSettings: onOpenSettings,
                      ),
                      SizedBox(height: compact ? 35 : 58),
                      NearbyStage(
                        devices: vm.devices,
                        animationsEnabled: animationsEnabled,
                        payloadSelected: !vm.selection.isEmpty,
                        onDeviceTap: vm.intents.canChooseTarget ? (device) => onDeviceTap?.call(device.key) : null,
                      ),
                      SizedBox(height: compact ? 25 : 34),
                      PayloadDock(selection: vm.selection, onSelect: onSelectPayload, onClear: onClearPayload),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _RelayHeader extends StatelessWidget {
  final String alias;
  final RelayPresence presence;
  final VoidCallback? onOpenHistory;
  final VoidCallback? onOpenSettings;

  const _RelayHeader({required this.alias, required this.presence, this.onOpenHistory, this.onOpenSettings});

  @override
  Widget build(BuildContext context) {
    final wordmark = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const RelaySymbol(size: 29),
        const SizedBox(width: 10),
        Text('Relay', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600)),
      ],
    );
    final actions = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Tooltip(
          message: 'History',
          child: IconButton(key: const ValueKey('relay-history-button'), onPressed: onOpenHistory, icon: const Icon(Icons.history_outlined)),
        ),
        const SizedBox(width: 4),
        Tooltip(
          message: 'Settings',
          child: IconButton(key: const ValueKey('relay-settings-button'), onPressed: onOpenSettings, icon: const Icon(Icons.tune_rounded)),
        ),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 500) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [wordmark, const Spacer(), actions]),
              const SizedBox(height: 10),
              SelfIdentityBlock(alias: alias, presence: presence),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                wordmark,
                const SizedBox(height: 9),
                SelfIdentityBlock(alias: alias, presence: presence),
              ],
            ),
            const Spacer(),
            Padding(padding: const EdgeInsets.only(top: 3), child: actions),
          ],
        );
      },
    );
  }
}
