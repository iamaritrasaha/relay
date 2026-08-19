import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:localsend_app/config/relay_brand.dart';
import 'package:localsend_app/model/persistence/color_mode.dart';
import 'package:localsend_app/pages/about/about_page.dart';
import 'package:localsend_app/pages/changelog_page.dart';
import 'package:localsend_app/pages/tabs/settings_tab_controller.dart';
import 'package:localsend_app/provider/settings_provider.dart';
import 'package:localsend_app/util/alias_generator.dart';
import 'package:localsend_app/util/i18n.dart';
import 'package:localsend_app/util/native/macos_channel.dart';
import 'package:localsend_app/util/native/pick_directory_path.dart';
import 'package:localsend_app/util/ui/theme_mode_ext.dart';
import 'package:localsend_app/widget/custom_dropdown_button.dart';
import 'package:localsend_app/widget/dialogs/file_name_input_dialog.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:routerino/routerino.dart';

/// Android Material 3 Settings Page.
class AndroidSettingsPage extends StatelessWidget {
  const AndroidSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).relayPalette;

    return ViewModelBuilder(
      provider: (ref) => settingsTabControllerProvider,
      builder: (context, vm) {
        final ref = context.ref;

        return Scaffold(
          appBar: AppBar(
            title: Text(
              'Settings',
              style: RelayTypography.title(palette.textPrimary),
            ),
          ),
          body: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            children: [
              // Appearance Section
              Padding(
                padding: const EdgeInsets.only(left: 16),
                child: Text(
                  'APPEARANCE',
                  style: RelayTypography.sectionHeader(palette.textSecondary),
                ),
              ),
              const SizedBox(height: 8),
              Card(
                elevation: 0,
                color: palette.softSurface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: palette.hairline),
                ),
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.brightness_6_rounded),
                      title: const Text('Theme'),
                      trailing: CustomDropdownButton<ThemeMode>(
                        expanded: false,
                        value: vm.settings.theme,
                        items: vm.themeModes.map((theme) {
                          return DropdownMenuItem(value: theme, child: Text(theme.humanName));
                        }).toList(),
                        onChanged: (theme) => vm.onChangeTheme(context, theme),
                      ),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.palette_outlined),
                      title: const Text('Color'),
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
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.language_rounded),
                      title: const Text('Language'),
                      subtitle: Text(vm.settings.locale?.getLocaleName() ?? 'System'),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => vm.onTapLanguage(context),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Device Identity
              Padding(
                padding: const EdgeInsets.only(left: 16),
                child: Text(
                  'DEVICE IDENTITY',
                  style: RelayTypography.sectionHeader(palette.textSecondary),
                ),
              ),
              const SizedBox(height: 8),
              Card(
                elevation: 0,
                color: palette.softSurface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: palette.hairline),
                ),
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.badge_outlined),
                      title: const Text('Device Name'),
                      subtitle: Text(vm.settings.alias),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.casino_outlined),
                            tooltip: 'Random Name',
                            onPressed: () async {
                              final newAlias = generateRandomAlias();
                              vm.aliasController.text = newAlias;
                              await ref.notifier(settingsProvider).setAlias(newAlias);
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.edit_rounded),
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
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.devices_rounded),
                      title: const Text('Device Type'),
                      trailing: Text(vm.settings.deviceType?.name ?? 'Mobile'),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Transfers & Storage
              Padding(
                padding: const EdgeInsets.only(left: 16),
                child: Text(
                  'TRANSFERS & STORAGE',
                  style: RelayTypography.sectionHeader(palette.textSecondary),
                ),
              ),
              const SizedBox(height: 8),
              Card(
                elevation: 0,
                color: palette.softSurface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: palette.hairline),
                ),
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.folder_open_rounded),
                      title: const Text('Destination'),
                      subtitle: Text(vm.settings.destination ?? 'Default (Downloads)'),
                      trailing: const Icon(Icons.chevron_right_rounded),
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
                    const Divider(height: 1),
                    SwitchListTile(
                      secondary: const Icon(Icons.history_rounded),
                      title: const Text('Save to History'),
                      subtitle: const Text('Record transfers in activity'),
                      value: vm.settings.saveToHistory,
                      onChanged: (b) async => ref.notifier(settingsProvider).setSaveToHistory(b),
                    ),
                    const Divider(height: 1),
                    SwitchListTile(
                      secondary: const Icon(Icons.check_circle_outline_rounded),
                      title: const Text('Auto-Finish'),
                      subtitle: const Text('Close finished transfer sessions automatically'),
                      value: vm.settings.autoFinish,
                      onChanged: (b) async => ref.notifier(settingsProvider).setAutoFinish(b),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // About Relay
              Padding(
                padding: const EdgeInsets.only(left: 16),
                child: Text(
                  'ABOUT',
                  style: RelayTypography.sectionHeader(palette.textSecondary),
                ),
              ),
              const SizedBox(height: 8),
              Card(
                elevation: 0,
                color: palette.softSurface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: palette.hairline),
                ),
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.info_outline_rounded),
                      title: const Text('About Relay'),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => context.push(() => const AboutPage()),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.update_rounded),
                      title: const Text('Changelog'),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => context.push(() => const ChangelogPage()),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
