import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:relay_app/config/relay_brand.dart';
import 'package:relay_app/model/persistence/color_mode.dart';
import 'package:relay_app/pages/about/about_page.dart';
import 'package:relay_app/pages/changelog_page.dart';
import 'package:relay_app/pages/tabs/settings_tab_controller.dart';
import 'package:relay_app/pages/tabs/settings_tab_vm.dart';
import 'package:relay_app/pages/relay_home_vm.dart';
import 'package:relay_app/provider/settings_provider.dart';
import 'package:relay_app/util/alias_generator.dart';
import 'package:relay_app/util/i18n.dart';
import 'package:relay_app/util/native/macos_channel.dart';
import 'package:relay_app/util/native/pick_directory_path.dart';
import 'package:relay_app/util/native/platform_check.dart';
import 'package:relay_app/util/ui/theme_mode_ext.dart';
import 'package:relay_app/widget/custom_dropdown_button.dart';
import 'package:relay_app/widget/dialogs/file_name_input_dialog.dart';
import 'package:relay_app/widget/dialogs/relay_pair_device_dialog.dart';
import 'package:relay_app/widget/gnome/adw_button.dart';
import 'package:relay_app/widget/relay/relay_device_silhouette.dart';
import 'package:relay_app/widget/relay_carbon/relay_settings.dart';
import 'package:relay_app/widget/relay_carbon/relay_surface.dart';
import 'package:relay_isolates/model/device.dart';
import 'package:routerino/routerino.dart';

/// Relay's settings, in Relay's own visual language.
///
/// Sections are headings and rules rather than boxes, which is what keeps this
/// page reading as the same product as the overview. Every row here maps to a
/// setting that already exists — nothing is surfaced that Relay cannot act on.
class GnomeSettingsView extends StatelessWidget {
  final VoidCallback? onBack;

