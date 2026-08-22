import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:relay_app/config/relay_brand.dart';
import 'package:relay_app/model/persistence/color_mode.dart';
import 'package:relay_app/model/ui/relay_device_vm.dart';
import 'package:relay_app/pages/about/about_page.dart';
import 'package:relay_app/pages/changelog_page.dart';
import 'package:relay_app/pages/relay_home_vm.dart';
import 'package:relay_app/pages/tabs/settings_tab_controller.dart';
import 'package:relay_app/pages/tabs/settings_tab_vm.dart';
import 'package:relay_app/provider/kdeconnect_provider.dart';
import 'package:relay_app/provider/settings_provider.dart';
import 'package:relay_app/util/alias_generator.dart';
import 'package:relay_app/util/i18n.dart';
import 'package:relay_app/util/native/macos_channel.dart';
import 'package:relay_app/util/native/pick_directory_path.dart';
import 'package:relay_app/util/native/platform_check.dart';
import 'package:relay_app/util/ui/theme_mode_ext.dart';
import 'package:relay_app/widget/dialogs/file_name_input_dialog.dart';
import 'package:relay_app/widget/dialogs/relay_pair_device_dialog.dart';
import 'package:relay_app/widget/gnome/adw_action_row.dart';
import 'package:relay_app/widget/gnome/adw_boxed_list.dart';
import 'package:relay_app/widget/relay_motion/relay_section_reveal.dart';
import 'package:relay_isolates/model/device.dart';
import 'package:relay_isolates/rust/api/kdeconnect.dart';
import 'package:routerino/routerino.dart';
import 'package:yaru/yaru.dart';

/// Relay's settings in GNOME / Yaru design system.
class GnomeSettingsView extends StatelessWidget {
  final VoidCallback? onBack;

