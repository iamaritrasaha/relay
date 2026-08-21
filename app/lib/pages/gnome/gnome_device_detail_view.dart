import 'dart:async';

import 'package:flutter/material.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:relay_app/config/relay_brand.dart';
import 'package:relay_app/config/relay_motion.dart';
import 'package:relay_app/model/ui/relay_capability_vm.dart';
import 'package:relay_app/model/ui/relay_device_vm.dart';
import 'package:relay_app/pages/relay_home_vm.dart';
import 'package:relay_app/provider/kdeconnect_provider.dart';
import 'package:relay_app/provider/receive_history_provider.dart';
import 'package:relay_app/util/native/open_file.dart';
import 'package:relay_app/util/native/open_folder.dart';
import 'package:relay_app/widget/gnome/adw_action_row.dart';
import 'package:relay_app/widget/gnome/adw_boxed_list.dart';
import 'package:relay_app/widget/gnome/adw_button.dart';
import 'package:relay_app/widget/relay/relay_device_relationship_tile.dart';
import 'package:relay_app/widget/relay_carbon/relay_action.dart';
import 'package:relay_app/widget/relay_carbon/relay_metric.dart';
import 'package:relay_app/widget/relay_carbon/relay_surface.dart';
import 'package:relay_app/widget/relay_motion/relay_breath.dart';
import 'package:relay_app/widget/relay_motion/relay_device_dock.dart';
import 'package:relay_app/widget/relay_motion/relay_edge_sweep.dart';
import 'package:relay_app/widget/relay_motion/relay_link_hero.dart';
import 'package:relay_isolates/model/device.dart';
import 'package:relay_isolates/util/file_size_helper.dart';

/// Relay's focused-device page.
///
/// The page is deliberately made of two major surfaces — the hero and the
/// content area — with the device dock, the action row and the detail rows
/// living directly on the window ground between them. Everything below reports
/// on the focused device using state the app already holds; where a reading is
/// not available the row says so rather than filling in a plausible number.
class GnomeDeviceDetailView extends StatelessWidget {
  final RelayDeviceVm device;
  final List<RelayDeviceVm> devices;
  final String selfAlias;
  final DeviceType selfDeviceType;
  final RelayTransferVm? activeTransfer;
  final bool animationsEnabled;
  final ValueChanged<RelayDeviceVm>? onSelectDevice;
  final VoidCallback onSendFiles;
  final VoidCallback onSendFolder;
  final VoidCallback onOpenClipboard;
  final VoidCallback onOpenMessages;
  final VoidCallback onOpenPhone;
  final VoidCallback onOpenDiagnostics;
  final VoidCallback? onCancelTransfer;

  const GnomeDeviceDetailView({
    super.key,
    required this.device,
    this.devices = const [],
    this.selfAlias = '',
    this.selfDeviceType = DeviceType.desktop,
    this.activeTransfer,
    this.animationsEnabled = true,
    this.onSelectDevice,
    required this.onSendFiles,
    required this.onSendFolder,
    required this.onOpenClipboard,
    required this.onOpenMessages,
    required this.onOpenPhone,
    required this.onOpenDiagnostics,
    this.onCancelTransfer,
  });

  bool get _connected => device.statusSummary == 'Connected' || device.statusSummary.startsWith('Connected · ') || device.continuityConnected;

  bool get _transferring =>
      device.phase == RelayDevicePhase.sending || device.phase == RelayDevicePhase.waiting || device.phase == RelayDevicePhase.verifying;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final horizontal = width >= 1100 ? 44.0 : (width >= 760 ? 32.0 : 22.0);

        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(horizontal, 26, horizontal, 44),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1360),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Hero(
                    device: device,
                    selfAlias: selfAlias,
                    selfDeviceType: selfDeviceType,
                    connected: _connected,
                    activeTransfer: _transferring ? activeTransfer : null,
                    animationsEnabled: animationsEnabled,
                  ),
                  if (devices.length > 1 && onSelectDevice != null) ...[
                    const SizedBox(height: 20),
                    RelayDeviceDock(
                      devices: devices,
                      selectedKey: device.key,
                      animationsEnabled: animationsEnabled,
                      onSelect: onSelectDevice!,
                    ),
                  ],
                  const SizedBox(height: 22),
                  _ActionRow(
                    device: device,
                    onSendFiles: onSendFiles,
                    onSendFolder: onSendFolder,
                    onOpenClipboard: onOpenClipboard,
                    onOpenMessages: onOpenMessages,
                    onOpenPhone: onOpenPhone,
                  ),
                  if (_transferring && activeTransfer != null) ...[
                    const SizedBox(height: 20),
                    _TransferStrip(device: device, transfer: activeTransfer!, onCancelTransfer: onCancelTransfer),
                  ],
                  const SizedBox(height: 22),
                  _ContentArea(device: device, connected: _connected),
                  const SizedBox(height: 34),
                  _DeviceDetails(device: device, onOpenDiagnostics: onOpenDiagnostics),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The focused device and its link to this desktop. Compact on purpose: the
