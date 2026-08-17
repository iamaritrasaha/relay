import 'dart:async';

import 'package:flutter/material.dart';
import 'package:localsend_app/pages/relay_home_vm.dart';
import 'package:localsend_app/provider/animation_provider.dart';
import 'package:localsend_app/provider/network/nearby_devices_provider.dart';
import 'package:localsend_app/provider/network/send_provider.dart';
import 'package:localsend_app/provider/selection/selected_sending_files_provider.dart';
import 'package:localsend_app/util/native/file_picker.dart';
import 'package:localsend_app/widget/dialogs/add_file_dialog.dart';
import 'package:localsend_app/widget/dialogs/cancel_session_dialog.dart';
import 'package:localsend_app/widget/relay/relay_shell.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:routerino/routerino.dart';

/// Relay's Home surface, mounted as the first page of [HomePage]'s page view.
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
        return RelayShell(
          vm: vm,
          animationsEnabled: animationsEnabled,
          onSelectPayload: () => unawaited(AddFileDialog.open(context: context, options: FilePickerOption.getOptionsForPlatform())),
          onClearPayload: () => ref.redux(selectedSendingFilesProvider).dispatch(ClearSelectionAction()),
          onCancelTransfer: () async {
            final sessionId = vm.activeTransfer?.sessionId;
            if (sessionId != null && await context.pushBottomSheet(() => const CancelSessionDialog()) == true) {
              ref.notifier(sendProvider).cancelSession(sessionId);
            }
          },
          onOpenHistory: onOpenHistory,
          onOpenSettings: onOpenSettings,
          onDeviceTap: (key) {
            final device = ref.read(nearbyDevicesProvider).allDevices[key];
            final files = ref.read(selectedSendingFilesProvider);
            if (device != null && files.isNotEmpty) {
              unawaited(ref.notifier(sendProvider).startSession(target: device, files: files, background: true));
            }
          },
        );
      },
    );
  }
}
