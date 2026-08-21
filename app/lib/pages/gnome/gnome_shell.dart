import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:relay_app/config/relay_brand.dart';
import 'package:relay_app/model/cross_file.dart';
import 'package:relay_app/model/ui/relay_device_vm.dart';
import 'package:relay_app/pages/gnome/gnome_activity_view.dart';
import 'package:relay_app/pages/gnome/gnome_clipboard_view.dart';
import 'package:relay_app/pages/gnome/gnome_device_detail_view.dart';
import 'package:relay_app/pages/gnome/gnome_device_sidebar.dart';
import 'package:relay_app/pages/gnome/gnome_diagnostics_dialog.dart';
import 'package:relay_app/pages/gnome/gnome_kde_messages_view.dart';
import 'package:relay_app/pages/gnome/gnome_kde_phone_view.dart';
import 'package:relay_app/pages/gnome/gnome_messages_view.dart';
import 'package:relay_app/pages/gnome/gnome_phone_view.dart';
import 'package:relay_app/pages/gnome/gnome_settings_view.dart';
import 'package:relay_app/pages/relay_home_vm.dart';
import 'package:relay_app/provider/network/nearby_devices_provider.dart';
import 'package:relay_app/provider/network/relay_send_service.dart';
import 'package:relay_app/provider/network/server/server_provider.dart';
import 'package:relay_app/provider/relay_paired_routes_provider.dart';
import 'package:relay_app/provider/relay_verified_lan_devices_provider.dart';
import 'package:relay_app/provider/selected_device_provider.dart';
import 'package:relay_app/provider/selection/selected_sending_files_provider.dart';
import 'package:relay_app/util/native/file_picker.dart';
import 'package:relay_app/widget/dialogs/cancel_session_dialog.dart';
import 'package:relay_app/widget/dialogs/relay_pair_device_dialog.dart';
import 'package:relay_app/config/relay_motion.dart';
import 'package:relay_app/widget/gnome/adw_header_bar.dart';
import 'package:relay_app/widget/gnome/adw_split_view.dart';
import 'package:relay_app/widget/gnome/adw_status_page.dart';
import 'package:relay_app/widget/relay_carbon/relay_surface.dart';
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

  bool _initializedDevice = false;

  @override
  void initState() {
    super.initState();
    if (widget.vm.devices.isNotEmpty) {
      _selectedDeviceKey = widget.vm.devices.first.key;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initializedDevice) {
      _initializedDevice = true;
      final current = ref.read(selectedDeviceProvider);
      if (current != null && widget.vm.devices.any((d) => d.key == current)) {
        _selectedDeviceKey = current;
      } else if (_selectedDeviceKey != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            ref.notifier(selectedDeviceProvider).selectDevice(_selectedDeviceKey);
          }
        });
      }
    }
  }

  @override
  void didUpdateWidget(covariant GnomeShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.vm.devices.isNotEmpty) {
      if (_selectedDeviceKey == null || !widget.vm.devices.any((d) => d.key == _selectedDeviceKey)) {
        _selectedDeviceKey = widget.vm.devices.first.key;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            ref.notifier(selectedDeviceProvider).selectDevice(_selectedDeviceKey);
          }
        });
      }
    } else {
      _selectedDeviceKey = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ref.notifier(selectedDeviceProvider).selectDevice(null);
        }
      });
    }
  }

  List<GnomeNavDestination> _destinations(RelayDeviceVm? selectedDevice) {
    final canSendFiles = selectedDevice != null && !selectedDevice.isKdeConnect;
    return [
      const GnomeNavDestination(icon: Icons.grid_view_rounded, label: 'Overview', view: GnomeSubView.overview),
      if (canSendFiles)
        GnomeNavDestination(
          icon: Icons.send_rounded,
          label: 'Send Files',
          action: () => unawaited(_pickAndSendFiles(selectedDevice)),
        ),
      if (selectedDevice != null) const GnomeNavDestination(icon: Icons.content_paste_rounded, label: 'Clipboard', view: GnomeSubView.clipboard),
      if (selectedDevice != null) const GnomeNavDestination(icon: Icons.forum_rounded, label: 'Messages', view: GnomeSubView.messages),
      if (selectedDevice != null && (!selectedDevice.isCompatibilityPeer || selectedDevice.isKdeConnect))
        const GnomeNavDestination(icon: Icons.call_rounded, label: 'Phone', view: GnomeSubView.phone),
      const GnomeNavDestination(icon: Icons.history_rounded, label: 'Activity', view: GnomeSubView.activity),
      const GnomeNavDestination(icon: Icons.settings_rounded, label: 'Settings', view: GnomeSubView.settings),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).relayPalette;

    final activeDeviceKey = _selectedDeviceKey ?? (widget.vm.devices.isNotEmpty ? widget.vm.devices.first.key : null);

    final selectedDevice =
        widget.vm.devices.firstWhereOrNull((d) => d.key == activeDeviceKey) ?? (widget.vm.devices.isNotEmpty ? widget.vm.devices.first : null);

    return Scaffold(
      backgroundColor: palette.canvas,
      body: RelayCanvas(
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 720;

              final sidebar = GnomeDeviceSidebar(
                vm: widget.vm,
                selectedDeviceKey: activeDeviceKey,
                subView: _subView,
                destinations: _destinations(selectedDevice),
                onSelectDevice: (key) {
                  setState(() {
                    _selectedDeviceKey = key;
                    _subView = GnomeSubView.overview;
                    _narrowShowDetail = true;
                  });
                  ref.notifier(selectedDeviceProvider).selectDevice(key);
                },
                onSelectDestination: (destination) {
                  if (destination.action != null) {
                    destination.action!();
                    return;
                  }
                  setState(() {
                    _subView = destination.view ?? GnomeSubView.overview;
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
              );

              final content = Column(
                children: [
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
                  Expanded(
                    child: _PageTransition(
                      destinationKey: '${_subView.name}:${selectedDevice?.key ?? '-'}',
                      child: _buildDetailContent(selectedDevice),
                    ),
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
      return const AdwStatusPage(
        icon: Icons.devices_other_rounded,
        title: 'No devices yet',
        description: 'Pair a device, or open Relay on another device on this network, and it will appear here.',
      );
    }

    if (_subView == GnomeSubView.clipboard) {
      return GnomeClipboardView(
        device: selectedDevice,
        onBack: () => setState(() => _subView = GnomeSubView.overview),
      );
    }

    if (_subView == GnomeSubView.messages) {
      if (selectedDevice.isKdeConnect) {
        return GnomeKdeMessagesView(
          device: selectedDevice,
          onBack: () => setState(() => _subView = GnomeSubView.overview),
        );
      }
      return GnomeMessagesView(
        device: selectedDevice,
        onBack: () => setState(() => _subView = GnomeSubView.overview),
      );
    }

    if (_subView == GnomeSubView.phone) {
      if (selectedDevice.isKdeConnect) {
        return GnomeKdePhoneView(
          device: selectedDevice,
          onBack: () => setState(() => _subView = GnomeSubView.overview),
        );
      }
      return GnomePhoneView(
        device: selectedDevice,
        onBack: () => setState(() => _subView = GnomeSubView.overview),
      );
    }

    return GnomeDeviceDetailView(
      device: selectedDevice,
      devices: widget.vm.devices,
      selfAlias: widget.vm.selfAlias,
      selfDeviceType: widget.vm.selfDeviceType,
      activeTransfer: widget.vm.activeTransfer,
      animationsEnabled: widget.animationsEnabled,
      onSelectDevice: (device) {
        setState(() => _selectedDeviceKey = device.key);
        ref.notifier(selectedDeviceProvider).selectDevice(device.key);
      },
      onSendFiles: () => _pickAndSendFiles(selectedDevice),
      onSendFolder: () => _pickAndSendFolder(selectedDevice),
      onOpenClipboard: () => setState(() => _subView = GnomeSubView.clipboard),
      onOpenMessages: () => setState(() => _subView = GnomeSubView.messages),
      onOpenPhone: () => setState(() => _subView = GnomeSubView.phone),
      onOpenDiagnostics: () => _openDiagnostics(selectedDevice),
      onCancelTransfer: () => _cancelTransfer(),
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
    final transfer = widget.vm.activeTransfer;
    if (transfer != null && await context.pushBottomSheet(() => const CancelSessionDialog()) == true) {
      if (transfer.isReceive) {
        ref.notifier(serverProvider).cancelSession();
      } else {
        ref.read(relaySendServiceProvider).cancel(transfer.sessionId);
      }
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

/// Navigation between destinations: a short fade with a small vertical settle,
/// and a plain swap when the platform asks for reduced motion.
class _PageTransition extends StatelessWidget {
  final String destinationKey;
  final Widget child;

  const _PageTransition({required this.destinationKey, required this.child});

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) {
      return KeyedSubtree(key: ValueKey(destinationKey), child: child);
    }

    return AnimatedSwitcher(
      duration: RelayMotion.navigation,
      switchInCurve: RelayMotion.curve,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(begin: const Offset(0, 0.010), end: Offset.zero).animate(animation),
          child: child,
        ),
      ),
      layoutBuilder: (currentChild, previousChildren) => Stack(
        alignment: Alignment.topLeft,
        children: [...previousChildren, ?currentChild],
      ),
      child: KeyedSubtree(key: ValueKey(destinationKey), child: child),
    );
  }
}
