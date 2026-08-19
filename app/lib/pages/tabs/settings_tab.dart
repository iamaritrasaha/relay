import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:relay_app/config/relay_brand.dart';
import 'package:relay_app/gen/strings.g.dart';
import 'package:relay_app/model/persistence/color_mode.dart';
import 'package:relay_app/pages/about/about_page.dart';
import 'package:relay_app/pages/changelog_page.dart';
import 'package:relay_app/pages/settings/network_interfaces_page.dart';
import 'package:relay_app/pages/tabs/settings_tab_controller.dart';
import 'package:relay_app/provider/network/server/server_provider.dart';
import 'package:relay_app/provider/relay_anywhere_listener_provider.dart';
import 'package:relay_app/provider/settings_provider.dart';
import 'package:relay_app/provider/version_provider.dart';
import 'package:relay_app/util/alias_generator.dart';
import 'package:relay_app/util/device_type_ext.dart';
import 'package:relay_app/util/i18n.dart';
import 'package:relay_app/util/native/macos_channel.dart';
import 'package:relay_app/util/native/pick_directory_path.dart';
import 'package:relay_app/util/native/platform_check.dart';
import 'package:relay_app/util/ui/theme_mode_ext.dart';
import 'package:relay_app/widget/custom_dropdown_button.dart';
import 'package:relay_app/widget/dialogs/encryption_disabled_notice.dart';
import 'package:relay_app/widget/dialogs/pin_dialog.dart';
import 'package:relay_app/widget/dialogs/quick_save_from_favorites_notice.dart';
import 'package:relay_app/widget/dialogs/quick_save_notice.dart';
import 'package:relay_app/widget/dialogs/text_field_tv.dart';
import 'package:relay_app/widget/dialogs/text_field_with_actions.dart';
import 'package:relay_app/widget/relay/relay_desktop_metrics.dart';
import 'package:relay_app/widget/relay/relay_settings_primitives.dart';
import 'package:relay_app/widget/relay/relay_top_bar.dart';
import 'package:relay_app/widget/responsive_list_view.dart';
import 'package:relay_isolates/constants.dart';
import 'package:relay_isolates/model/device.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:routerino/routerino.dart';
import 'package:url_launcher/url_launcher.dart';

class SettingsTab extends StatelessWidget {
  final VoidCallback? onClose;

  const SettingsTab({super.key, this.onClose});

