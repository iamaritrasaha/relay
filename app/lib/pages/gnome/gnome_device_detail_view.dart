import 'dart:async';
import 'dart:math' as math;

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
import 'package:relay_app/widget/gnome/relay_connection_stage.dart';
import 'package:relay_app/widget/gnome/relay_connection_status.dart';
import 'package:relay_app/widget/relay/relay_device_relationship_tile.dart';
import 'package:relay_app/widget/relay_carbon/relay_surface.dart';
import 'package:relay_app/widget/relay_motion/relay_ambient_clock.dart';
import 'package:relay_app/widget/relay_motion/relay_atmospheric_drift.dart';
import 'package:relay_app/widget/relay_motion/relay_breath.dart';
import 'package:relay_app/widget/relay_motion/relay_device_dock.dart';
import 'package:relay_app/widget/relay_motion/relay_edge_sweep.dart';
import 'package:relay_app/widget/relay_motion/relay_section_reveal.dart';
import 'package:relay_isolates/model/device.dart';
import 'package:relay_isolates/util/file_size_helper.dart';
import 'package:yaru/yaru.dart';

const double _overviewMaxWidth = 1080;
const double _overviewGridBreakpoint = 860;
const double _overviewGridGutter = 18;
const double _overviewSectionGap = 24;
const double _overviewTitleGap = 10;
const double _overviewPrimaryGap = 18;
const double _overviewDetailsGap = 26;

