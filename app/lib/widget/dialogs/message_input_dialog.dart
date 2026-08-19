import 'package:flutter/material.dart';
import 'package:relay_app/gen/strings.g.dart';
import 'package:relay_app/widget/relay/relay_dialog.dart';
import 'package:routerino/routerino.dart';

class MessageInputDialog extends StatefulWidget {
  final String? initialText;

  const MessageInputDialog({this.initialText});

  @override
  State<MessageInputDialog> createState() => _MessageInputDialogState();
}

class _MessageInputDialogState extends State<MessageInputDialog> {
  final _textController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _textController.text = widget.initialText ?? '';
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RelayDialog(
      title: t.dialogs.messageInput.title,
      actions: [
        TextButton(
          style: relayQuietButtonStyle(context),
          onPressed: () => context.pop(),
          child: Text(t.general.cancel),
        ),
        FilledButton(
          style: relayPrimaryButtonStyle(context),
          onPressed: () => context.pop(_textController.text),
          child: Text(t.general.confirm),
        ),
      ],
      child: TextFormField(
        controller: _textController,
        keyboardType: TextInputType.multiline,
        maxLines: null,
        autofocus: true,
      ),
    );
  }
}