/// relationship is the point, not the empty space around it.
class _Hero extends StatelessWidget {
  final RelayDeviceVm device;
  final String selfAlias;
  final DeviceType selfDeviceType;
  final bool connected;
  final RelayTransferVm? activeTransfer;
  final bool animationsEnabled;

  const _Hero({
    required this.device,
    required this.selfAlias,
    required this.selfDeviceType,
    required this.connected,
    required this.activeTransfer,
    required this.animationsEnabled,
  });

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).relayPalette;

    final identity = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        RelayStatusPill(
          tone: switch (device.phase) {
            RelayDevicePhase.failed => RelayPresenceTone.attention,
            RelayDevicePhase.sending || RelayDevicePhase.waiting || RelayDevicePhase.verifying => RelayPresenceTone.busy,
            _ => connected ? RelayPresenceTone.online : RelayPresenceTone.offline,
          },
          label: device.statusSummary,
          compact: true,
        ),
        const SizedBox(height: 10),
        Text(
          device.alias,
          style: RelayTypography.deviceName(palette.textPrimary),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        if (selfAlias.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            connected ? 'Connected to $selfAlias' : 'Paired with $selfAlias',
            style: RelayTypography.subtitle(palette.textSecondary, isGnome: true),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    );

    final link = RelayLinkHero(
      device: device,
      selfAlias: selfAlias.isEmpty ? 'This desktop' : selfAlias,
      selfDeviceType: selfDeviceType,
      connected: connected,
      activeTransfer: activeTransfer,
      animationsEnabled: animationsEnabled,
    );

    final surface = RelaySurface(
      radius: RelayRadius.hero,
      padding: const EdgeInsets.fromLTRB(30, 26, 30, 26),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Wide enough to sit the identity and the link side by side, which is
          // what keeps the hero short instead of stacking into a tall band.
          if (constraints.maxWidth >= 720) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(flex: 5, child: identity),
                const SizedBox(width: 28),
                Expanded(flex: 6, child: link),
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              identity,
              const SizedBox(height: 24),
              link,
            ],
          );
        },
      ),
    );

    // The sweep sits outside the breath so its travelling segment lands on top
    // of the breathing edge rather than under the breath's wash.
    return RelayEdgeSweep(
      ambient: connected,
      animationsEnabled: animationsEnabled,
      trigger: activeTransfer != null || device.phase == RelayDevicePhase.sending || device.phase == RelayDevicePhase.success,
      radius: RelayRadius.hero,
      child: RelayBreath(
        active: connected,
        animationsEnabled: animationsEnabled,
        radius: RelayRadius.hero,
        child: surface,
      ),
    );
  }
}

/// The primary action row. Only actions this device can really perform.
class _ActionRow extends StatelessWidget {
  final RelayDeviceVm device;
  final VoidCallback onSendFiles;
  final VoidCallback onSendFolder;
  final VoidCallback onOpenClipboard;
  final VoidCallback onOpenMessages;
  final VoidCallback onOpenPhone;

  const _ActionRow({
    required this.device,
    required this.onSendFiles,
    required this.onSendFolder,
    required this.onOpenClipboard,
    required this.onOpenMessages,
    required this.onOpenPhone,
  });

  static bool _usable(CapabilityStatus? status) => switch (status) {
    CapabilityStatus.available || CapabilityStatus.limited => true,
    _ => false,
  };

