import 'package:flutter/material.dart';
import 'package:relay_app/gen/strings.g.dart';
import 'package:relay_app/widget/relay/relay_dialog.dart';
import 'package:routerino/routerino.dart';

class ErrorDialog extends StatelessWidget {
  final String error;

  const ErrorDialog({required this.error, super.key});

  @override
  Widget build(BuildContext context) {
    return RelayDialog(
      title: t.dialogs.errorDialog.title,
      actions: [
        TextButton(
          style: relayQuietButtonStyle(context),
          onPressed: () => context.pop(),
          child: Text(t.general.close),
        ),
      ],
      child: SelectableText(error),
    );
  }
}
