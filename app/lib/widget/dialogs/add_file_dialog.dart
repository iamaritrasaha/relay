import 'package:flutter/material.dart';
import 'package:localsend_app/config/relay_brand.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/util/native/file_picker.dart';
import 'package:localsend_app/util/native/platform_check.dart';
import 'package:refena_flutter/addons.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:routerino/routerino.dart';

/// Relay-native payload selection surface. The picker actions themselves remain
/// owned by [PickFileAction]; this widget changes presentation only.
class AddFileDialog extends StatelessWidget {
  final List<FilePickerOption> options;
  final ValueChanged<FilePickerOption>? onOptionSelected;
  final bool mobile;

  const AddFileDialog({required this.options, this.onOptionSelected, this.mobile = false, super.key});

  static Future<void> open({required BuildContext context, required List<FilePickerOption> options}) async {
    if (checkPlatformIsDesktop()) {
      await showDialog<void>(
        context: context,
        builder: (_) => Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: AddFileDialog(options: options),
          ),
        ),
      );
    } else {
      await context.pushBottomSheet(() => SafeArea(top: false, child: AddFileDialog(options: options, mobile: true)));
    }
  }

  Future<void> _select(BuildContext context, FilePickerOption option) async {
    if (onOptionSelected != null) {
      onOptionSelected!(option);
      return;
    }
    final ref = context.ref;
    await ref.global.dispatchAsync(PickFileAction(option: option, context: context));
    ref.global.dispatch(NavigateAction.popUntilRoot());
  }

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).relayPalette;
    final radius = BorderRadius.vertical(top: const Radius.circular(22), bottom: Radius.circular(mobile ? 0 : 22));
    return Material(
      key: const ValueKey('relay-add-selection-surface'),
      color: palette.elevated,
      borderRadius: radius,
      clipBehavior: Clip.antiAlias,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: palette.hairline),
          borderRadius: radius,
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(mobile ? 20 : 28, mobile ? 22 : 28, mobile ? 20 : 28, mobile ? 24 : 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t.dialogs.addFile.title,
                          key: const ValueKey('relay-add-selection-title'),
                          style: TextStyle(fontSize: mobile ? 21 : 23, height: 1.2, fontWeight: FontWeight.w600, color: palette.textPrimary),
                        ),
                        const SizedBox(height: 7),
                        Text(t.dialogs.addFile.content, style: TextStyle(fontSize: 13.5, height: 1.4, color: palette.textSecondary)),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: t.general.close,
                    onPressed: () => context.pop(),
                    style: IconButton.styleFrom(foregroundColor: palette.textSecondary, backgroundColor: palette.softSurface),
                    icon: const Icon(Icons.close_rounded, size: 19),
                  ),
                ],
              ),
              SizedBox(height: mobile ? 22 : 26),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: mobile ? 10 : 12,
                  mainAxisSpacing: mobile ? 10 : 12,
                  childAspectRatio: mobile ? 1.55 : 2.15,
                ),
                itemCount: options.length,
                itemBuilder: (context, index) {
                  final option = options[index];
                  return _RelayPickerAction(
                    key: ValueKey('relay-picker-${option.name}'),
                    option: option,
                    onPressed: () => _select(context, option),
                  );
                },
              ),
              if (!mobile) ...[
                const SizedBox(height: 18),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => context.pop(),
                    style: TextButton.styleFrom(foregroundColor: palette.textSecondary),
                    child: Text(t.general.cancel),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _RelayPickerAction extends StatelessWidget {
  final FilePickerOption option;
  final VoidCallback onPressed;

  const _RelayPickerAction({required this.option, required this.onPressed, super.key});

  String get helper => switch (option) {
    FilePickerOption.file => 'Choose one or more files',
    FilePickerOption.folder => 'Share a folder and its contents',
    FilePickerOption.media => 'Choose photos or videos',
    FilePickerOption.text => 'Write a short message',
    FilePickerOption.app => 'Choose an installed app',
    FilePickerOption.clipboard => 'Use copied text, image, or files',
  };

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).relayPalette;
    return Material(
      color: palette.softSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(13),
        side: BorderSide(color: palette.hairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        focusColor: palette.accent.withValues(alpha: 0.12),
        hoverColor: palette.accent.withValues(alpha: 0.075),
        splashColor: palette.accent.withValues(alpha: 0.12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(color: palette.accent.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                child: Icon(option.icon, size: 19, color: palette.accentSoft),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      option.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: palette.textPrimary),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      helper,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11.5, height: 1.25, color: palette.textTertiary),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
