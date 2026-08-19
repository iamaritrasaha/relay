import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:relay_app/config/relay_brand.dart';
import 'package:relay_app/model/cross_file.dart';
import 'package:relay_app/model/ui/relay_device_vm.dart';
import 'package:relay_app/pages/gnome/gnome_activity_view.dart';
import 'package:relay_app/pages/gnome/gnome_clipboard_view.dart';
import 'package:relay_app/pages/gnome/gnome_device_detail_view.dart';
import 'package:relay_app/pages/gnome/gnome_device_sidebar.dart';
import 'package:relay_app/pages/gnome/gnome_diagnostics_dialog.dart';
import 'package:relay_app/pages/gnome/gnome_messages_view.dart';
import 'package:relay_app/pages/gnome/gnome_phone_view.dart';
import 'package:relay_app/pages/gnome/gnome_settings_view.dart';
import 'package:relay_app/pages/relay_home_vm.dart';
import 'package:relay_app/provider/network/nearby_devices_provider.dart';
import 'package:relay_app/provider/network/relay_send_service.dart';
import 'package:relay_app/provider/relay_paired_routes_provider.dart';
import 'package:relay_app/provider/relay_verified_lan_devices_provider.dart';
import 'package:relay_app/provider/selection/selected_sending_files_provider.dart';
import 'package:relay_app/util/native/file_picker.dart';
import 'package:relay_app/widget/dialogs/cancel_session_dialog.dart';
import 'package:relay_app/widget/dialogs/relay_pair_device_dialog.dart';
import 'package:relay_app/widget/gnome/adw_header_bar.dart';
import 'package:relay_app/widget/gnome/adw_split_view.dart';
import 'package:relay_app/widget/gnome/adw_status_page.dart';
import 'package:relay_app/widget/relay_motion/relay_spatial_scene.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:routerino/routerino.dart';

enum GnomeSubView {
  overview,
  clipboard,
  messages,
  phone,
  activity,
  settings,
}

/// Root GNOME presentation shell for Linux desktop.
class GnomeShell extends StatefulWidget {
  final RelayHomeVm vm;
  final bool animationsEnabled;
  final VoidCallback? onOpenHistory;
  final VoidCallback? onOpenSettings;
  final VoidCallback? onPairDevice;

  const GnomeShell({
    super.key,
    required this.vm,
    required this.animationsEnabled,
    this.onOpenHistory,
    this.onOpenSettings,
    this.onPairDevice,
  });

  @override
  State<GnomeShell> createState() => _GnomeShellState();
}

class _GnomeShellState extends State<GnomeShell> with Refena {
  String? _selectedDeviceKey;
  GnomeSubView _subView = GnomeSubView.overview;
  bool _narrowShowDetail = false;

  @override
  void didUpdateWidget(covariant GnomeShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.vm.devices.isNotEmpty) {
      if (_selectedDeviceKey == null || !widget.vm.devices.any((d) => d.key == _selectedDeviceKey)) {
        _selectedDeviceKey = widget.vm.devices.first.key;
      }
    } else {
      _selectedDeviceKey = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).relayPalette;

    if (widget.vm.devices.isNotEmpty && _selectedDeviceKey == null) {
      _selectedDeviceKey = widget.vm.devices.first.key;
    }

    final selectedDevice =
        widget.vm.devices.firstWhereOrNull((d) => d.key == _selectedDeviceKey) ?? (widget.vm.devices.isNotEmpty ? widget.vm.devices.first : null);