  const GnomeSettingsView({super.key, this.onBack});

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).relayPalette;

    return ViewModelBuilder(
      provider: (ref) => settingsTabControllerProvider,
      builder: (context, vm) {
        final ref = context.ref;
        final deviceType = vm.settings.deviceType ?? DeviceType.desktop;

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(44, 30, 44, 56),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      if (onBack != null) ...[
                        AdwButton.flat(icon: Icons.arrow_back_rounded, label: 'Back', onPressed: onBack),
                        const SizedBox(width: 14),
                      ],
                      Expanded(
                        child: Text('Settings', style: RelayTypography.deviceName(palette.textPrimary)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),

                  _ThisDevice(vm: vm, deviceType: deviceType),
                  const SizedBox(height: 34),

                  RelaySettingsSection(
                    title: 'General',
                    children: [
                      if (checkPlatformHasTray())
                        RelaySettingsSwitchRow(
                          title: 'Minimize to tray',
                          subtitle: 'Closing the window keeps Relay running in the background',
                          value: vm.settings.minimizeToTray,
                          onChanged: (b) async => ref.notifier(settingsProvider).setMinimizeToTray(b),
                        ),
                      RelaySettingsSwitchRow(
                        title: 'Start Relay at login',
                        subtitle: 'Relay is ready as soon as you sign in',
                        value: vm.autoStart,
                        onChanged: (_) => vm.onToggleAutoStart(context),
                      ),
                      if (vm.autoStart)
                        RelaySettingsSwitchRow(
                          title: 'Start hidden',
                          subtitle: 'Launch into the background without opening the window',
                          value: vm.autoStartLaunchHidden,
                          onChanged: (_) => vm.onToggleAutoStartLaunchHidden(context),
                        ),
                      RelaySettingsSwitchRow(
                        title: 'Spatial Animations',
                        subtitle: 'Devices move between the hero and the dock as you switch between them',
                        value: vm.settings.enableAnimations,
                        onChanged: (b) async => ref.notifier(settingsProvider).setEnableAnimations(b),
                      ),
                    ],
                  ),

                  RelaySettingsSection(
                    title: 'Devices',
                    children: [
                      RelaySettingsNavRow(
                        title: 'Pair New Device',
                        subtitle: 'Establish a trusted connection with another device',
                        onTap: () => unawaited(
                          showDialog<void>(context: context, builder: (_) => const RelayPairDeviceDialog()),
                        ),
                      ),
                    ],
                  ),

                  if (defaultTargetPlatform == TargetPlatform.linux) ...[
                    () {
                      final homeVm = ref.watch(relayHomeVmProvider);
                      final pairedPhones = homeVm.devices.where((d) => d.deviceType == DeviceType.mobile && d.isPaired).toList();
                      final currentPanelId = vm.settings.gnomePanelDeviceId;
                      final hasCurrentInList = currentPanelId == null || pairedPhones.any((d) => d.key == currentPanelId);

                      return RelaySettingsSection(
                        title: 'GNOME Panel',
                        children: [
                          RelaySettingsDropdownRow<String?>(
                            title: 'Panel device',
                            subtitle: 'Choose which phone appears in the GNOME top bar',
                            value: currentPanelId,
                            items: [
                              const DropdownMenuItem<String?>(
                                value: null,
                                child: Text('Follow selected device'),
                              ),
                              for (final device in pairedPhones)
                                DropdownMenuItem<String?>(
                                  value: device.key,
                                  child: Text(device.alias),
                                ),
                              if (!hasCurrentInList && currentPanelId != null)
                                DropdownMenuItem<String?>(
                                  value: currentPanelId,
                                  child: Text(currentPanelId),
                                ),
                            ],
                            onChanged: (key) async => ref.notifier(settingsProvider).setGnomePanelDeviceId(key),
                          ),
                          RelaySettingsSwitchRow(
                            title: 'Show network type',
                            subtitle: 'Present mobile generation (LTE, 5G) in the top bar',
                            value: vm.settings.gnomePanelShowNetworkType,
                            onChanged: (b) async => ref.notifier(settingsProvider).setGnomePanelShowNetworkType(b),
                          ),
                          RelaySettingsSwitchRow(
                            title: 'Show battery percentage',
                            subtitle: 'Display numerical charge alongside the battery icon',
                            value: vm.settings.gnomePanelShowBatteryPercentage,
                            onChanged: (b) async => ref.notifier(settingsProvider).setGnomePanelShowBatteryPercentage(b),
                          ),
                          RelaySettingsSwitchRow(
                            title: 'Show notifications indicator',
                            subtitle: 'Display the notification bell when messages or alerts arrive',
                            value: vm.settings.gnomePanelShowNotifications,
                            onChanged: (b) async => ref.notifier(settingsProvider).setGnomePanelShowNotifications(b),
                          ),
                          RelaySettingsSwitchRow(
                            title: 'Charging animation',
                            subtitle: 'Subtle warmth glow on the battery icon while charging',
                            value: vm.settings.gnomePanelChargingAnimation,
                            onChanged: (b) async => ref.notifier(settingsProvider).setGnomePanelChargingAnimation(b),
                          ),
                        ],
                      );
                    }(),
                  ],

                  RelaySettingsSection(
                    title: 'Transfers',
                    children: [
                      RelaySettingsNavRow(
                        title: 'Destination Directory',
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
                      RelaySettingsSwitchRow(
                        title: 'Quick Save',
                        subtitle: 'Automatically accept incoming transfers without manual confirmation',
                        value: vm.settings.quickSave,
                        onChanged: (b) async => ref.notifier(settingsProvider).setQuickSave(b),
                      ),
                      RelaySettingsSwitchRow(
                        title: 'Quick Save from Favorites',
                        subtitle: 'Automatically accept transfers from devices marked as favorites',
                        value: vm.settings.quickSaveFromFavorites,
                        onChanged: (b) async => ref.notifier(settingsProvider).setQuickSaveFromFavorites(b),
                      ),
                      RelaySettingsSwitchRow(
                        title: 'Save to History',
                        subtitle: 'Record completed file transfers in Activity',
                        value: vm.settings.saveToHistory,
                        onChanged: (b) async => ref.notifier(settingsProvider).setSaveToHistory(b),
                      ),
                      RelaySettingsSwitchRow(
                        title: 'Auto-Finish',
                        subtitle: 'Close completed transfer sessions on their own',
                        value: vm.settings.autoFinish,
                        onChanged: (b) async => ref.notifier(settingsProvider).setAutoFinish(b),
                      ),
                    ],
                  ),

                  RelaySettingsSection(
                    title: 'Privacy & Security',
                    children: [
                      // Reported, not offered: turning transport encryption off
                      // restarts the server, so that decision stays where it
                      // already lives rather than becoming a one-tap switch here.
                      RelaySettingsValueRow(
                        title: 'Transport encryption',
                        subtitle: 'Transfers between devices are encrypted in flight',
                        value: vm.settings.https ? 'Enabled' : 'Disabled',
                        tint: vm.settings.https ? palette.success : palette.warning,
                      ),
                      RelaySettingsSwitchRow(
                        title: 'Create checksums',
                        subtitle: 'Attach a checksum to files you send so the other device can verify them',
                        value: vm.settings.createChecksums,
                        onChanged: (b) async => ref.notifier(settingsProvider).setCreateChecksums(b),
                      ),
                      RelaySettingsSwitchRow(
                        title: 'Verify checksums',
                        subtitle: 'Check received files against the checksum the sender provided',
                        value: vm.settings.verifyChecksums,
                        onChanged: (b) async => ref.notifier(settingsProvider).setVerifyChecksums(b),
                      ),
                    ],
                  ),

                  RelaySettingsSection(
                    title: 'Appearance',
                    children: [
                      RelaySettingsRow(
                        title: 'Theme',
                        trailing: CustomDropdownButton<ThemeMode>(
                          expanded: false,
                          value: vm.settings.theme,
                          items: vm.themeModes.map((theme) {
                            return DropdownMenuItem(value: theme, child: Text(theme.humanName));
                          }).toList(),
                          onChanged: (theme) => vm.onChangeTheme(context, theme),
                        ),
                      ),
                      RelaySettingsRow(
                        title: 'Color Theme',
                        trailing: CustomDropdownButton<ColorMode>(
                          expanded: false,
                          value: vm.settings.colorMode,
                          items: vm.colorModes.map((colorMode) {
                            return DropdownMenuItem(
                              value: colorMode,
                              child: Text(colorMode.humanName, overflow: TextOverflow.ellipsis),
                            );
                          }).toList(),
                          onChanged: (colorMode) => vm.onChangeColorMode(context, colorMode),
                        ),
                      ),
                      RelaySettingsNavRow(
                        title: 'Language',
                        valueText: vm.settings.locale?.getLocaleName() ?? 'System',
                        onTap: () => vm.onTapLanguage(context),
                      ),
                    ],
                  ),

                  RelaySettingsSection(
                    title: 'About Relay',
                    children: [
                      RelaySettingsNavRow(
                        title: 'About',
                        valueText: RelayProduct.name,
                        onTap: () => context.push(() => const AboutPage()),
                      ),
                      RelaySettingsNavRow(
                        title: 'Changelog',
                        onTap: () => context.push(() => const ChangelogPage()),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// This machine's own identity, at the head of Settings where it belongs.
class _ThisDevice extends StatelessWidget {
  final SettingsTabVm vm;
  final DeviceType deviceType;

  const _ThisDevice({required this.vm, required this.deviceType});

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).relayPalette;
    final ref = context.ref;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const RelaySectionLabel(label: 'This Device'),
        const SizedBox(height: 16),
        Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(color: palette.softSurface, shape: BoxShape.circle),
              alignment: Alignment.center,
              child: RelayDeviceSilhouette(deviceType: deviceType, color: palette.textSecondary, size: 30),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(vm.settings.alias, style: RelayTypography.title(palette.textPrimary, isGnome: true)),
                  const SizedBox(height: 3),
                  Text(
                    switch (deviceType) {
                      DeviceType.mobile => 'Mobile · Relay Device',
                      DeviceType.desktop => 'Desktop · Relay Device',
                      DeviceType.web => 'Web · Relay Device',
                      DeviceType.headless || DeviceType.server => 'Server · Relay Device',
                    },
                    style: RelayTypography.caption(palette.textTertiary, isGnome: true),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.casino_outlined, size: 18),
              tooltip: 'Random Name',
              onPressed: () async {
                final newAlias = generateRandomAlias();
                vm.aliasController.text = newAlias;
                await ref.notifier(settingsProvider).setAlias(newAlias);
              },
            ),
            IconButton(
              icon: const Icon(Icons.edit_rounded, size: 18),
              tooltip: 'Edit Device Name',
              onPressed: () async {
                final result = await showDialog<String>(
                  context: context,
                  builder: (_) => FileNameInputDialog(
                    originalName: vm.settings.alias,
                    initialName: vm.settings.alias,
                  ),
                );
                if (result != null && result.trim().isNotEmpty) {
                  vm.aliasController.text = result.trim();
                  await ref.notifier(settingsProvider).setAlias(result.trim());
                }
              },
            ),
          ],
        ),
      ],
    );
  }
}