/// Relay's focused-device page in GNOME / Yaru design system.
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
        final horizontal = width >= 960 ? 32.0 : (width >= 640 ? 24.0 : 16.0);
        final theme = Theme.of(context);
        final devicePalette = RelayDevicePalette.fromDevice(device, brightness: theme.brightness);

        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(horizontal, 20, horizontal, 36),
          child: Center(
            child: ConstrainedBox(
              key: const ValueKey('overview-master-content'),
              constraints: const BoxConstraints(maxWidth: _overviewMaxWidth),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  GnomeSelectedDeviceHeader(
                    device: device,
                    selfAlias: selfAlias,
                    selfDeviceType: selfDeviceType,
                    connected: _connected,
                    animationsEnabled: animationsEnabled,
                  ),
                  if (devices.length > 1 && onSelectDevice != null) ...[
                    const SizedBox(height: 16),
                    RelayDeviceDock(
                      key: const ValueKey('overview-device-selector'),
                      devices: devices,
                      selectedKey: device.key,
                      animationsEnabled: animationsEnabled,
                      onSelect: onSelectDevice!,
                    ),
                  ],
                  const SizedBox(height: 16),
                  KeyedSubtree(
                    key: const ValueKey('overview-quick-actions'),
                    child: _ActionRow(
                      device: device,
                      palette: devicePalette,
                      animationsEnabled: animationsEnabled,
                      onSendFiles: onSendFiles,
                      onSendFolder: onSendFolder,
                      onOpenClipboard: onOpenClipboard,
                      onOpenMessages: onOpenMessages,
                      onOpenPhone: onOpenPhone,
                    ),
                  ),
                  if (_transferring && activeTransfer != null) ...[
                    const SizedBox(height: 16),
                    _TransferStrip(
                      device: device,
                      transfer: activeTransfer!,
                      palette: devicePalette,
                      onCancelTransfer: onCancelTransfer,
                    ),
                  ],
                  const SizedBox(height: _overviewPrimaryGap),
                  _ContentArea(
                    device: device,
                    palette: devicePalette,
                    connected: _connected,
                    animationsEnabled: animationsEnabled,
                  ),
                  const SizedBox(height: _overviewDetailsGap),
                  RelaySectionReveal(
                    index: 2,
                    animationsEnabled: animationsEnabled,
                    child: _DeviceDetails(
                      device: device,
                      palette: devicePalette,
                      connected: _connected,
                      animationsEnabled: animationsEnabled,
                      onOpenDiagnostics: onOpenDiagnostics,
                    ),
                  ),
                  if (!device.isCompatibilityPeer) ...[
                    const SizedBox(height: 18),
                    _DeviceMaintenanceAction(device: device),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The multi-layered ambient showpiece in the GNOME shell.
///
/// Combines:
/// Layer A: Travelling multicolor perimeter sweep
/// Layer B: Atmospheric gradient drift
/// Layer C: Subtle multicolor breath
/// Layer D: Connection Stage (Remote silhouette ↔ Relay Link Core ↔ Local silhouette)
/// Layer E: Device-palette connection indicator & Secure state
class GnomeSelectedDeviceHeader extends StatelessWidget {
  final RelayDeviceVm device;
  final String selfAlias;
  final DeviceType selfDeviceType;
  final bool selected;
  final bool connected;
  final bool animationsEnabled;

  const GnomeSelectedDeviceHeader({
    super.key,
    required this.device,
    required this.selfAlias,
    required this.selfDeviceType,
    this.selected = true,
    required this.connected,
    required this.animationsEnabled,
  });

  @override
  Widget build(BuildContext context) {
    final active = selected && connected;
    final theme = Theme.of(context);
    final devicePalette = RelayDevicePalette.fromDevice(device, brightness: theme.brightness);

    return RelayEdgeSweep(
      key: const ValueKey('selected-device-edge-sweep'),
      radius: RelayRadius.hero,
      palette: devicePalette,
      ambient: active,
      animationsEnabled: animationsEnabled,
      child: RelayAtmosphericDrift(
        key: const ValueKey('selected-device-drift'),
        radius: RelayRadius.hero,
        palette: devicePalette,
        active: active,
        animationsEnabled: animationsEnabled,
        child: RelayBreath(
          key: const ValueKey('selected-device-breath'),
          radius: RelayRadius.hero,
          palette: devicePalette,
          active: active,
          animationsEnabled: animationsEnabled,
          child: _DeviceHeader(
            device: device,
            palette: devicePalette,
            selfAlias: selfAlias,
            selfDeviceType: selfDeviceType,
            connected: connected,
            animationsEnabled: animationsEnabled,
          ),
        ),
      ),
    );
  }
}

/// The focused device header with Connection Stage.
class _DeviceHeader extends StatelessWidget {
  final RelayDeviceVm device;
  final RelayDevicePalette palette;
  final String selfAlias;
  final DeviceType selfDeviceType;
  final bool connected;
  final bool animationsEnabled;

  const _DeviceHeader({
    required this.device,
    required this.palette,
    required this.selfAlias,
    required this.selfDeviceType,
    required this.connected,
    this.animationsEnabled = true,
  });

  bool get _isSecure =>
      connected &&
      (device.isCompatibilityPeer ||
          device.continuityConnected ||
          device.isPaired ||
          device.isVerifiedRelay ||
          device.isPairedRelay ||
          device.targetKind == RelayDeviceTargetKind.kdeConnect);

  bool get _connecting => device.phase == RelayDevicePhase.waiting || device.phase == RelayDevicePhase.verifying;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final tone = switch (device.phase) {
      RelayDevicePhase.failed => RelayPresenceTone.attention,
      RelayDevicePhase.sending || RelayDevicePhase.waiting || RelayDevicePhase.verifying => RelayPresenceTone.busy,
      _ => connected ? RelayPresenceTone.online : RelayPresenceTone.offline,
    };

    return YaruBorderContainer(
      borderRadius: BorderRadius.circular(RelayRadius.hero),
      clipBehavior: Clip.antiAlias,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Top Identity Row
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      device.alias,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      selfAlias.isNotEmpty
                          ? (connected ? 'Connected to $selfAlias' : 'Paired with $selfAlias')
                          : (connected ? 'Connected' : 'Paired'),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurface.withValues(alpha: 0.7),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              if (device.phase == RelayDevicePhase.idle)
                RelayConnectionStatus(
                  connected: connected,
                  label: connected ? device.statusSummary : device.detail,
                  palette: palette,
                  animationsEnabled: animationsEnabled,
                  ambient: true,
                  compact: true,
                )
              else
                RelayStatusPill(
                  tone: tone,
                  label: device.statusSummary,
                  compact: true,
                ),
            ],
          ),
          const SizedBox(height: 16),
          // Live Connection Stage
          RelayConnectionStage(
            device: device,
            palette: palette,
            selfAlias: selfAlias,
            selfDeviceType: selfDeviceType,
            connected: connected,
            connecting: _connecting,
            animationsEnabled: animationsEnabled,
          ),
          if (_isSecure) ...[
            const SizedBox(height: 10),
            Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    YaruIcons.lock,
                    size: 13,
                    color: colorScheme.onSurface.withValues(alpha: 0.60),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    'Secure connection',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colorScheme.onSurface.withValues(alpha: 0.65),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The primary action row with tactile press and finite interaction animations.
class _ActionRow extends StatelessWidget {
  final RelayDeviceVm device;
  final RelayDevicePalette palette;
  final bool animationsEnabled;
  final VoidCallback onSendFiles;
  final VoidCallback onSendFolder;
  final VoidCallback onOpenClipboard;
  final VoidCallback onOpenMessages;
  final VoidCallback onOpenPhone;

  const _ActionRow({
    required this.device,
    required this.palette,
    this.animationsEnabled = true,
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
        FilledButton.icon(
          key: const ValueKey('gnome-send-files-button'),
          icon: const Icon(YaruIcons.send, size: 18),
          label: const Text('Send Files'),
          onPressed: onSendFiles,
        ),
        OutlinedButton.icon(
          key: const ValueKey('gnome-send-folder-button'),
          icon: const Icon(YaruIcons.folder, size: 18),
          label: const Text('Send Folder'),
          onPressed: onSendFolder,
        ),
        OutlinedButton.icon(
          key: const ValueKey('gnome-clipboard-button'),
          icon: const Icon(YaruIcons.copy, size: 18),
          label: const Text('Clipboard'),
          onPressed: onOpenClipboard,
        ),
        OutlinedButton.icon(
          key: const ValueKey('gnome-messages-button'),
          icon: const Icon(YaruIcons.chat_bubble, size: 18),
          label: const Text('Messages'),
          onPressed: onOpenMessages,
        ),
        if (!device.isCompatibilityPeer)
          OutlinedButton.icon(
            key: const ValueKey('gnome-phone-button'),
            icon: const Icon(YaruIcons.phone, size: 18),
            label: const Text('Phone'),
            onPressed: onOpenPhone,
          ),
      ] else if (device.isPaired) ...[
        if (_usable(device.capabilityStatuses[RelayCapability.clipboard]))
          FilledButton.icon(
            key: const ValueKey('gnome-clipboard-button'),
            icon: const Icon(YaruIcons.copy, size: 18),
            label: const Text('Clipboard'),
            onPressed: onOpenClipboard,
          ),
        if (_usable(device.capabilityStatuses[RelayCapability.messages]))
          OutlinedButton.icon(
            key: const ValueKey('gnome-messages-button'),
            icon: const Icon(YaruIcons.chat_bubble, size: 18),
            label: const Text('Messages'),
            onPressed: onOpenMessages,
          ),
        if (_usable(device.capabilityStatuses[RelayCapability.phone]))
          OutlinedButton.icon(
            key: const ValueKey('gnome-phone-button'),
            icon: const Icon(YaruIcons.phone, size: 18),
            label: const Text('Phone'),
            onPressed: onOpenPhone,
          ),
        _PingActionButton(
          palette: palette,
          animationsEnabled: animationsEnabled,
          enabled: device.canPing,
          onPressed: () => unawaited(context.ref.redux(kdeConnectProvider).dispatchAsync(KdeConnectPingAction(deviceId))),
        ),
        _FindPhoneActionButton(
          palette: palette,
          animationsEnabled: animationsEnabled,
          enabled: device.canFindDevice,
          onPressed: () => unawaited(context.ref.redux(kdeConnectProvider).dispatchAsync(KdeConnectFindPhoneAction(deviceId))),
        ),
      ],
    ];

    if (actions.isEmpty) {
      return const SizedBox.shrink();
    }

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: actions,
    );
  }
}

/// Ping action with 3 staggered expanding visual ripple rings upon trigger.
class _PingActionButton extends StatefulWidget {
  final RelayDevicePalette palette;
  final bool animationsEnabled;
  final bool enabled;
  final VoidCallback onPressed;

  const _PingActionButton({
    required this.palette,
    required this.animationsEnabled,
    required this.enabled,
    required this.onPressed,
  });

  @override
  State<_PingActionButton> createState() => _PingActionButtonState();
}

class _PingActionButtonState extends State<_PingActionButton> with SingleTickerProviderStateMixin {
  late final AnimationController _ripple;

  @override
  void initState() {
    super.initState();
    _ripple = AnimationController(vsync: this, duration: RelayMotion.pingRipple);
  }

  @override
  void dispose() {
    _ripple.dispose();
    super.dispose();
  }

  void _trigger() {
    widget.onPressed();
    if (widget.animationsEnabled && !(MediaQuery.maybeDisableAnimationsOf(context) ?? false)) {
      unawaited(_ripple.forward(from: 0));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        if (_ripple.isAnimating)
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _ripple,
              builder: (context, _) {
                final t = _ripple.value;
                return CustomPaint(
                  painter: _PingRipplePainter(progress: t, color: widget.palette.primary),
                );
              },
            ),
          ),
        OutlinedButton.icon(
          icon: const Icon(YaruIcons.network_wireless, size: 18),
          label: const Text('Ping'),
          onPressed: widget.enabled ? _trigger : null,
        ),
      ],
    );
  }
}

