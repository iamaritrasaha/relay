import 'package:flutter/material.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:relay_app/pages/gnome/gnome_shell.dart';
import 'package:relay_app/pages/relay_home_vm.dart';
import 'package:relay_app/provider/animation_provider.dart';
import 'package:relay_app/widget/dialogs/kdeconnect_incoming_pair_dialog.dart';
import 'package:relay_app/widget/dialogs/relay_incoming_pair_request_dialog.dart';
import 'package:relay_app/widget/dialogs/relay_pair_device_dialog.dart';

/// Relay's Root Home surface, mounted as the primary page of [HomePage].
///
/// Deliberately renders the GNOME Libadwaita presentation shell for Relay Linux.
class RelayHomePage extends StatelessWidget {
  final VoidCallback? onOpenHistory;
  final VoidCallback? onOpenSettings;

  const RelayHomePage({super.key, this.onOpenHistory, this.onOpenSettings});

  @override
  Widget build(BuildContext context) {
    return ViewModelBuilder(
      provider: (ref) => relayHomeVmProvider,
      builder: (context, vm) {
        final ref = context.ref;
        final animationsEnabled = ref.watch(animationProvider);

        // A pairing request must reach the user wherever they are, so the
        // prompt is hosted above the shell rather than inside one screen.
        return RelayIncomingPairRequestHost(
          child: KdeConnectIncomingPairHost(
            child: GnomeShell(
              vm: vm,
              animationsEnabled: animationsEnabled,
              onOpenHistory: onOpenHistory,
              onOpenSettings: onOpenSettings,
              onPairDevice: () => showDialog<void>(context: context, builder: (_) => const RelayPairDeviceDialog()),
            ),
          ),
        );
      },
    );
  }
}