    return Scaffold(
      backgroundColor: palette.canvas,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 720;

            final sidebar = GnomeDeviceSidebar(
              vm: widget.vm,
              selectedDeviceKey: _selectedDeviceKey,
              onSelectDevice: (key) {
                setState(() {
                  _selectedDeviceKey = key;
                  _subView = GnomeSubView.overview;
                  _narrowShowDetail = true;
                });
              },
              onAddDevice: () {
                if (widget.onPairDevice != null) {
                  widget.onPairDevice!();
                } else {
                  _openPairDialog();
                }
              },
              onOpenSettings: () {
                setState(() {
                  _subView = GnomeSubView.settings;
                  _narrowShowDetail = true;
                });
              },
              onOpenActivity: () {
                setState(() {
                  _subView = GnomeSubView.activity;
                  _narrowShowDetail = true;
                });
              },
            );

            final content = Column(
              children: [
                // Adwaita HeaderBar
                AdwHeaderBar(
                  leading: (!isWide && _narrowShowDetail)
                      ? AdwIconButton(
                          icon: Icons.arrow_back_rounded,
                          tooltip: 'Back to Devices',
                          onPressed: () {
                            setState(() {
                              _narrowShowDetail = false;
                              _subView = GnomeSubView.overview;
                            });
                          },
                        )
                      : null,
                  titleText: _getHeaderTitle(selectedDevice),
                  subtitleText: _getHeaderSubtitle(selectedDevice),
                  actions: [
                    AdwIconButton(
                      icon: Icons.history_rounded,
                      tooltip: 'Activity',
                      isPrimary: _subView == GnomeSubView.activity,
                      onPressed: () {
                        setState(() {
                          _subView = _subView == GnomeSubView.activity ? GnomeSubView.overview : GnomeSubView.activity;
                          _narrowShowDetail = true;
                        });
                      },
                    ),
                    AdwIconButton(
                      icon: Icons.add_link_rounded,
                      tooltip: 'Add Device',
                      onPressed: () {
                        if (widget.onPairDevice != null) {
                          widget.onPairDevice!();
                        } else {
                          _openPairDialog();
                        }
                      },
                    ),
                    AdwIconButton(
                      icon: Icons.settings_outlined,
                      tooltip: 'Preferences',
                      isPrimary: _subView == GnomeSubView.settings,
                      onPressed: () {
                        setState(() {
                          _subView = _subView == GnomeSubView.settings ? GnomeSubView.overview : GnomeSubView.settings;
                          _narrowShowDetail = true;
                        });
                      },
                    ),
                  ],
                ),

                // Main Content Body
                Expanded(
                  child: _buildDetailContent(selectedDevice),
                ),
              ],
            );

            return AdwSplitView(
              sidebar: sidebar,
              content: content,
              showSidebarOnNarrow: !_narrowShowDetail,
            );
          },
        ),
      ),
    );
  }

  String _getHeaderTitle(RelayDeviceVm? selectedDevice) {
    return switch (_subView) {
      GnomeSubView.settings => 'Preferences',
      GnomeSubView.activity => 'Activity',
      GnomeSubView.clipboard => 'Clipboard',
      GnomeSubView.messages => 'Messages',
      GnomeSubView.phone => 'Phone',
      GnomeSubView.overview => selectedDevice?.alias ?? 'Relay',
    };
  }

  String? _getHeaderSubtitle(RelayDeviceVm? selectedDevice) {
    if (_subView != GnomeSubView.overview) {
      return null;
    }
    return selectedDevice?.statusSummary;
  }

  Widget _buildDetailContent(RelayDeviceVm? selectedDevice) {
    if (_subView == GnomeSubView.settings) {
      return GnomeSettingsView(
        onBack: () => setState(() => _subView = GnomeSubView.overview),
      );
    }
    if (_subView == GnomeSubView.activity) {
      return GnomeActivityView(
        onBack: () => setState(() => _subView = GnomeSubView.overview),
      );
    }

    if (selectedDevice == null) {
      return ListView(
        children: [
          RelaySpatialScene(
            selfAlias: widget.vm.selfAlias,
            selfDeviceType: widget.vm.selfDeviceType,
            presence: widget.vm.presence,
            devices: widget.vm.devices,
            selectedDeviceKey: _selectedDeviceKey,
            animationsEnabled: widget.animationsEnabled,
            height: 280,
            onDeviceSelected: (device) {
              setState(() => _selectedDeviceKey = device?.key);
            },
          ),
          const AdwStatusPage(
            icon: Icons.devices_other_rounded,
            title: 'No nearby devices',
            description: 'When another device is available, select it here to send files.',
          ),
        ],
      );
    }

    if (_subView == GnomeSubView.clipboard) {
      return GnomeClipboardView(
        device: selectedDevice,
        onBack: () => setState(() => _subView = GnomeSubView.overview),
      );
    }

    if (_subView == GnomeSubView.messages) {
      return GnomeMessagesView(
        device: selectedDevice,
        onBack: () => setState(() => _subView = GnomeSubView.overview),
      );
    }

    if (_subView == GnomeSubView.phone) {
      return GnomePhoneView(
        device: selectedDevice,
        onBack: () => setState(() => _subView = GnomeSubView.overview),
      );
    }

    return ListView(
      children: [
        RelaySpatialScene(
          selfAlias: widget.vm.selfAlias,
          selfDeviceType: widget.vm.selfDeviceType,
          presence: widget.vm.presence,
          devices: widget.vm.devices,
          activeTransfer: widget.vm.activeTransfer,
          selectedDeviceKey: _selectedDeviceKey,
          animationsEnabled: widget.animationsEnabled,
          height: 280,
          onDeviceSelected: (device) {
            setState(() => _selectedDeviceKey = device?.key);
          },
          onSendFiles: (device) => _pickAndSendFiles(device),
          onOpenDetails: (device) => _openDiagnostics(device),
          onCancelTransfer: () => _cancelTransfer(),
        ),
        GnomeDeviceDetailView(
          device: selectedDevice,
          activeTransfer: widget.vm.activeTransfer,
          onSendFiles: () => _pickAndSendFiles(selectedDevice),
          onSendFolder: () => _pickAndSendFolder(selectedDevice),
          onOpenClipboard: () => setState(() => _subView = GnomeSubView.clipboard),
          onOpenMessages: () => setState(() => _subView = GnomeSubView.messages),
          onOpenPhone: () => setState(() => _subView = GnomeSubView.phone),
          onOpenDiagnostics: () => _openDiagnostics(selectedDevice),
          onCancelTransfer: () => _cancelTransfer(),
        ),
      ],
    );
  }

  Future<void> _pickAndSendFiles(RelayDeviceVm device) async {
    await ref.global.dispatchAsync(PickFileAction(option: FilePickerOption.file, context: context));
    final files = ref.read(selectedSendingFilesProvider);
    if (files.isNotEmpty) {
      await _sendToDevice(device, files);
    }
  }

  Future<void> _pickAndSendFolder(RelayDeviceVm device) async {
    await ref.global.dispatchAsync(PickFileAction(option: FilePickerOption.folder, context: context));
    final files = ref.read(selectedSendingFilesProvider);
    if (files.isNotEmpty) {
      await _sendToDevice(device, files);
    }
  }

  Future<void> _sendToDevice(RelayDeviceVm device, List<CrossFile> files) async {
    final nearbyDevice = ref.read(nearbyDevicesProvider).allDevices[device.key];
    if (nearbyDevice != null) {
      unawaited(ref.read(relaySendServiceProvider).send(target: nearbyDevice, files: files, background: true));
      return;
    }

    final relayId = device.relayId ?? (device.key.startsWith('relay:') ? device.key.substring('relay:'.length) : null);
    final route = relayId == null ? null : ref.read(relayPairedRoutesProvider).firstWhereOrNull((entry) => entry.relayId == relayId);
    final verifiedLan = relayId == null ? null : ref.read(relayVerifiedLanDevicesProvider)[relayId];

    if (relayId != null && (route != null || verifiedLan != null)) {
      unawaited(
        ref
            .read(relaySendServiceProvider)
            .sendRelayDevice(
              relayId: relayId,
              verifiedLanTarget: verifiedLan == null ? null : ref.read(nearbyDevicesProvider).allDevices[verifiedLan.device.fingerprint],
              pairedRoute: route,
              files: files,
              background: true,
            )
            .onError((error, _) {
              if (!mounted) return;
              final message = error is RelaySendFailure && error.category == 'identity'
                  ? 'Device identity could not be verified.'
                  : 'Transfer failed.';
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
            }),
      );
    }
  }

  Future<void> _cancelTransfer() async {
    final sessionId = widget.vm.activeTransfer?.sessionId;
    if (sessionId != null && await context.pushBottomSheet(() => const CancelSessionDialog()) == true) {
      ref.read(relaySendServiceProvider).cancel(sessionId);
    }
  }

  void _openDiagnostics(RelayDeviceVm device) {
    unawaited(
      showDialog<void>(
        context: context,
        builder: (_) => GnomeDiagnosticsDialog(device: device),
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
