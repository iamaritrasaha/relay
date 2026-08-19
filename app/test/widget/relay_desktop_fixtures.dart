import 'package:flutter/material.dart';
import 'package:relay_app/model/ui/relay_device_vm.dart';
import 'package:relay_app/pages/about/about_page.dart';
import 'package:relay_app/pages/relay_home_vm.dart';
import 'package:relay_app/widget/relay/relay_desktop_metrics.dart';
import 'package:relay_app/widget/relay/relay_settings_primitives.dart';
import 'package:relay_app/widget/relay/relay_shell.dart';
import 'package:relay_app/widget/relay/relay_top_bar.dart';
import 'package:relay_isolates/model/device.dart';

enum RelayHomeState { empty, nearby, sending }

/// Shared fixtures for the desktop regression tests and the review renders.
///
/// Home and About are the real widgets. Settings composes the real primitives
/// with the real shipped labels: its own page builds its view model from the
/// full provider graph (persistence, isolates, server), which a widget test
/// cannot stand up, so the wiring — not the layout — is what is stubbed here.
abstract final class RelayDesktopFixtures {
  static const _devices = [
    RelayDeviceVm(
      key: 'aritras-phone',
      alias: "Aritra's Phone",
      deviceType: DeviceType.mobile,
      phase: RelayDevicePhase.idle,
      progress: null,
      detail: 'Ready',
    ),
    RelayDeviceVm(
      key: 'thinkpad',
      alias: 'ThinkPad',
      deviceType: DeviceType.desktop,
      phase: RelayDevicePhase.idle,
      progress: null,
      detail: 'Ready',
    ),
    RelayDeviceVm(
      key: 'galaxy-tab',
      alias: 'Galaxy Tab',
      deviceType: DeviceType.web,
      phase: RelayDevicePhase.idle,
      progress: null,
      detail: 'Ready',
    ),
  ];

  static Widget home({required RelayHomeState state}) {
    final sending = state == RelayHomeState.sending;
    final devices = switch (state) {
      RelayHomeState.empty => const <RelayDeviceVm>[],
      RelayHomeState.nearby => _devices,
      RelayHomeState.sending => [
        _devices[0],
        const RelayDeviceVm(
          key: 'thinkpad',
          alias: 'ThinkPad',
          deviceType: DeviceType.desktop,
          phase: RelayDevicePhase.sending,
          progress: 0.62,
          detail: 'Sending',
        ),
        _devices[2],
      ],
    };

    return RelayShell(
      vm: RelayHomeVm(
        selfAlias: 'Efficient Banana',
        selfDeviceType: DeviceType.desktop,
        presence: RelayPresence.ready,
        selection: RelayPayloadVm(fileCount: sending ? 3 : 0, totalBytes: sending ? 50539724 : 0),
        devices: devices,
        incoming: const RelayIncomingVm(hasActiveRequest: false),
        intents: RelayHomeIntents(canSelectPayload: true, canChooseTarget: sending),
        activeTransfer: sending ? const RelayTransferVm(sessionId: 'review', targetAlias: 'ThinkPad', progress: 0.62) : null,
      ),
      animationsEnabled: false,
      onSelectPayload: () {},
      onClearPayload: () {},
      onCancelTransfer: () {},
      onDeviceTap: (_) {},
      onOpenHistory: () {},
      onOpenSettings: () {},
    );
  }

  static Widget settings() => const _SettingsFixture();

  static Widget about() => const _AboutFixture();
}

class _SettingsFixture extends StatefulWidget {
  const _SettingsFixture();

  @override
  State<_SettingsFixture> createState() => _SettingsFixtureState();
}

class _SettingsFixtureState extends State<_SettingsFixture> {
  final _values = <String, bool>{
    'Autostart after login': true,
    'Minimize to the System Tray/Menu Bar when closing': false,
    'Animations': true,
    'Advanced settings': true,
    'Save media to gallery': false,
    'Auto Finish': true,
    'Save to history': true,
    'Verify checksums when receiving files': false,
    'Automatically accept requests in "Share via link" mode': false,
    'Create checksums when sending files': true,
    'Encryption': true,
  };

