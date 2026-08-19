import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:relay_app/config/relay_brand.dart';
import 'package:relay_app/model/persistence/color_mode.dart';
import 'package:relay_app/pages/about/about_page.dart';
import 'package:relay_app/pages/changelog_page.dart';
import 'package:relay_app/pages/tabs/settings_tab_controller.dart';
import 'package:relay_app/provider/settings_provider.dart';
import 'package:relay_app/util/alias_generator.dart';
import 'package:relay_app/util/i18n.dart';
import 'package:relay_app/util/native/macos_channel.dart';
import 'package:relay_app/util/native/pick_directory_path.dart';
import 'package:relay_app/util/native/platform_check.dart';
import 'package:relay_app/util/ui/theme_mode_ext.dart';
import 'package:relay_app/widget/custom_dropdown_button.dart';
import 'package:relay_app/widget/dialogs/file_name_input_dialog.dart';
import 'package:relay_app/widget/gnome/adw_action_row.dart';
import 'package:relay_app/widget/gnome/adw_boxed_list.dart';
import 'package:relay_app/widget/gnome/adw_button.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:routerino/routerino.dart';

/// GNOME Libadwaita Preferences Window / View.
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

        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Header
                  Row(
                    children: [
                      if (onBack != null) ...[
                        AdwButton.flat(
                          icon: Icons.arrow_back_rounded,
                          label: 'Back',
                          onPressed: onBack,
                        ),
                        const SizedBox(width: 12),
                      ],
                      Expanded(
                        child: Text(
                          'Preferences',
                          style: RelayTypography.largeTitle(palette.textPrimary, isGnome: true),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // General
                  AdwPreferencesGroup(
                    title: 'General',
                    children: [
                      AdwActionRow(
                        leading: const Icon(Icons.brightness_6_rounded),
                        title: 'Appearance',
                        trailing: CustomDropdownButton<ThemeMode>(
                          expanded: false,
                          value: vm.settings.theme,
                          items: vm.themeModes.map((theme) {
                            return DropdownMenuItem(value: theme, child: Text(theme.humanName));
                          }).toList(),
                          onChanged: (theme) => vm.onChangeTheme(context, theme),
                        ),
                      ),
                      AdwActionRow(
                        leading: const Icon(Icons.palette_outlined),
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
                      AdwNavigationRow(
                        leading: const Icon(Icons.language_rounded),
                        title: 'Language',
                        valueText: vm.settings.locale?.getLocaleName() ?? 'System',
                        onTap: () => vm.onTapLanguage(context),
                      ),
                      if (checkPlatformHasTray())
                        AdwSwitchRow(
                          leading: const Icon(Icons.system_update_alt_rounded),
                          title: 'Minimize to Tray',
                          value: vm.settings.minimizeToTray,
                          onChanged: (b) async => ref.notifier(settingsProvider).setMinimizeToTray(b),
                        ),
                    ],
                  ),

                  // Devices
                  AdwPreferencesGroup(
                    title: 'Device Identity',
                    children: [
                      AdwActionRow(
                        leading: const Icon(Icons.badge_outlined),
                        title: 'Device Name',
                        subtitle: vm.settings.alias,
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
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
                      ),
                      AdwActionRow(
                        leading: const Icon(Icons.devices_rounded),
                        title: 'Device Type',
                        trailing: Text(
                          vm.settings.deviceType?.name ?? 'Desktop',
                          style: RelayTypography.body(palette.textSecondary, isGnome: true),
                        ),
                      ),
                    ],
                  ),

                  // Transfers
                  AdwPreferencesGroup(
                    title: 'Transfers & Storage',
                    children: [
                      AdwNavigationRow(
                        leading: const Icon(Icons.folder_open_rounded),
                        title: 'Destination Directory',
                        subtitle: vm.settings.destination ?? 'Default (Downloads)',
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
                        leading: const Icon(Icons.history_rounded),
                        title: 'Save to History',
                        subtitle: 'Record completed file transfers in activity',
                        value: vm.settings.saveToHistory,
                        onChanged: (b) async => ref.notifier(settingsProvider).setSaveToHistory(b),
                      ),
                      AdwSwitchRow(
                        leading: const Icon(Icons.check_circle_outline_rounded),
                        title: 'Auto-Finish',
                        subtitle: 'Automatically close completed transfer sessions',
                        value: vm.settings.autoFinish,
                        onChanged: (b) async => ref.notifier(settingsProvider).setAutoFinish(b),
                      ),
                    ],
                  ),

                  // About & Help
                  AdwPreferencesGroup(
                    title: 'About Relay',
                    children: [
                      AdwNavigationRow(
                        leading: const Icon(Icons.info_outline_rounded),
                        title: 'About',
                        valueText: RelayProduct.name,
                        onTap: () => context.push(() => const AboutPage()),
                      ),
                      AdwNavigationRow(
                        leading: const Icon(Icons.update_rounded),
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