class _PingRipplePainter extends CustomPainter {
  final double progress;
  final Color color;

  _PingRipplePainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    for (int i = 0; i < 3; i++) {
      final ringProgress = (progress - (i * 0.18)).clamp(0.0, 1.0);
      if (ringProgress <= 0 || ringProgress >= 1.0) continue;

      final radius = (size.width / 2) * (0.8 + ringProgress * 0.8);
      final alpha = (1.0 - ringProgress) * 0.45;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8 * (1.0 - ringProgress)
        ..color = color.withValues(alpha: alpha);
      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _PingRipplePainter oldDelegate) => oldDelegate.progress != progress;
}

/// Find Phone action with finite phone wiggle oscillation on trigger.
class _FindPhoneActionButton extends StatefulWidget {
  final RelayDevicePalette palette;
  final bool animationsEnabled;
  final bool enabled;
  final VoidCallback onPressed;

  const _FindPhoneActionButton({
    required this.palette,
    required this.animationsEnabled,
    required this.enabled,
    required this.onPressed,
  });

  @override
  State<_FindPhoneActionButton> createState() => _FindPhoneActionButtonState();
}

class _FindPhoneActionButtonState extends State<_FindPhoneActionButton> with SingleTickerProviderStateMixin {
  late final AnimationController _wiggle;
  late final Animation<double> _rotation;