  @override
  Widget build(BuildContext context) {
    final deviceId = device.key.replaceFirst('kdeconnect:', '');

    final actions = <Widget>[
      if (!device.isKdeConnect) ...[
        RelayAction(
          key: const ValueKey('gnome-send-files-button'),
          icon: Icons.arrow_upward_rounded,
          label: 'Send Files',
          primary: true,
          onPressed: onSendFiles,
        ),
        RelayAction(
          key: const ValueKey('gnome-send-folder-button'),
          icon: Icons.folder_outlined,
          label: 'Send Folder',
          onPressed: onSendFolder,
        ),
        RelayAction(
          key: const ValueKey('gnome-clipboard-button'),
          icon: Icons.content_paste_rounded,
          label: 'Clipboard',
          onPressed: onOpenClipboard,
        ),
        RelayAction(
          key: const ValueKey('gnome-messages-button'),
          icon: Icons.chat_bubble_outline_rounded,
          label: 'Messages',
          onPressed: onOpenMessages,
        ),
        if (!device.isCompatibilityPeer)
          RelayAction(
            key: const ValueKey('gnome-phone-button'),
            icon: Icons.call_outlined,
            label: 'Phone',
            onPressed: onOpenPhone,
          ),
      ] else if (device.isPaired) ...[
        if (_usable(device.capabilityStatuses[RelayCapability.clipboard]))
          RelayAction(
            key: const ValueKey('gnome-clipboard-button'),
            icon: Icons.content_paste_rounded,
            label: 'Clipboard',
            primary: true,
            onPressed: onOpenClipboard,
          ),
        if (_usable(device.capabilityStatuses[RelayCapability.messages]))
          RelayAction(
            key: const ValueKey('gnome-messages-button'),
            icon: Icons.chat_bubble_outline_rounded,
            label: 'Messages',
            onPressed: onOpenMessages,
          ),
        if (_usable(device.capabilityStatuses[RelayCapability.phone]))
          RelayAction(
            key: const ValueKey('gnome-phone-button'),
            icon: Icons.call_outlined,
            label: 'Phone',
            onPressed: onOpenPhone,
          ),
        RelayAction(
          icon: Icons.wifi_tethering_rounded,
          label: 'Ping',
          hint: device.canPing ? 'Check if this phone is reachable' : 'This phone has not advertised ping',
          enabled: device.canPing,
          onPressed: device.canPing ? () => unawaited(context.ref.redux(kdeConnectProvider).dispatchAsync(KdeConnectPingAction(deviceId))) : null,
        ),
        RelayAction(
          icon: Icons.ring_volume_outlined,
          label: 'Find Phone',
          hint: device.canFindDevice ? 'Ring this phone even if it is on silent' : 'This phone has not advertised find device',
          enabled: device.canFindDevice,
          onPressed: device.canFindDevice
              ? () => unawaited(context.ref.redux(kdeConnectProvider).dispatchAsync(KdeConnectFindPhoneAction(deviceId)))
              : null,
        ),
      ],
    ];

    if (actions.isEmpty) {
      return const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 900
            ? actions.length
            : constraints.maxWidth >= 620
            ? 3
            : 2;
        final itemWidth = ((constraints.maxWidth - (columns - 1) * 10) / columns).clamp(120.0, 186.0);
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final action in actions) SizedBox(width: itemWidth, child: action),
          ],
        );
      },
    );
  }
}

/// Progress for the one transfer that is genuinely in flight.
class _TransferStrip extends StatelessWidget {
  final RelayDeviceVm device;
  final RelayTransferVm transfer;
  final VoidCallback? onCancelTransfer;

  const _TransferStrip({required this.device, required this.transfer, this.onCancelTransfer});

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).relayPalette;
    final reducedMotion = MediaQuery.disableAnimationsOf(context);

    // A live transfer is a continuously true state, not a one-off event, so the
    // strip carries the ambient segment for as long as it is on screen.
    return RelayEdgeSweep(
      ambient: !reducedMotion,
      radius: RelayRadius.panel,
      child: RelaySurface(
        radius: RelayRadius.panel,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        accented: true,
        outlined: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    transfer.isReceive ? 'Receiving from ${device.alias}…' : 'Sending to ${device.alias}…',
                    style: RelayTypography.body(palette.textPrimary, isGnome: true, bold: true),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (transfer.progress != null)
                  AnimatedSwitcher(
                    duration: reducedMotion ? Duration.zero : RelayMotion.state,
                    child: Text(
                      '${((transfer.progress ?? 0) * 100).toStringAsFixed(0)}%',
                      key: ValueKey(((transfer.progress ?? 0) * 100).toStringAsFixed(0)),
                      style: RelayTypography.body(palette.accent, isGnome: true, bold: true),
                    ),
                  ),
                if (onCancelTransfer != null) ...[
                  const SizedBox(width: 12),
                  AdwButton.flat(label: 'Cancel', onPressed: onCancelTransfer),
                ],
              ],
            ),
            if (transfer.progress != null) ...[
              const SizedBox(height: 12),
              RelayLevelBar(fraction: transfer.progress!.clamp(0.0, 1.0), color: palette.accent, height: 4),
            ],
          ],
        ),
      ),
    );
  }
}

