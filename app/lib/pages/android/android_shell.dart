import 'dart:async';

import 'package:flutter/material.dart';
import 'package:relay_app/config/relay_brand.dart';
import 'package:relay_app/pages/android/android_activity_page.dart';
import 'package:relay_app/pages/android/android_home_page.dart';
import 'package:relay_app/pages/android/android_settings_page.dart';
import 'package:relay_app/pages/relay_home_vm.dart';
import 'package:relay_app/widget/dialogs/relay_pair_device_dialog.dart';

/// Android Material 3 root presentation shell.
class AndroidShell extends StatefulWidget {
  final RelayHomeVm vm;
  final bool animationsEnabled;
  final VoidCallback? onPairDevice;

  const AndroidShell({
    super.key,
    required this.vm,
    required this.animationsEnabled,
    this.onPairDevice,
  });

  @override
  State<AndroidShell> createState() => _AndroidShellState();
}

class _AndroidShellState extends State<AndroidShell> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).relayPalette;

    return Scaffold(
      backgroundColor: palette.canvas,
      appBar: _currentIndex == 0
          ? AppBar(
              title: Text(
                'Relay',
                style: RelayTypography.wordmark(palette.textPrimary),
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.add_link_rounded),
                  tooltip: 'Pair Device',
                  onPressed: () {
                    if (widget.onPairDevice != null) {
                      widget.onPairDevice!();
                    } else {
                      _openPairDialog();
                    }
                  },
                ),
              ],
            )
          : null,
      body: SafeArea(
        child: switch (_currentIndex) {
          0 => AndroidHomePage(
            vm: widget.vm,
            animationsEnabled: widget.animationsEnabled,
            onAddDevice: () {
              if (widget.onPairDevice != null) {
                widget.onPairDevice!();
              } else {
                _openPairDialog();
              }
            },
          ),
          1 => const AndroidActivityPage(),
          _ => const AndroidSettingsPage(),
        },
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) => setState(() => _currentIndex = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.devices_outlined),
            selectedIcon: Icon(Icons.devices_rounded),
            label: 'Devices',
          ),
          NavigationDestination(
            icon: Icon(Icons.history_outlined),
            selectedIcon: Icon(Icons.history_rounded),
            label: 'Activity',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings_rounded),
            label: 'Settings',
          ),
        ],
      ),
    );
  }

  void _openPairDialog() {
    unawaited(
      showDialog<void>(
        context: context,
        builder: (_) => const RelayPairDeviceDialog(),
      ),
    );
  }
}
