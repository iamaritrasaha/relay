import 'package:flutter/material.dart';
import 'package:relay_app/gen/strings.g.dart';
import 'package:relay_app/widget/relay/relay_dialog.dart';
import 'package:routerino/routerino.dart';

class NoPermissionDialog extends StatelessWidget {
  const NoPermissionDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return RelayDialog(
      title: t.dialogs.noPermission.title,
      actions: [
        TextButton(
          style: relayQuietButtonStyle(context),
          onPressed: () => context.pop(),
          child: Text(t.general.close),
        ),
      ],
      child: Text(t.dialogs.noPermission.content),
    );
  }
}