/// One content surface, split into columns by hairlines rather than into
/// separate floating cards.
class _ContentArea extends StatelessWidget {
  final RelayDeviceVm device;
  final bool connected;

  const _ContentArea({required this.device, required this.connected});

  @override
  Widget build(BuildContext context) {
    final sections = <Widget>[
      _RecentActivitySection(),
      _DeviceStatusSection(device: device, connected: connected),
      _NotificationsSection(device: device),
    ];

    return RelaySurface(
      padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 28),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final available = constraints.maxWidth;
          final columns = available >= 1000 ? 3 : (available >= 700 ? 2 : 1);

          if (columns == 1) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < sections.length; i++) ...[
                  if (i > 0) ...[
                    const SizedBox(height: 22),
                    const RelayDivider(),
                    const SizedBox(height: 22),
                  ],
                  sections[i],
                ],
              ],
            );
          }

          final rows = <List<Widget>>[];
          for (var i = 0; i < sections.length; i += columns) {
            rows.add(sections.sublist(i, (i + columns).clamp(0, sections.length)));
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var r = 0; r < rows.length; r++) ...[
                if (r > 0) ...[
                  const SizedBox(height: 28),
                  const RelayDivider(),
                  const SizedBox(height: 28),
                ],
                _ColumnRow(sections: rows[r]),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// A row of sections with a hairline rule drawn down each gap.
///
/// The rules are painted rather than laid out so the row never has to report
/// intrinsic dimensions: a column of wrapping text measures differently
/// unconstrained than it lays out, which is exactly the mismatch that makes an
/// intrinsic-height row overflow.
class _ColumnRow extends StatelessWidget {
  final List<Widget> sections;

  static const double _gap = 60;

  const _ColumnRow({required this.sections});

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).relayPalette;

    return CustomPaint(
      foregroundPainter: _ColumnRulesPainter(count: sections.length, gap: _gap, color: palette.hairline),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var c = 0; c < sections.length; c++) ...[
            if (c > 0) const SizedBox(width: _gap),
            Expanded(child: sections[c]),
          ],
        ],
      ),
    );
  }
}

class _ColumnRulesPainter extends CustomPainter {
  final int count;
  final double gap;
  final Color color;

  const _ColumnRulesPainter({required this.count, required this.gap, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (count < 2) {
      return;
    }
    final columnWidth = (size.width - gap * (count - 1)) / count;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    for (var i = 1; i < count; i++) {
      final x = i * columnWidth + (i - 0.5) * gap;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ColumnRulesPainter old) => old.count != count || old.gap != gap || old.color != color;
}

class _RecentActivitySection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).relayPalette;
    final history = context.watch(receiveHistoryProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const RelaySectionLabel(label: 'Recent Activity'),
        const SizedBox(height: 20),
        if (history.isEmpty)
          const _EmptySection(icon: Icons.inbox_outlined, title: 'Nothing yet', body: 'Files you send or receive appear here.')
        else
          for (final entry in history.take(5))
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Icon(
                      entry.isMessage ? Icons.chat_bubble_outline_rounded : Icons.description_outlined,
                      size: 16,
                      color: palette.textTertiary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          entry.fileName,
                          style: RelayTypography.body(palette.textPrimary, isGnome: true),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${entry.senderAlias} · ${entry.fileSize.asReadableFileSize} · ${_formatDate(entry.timestamp)}',
                          style: RelayTypography.caption(palette.textTertiary, isGnome: true),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  if (entry.path != null) ...[
                    _QuietIconButton(
                      icon: Icons.folder_open_outlined,
                      tooltip: 'Open Folder',
                      onPressed: () => openFolder(folderPath: entry.path!),
                    ),
                    _QuietIconButton(
                      icon: Icons.open_in_new_rounded,
                      tooltip: 'Open File',
                      onPressed: () => openFile(context, entry.fileType, entry.path!),
                    ),
                  ],
                ],
              ),
            ),
      ],
    );
  }

  static String _formatDate(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays == 1) return 'Yesterday';
    return '${dt.month}/${dt.day}';
  }
}