  @override
  void initState() {
    super.initState();
    _wiggle = AnimationController(vsync: this, duration: RelayMotion.findPhoneVibrate);
    _rotation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: -0.06), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -0.06, end: 0.06), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 0.06, end: -0.04), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -0.04, end: 0.04), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 0.04, end: 0.0), weight: 1),
    ]).animate(CurvedAnimation(parent: _wiggle, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _wiggle.dispose();
    super.dispose();
  }

  void _trigger() {
    widget.onPressed();
    if (widget.animationsEnabled && !(MediaQuery.maybeDisableAnimationsOf(context) ?? false)) {
      unawaited(_wiggle.forward(from: 0));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _wiggle,
      builder: (context, child) {
        return Transform.rotate(
          angle: _wiggle.isAnimating ? _rotation.value : 0.0,
          child: OutlinedButton.icon(
            icon: const Icon(YaruIcons.bell, size: 18),
            label: const Text('Find Phone'),
            onPressed: widget.enabled ? _trigger : null,
          ),
        );
      },
    );
  }
}

/// Progress for the transfer in flight with moving device-palette gradient.
class _TransferStrip extends StatefulWidget {
  final RelayDeviceVm device;
  final RelayTransferVm transfer;
  final RelayDevicePalette palette;
  final VoidCallback? onCancelTransfer;

  const _TransferStrip({
    required this.device,
    required this.transfer,
    required this.palette,
    this.onCancelTransfer,
  });

  @override
  State<_TransferStrip> createState() => _TransferStripState();
}

