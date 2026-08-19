import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:refena_flutter/refena_flutter.dart';
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
import 'package:relay_app/util/ui/theme_mode_ext.dart';
import 'package:relay_app/widget/custom_dropdown_button.dart';
import 'package:relay_app/widget/dialogs/file_name_input_dialog.dart';
import 'package:relay_app/widget/dialogs/relay_pair_device_dialog.dart';
import 'package:relay_app/widget/relay/relay_device_silhouette.dart';
import 'package:relay_isolates/model/device.dart';
import 'package:routerino/routerino.dart';

/// Reconstructed Android Material 3 Settings Experience with 5 clear semantic sections.
class AndroidSettingsPage extends StatelessWidget {
  const AndroidSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).relayPalette;

    return ViewModelBuilder(
      provider: (ref) => settingsTabControllerProvider,
      builder: (context, vm) {
        final ref = context.ref;
        final deviceType = vm.settings.deviceType ?? DeviceType.mobile;

        return Scaffold(
          backgroundColor: palette.canvas,
          appBar: AppBar(
            backgroundColor: palette.canvas,
            elevation: 0,
            title: Text(
              'Settings',
              style: RelayTypography.title(palette.textPrimary),
            ),
          ),
          body: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            children: [
              // ==========================================
              // SECTION 1: THIS DEVICE HERO
              // ==========================================
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 8),
                child: Text(
                  'THIS DEVICE',
                  style: RelayTypography.sectionHeader(palette.textSecondary),
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: palette.hairline),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [palette.topHighlight, palette.softSurface],
                  ),
                ),
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: palette.canvas,
                            border: Border.all(color: palette.hairline),
                          ),
                          alignment: Alignment.center,
                          child: RelayDeviceSilhouette(
                            deviceType: deviceType,
                            color: palette.accentSoft,
                            size: 38,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                vm.settings.alias,
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                  color: palette.textPrimary,
                                  letterSpacing: -0.3,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                switch (deviceType) {
                                  DeviceType.mobile => 'Mobile',
                                  DeviceType.desktop => 'Desktop',
                                  DeviceType.web => 'Web',
                                  DeviceType.headless || DeviceType.server => 'Server',
                                },
                                style: TextStyle(
                                  fontSize: 13,
                                  color: palette.textSecondary,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                                decoration: BoxDecoration(
                                  color: palette.canvas,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: palette.hairline),
                                ),
                                child: Text(
                                  'Relay Device',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w500,
                                    color: palette.textSecondary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Divider(height: 1, color: palette.hairline),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        OutlinedButton.icon(
                          icon: const Icon(Icons.casino_outlined, size: 18),
                          label: const Text('Randomize'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: palette.textSecondary,
                            side: BorderSide(color: palette.hairline),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          ),
                          onPressed: () async {
                            final newAlias = generateRandomAlias();
                            vm.aliasController.text = newAlias;
                            await ref.notifier(settingsProvider).setAlias(newAlias);
                          },
                        ),
                        const SizedBox(width: 8),
                        FilledButton.icon(
                          icon: const Icon(Icons.edit_rounded, size: 16),
                          label: const Text('Rename'),
                          style: FilledButton.styleFrom(
                            backgroundColor: palette.accent.withValues(alpha: 0.2),
                            foregroundColor: palette.accentSoft,
                            side: BorderSide(color: palette.accent.withValues(alpha: 0.4)),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          ),
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
                ),
              ),

              const SizedBox(height: 24),

              // ==========================================
              // SECTION 2: RELAY EXPERIENCE
              // ==========================================
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 8),
                child: Text(
                  'RELAY EXPERIENCE',
                  style: RelayTypography.sectionHeader(palette.textSecondary),
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  color: palette.softSurface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: palette.hairline),
                ),
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.add_link_rounded),
                      title: const Text('Pair New Device'),
                      subtitle: const Text('Connect trusted devices via PIN or manual route'),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () {
                        unawaited(
                          showDialog<void>(
                            context: context,
                            builder: (_) => const RelayPairDeviceDialog(),
                          ),
                        );
                      },
                    ),
                    Divider(height: 1, color: palette.hairline),
                    SwitchListTile.adaptive(
                      secondary: const Icon(Icons.flash_on_rounded),
                      title: const Text('Quick Save'),
                      subtitle: const Text('Automatically accept incoming transfer requests'),
                      value: vm.settings.quickSave,
                      onChanged: (b) async => ref.notifier(settingsProvider).setQuickSave(b),
                    ),
                    Divider(height: 1, color: palette.hairline),
                    SwitchListTile.adaptive(
                      secondary: const Icon(Icons.star_outline_rounded),
                      title: const Text('Quick Save from Favorites'),
                      subtitle: const Text('Automatically accept transfers from devices marked as favorites'),
                      value: vm.settings.quickSaveFromFavorites,
                      onChanged: (b) async => ref.notifier(settingsProvider).setQuickSaveFromFavorites(b),
                    ),
                    Divider(height: 1, color: palette.hairline),
                    SwitchListTile.adaptive(
                      secondary: const Icon(Icons.motion_photos_on_rounded),
                      title: const Text('Spatial Animations'),
                      subtitle: const Text('Living orbital revolution and transfer streams'),
                      value: vm.settings.enableAnimations,
                      onChanged: (b) async => ref.notifier(settingsProvider).setEnableAnimations(b),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // ==========================================
              // SECTION 3: TRANSFERS
              // ==========================================
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 8),
                child: Text(
                  'TRANSFERS',
                  style: RelayTypography.sectionHeader(palette.textSecondary),
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  color: palette.softSurface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: palette.hairline),
                ),
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.folder_open_rounded),
                      title: const Text('Destination Directory'),
                      subtitle: Text(
                        vm.settings.destination ?? 'Default (Downloads)',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
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
                    if (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS) ...[
                      Divider(height: 1, color: palette.hairline),
                      SwitchListTile.adaptive(
                        secondary: const Icon(Icons.photo_library_outlined),
                        title: const Text('Save to Gallery'),
                        subtitle: const Text('Save photos and videos directly into device gallery'),
                        value: vm.settings.saveToGallery,
                        onChanged: (b) async => ref.notifier(settingsProvider).setSaveToGallery(b),
                      ),
                    ],
                    Divider(height: 1, color: palette.hairline),
                    SwitchListTile.adaptive(
                      secondary: const Icon(Icons.history_rounded),
                      title: const Text('Save to History'),
                      subtitle: const Text('Record completed transfers in activity'),
                      value: vm.settings.saveToHistory,
                      onChanged: (b) async => ref.notifier(settingsProvider).setSaveToHistory(b),
                    ),
                    Divider(height: 1, color: palette.hairline),
                    SwitchListTile.adaptive(
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

              // ==========================================
              // SECTION 4: APPEARANCE
              // ==========================================
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 8),
                child: Text(
                  'APPEARANCE',
                  style: RelayTypography.sectionHeader(palette.textSecondary),
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  color: palette.softSurface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: palette.hairline),
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
                    Divider(height: 1, color: palette.hairline),
                    ListTile(
                      leading: const Icon(Icons.palette_outlined),
                      title: const Text('Color Theme'),
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
                    Divider(height: 1, color: palette.hairline),
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

              // ==========================================
              // SECTION 5: ABOUT
              // ==========================================
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 8),
                child: Text(
                  'ABOUT',
                  style: RelayTypography.sectionHeader(palette.textSecondary),
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  color: palette.softSurface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: palette.hairline),
                ),
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.info_outline_rounded),
                      title: const Text('About Relay'),
                      subtitle: const Text('Open source file transfer'),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => context.push(() => const AboutPage()),
                    ),
                    Divider(height: 1, color: palette.hairline),
                    ListTile(
                      leading: const Icon(Icons.update_rounded),
                      title: const Text('Changelog'),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => context.push(() => const ChangelogPage()),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
            ],
          ),
        );
      },
    );
  }
}