class _DeviceStatusSection extends StatelessWidget {
  final RelayDeviceVm device;
  final bool connected;

  const _DeviceStatusSection({required this.device, required this.connected});

  static Color? batteryTint(RelayPalette palette, int percentage, bool charging) {
    if (charging) return palette.success;
    if (percentage <= 15) return palette.error;
    if (percentage <= 30) return palette.warning;
    return null;
  }

  static String signalLabel(int? level) => switch (level) {
    final value when value == null || value <= 0 => 'Unavailable',
    1 => 'Weak',
    2 => 'Fair',
    3 => 'Good',
    _ => 'Excellent',
  };

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).relayPalette;
    final battery = device.battery;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const RelaySectionLabel(label: 'Device Status'),
        const SizedBox(height: 10),
        RelayStatRow(
          label: 'Connection',
          value: connected ? 'Connected' : device.statusSummary,
          tint: connected ? palette.success : null,
        ),
        const RelayDivider(),
        RelayStatRow(
          label: 'Battery',
          value: battery.hasInfo ? '${battery.percentage}%' : '—',
          fraction: battery.hasInfo ? (battery.percentage ?? 0) / 100 : null,
          tint: battery.hasInfo ? batteryTint(palette, battery.percentage ?? 0, battery.isCharging) : null,
          barColor: palette.textSecondary,
        ),
        const RelayDivider(),
        RelayStatRow(
          label: 'Signal',
          value: device.networkType == null && device.signalLevel == null
              ? '—'
              : '${device.networkType ?? 'Mobile'} · ${signalLabel(device.signalLevel)}',
          level: device.signalLevel,
        ),
        const RelayDivider(),
        RelayStatRow(label: 'Device', value: device.deviceModel ?? device.alias),
        const SizedBox(height: 18),
        Align(
          alignment: Alignment.centerLeft,
          child: device.isKdeConnect
              ? _KdeConnectRelationshipTile(device: device)
              : (device.isCompatibilityPeer ? const SizedBox.shrink() : RelayDeviceRelationshipTile(device: device)),
        ),
      ],
    );
  }
}

/// Notifications forwarded by the focused phone. Real entries only — when
/// nothing has arrived the section says nothing has arrived.
class _NotificationsSection extends StatelessWidget {
  final RelayDeviceVm device;

  const _NotificationsSection({required this.device});

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).relayPalette;

    if (!device.isKdeConnect || !device.isPaired) {
      return const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          RelaySectionLabel(label: 'Notifications'),
          SizedBox(height: 20),
          _EmptySection(
            icon: Icons.notifications_off_outlined,
            title: 'Not available',
            body: 'This device does not forward notifications to Relay.',
          ),
        ],
      );
    }

    final rawId = device.key.replaceFirst('kdeconnect:', '');
    final notifications = context.watch(kdeConnectProvider.select((s) => s.notifications[rawId] ?? const []));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const RelaySectionLabel(label: 'Notifications'),
        const SizedBox(height: 20),
        if (notifications.isEmpty)
          const _EmptySection(
            icon: Icons.notifications_none_rounded,
            title: 'All clear',
            body: 'Notifications from this phone appear here.',
          )
        else
          for (final notification in notifications.take(5))
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    notification.title?.isNotEmpty == true ? notification.title! : (notification.appName ?? 'Notification'),
                    style: RelayTypography.body(palette.textPrimary, isGnome: true, bold: true),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (notification.appName != null && notification.title?.isNotEmpty == true)
                    Text(
                      notification.appName!,
                      style: RelayTypography.caption(palette.textTertiary, isGnome: true),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  if (notification.text != null && notification.text!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        notification.text!,
                        style: RelayTypography.caption(palette.textSecondary, isGnome: true),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              ),
            ),
      ],
    );
  }
}

