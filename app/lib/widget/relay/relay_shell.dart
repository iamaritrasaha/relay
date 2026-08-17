import 'package:flutter/material.dart';
import 'package:localsend_app/pages/relay_home_vm.dart';
import 'package:localsend_app/widget/relay/nearby_stage.dart';
import 'package:localsend_app/widget/relay/payload_dock.dart';
import 'package:localsend_app/widget/relay/self_identity_block.dart';

class RelayShell extends StatelessWidget {
  final RelayHomeVm vm;
  final bool animationsEnabled;
  final ValueChanged<String>? onDeviceTap;
  final VoidCallback onSelectPayload;
  final VoidCallback? onClearPayload;

  const RelayShell({
    required this.vm,
    required this.animationsEnabled,
    required this.onSelectPayload,
    this.onClearPayload,
    this.onDeviceTap,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxHeight < 720 || constraints.maxWidth < 600;
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 980),
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(32, compact ? 20 : 28, 32, compact ? 24 : 34),
                  child: Column(
                    children: [
                      _RelayHeader(alias: vm.selfAlias, presence: vm.presence),
                      SizedBox(height: compact ? 34 : 52),
                      NearbyStage(
                        devices: vm.devices,
                        animationsEnabled: animationsEnabled,
                        payloadSelected: !vm.selection.isEmpty,
                        onDeviceTap: vm.intents.canChooseTarget ? (device) => onDeviceTap?.call(device.key) : null,
                      ),
                      SizedBox(height: compact ? 18 : 28),
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

  const _RelayHeader({required this.alias, required this.presence});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Relay', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            SelfIdentityBlock(alias: alias, presence: presence),
          ],
        ),
        const Spacer(),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            children: [
              Text('History', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
              const SizedBox(width: 24),
              Text('Settings', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ],
          ),
        ),
      ],
    );
  }
}
