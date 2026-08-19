import 'package:flutter/material.dart';
import 'package:localsend_app/pages/android/android_shell.dart';
import 'package:localsend_app/pages/gnome/gnome_shell.dart';
import 'package:localsend_app/pages/relay_home_vm.dart';
import 'package:localsend_app/provider/animation_provider.dart';
import 'package:localsend_app/util/native/platform_check.dart';
import 'package:localsend_app/widget/dialogs/relay_pair_device_dialog.dart';
import 'package:refena_flutter/refena_flutter.dart';

/// Relay's Root Home surface, mounted as the primary page of [HomePage].
///
/// Deliberately selects the GNOME Libadwaita presentation shell on Linux / Desktop
/// and the Material 3 presentation shell on Android / Mobile, ensuring native
/// hierarchy, navigation, and interaction patterns on each target platform.
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

        if (checkPlatformIsDesktop()) {
          return GnomeShell(
            vm: vm,
            animationsEnabled: animationsEnabled,
            onOpenHistory: onOpenHistory,
            onOpenSettings: onOpenSettings,
            onPairDevice: () => showDialog<void>(context: context, builder: (_) => const RelayPairDeviceDialog()),
          );
        }

        return AndroidShell(
          vm: vm,
          animationsEnabled: animationsEnabled,
          onPairDevice: () => showDialog<void>(context: context, builder: (_) => const RelayPairDeviceDialog()),
        );
      },
    );
  }
}