/// A lightweight empty state: an icon, a line, a sentence. No inset rectangle.
class _EmptySection extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;

  const _EmptySection({required this.icon, required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).relayPalette;
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 19, color: palette.textTertiary),
          const SizedBox(height: 10),
          Text(title, style: RelayTypography.body(palette.textSecondary, isGnome: true)),
          const SizedBox(height: 3),
          Text(body, style: RelayTypography.caption(palette.textTertiary, isGnome: true)),
        ],
      ),
    );
  }
}

class _QuietIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  const _QuietIconButton({required this.icon, required this.tooltip, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).relayPalette;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(5),
          child: Icon(icon, size: 16, color: palette.textTertiary),
        ),
      ),
    );
  }
}

/// The technical rows, kept at the very bottom as a borderless section. This is
/// where the backend a device happens to speak belongs.
class _DeviceDetails extends StatelessWidget {
  final RelayDeviceVm device;
  final VoidCallback onOpenDiagnostics;

  const _DeviceDetails({required this.device, required this.onOpenDiagnostics});

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).relayPalette;

    return AdwPreferencesGroup(
      title: 'Device Details',
      margin: EdgeInsets.zero,
      children: [
        AdwActionRow(
          leading: const Icon(Icons.wifi_rounded),
          title: 'Connection',
          subtitle: device.isKdeConnect
              ? device.detail == 'Connected'
                    ? 'Connected on your local network'
                    : device.detail == 'Paired'
                    ? 'Paired'
                    : 'Nearby on your local network'
              : device.isCompatibilityPeer
              ? 'Nearby on your local network'
              : device.connectionType == RelayConnectionType.direct
              ? 'Direct connection'
              : device.connectionType == RelayConnectionType.relayed
              ? 'Connected remotely'
              : 'Nearby on your local network',
        ),
        AdwActionRow(
          leading: Icon(device.isVerifiedRelay ? Icons.verified_user_rounded : Icons.info_outline_rounded),
          title: 'Device verification',
          subtitle: device.isKdeConnect
              ? 'KDE Connect'
              : device.isVerifiedRelay
              ? 'Authenticated Relay device identity'
              : 'Relay-compatible device (unauthenticated)',
        ),
        AdwActionRow(
          leading: const Icon(Icons.battery_std_rounded),
          title: 'Battery',
          subtitle: switch (device.battery) {
            final battery when !battery.hasInfo =>
              device.isKdeConnect
                  ? 'Waiting for battery status'
                  : device.isCompatibilityPeer
                  ? 'LocalSend-compatible devices do not share battery status'
                  : 'Not shared by this device',
            final battery when battery.isStale => 'Last known before disconnecting',
            final battery when battery.isFull => 'Charged',
            final battery when battery.isCharging => 'Charging',
            _ => 'On battery',
          },
          trailing: Text(
            device.battery.hasInfo ? '${device.battery.percentage}%' : '—',
            style: RelayTypography.body(palette.textSecondary, isGnome: true),
          ),
        ),
        if (!device.isKdeConnect)
          AdwNavigationRow(
            leading: const Icon(Icons.tune_rounded),
            title: 'Security & diagnostics',
            subtitle: 'Verify this device and view technical details',
            onTap: onOpenDiagnostics,
          ),
      ],
    );
  }
}

class _KdeConnectRelationshipTile extends StatelessWidget {
  final RelayDeviceVm device;

  const _KdeConnectRelationshipTile({required this.device});

  String get _deviceId => device.key.startsWith('kdeconnect:') ? device.key.substring('kdeconnect:'.length) : device.key;

  @override
  Widget build(BuildContext context) {
    final paired = device.detail == 'Paired' || device.detail == 'Connected';

    if (paired) {
      return AdwButton.destructive(
        key: const ValueKey('kdeconnect-remove-device'),
        icon: Icons.link_off_rounded,
        label: 'Remove Device',
        onPressed: () => unawaited(context.redux(kdeConnectProvider).dispatchAsync(KdeConnectUnpairAction(_deviceId))),
      );
    }
    return AdwButton.suggested(
      key: const ValueKey('kdeconnect-pair-device'),
      icon: Icons.link_rounded,
      label: 'Pair',
      onPressed: () => unawaited(context.redux(kdeConnectProvider).dispatchAsync(KdeConnectRequestPairAction(_deviceId))),
    );
  }
}