  RelayBooleanEntry _boolean(String label, {String? description}) => RelayBooleanEntry(
    label: label,
    description: description,
    value: _values[label]!,
    onChanged: (value) => setState(() => _values[label] = value),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          RelayTopBar.titled(title: 'Settings', onBack: () {}, backTooltip: 'Back to Relay'),
          Expanded(
            child: SingleChildScrollView(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: RelayDesktopMetrics.settingsWideFrameWidth),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      RelayDesktopMetrics.settingsDesktopGutter,
                      36,
                      RelayDesktopMetrics.settingsDesktopGutter,
                      56,
                    ),
                    child: RelaySettingsColumns(
                      groups: [
                        RelaySettingsGroup(
                          title: 'General',
                          children: [
                            RelayNavigationEntry(label: 'Theme', value: 'Dark', onTap: () {}),
                            RelayNavigationEntry(label: 'Color', value: 'Relay', onTap: () {}),
                            RelayNavigationEntry(label: 'Language', value: 'English', onTap: () {}),
                            _boolean('Autostart after login'),
                            _boolean('Minimize to the System Tray/Menu Bar when closing'),
                            _boolean('Animations'),
                            _boolean('Advanced settings'),
                          ],
                        ),
                        RelaySettingsGroup(
                          title: 'Receive',
                          children: [
                            RelayNavigationEntry(label: 'Save to folder', value: '~/Downloads/Relay', onTap: () {}),
                            _boolean('Save media to gallery'),
                            _boolean('Auto Finish'),
                            _boolean('Save to history'),
                            _boolean('Verify checksums when receiving files', description: 'Checksums are verified by the server, so it restarts.'),
                          ],
                        ),
                        RelaySettingsGroup(
                          title: 'Network',
                          children: [
                            RelaySettingsEntry(
                              label: 'Server',
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    tooltip: 'Restart',
                                    visualDensity: VisualDensity.compact,
                                    iconSize: 20,
                                    onPressed: () {},
                                    icon: const Icon(Icons.refresh_rounded),
                                  ),
                                  IconButton(
                                    tooltip: 'Stop',
                                    visualDensity: VisualDensity.compact,
                                    iconSize: 20,
                                    onPressed: () {},
                                    icon: const Icon(Icons.stop_rounded),
                                  ),
                                ],
                              ),
                            ),
                            RelaySettingsEntry(
                              label: 'Device name',
                              child: _Field(text: 'Efficient Banana'),
                            ),
                            RelaySettingsEntry(
                              label: 'Port',
                              controlMaxWidth: 120,
                              child: _Field(text: '53317'),
                            ),
                            RelayNavigationEntry(label: 'Network', value: 'All interfaces', onTap: () {}),
                            RelaySettingsEntry(
                              label: 'Discovery Timeout',
                              controlMaxWidth: 120,
                              child: _Field(text: '500'),
                            ),
                            _boolean('Encryption'),
                            RelaySettingsEntry(
                              label: 'Multicast address',
                              controlMaxWidth: 160,
                              child: _Field(text: '224.0.0.167'),
                            ),
                          ],
                        ),
                        RelaySettingsGroup(
                          title: 'Send',
                          children: [
                            _boolean('Automatically accept requests in "Share via link" mode'),
                            _boolean('Create checksums when sending files'),
                          ],
                        ),
                        RelaySettingsGroup(
                          title: 'About',
                          children: [
                            RelayNavigationEntry(label: 'About Relay', value: 'Version 0.1.0 (62)', onTap: () {}),
                            RelayNavigationEntry(label: 'Release notes', value: '0.1.0', onTap: () {}),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  final String text;

  const _Field({required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.inputDecorationTheme.fillColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
        child: Text(text, style: const TextStyle(fontSize: 13)),
      ),
    );
  }
}

class _AboutFixture extends StatelessWidget {
  const _AboutFixture();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          RelayTopBar.titled(title: 'About', onBack: () {}),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 36),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: RelayDesktopMetrics.settingsFrameWidth),
                  child: const Align(
                    alignment: Alignment.topLeft,
                    child: RelayAboutIdentity(version: '0.1.0', buildNumber: '62'),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