  @override
  Widget build(BuildContext context) {
    return ViewModelBuilder(
      provider: (ref) => settingsTabControllerProvider,
      builder: (context, vm) {
        final ref = context.ref;
        final palette = Theme.of(context).relayPalette;

        Widget note(Widget child) => Padding(padding: const EdgeInsets.only(top: 12), child: child);

        final general = RelaySettingsGroup(
          title: t.settingsTab.general.title,
          children: [
            RelaySettingsEntry(
              label: t.settingsTab.general.brightness,
              child: CustomDropdownButton<ThemeMode>(
                expanded: false,
                value: vm.settings.theme,
                items: vm.themeModes.map((theme) {
                  return DropdownMenuItem(value: theme, child: Text(theme.humanName));
                }).toList(),
                onChanged: (theme) => vm.onChangeTheme(context, theme),
              ),
            ),
            RelaySettingsEntry(
              label: t.settingsTab.general.color,
              child: CustomDropdownButton<ColorMode>(
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
            RelayNavigationEntry(
              label: t.settingsTab.general.language,
              value: vm.settings.locale?.getLocaleName() ?? t.settingsTab.general.languageOptions.system,
              onTap: () => vm.onTapLanguage(context),
            ),
            if (checkPlatformIsDesktop()) ...[
              // Wayland handles window position itself. See relay/relay#544.
              if (vm.advanced && checkPlatformIsNotWaylandDesktop())
                RelayBooleanEntry(
                  label: defaultTargetPlatform == TargetPlatform.windows
                      ? t.settingsTab.general.saveWindowPlacementWindows
                      : t.settingsTab.general.saveWindowPlacement,
                  value: vm.settings.saveWindowPlacement,
                  onChanged: (b) async => ref.notifier(settingsProvider).setSaveWindowPlacement(b),
                ),
              if (checkPlatformHasTray())
                RelayBooleanEntry(
                  label: t.settingsTab.general.minimizeToTray,
                  value: vm.settings.minimizeToTray,
                  onChanged: (b) async => ref.notifier(settingsProvider).setMinimizeToTray(b),
                ),
              RelayBooleanEntry(
                label: t.settingsTab.general.launchAtStartup,
                value: vm.autoStart,
                onChanged: (_) => vm.onToggleAutoStart(context),
              ),
              if (vm.autoStart)
                RelayBooleanEntry(
                  label: t.settingsTab.general.launchMinimized,
                  value: vm.autoStartLaunchHidden,
                  onChanged: (_) => vm.onToggleAutoStartLaunchHidden(context),
                ),
              if (vm.advanced && checkPlatform([TargetPlatform.windows]))
                RelayBooleanEntry(
                  label: t.settingsTab.general.showInContextMenu,
                  value: vm.showInContextMenu,
                  onChanged: (_) => vm.onToggleShowInContextMenu(context),
                ),
            ],
            RelayBooleanEntry(
              label: t.settingsTab.general.animations,
              value: vm.settings.enableAnimations,
              onChanged: (b) async => ref.notifier(settingsProvider).setEnableAnimations(b),
            ),
            RelayBooleanEntry(
              label: t.settingsTab.advancedSettings,
              value: vm.advanced,
              onChanged: (b) async {
                vm.onTapAdvanced(b);
                await ref.notifier(settingsProvider).setAdvancedSettingsEnabled(b);
              },
            ),
          ],
        );

        final receiving = RelaySettingsGroup(
          title: t.settingsTab.receive.title,
          children: [
            RelayBooleanEntry(
              label: t.settingsTab.receive.quickSave,
              value: vm.settings.quickSave,
              onChanged: (b) async {
                final old = vm.settings.quickSave;
                await ref.notifier(settingsProvider).setQuickSave(b);
                if (b) {
                  await ref.notifier(settingsProvider).setQuickSaveFromFavorites(false);
                }
                if (!old && b && context.mounted) {
                  await QuickSaveNotice.open(context);
                }
              },
            ),
            RelayBooleanEntry(
              label: t.settingsTab.receive.quickSaveFromFavorites,
              value: vm.settings.quickSaveFromFavorites,
              onChanged: (b) async {
                final old = vm.settings.quickSaveFromFavorites;
                await ref.notifier(settingsProvider).setQuickSaveFromFavorites(b);
                if (b) {
                  await ref.notifier(settingsProvider).setQuickSave(false);
                }
                if (!old && b && context.mounted) {
                  await QuickSaveFromFavoritesNotice.open(context);
                }
              },
            ),
            RelayBooleanEntry(
              label: t.settingsTab.receive.requirePin,
              value: vm.settings.receivePin != null,
              onChanged: (b) async {
                final currentPIN = vm.settings.receivePin;
                if (currentPIN != null) {
                  await ref.notifier(settingsProvider).setReceivePin(null);
                } else {
                  final String? newPin = await showDialog<String>(
                    context: context,
                    builder: (_) => const PinDialog(obscureText: false, generateRandom: false),
                  );

                  if (newPin != null && newPin.isNotEmpty) {
                    await ref.notifier(settingsProvider).setReceivePin(newPin);
                  }
                }

                // The pin is enforced by the Rust server, so it needs a restart.
                if (ref.read(serverProvider) != null) {
                  await ref.notifier(serverProvider).restartServerFromSettings();
                }
              },
            ),
            if (checkPlatformWithFileSystem())
              RelayNavigationEntry(
                label: t.settingsTab.receive.destination,
                value: vm.settings.destination ?? t.settingsTab.receive.downloads,
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
            if (checkPlatformWithGallery())
              RelayBooleanEntry(
                label: t.settingsTab.receive.saveToGallery,
                value: vm.settings.saveToGallery,
                onChanged: (b) async => ref.notifier(settingsProvider).setSaveToGallery(b),
              ),
            RelayBooleanEntry(
              label: t.settingsTab.receive.autoFinish,
              value: vm.settings.autoFinish,
              onChanged: (b) async => ref.notifier(settingsProvider).setAutoFinish(b),
            ),
            RelayBooleanEntry(
              label: t.settingsTab.receive.saveToHistory,
              value: vm.settings.saveToHistory,
              onChanged: (b) async => ref.notifier(settingsProvider).setSaveToHistory(b),
            ),
            if (vm.advanced)
              RelayBooleanEntry(
                label: t.settingsTab.receive.verifyChecksums,
                value: vm.settings.verifyChecksums,
                onChanged: (b) async {
                  await ref.notifier(settingsProvider).setVerifyChecksums(b);

                  // The checksums are verified by the Rust server, so it needs a restart.
                  if (ref.read(serverProvider) != null) {
                    await ref.notifier(serverProvider).restartServerFromSettings();
                  }
                },
              ),
          ],
        );

        final sending = RelaySettingsGroup(
          title: t.settingsTab.send.title,
          children: [
            if (vm.advanced) ...[
              RelayBooleanEntry(
                label: t.settingsTab.send.shareViaLinkAutoAccept,
                value: vm.settings.shareViaLinkAutoAccept,
                onChanged: (b) async => ref.notifier(settingsProvider).setShareViaLinkAutoAccept(b),
              ),
              RelayBooleanEntry(
                label: t.settingsTab.send.createChecksums,
                value: vm.settings.createChecksums,
                onChanged: (b) async => ref.notifier(settingsProvider).setCreateChecksums(b),
              ),
            ],
          ],
        );

        final needsRestart =
            vm.serverState != null &&
            (vm.serverState!.alias != vm.settings.alias || vm.serverState!.port != vm.settings.port || vm.serverState!.https != vm.settings.https);

        final network = RelaySettingsGroup(
          title: t.settingsTab.network.title,
          notes: [
            if (needsRestart) note(Text(t.settingsTab.network.needRestart, style: TextStyle(fontSize: 12.5, color: palette.warning))),
            if (vm.settings.port != defaultPort)
              note(
                Text(
                  t.settingsTab.network.portWarning(defaultPort: defaultPort),
                  style: TextStyle(fontSize: 12.5, color: palette.textTertiary),
                ),
              ),
            if (vm.settings.multicastGroup != defaultMulticastGroup)
              note(
                Text(
                  t.settingsTab.network.multicastGroupWarning(defaultMulticast: defaultMulticastGroup),
                  style: TextStyle(fontSize: 12.5, color: palette.textTertiary),
                ),
              ),
          ],
          children: [
            RelaySettingsEntry(
              label: '${t.settingsTab.network.server}${vm.serverState == null ? ' (${t.general.offline})' : ''}',
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (vm.serverState == null)
                    IconButton(
                      tooltip: t.general.start,
                      visualDensity: VisualDensity.compact,
                      iconSize: 20,
                      onPressed: () => vm.onTapStartServer(context),
                      icon: const Icon(Icons.play_arrow_rounded),
                    )
                  else
                    IconButton(
                      tooltip: t.general.restart,
                      visualDensity: VisualDensity.compact,
                      iconSize: 20,
                      onPressed: () => vm.onTapRestartServer(context),
                      icon: const Icon(Icons.refresh_rounded),
                    ),
                  IconButton(
                    tooltip: t.general.stop,
                    visualDensity: VisualDensity.compact,
                    iconSize: 20,
                    onPressed: vm.serverState == null ? null : vm.onTapStopServer,
                    icon: const Icon(Icons.stop_rounded),
                  ),
                ],
              ),
            ),
            RelaySettingsEntry(
              label: t.settingsTab.network.alias,
              child: TextFieldWithActions(
                name: t.settingsTab.network.alias,
                controller: vm.aliasController,
                onChanged: (s) async => ref.notifier(settingsProvider).setAlias(s),
                actions: [
                  Tooltip(
                    message: t.settingsTab.network.generateRandomAlias,
                    child: IconButton(
                      onPressed: () async {
                        final newAlias = generateRandomAlias();
                        vm.aliasController.text = newAlias;
                        await ref.notifier(settingsProvider).setAlias(newAlias);
                      },
                      icon: const Icon(Icons.casino),
                    ),
                  ),
                  Tooltip(
                    message: t.settingsTab.network.useSystemName,
                    child: IconButton(
                      onPressed: () async {
                        final String newAlias;
                        if (Platform.isMacOS) {
                          final result = await Process.run('scutil', ['--get', 'ComputerName']);
                          newAlias = result.stdout.toString().trim();
                        } else {
                          newAlias = Platform.localHostname;
                        }

                        vm.aliasController.text = newAlias;
                        await ref.notifier(settingsProvider).setAlias(newAlias);
                      },
                      icon: const Icon(Icons.desktop_windows_rounded),
                    ),
                  ),
                ],
              ),
            ),
            if (checkPlatform([TargetPlatform.android, TargetPlatform.linux]))
              RelayBooleanEntry(
                label: 'Remote Relay',
                description: 'Receive through an authenticated Relay address. This does not advertise you on the local network.',
                value: vm.settings.remoteRelayEnabled,
                onChanged: (enabled) async {
                  await ref.notifier(settingsProvider).setRemoteRelayEnabled(enabled);
                  final listener = ref.read(relayAnywhereListenerServiceProvider);
                  if (enabled) {
                    await listener.startIfEnabled(enabled: true, alias: vm.settings.alias);
                  } else {
                    await listener.stop();
                  }
                },
              ),
            if (vm.advanced) ...[
              RelaySettingsEntry(
                label: t.settingsTab.network.deviceType,
                controlMaxWidth: 110,
                child: CustomDropdownButton<DeviceType>(
                  expanded: false,
                  value: vm.deviceInfo.deviceType,
                  items: DeviceType.values.map((type) {
                    return DropdownMenuItem(value: type, child: Icon(type.icon));
                  }).toList(),
                  onChanged: (type) async => ref.notifier(settingsProvider).setDeviceType(type),
                ),
              ),
              RelaySettingsEntry(
                label: t.settingsTab.network.deviceModel,
                child: TextFieldTv(
                  name: t.settingsTab.network.deviceModel,
                  controller: vm.deviceModelController,
                  onChanged: (s) async => ref.notifier(settingsProvider).setDeviceModel(s),
                ),
              ),
              RelaySettingsEntry(
                label: t.settingsTab.network.port,
                controlMaxWidth: 120,
                child: TextFieldTv(
                  name: t.settingsTab.network.port,
                  controller: vm.portController,
                  onChanged: (s) async {
                    final port = int.tryParse(s);
                    if (port != null) {
                      await ref.notifier(settingsProvider).setPort(port);
                    }
                  },
                ),
              ),
              RelayNavigationEntry(
                label: t.settingsTab.network.network,
                value: switch (vm.settings.networkWhitelist != null || vm.settings.networkBlacklist != null) {
                  true => t.settingsTab.network.networkOptions.filtered,
                  false => t.settingsTab.network.networkOptions.all,
                },
                onTap: () async => context.push(() => const NetworkInterfacesPage()),
              ),
              RelaySettingsEntry(
                label: t.settingsTab.network.discoveryTimeout,
                controlMaxWidth: 120,
                child: TextFieldTv(
                  name: t.settingsTab.network.discoveryTimeout,
                  controller: vm.timeoutController,
                  onChanged: (s) async {
                    final timeout = int.tryParse(s);
                    if (timeout != null) {
                      await ref.notifier(settingsProvider).setDiscoveryTimeout(timeout);
                    }
                  },
                ),
              ),
              RelayBooleanEntry(
                label: t.settingsTab.network.encryption,
                value: vm.settings.https,
                onChanged: (b) async {
                  final old = vm.settings.https;
                  await ref.notifier(settingsProvider).setHttps(b);
                  if (old && !b && context.mounted) {
                    await EncryptionDisabledNotice.open(context);
                  }
                },
              ),
              RelaySettingsEntry(
                label: t.settingsTab.network.multicastGroup,
                controlMaxWidth: 160,
                child: TextFieldTv(
                  name: t.settingsTab.network.multicastGroup,
                  controller: vm.multicastController,
                  onChanged: (s) async => ref.notifier(settingsProvider).setMulticastGroup(s),
                ),
              ),
            ],
          ],
        );

        final about = RelaySettingsGroup(
          title: 'About',
          children: [
            RelayNavigationEntry(
              // Not t.aboutPage.title — the inherited string reads "About
              // Relay". Relay's own surfaces name themselves.
              label: 'About Relay',
              value: ref
                  .watch(versionProvider)
                  .maybeWhen(
                    data: (version) => 'Version ${version.combinedString}',
                    orElse: () => t.general.open,
                  ),
              onTap: () async => context.push(() => const AboutPage()),
            ),
            RelayNavigationEntry(
              label: 'Release notes',
              value: ref.watch(versionProvider).maybeWhen(data: (version) => version.version, orElse: () => t.general.open),
              onTap: () async => context.push(() => const ChangelogPage()),
            ),
            // Store requirement on Apple platforms; kept where it applies.
            // Relay's privacy policy is deliberately not linked here — it
            // is not Relay's, and the upstream references live in About.
            if (checkPlatform([TargetPlatform.iOS, TargetPlatform.macOS]))
              RelayNavigationEntry(
                label: t.settingsTab.other.termsOfUse,
                value: t.general.open,
                onTap: () async => launchUrl(
                  Uri.parse('https://www.apple.com/legal/internet-services/itunes/dev/stdeula/'),
                  mode: LaunchMode.externalApplication,
                ),
              ),
          ],
        );

        return Column(
          children: [
            RelayTopBar.titled(title: 'Settings', onBack: onClose, backTooltip: 'Back to Relay'),
            Expanded(
              // NOTE: [ResponsiveListView.single] does not scroll — it expects a
              // child that scrolls itself. Settings is a plain column, so it
              // must use the scrolling variant or it overflows on short windows.
              child: ResponsiveListView(
                maxWidth: RelayDesktopMetrics.settingsWideFrameWidth,
                padding: const EdgeInsets.fromLTRB(RelayDesktopMetrics.compactGutter, 24, RelayDesktopMetrics.compactGutter, 40),
                tabletPadding: const EdgeInsets.fromLTRB(
                  RelayDesktopMetrics.settingsDesktopGutter,
                  36,
                  RelayDesktopMetrics.settingsDesktopGutter,
                  56,
                ),
                children: [
                  RelaySettingsColumns(groups: [general, receiving, network, sending, about]),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