class _TransferStripState extends State<_TransferStrip> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat();
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final progressVal = (widget.transfer.progress ?? 0.0).clamp(0.0, 1.0);

    return YaruBorderContainer(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.transfer.isReceive ? 'Receiving from ${widget.device.alias}…' : 'Sending to ${widget.device.alias}…',
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (widget.transfer.progress != null)
                Text(
                  '${(progressVal * 100).toStringAsFixed(0)}%',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: widget.palette.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              if (widget.onCancelTransfer != null) ...[
                const SizedBox(width: 12),
                OutlinedButton(
                  onPressed: widget.onCancelTransfer,
                  child: const Text('Cancel'),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              height: 6,
              child: Stack(
                children: [
                  Container(color: colorScheme.surfaceContainerHighest),
                  FractionallySizedBox(
                    widthFactor: progressVal,
                    child: AnimatedBuilder(
                      animation: _pulse,
                      builder: (context, _) {
                        return Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [widget.palette.primary, widget.palette.secondary],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The Overview's responsive primary grid with staggered section reveals.
class _ContentArea extends StatelessWidget {
  final RelayDeviceVm device;
  final RelayDevicePalette palette;
  final bool connected;
  final bool animationsEnabled;

  const _ContentArea({
    required this.device,
    required this.palette,
    required this.connected,
    required this.animationsEnabled,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxWidth;
        final wide = available >= _overviewGridBreakpoint;

        final recentActivity = RelaySectionReveal(
          index: 0,
          animationsEnabled: animationsEnabled,
          child: const _OverviewSection(
            key: ValueKey('recent-activity-section'),
            title: 'Recent Activity',
            child: _OverviewContentSurface(
              key: ValueKey('recent-activity-panel'),
              child: _RecentActivitySection(),
            ),
          ),
        );

        final deviceStatus = RelaySectionReveal(
          index: 1,
          animationsEnabled: animationsEnabled,
          child: _DeviceStatusSection(
            device: device,
            palette: palette,
            connected: connected,
            animationsEnabled: animationsEnabled,
          ),
        );

        final notifications = RelaySectionReveal(
          index: 1,
          animationsEnabled: animationsEnabled,
          child: _OverviewSection(
            key: const ValueKey('notifications-section'),
            title: 'Notifications',
            child: _OverviewContentSurface(
              key: const ValueKey('notifications-panel'),
              child: _NotificationsSection(device: device),
            ),
          ),
        );

        final leftColumn = Column(
          key: const ValueKey('overview-left-column'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            recentActivity,
            const SizedBox(height: _overviewSectionGap),
            notifications,
          ],
        );

        final rightColumn = Column(
          key: const ValueKey('overview-right-column'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [deviceStatus],
        );

        if (wide) {
          return Row(
            key: const ValueKey('overview-primary-grid-wide'),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 7, child: leftColumn),
              const SizedBox(width: _overviewGridGutter),
              Expanded(flex: 5, child: rightColumn),
            ],
          );
        }

        return Column(
          key: const ValueKey('overview-primary-grid-narrow'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            leftColumn,
            const SizedBox(height: _overviewSectionGap),
            rightColumn,
          ],
        );
      },
    );
  }
}

class _OverviewSection extends StatelessWidget {
  final String title;
  final Widget child;

  const _OverviewSection({super.key, required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(height: _overviewTitleGap),
        child,
      ],
    );
  }
}

class _OverviewContentSurface extends StatelessWidget {
  final Widget child;

  const _OverviewContentSurface({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).relayPalette;
    return Material(
      color: palette.elevated,
      borderRadius: BorderRadius.circular(RelayRadius.panel),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
        child: child,
      ),
    );
  }
}

class _RecentActivitySection extends StatelessWidget {
  const _RecentActivitySection();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final history = context.watch(receiveHistoryProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (history.isEmpty)
          const _EmptySection(
            icon: YaruIcons.inbox,
            title: 'Nothing yet',
            body: 'Files you send or receive appear here.',
          )
        else
          for (final entry in history.take(5))
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Icon(
                      entry.isMessage ? YaruIcons.chat_bubble : YaruIcons.document,
                      size: 16,
                      color: colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          entry.fileName,
                          style: theme.textTheme.bodyMedium,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${entry.senderAlias} · ${entry.fileSize.asReadableFileSize} · ${_formatDate(entry.timestamp)}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurface.withValues(alpha: 0.5),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  if (entry.path != null) ...[
                    YaruIconButton(
                      icon: const Icon(YaruIcons.folder_open, size: 16),
                      tooltip: 'Open Folder',
                      onPressed: () => openFolder(folderPath: entry.path!),
                    ),
                    YaruIconButton(
                      icon: const Icon(YaruIcons.external_link, size: 16),
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
  final RelayDevicePalette palette;
  final bool connected;
  final bool animationsEnabled;

  const _DeviceStatusSection({
    required this.device,
    required this.palette,
    required this.connected,
    required this.animationsEnabled,
  });

  static Color? batteryTint(BuildContext context, int percentage) {
    final yaruColors = YaruColors.of(context);
    if (percentage <= 15) return Theme.of(context).colorScheme.error;
    if (percentage <= 30) return yaruColors.warning;
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
    final battery = device.battery;

    return _OverviewSection(
      key: const ValueKey('device-status-section'),
      title: 'Device Status',
      child: AdwRowGeometry(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        minHeight: 56,
        child: AdwBoxedList(
          key: const ValueKey('device-status-group'),
          children: [
            AdwActionRow(
              leading: const Icon(YaruIcons.network_wireless),
              title: 'Connection',
              trailing: RelayConnectionStatus(
                connected: connected,
                label: connected ? 'Connected' : device.statusSummary,
                palette: palette,
                animationsEnabled: animationsEnabled,
                ambient: true,
              ),
            ),
            _StatusRow(
              icon: YaruIcons.battery,
              label: 'Battery',
              value: battery.hasInfo ? '${battery.percentage}%${battery.isCharging ? ' · Charging' : ''}' : '—',
              valueColor: battery.hasInfo ? batteryTint(context, battery.percentage ?? 0) : null,
              animationsEnabled: animationsEnabled,
            ),
            _StatusRow(
              icon: YaruIcons.network_cellular,
              label: 'Signal',
              value: device.networkType == null && device.signalLevel == null
                  ? '—'
                  : '${device.networkType ?? 'Mobile'} · ${signalLabel(device.signalLevel)}',
              animationsEnabled: animationsEnabled,
            ),
            _StatusRow(
              icon: YaruIcons.information,
              label: 'Device',
              value: device.deviceModel ?? device.alias,
              animationsEnabled: animationsEnabled,
            ),
          ],
        ),
      ),
    );
  }
}

class _DeviceMaintenanceAction extends StatelessWidget {
  final RelayDeviceVm device;

  const _DeviceMaintenanceAction({required this.device});

  @override
  Widget build(BuildContext context) {
    return Align(
      key: const ValueKey('device-relationship-section'),
      alignment: Alignment.centerLeft,
      child: device.isKdeConnect ? _KdeConnectRelationshipTile(device: device) : RelayDeviceRelationshipTile(device: device),
    );
  }
}

class _CompactDeviceAction extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool destructive;
  final VoidCallback onPressed;

  const _CompactDeviceAction({
    super.key,
    required this.icon,
    required this.label,
    required this.destructive,
    required this.onPressed,
  });

  @override
  State<_CompactDeviceAction> createState() => _CompactDeviceActionState();
}

class _CompactDeviceActionState extends State<_CompactDeviceAction> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final foreground = widget.destructive ? colorScheme.error : colorScheme.primary;
    final highlighted = _hovered || _focused;
    const radius = BorderRadius.all(Radius.circular(8));

    return AnimatedContainer(
      key: const ValueKey('device-maintenance-hover-region'),
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: highlighted ? foreground.withValues(alpha: 0.08) : Colors.transparent,
        borderRadius: radius,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: radius,
        child: InkWell(
          borderRadius: radius,
          hoverColor: Colors.transparent,
          focusColor: Colors.transparent,
          splashColor: foreground.withValues(alpha: 0.12),
          highlightColor: foreground.withValues(alpha: 0.06),
          onHover: (value) => setState(() => _hovered = value),
          onFocusChange: (value) => setState(() => _focused = value),
          onTap: widget.onPressed,
          child: SizedBox(
            height: 38,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(widget.icon, size: 16, color: foreground),
                  const SizedBox(width: 8),
                  Text(
                    widget.label,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(color: foreground, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;
  final bool animationsEnabled;

  const _StatusRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
    this.animationsEnabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final motionAllowed = animationsEnabled && !(MediaQuery.maybeDisableAnimationsOf(context) ?? false);

    return AdwActionRow(
      leading: Icon(icon),
      title: label,
      trailing: AnimatedSwitcher(
        duration: motionAllowed ? RelayMotion.state : Duration.zero,
        switchInCurve: RelayMotion.curve,
        switchOutCurve: RelayMotion.curve,
        child: Text(
          value,
          key: ValueKey(value),
          textAlign: TextAlign.end,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: valueColor ?? theme.colorScheme.onSurface,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

/// Notifications forwarded by the focused phone.
class _NotificationsSection extends StatelessWidget {
  final RelayDeviceVm device;

  const _NotificationsSection({required this.device});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (!device.isKdeConnect || !device.isPaired) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const _EmptySection(
            icon: YaruIcons.notification,
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
        if (notifications.isEmpty)
          const _EmptySection(
            icon: YaruIcons.bell,
            title: 'All clear',
            body: 'Notifications from this phone appear here.',
          )
        else
          for (final notification in notifications.take(5))
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    notification.title?.isNotEmpty == true ? notification.title! : (notification.appName ?? 'Notification'),
                    style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (notification.appName != null && notification.title?.isNotEmpty == true)
                    Text(
                      notification.appName!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurface.withValues(alpha: 0.5),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  if (notification.text != null && notification.text!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        notification.text!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurface.withValues(alpha: 0.7),
                        ),
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

class _EmptySection extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;

  const _EmptySection({required this.icon, required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 20, color: colorScheme.onSurface.withValues(alpha: 0.4)),
          const SizedBox(height: 8),
          Text(title, style: theme.textTheme.bodyMedium?.copyWith(color: colorScheme.onSurface.withValues(alpha: 0.8))),
          const SizedBox(height: 2),
          Text(body, style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurface.withValues(alpha: 0.5))),
        ],
      ),
    );
  }
}

/// The technical rows as a GNOME preferences group.
class _DeviceDetails extends StatelessWidget {
  final RelayDeviceVm device;
  final RelayDevicePalette palette;
  final bool connected;
  final bool animationsEnabled;
  final VoidCallback onOpenDiagnostics;

  const _DeviceDetails({
    required this.device,
    required this.palette,
    required this.connected,
    required this.animationsEnabled,
    required this.onOpenDiagnostics,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return _OverviewSection(
      key: const ValueKey('device-details-section'),
      title: 'Device Details',
      child: AdwRowGeometry(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        minHeight: 56,
        child: AdwBoxedList(
          key: const ValueKey('device-details-group'),
          children: [
            AdwActionRow(
              leading: const Icon(YaruIcons.network_wireless),
              title: 'Connection',
              subtitle: device.isKdeConnect
                  ? device.detail == 'Connected'
                        ? 'Local network'
                        : device.detail == 'Paired'
                        ? 'Paired'
                        : 'Nearby on your local network'
                  : device.isCompatibilityPeer
                  ? 'Nearby on your local network'
                  : device.connectionType == RelayConnectionType.direct
                  ? 'Direct connection'
                  : device.connectionType == RelayConnectionType.relayed
                  ? 'Remote connection'
                  : 'Nearby on your local network',
              trailing: RelayConnectionStatus(
                connected: connected,
                label: connected ? 'Connected' : device.statusSummary,
                palette: palette,
                animationsEnabled: animationsEnabled,
              ),
            ),
            AdwActionRow(
              leading: Icon(device.isVerifiedRelay ? YaruIcons.shield : YaruIcons.information),
              title: 'Device verification',
              subtitle: device.isKdeConnect
                  ? 'KDE Connect'
                  : device.isVerifiedRelay
                  ? 'Authenticated Relay device identity'
                  : 'Relay-compatible device (unauthenticated)',
            ),
            AdwActionRow(
              leading: const Icon(YaruIcons.battery),
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
                style: theme.textTheme.bodyMedium,
              ),
            ),
            if (!device.isKdeConnect)
              AdwNavigationRow(
                leading: const Icon(YaruIcons.settings),
                title: 'Security & diagnostics',
                subtitle: 'Verify this device and view technical details',
                onTap: onOpenDiagnostics,
              ),
          ],
        ),
      ),
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
      return _CompactDeviceAction(
        key: const ValueKey('kdeconnect-remove-device'),
        icon: YaruIcons.trash,
        label: 'Remove Device',
        destructive: true,
        onPressed: () => unawaited(context.redux(kdeConnectProvider).dispatchAsync(KdeConnectUnpairAction(_deviceId))),
      );
    }
    return _CompactDeviceAction(
      key: const ValueKey('kdeconnect-pair-device'),
      icon: YaruIcons.insert_link,
      label: 'Pair',
      destructive: false,
      onPressed: () => unawaited(context.redux(kdeConnectProvider).dispatchAsync(KdeConnectRequestPairAction(_deviceId))),
    );
  }
}