  const GnomeSettingsView({super.key, this.onBack});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ViewModelBuilder(
      provider: (ref) => settingsTabControllerProvider,
      builder: (context, vm) {
        final ref = context.ref;
        final deviceType = vm.settings.deviceType ?? DeviceType.desktop;
        final panelDevices = defaultTargetPlatform == TargetPlatform.linux
            ? ref.watch(relayHomeVmProvider).devices.where((device) => device.deviceType == DeviceType.mobile && device.isPaired).toList()
            : const <RelayDeviceVm>[];
        final currentPanelId = vm.settings.gnomePanelDeviceId;
        final panelValue = currentPanelId ?? _followSelectedDevice;
        final hasCurrentPanelDevice = currentPanelId == null || panelDevices.any((device) => device.key == currentPanelId);

        Widget group(String title, List<Widget> children, {int index = 0}) => RelaySectionReveal(
          index: index,
          animationsEnabled: vm.settings.enableAnimations,
          child: AdwPreferencesGroup(
            key: ValueKey('settings-group-${title.toLowerCase().replaceAll(' ', '-')}'),
            title: title,
            uppercaseTitle: false,
            margin: const EdgeInsets.only(bottom: 26),
            rowPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            rowMinHeight: 54,
            children: children,
          ),
        );

        return LayoutBuilder(
          builder: (context, constraints) {
            final horizontalPadding = constraints.maxWidth < 600 ? 16.0 : 32.0;
            return SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(horizontalPadding, 24, horizontalPadding, 36),
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  key: const ValueKey('gnome-settings-document'),
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      group('General', [
                        if (checkPlatformHasTray())
                          AdwSwitchRow(
                            title: 'Minimize to tray',
                            subtitle: 'Closing the window keeps Relay running in the background',
                            value: vm.settings.minimizeToTray,
                            onChanged: (b) async => ref.notifier(settingsProvider).setMinimizeToTray(b),
                          ),
                        AdwSwitchRow(
                          title: 'Start Relay at login',
                          subtitle: 'Launch Relay automatically when you sign in',
                          value: vm.autoStart,
                          onChanged: (_) => vm.onToggleAutoStart(context),
                        ),
                        if (vm.autoStart)
                          AdwSwitchRow(
                            title: 'Start hidden',
                            subtitle: 'Launch into the background without opening the window',
                            value: vm.autoStartLaunchHidden,
                            onChanged: (_) => vm.onToggleAutoStartLaunchHidden(context),
                          ),
                        AdwSwitchRow(
                          title: 'Spatial animations',
                          subtitle: 'Animate device and page transitions',
                          value: vm.settings.enableAnimations,
                          onChanged: (b) async => ref.notifier(settingsProvider).setEnableAnimations(b),
                        ),
                        _SettingsChoiceRow<ThemeMode>(
                          title: 'Theme',
                          value: vm.settings.theme,
                          valueLabel: vm.settings.theme.humanName,
                          choices: [for (final value in vm.themeModes) _SettingsChoice(value: value, label: value.humanName)],
                          onSelected: (value) => vm.onChangeTheme(context, value),
                        ),
                        _SettingsChoiceRow<ColorMode>(
                          title: 'Color theme',
                          value: vm.settings.colorMode,
                          valueLabel: vm.settings.colorMode.humanName,
                          choices: [for (final value in vm.colorModes) _SettingsChoice(value: value, label: value.humanName)],
                          onSelected: (value) => vm.onChangeColorMode(context, value),
                        ),
                        AdwNavigationRow(
                          leading: const Icon(YaruIcons.globe),
                          title: 'Language',
                          valueText: vm.settings.locale?.getLocaleName() ?? 'System',
                          onTap: () => vm.onTapLanguage(context),
                        ),
                      ]),

                      group('Devices', [
                        AdwNavigationRow(
                          leading: const Icon(YaruIcons.desktop),
                          title: 'Device name',
                          subtitle: _deviceDescription(deviceType),
                          valueText: vm.settings.alias,
                          onTap: () => unawaited(_editDeviceName(context, vm)),
                        ),
                        AdwActionRow(
                          leading: const Icon(YaruIcons.refresh),
                          title: 'Generate a random device name',
                          onTap: () => unawaited(_randomizeDeviceName(context, vm)),
                          trailing: const Icon(Icons.chevron_right_rounded, size: 18),
                        ),
                        AdwNavigationRow(
                          leading: const Icon(YaruIcons.plus),
                          title: 'Pair new device',
                          subtitle: 'Establish a trusted connection',
                          onTap: () => unawaited(
                            showDialog<void>(context: context, builder: (_) => const RelayPairDeviceDialog()),
                          ),
                        ),
                      ]),

                      group('Transfers', [
                        AdwNavigationRow(
                          leading: const Icon(YaruIcons.folder),
                          title: 'Destination directory',
                          valueText: vm.settings.destination ?? 'Default (Downloads)',
                          onTap: () async {
                            if (vm.settings.destination != null) {
                              await ref.notifier(settingsProvider).setDestination(null);
                              if (defaultTargetPlatform == TargetPlatform.macOS) {
                                await removeExistingDestinationAccess();
                              }
                              return;
                            }
                            final directory = await pickDirectoryPath();
                            if (directory != null) {
                              if (defaultTargetPlatform == TargetPlatform.macOS) {
                                await persistDestinationFolderAccess(directory);
                              }
                              await ref.notifier(settingsProvider).setDestination(directory);
                            }
                          },
                        ),
                        AdwSwitchRow(
                          title: 'Quick save',
                          subtitle: 'Accept incoming transfers without confirmation',
                          value: vm.settings.quickSave,
                          onChanged: (b) async => ref.notifier(settingsProvider).setQuickSave(b),
                        ),
                        AdwSwitchRow(
                          title: 'Quick save from favorites',
                          subtitle: 'Accept transfers automatically from favorite devices',
                          value: vm.settings.quickSaveFromFavorites,
                          onChanged: (b) async => ref.notifier(settingsProvider).setQuickSaveFromFavorites(b),
                        ),
                        AdwSwitchRow(
                          title: 'Save to history',
                          value: vm.settings.saveToHistory,
                          onChanged: (b) async => ref.notifier(settingsProvider).setSaveToHistory(b),
                        ),
                        AdwSwitchRow(
                          title: 'Finish completed transfers automatically',
                          value: vm.settings.autoFinish,
                          onChanged: (b) async => ref.notifier(settingsProvider).setAutoFinish(b),
                        ),
                      ]),

                      if (defaultTargetPlatform == TargetPlatform.linux)
                        group('GNOME Panel', [
                          _SettingsChoiceRow<String>(
                            title: 'Panel device',
                            leading: const Icon(YaruIcons.smartphone),
                            value: panelValue,
                            valueLabel: currentPanelId == null
                                ? 'Follow selected device'
                                : panelDevices.where((device) => device.key == currentPanelId).firstOrNull?.alias ?? currentPanelId,
                            choices: [
                              const _SettingsChoice(value: _followSelectedDevice, label: 'Follow selected device'),
                              for (final device in panelDevices) _SettingsChoice(value: device.key, label: device.alias),
                              if (!hasCurrentPanelDevice) _SettingsChoice(value: currentPanelId, label: currentPanelId),
                            ],
                            onSelected: (value) async =>
                                ref.notifier(settingsProvider).setGnomePanelDeviceId(value == _followSelectedDevice ? null : value),
                          ),
                          AdwSwitchRow(
                            title: 'Network type',
                            value: vm.settings.gnomePanelShowNetworkType,
                            onChanged: (b) async => ref.notifier(settingsProvider).setGnomePanelShowNetworkType(b),
                          ),
                          AdwSwitchRow(
                            title: 'Battery percentage',
                            value: vm.settings.gnomePanelShowBatteryPercentage,
                            onChanged: (b) async => ref.notifier(settingsProvider).setGnomePanelShowBatteryPercentage(b),
                          ),
                          AdwSwitchRow(
                            title: 'Notifications',
                            value: vm.settings.gnomePanelShowNotifications,
                            onChanged: (b) async => ref.notifier(settingsProvider).setGnomePanelShowNotifications(b),
                          ),
                          AdwSwitchRow(
                            title: 'Charging animation',
                            subtitle: 'Animate battery status in the GNOME top bar',
                            value: vm.settings.gnomePanelChargingAnimation,
                            onChanged: (b) async => ref.notifier(settingsProvider).setGnomePanelChargingAnimation(b),
                          ),
                        ]),

                      if (defaultTargetPlatform == TargetPlatform.linux)
                        group('Remote input', [
                          AdwSwitchRow(
                            title: 'Allow remote input',
                            subtitle: 'Let a paired phone act as a trackpad and keyboard',
                            value: ref.watch(kdeConnectProvider).remoteInputEnabled,
                            onChanged: (enabled) async =>
                                ref.redux(kdeConnectProvider).dispatchAsync(KdeConnectSetRemoteInputEnabledAction(enabled)),
                          ),
                          // Enabling is not sufficient: the desktop session has
                          // to grant input control, and only a person at this
                          // machine can approve that.
                          if (ref.watch(kdeConnectProvider).remoteInputEnabled)
                            AdwActionRow(
                              leading: const Icon(YaruIcons.keyboard),
                              title: 'Desktop permission',
                              subtitle: ref.watch(kdeConnectProvider).remoteInputReady
                                  ? 'Granted for this session'
                                  : 'Required before a phone can control this computer',
                              trailing: ref.watch(kdeConnectProvider).remoteInputReady
                                  ? OutlinedButton(
                                      onPressed: () async =>
                                          ref.redux(kdeConnectProvider).dispatchAsync(KdeConnectRevokeRemoteInputAction()),
                                      child: const Text('Revoke'),
                                    )
                                  : FilledButton(
                                      onPressed: () async =>
                                          ref.redux(kdeConnectProvider).dispatchAsync(KdeConnectAuthorizeRemoteInputAction()),
                                      child: const Text('Allow'),
                                    ),
                            ),
                        ]),

                      if (defaultTargetPlatform == TargetPlatform.linux)
                        group('Remote commands', [
                          for (final command in ref.watch(kdeConnectProvider).runCommands)
                            AdwActionRow(
                              key: ValueKey('run-command-${command.id}'),
                              leading: const Icon(YaruIcons.terminal),
                              title: command.name.isEmpty ? 'Untitled command' : command.name,
                              subtitle: command.command,
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  YaruSwitch(
                                    value: command.enabled,
                                    onChanged: (enabled) => _saveRunCommand(context, command.copyWithEnabled(enabled)),
                                  ),
                                  IconButton(
                                    icon: const Icon(YaruIcons.pen, size: 18),
                                    tooltip: 'Edit',
                                    onPressed: () => _editRunCommand(context, command),
                                  ),
                                  IconButton(
                                    icon: const Icon(YaruIcons.trash, size: 18),
                                    tooltip: 'Remove',
                                    onPressed: () => _removeRunCommand(context, command),
                                  ),
                                ],
                              ),
                            ),
                          AdwActionRow(
                            leading: const Icon(YaruIcons.plus),
                            title: 'Add command',
                            subtitle: 'Only commands listed here can be run from a paired phone',
                            onTap: () => _editRunCommand(context, null),
                          ),
                        ]),

                      group('Advanced', [
                        AdwActionRow(
                          leading: const Icon(YaruIcons.shield),
                          title: 'Transport encryption',
                          subtitle: 'Transfers between devices are encrypted in flight',
                          trailing: Text(
                            vm.settings.https ? 'Enabled' : 'Disabled',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: vm.settings.https ? YaruColors.of(context).success : YaruColors.of(context).warning,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        AdwSwitchRow(
                          title: 'Create checksums',
                          subtitle: 'Attach verification data to files you send',
                          value: vm.settings.createChecksums,
                          onChanged: (b) async => ref.notifier(settingsProvider).setCreateChecksums(b),
                        ),
                        AdwSwitchRow(
                          title: 'Verify checksums',
                          subtitle: 'Verify received files against sender checksums',
                          value: vm.settings.verifyChecksums,
                          onChanged: (b) async => ref.notifier(settingsProvider).setVerifyChecksums(b),
                        ),
                      ]),

                      group('About Relay', [
                        AdwNavigationRow(
                          leading: const Icon(YaruIcons.information),
                          title: 'About',
                          valueText: RelayProduct.name,
                          onTap: () => context.push(() => const AboutPage()),
                        ),
                        AdwNavigationRow(
                          leading: const Icon(YaruIcons.document),
                          title: 'Changelog',
                          onTap: () => context.push(() => const ChangelogPage()),
                        ),
                      ]),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

const _followSelectedDevice = '__follow_selected_device__';

String _deviceDescription(DeviceType deviceType) => switch (deviceType) {
  DeviceType.mobile => 'Mobile · Relay device',
  DeviceType.desktop => 'Desktop · Relay device',
  DeviceType.web => 'Web · Relay device',
  DeviceType.headless || DeviceType.server => 'Server · Relay device',
};

Future<void> _randomizeDeviceName(BuildContext context, SettingsTabVm vm) async {
  final newAlias = generateRandomAlias();
  vm.aliasController.text = newAlias;
  await context.ref.notifier(settingsProvider).setAlias(newAlias);
}

Future<void> _editDeviceName(BuildContext context, SettingsTabVm vm) async {
  final result = await showDialog<String>(
    context: context,
    builder: (_) => FileNameInputDialog(originalName: vm.settings.alias, initialName: vm.settings.alias),
  );
  if (result != null && result.trim().isNotEmpty && context.mounted) {
    vm.aliasController.text = result.trim();
    await context.ref.notifier(settingsProvider).setAlias(result.trim());
  }
}

/// Persists one added or edited command, leaving every other entry untouched.
Future<void> _saveRunCommand(BuildContext context, RsRunCommand command) async {
  final ref = context.ref;
  final current = ref.read(kdeConnectProvider).runCommands;
  final index = current.indexWhere((existing) => existing.id == command.id);
  final next = [...current];
  if (index >= 0) {
    next[index] = command;
  } else {
    next.add(command);
  }
  await ref.redux(kdeConnectProvider).dispatchAsync(KdeConnectSetRunCommandsAction(next));
}

Future<void> _removeRunCommand(BuildContext context, RsRunCommand command) async {
  final ref = context.ref;
  final next = ref.read(kdeConnectProvider).runCommands.where((existing) => existing.id != command.id).toList();
  await ref.redux(kdeConnectProvider).dispatchAsync(KdeConnectSetRunCommandsAction(next));
}

/// Opens the add/edit dialog. A new command gets its id from the Rust side, so
/// ids are generated the same way wherever they come from and stay stable once
/// written.
Future<void> _editRunCommand(BuildContext context, RsRunCommand? existing) async {
  final id = existing?.id ?? await kdeconnectNewRunCommandId();
  if (!context.mounted) return;
  final result = await showDialog<RsRunCommand>(
    context: context,
    builder: (_) => RunCommandDialog(
      command: existing ?? RsRunCommand(id: id, name: '', command: '', enabled: true),
      isNew: existing == null,
    ),
  );
  if (result != null && context.mounted) {
    await _saveRunCommand(context, result);
  }
}

extension _RunCommandCopy on RsRunCommand {
  RsRunCommand copyWithEnabled(bool enabled) => RsRunCommand(id: id, name: name, command: command, enabled: enabled);
}

/// Minimal add/edit form for one RunCommand entry. Public so its Save-enabling
/// behaviour can be tested directly.
class RunCommandDialog extends StatefulWidget {
  final RsRunCommand command;
  final bool isNew;

  const RunCommandDialog({required this.command, required this.isNew});

  @override
  State<RunCommandDialog> createState() => _RunCommandDialogState();
}

class _RunCommandDialogState extends State<RunCommandDialog> {
  late final TextEditingController _name = TextEditingController(text: widget.command.name);
  late final TextEditingController _command = TextEditingController(text: widget.command.command);
  late bool _enabled = widget.command.enabled;

  @override
  void initState() {
    super.initState();
    // Save is enabled only once a command line exists, and that is decided at
    // build time -- so the field has to rebuild the dialog as it is typed into.
    // Without this the button stays disabled forever on a new command, because
    // it is first built while the field is still empty.
    _command.addListener(_onCommandChanged);
  }

  void _onCommandChanged() => setState(() {});

  @override
  void dispose() {
    _command.removeListener(_onCommandChanged);
    _name.dispose();
    _command.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.isNew ? 'Add command' : 'Edit command'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _name,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Name', hintText: 'Lock screen'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _command,
            decoration: const InputDecoration(labelText: 'Command', hintText: 'loginctl lock-session'),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              YaruSwitch(value: _enabled, onChanged: (value) => setState(() => _enabled = value)),
              const SizedBox(width: 12),
              const Expanded(child: Text('Allow paired phones to run this')),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(
          onPressed: _command.text.trim().isEmpty
              ? null
              : () => Navigator.of(context).pop(
                  RsRunCommand(
                    id: widget.command.id,
                    name: _name.text.trim(),
                    command: _command.text.trim(),
                    enabled: _enabled,
                  ),
                ),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _SettingsChoice<T> {
  final T value;
  final String label;

  const _SettingsChoice({required this.value, required this.label});
}

class _SettingsChoiceRow<T> extends StatefulWidget {
  final Widget? leading;
  final String title;
  final T value;
  final String valueLabel;
  final List<_SettingsChoice<T>> choices;
  final ValueChanged<T> onSelected;

  const _SettingsChoiceRow({
    this.leading,
    required this.title,
    required this.value,
    required this.valueLabel,
    required this.choices,
    required this.onSelected,
  });

  @override
  State<_SettingsChoiceRow<T>> createState() => _SettingsChoiceRowState<T>();
}

class _SettingsChoiceRowState<T> extends State<_SettingsChoiceRow<T>> {
  final _menuKey = GlobalKey<PopupMenuButtonState<T>>();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AdwActionRow(
      leading: widget.leading,
      title: widget.title,
      onTap: () => _menuKey.currentState?.showButtonMenu(),
      trailing: IgnorePointer(
        child: PopupMenuButton<T>(
          key: _menuKey,
          initialValue: widget.value,
          tooltip: '',
          onSelected: widget.onSelected,
          itemBuilder: (context) => [
            for (final choice in widget.choices)
              PopupMenuItem<T>(
                value: choice.value,
                child: Row(
                  children: [
                    Expanded(child: Text(choice.label)),
                    if (choice.value == widget.value) Icon(YaruIcons.ok, size: 18, color: theme.colorScheme.primary),
                  ],
                ),
              ),
          ],
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 240),
                child: Text(
                  widget.valueLabel,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right_rounded, size: 18, color: theme.colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
