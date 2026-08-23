import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:relay_app/config/relay_brand.dart';
import 'package:relay_app/model/ui/relay_connection_state.dart';
import 'package:relay_app/model/ui/relay_device_vm.dart';
import 'package:relay_app/model/ui/relay_last_seen.dart';
import 'package:relay_app/widget/gnome/adw_action_row.dart';
import 'package:relay_app/widget/gnome/adw_boxed_list.dart';
import 'package:relay_app/widget/gnome/adw_header_bar.dart';
import 'package:relay_app/widget/relay/relay_dialog.dart';
import 'package:relay_app/widget/relay_carbon/relay_surface.dart';
import 'package:relay_isolates/model/device.dart';
import 'package:yaru/yaru.dart';

/// Device Diagnostics: a GNOME/libadwaita-style preferences surface, not a
/// generic modal. A proper header bar (device icon, title/subtitle, top-right
/// close) sits above four AdwPreferencesGroup sections -- Identity,
/// Connection, Device, Capabilities -- each one boxed surface of hairline-
/// separated rows, the same language as Relay Settings and Device Details.
///
/// Presentation only: every field the original panel showed is still here.
class GnomeDiagnosticsDialog extends StatelessWidget {
  final RelayDeviceVm device;

  const GnomeDiagnosticsDialog({super.key, required this.device});

  static const _rowPadding = EdgeInsets.symmetric(horizontal: 14, vertical: 14);
  static const _groupSpacing = EdgeInsets.only(bottom: 20);

  String get _targetLabel => switch (device.targetKind) {
    RelayDeviceTargetKind.kdeConnect => 'KDE Connect',
    RelayDeviceTargetKind.verifiedRelay || RelayDeviceTargetKind.pairedRelay => 'Relay',
    RelayDeviceTargetKind.unresolvedLan => 'LocalSend',
  };

  RelayPresenceTone get _connectionTone => switch (device.connectionState) {
    RelayConnectionState.local => RelayPresenceTone.online,
    RelayConnectionState.remoteDirect || RelayConnectionState.remoteRelay => RelayPresenceTone.busy,
    RelayConnectionState.reconnecting => RelayPresenceTone.attention,
    RelayConnectionState.offline => RelayPresenceTone.offline,
  };

  IconData get _deviceIcon => switch (device.deviceType) {
    DeviceType.mobile => YaruIcons.smartphone,
    DeviceType.desktop => YaruIcons.desktop,
    _ => YaruIcons.computer,
  };

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).relayPalette;
    final fingerprint = device.lanFingerprint ?? (device.key.startsWith('relay:') ? null : device.key);
    final groupSurface = palette.canvasTonalHigh;

    return RelayDialog(
      maxWidth: 640,
      header: _DiagnosticsHeader(
        icon: _deviceIcon,
        alias: device.alias,
        tone: _connectionTone,
        statusLabel: device.connectionState.userLabel,
      ),
      child: ConstrainedBox(
        // The dialog never asks for more height than a normal desktop
        // viewport has to give -- header, dialog padding and inset margins
        // cost roughly 220px on top of this scrollable region.
        constraints: BoxConstraints(maxHeight: (MediaQuery.sizeOf(context).height - 220).clamp(260, 520)),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              AdwPreferencesGroup(
                title: 'Identity',
                margin: _groupSpacing,
                rowPadding: _rowPadding,
                rowMinHeight: 0,
                surfaceColor: groupSurface,
                children: [
                  AdwActionRow(title: 'Alias', trailing: _ValueText(device.alias)),
                  AdwActionRow(title: 'Target', trailing: _ValueText(_targetLabel)),
                  if (device.relayId != null)
                    AdwActionRow(
                      title: 'Relay ID',
                      trailing: _CopyableValue(value: device.relayId!, label: 'Relay ID', monospace: true, truncate: true),
                    ),
                  if (fingerprint != null)
                    AdwActionRow(
                      title: 'Fingerprint',
                      trailing: _CopyableValue(value: fingerprint, label: 'fingerprint', monospace: true, truncate: true),
                    ),
                ],
              ),

              if (device.hasFabricRecord) ...[
                AdwPreferencesGroup(
                  title: 'Connection',
                  margin: _groupSpacing,
                  rowPadding: _rowPadding,
                  rowMinHeight: 0,
                  surfaceColor: groupSurface,
                  children: [
                    AdwActionRow(title: 'Route', trailing: _ValueText(device.connectionState.diagnosticLabel)),
                    AdwActionRow(
                      title: 'Local network',
                      trailing: _StatusValue(
                        tone: device.lanAvailable ? RelayPresenceTone.online : RelayPresenceTone.offline,
                        label: device.lanAvailable ? 'Available' : 'Unavailable',
                      ),
                    ),
                    AdwActionRow(
                      title: 'Remote binding',
                      trailing: _StatusValue(
                        tone: !device.wanBound
                            ? RelayPresenceTone.offline
                            : device.wanAvailable
                            ? RelayPresenceTone.online
                            : RelayPresenceTone.attention,
                        label: device.wanBound ? 'Bound' : 'Not bound',
                        detail: switch ((device.wanBound, device.wanAvailable, device.wanPath)) {
                          (false, _, _) => null,
                          (true, true, 'relay') => 'Relayed · Up',
                          (true, true, _) => 'Direct · Up',
                          (true, false, _) => 'Down',
                        },
                      ),
                    ),
                    AdwActionRow(
                      title: 'Last local activity',
                      trailing: _ValueText(
                        device.lanLastSeenUnix == null ? 'Never' : relayLastSeenLabel(device.lanLastSeenUnix, now: DateTime.now()),
                      ),
                    ),
                    AdwActionRow(
                      title: 'Last remote activity',
                      trailing: _ValueText(
                        device.wanLastSeenUnix == null ? 'Never' : relayLastSeenLabel(device.wanLastSeenUnix, now: DateTime.now()),
                      ),
                    ),
                  ],
                ),

                AdwPreferencesGroup(
                  title: 'Device',
                  margin: _groupSpacing,
                  rowPadding: _rowPadding,
                  rowMinHeight: 0,
                  surfaceColor: groupSurface,
                  children: [
                    if (device.deviceClass != null) AdwActionRow(title: 'Device class', trailing: _ValueText(device.deviceClass!.label)),
                    // The real reported value only -- never a fabricated "Android"
                    // when the backend has actually reported something else (or
                    // nothing at all).
                    if (device.platform != null)
                      AdwActionRow(
                        title: 'Operating system',
                        trailing: _ValueText([_titleCase(device.platform!), device.platformVersion].whereType<String>().join(' ')),
                      ),
                    if (device.relayVersion != null) AdwActionRow(title: 'Protocol version', trailing: _ValueText(device.relayVersion!)),
                  ],
                ),

                _CapabilitiesGroup(device: device, groupSpacing: _groupSpacing, rowPadding: _rowPadding, surfaceColor: groupSurface),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

String _titleCase(String value) => value.isEmpty ? value : '${value[0].toUpperCase()}${value.substring(1)}';

/// The GNOME-style header bar: device icon, alias + live status as the
/// title/subtitle group on the left, a single close affordance on the right.
/// Full-bleed edge to edge, with the same bottom hairline GNOME headerbars use
/// to separate themselves from the content below.
class _DiagnosticsHeader extends StatelessWidget {
  final IconData icon;
  final String alias;
  final RelayPresenceTone tone;
  final String statusLabel;

  const _DiagnosticsHeader({
    required this.icon,
    required this.alias,
    required this.tone,
    required this.statusLabel,
  });

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).relayPalette;

    return Container(
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: palette.hairline))),
      padding: const EdgeInsets.fromLTRB(20, 14, 10, 14),
      child: Row(
        children: [
          Icon(icon, size: 22, color: palette.textSecondary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Device diagnostics',
                  style: RelayTypography.heading(palette.textPrimary, isGnome: true),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        alias,
                        style: RelayTypography.caption(palette.textSecondary, isGnome: true),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    RelayStatusPill(tone: tone, label: statusLabel, compact: true),
                  ],
                ),
              ],
            ),
          ),
          AdwIconButton(
            icon: YaruIcons.window_close,
            tooltip: 'Close',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}

/// A single value, right-aligned, in the same secondary tone the rest of
/// Relay uses for a row's trailing fact.
class _ValueText extends StatelessWidget {
  final String value;

  const _ValueText(this.value);

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).relayPalette;
    return Text(
      value,
      style: RelayTypography.body(palette.textSecondary, isGnome: true),
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.right,
    );
  }
}

/// A restrained status readout: small dot + word, with an optional smaller
/// technical detail line beneath it (e.g. "Direct · Up"). Only the dot
/// carries the semantic color -- the label stays the normal secondary tone,
/// never a wall of bright green text.
class _StatusValue extends StatelessWidget {
  final RelayPresenceTone tone;
  final String label;
  final String? detail;

  const _StatusValue({required this.tone, required this.label, this.detail});

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).relayPalette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6,
              height: 6,
              margin: const EdgeInsets.only(right: 7),
              decoration: BoxDecoration(shape: BoxShape.circle, color: tone.color(palette)),
            ),
            Text(label, style: RelayTypography.body(palette.textSecondary, isGnome: true)),
          ],
        ),
        if (detail != null) ...[
          const SizedBox(height: 2),
          Text(detail!, style: RelayTypography.caption(palette.textTertiary, isGnome: true)),
        ],
      ],
    );
  }
}

/// A value with an unobtrusive inline copy affordance -- a bare icon, never a
/// second boxed button competing with the row itself. Long/opaque values are
/// shown truncated but the full value is what actually gets copied.
class _CopyableValue extends StatelessWidget {
  final String value;
  final String label;
  final bool monospace;
  final bool truncate;

  const _CopyableValue({
    required this.value,
    required this.label,
    this.monospace = false,
    this.truncate = false,
  });

  String get _display {
    if (!truncate || value.length <= 18) return value;
    return '${value.substring(0, 10)}…${value.substring(value.length - 6)}';
  }

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).relayPalette;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          _display,
          style: monospace ? RelayTypography.monospace(palette.textSecondary) : RelayTypography.body(palette.textSecondary, isGnome: true),
        ),
        const SizedBox(width: 2),
        Tooltip(
          message: 'Copy $label',
          child: InkResponse(
            radius: 16,
            onTap: () {
              unawaited(Clipboard.setData(ClipboardData(text: value)));
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text('${label[0].toUpperCase()}${label.substring(1)} copied to clipboard')));
            },
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Icon(YaruIcons.copy, size: 13, color: palette.textTertiary),
            ),
          ),
        ),
      ],
    );
  }
}

/// Capabilities as ordinary boxed preference rows -- one column, a status dot
/// per feature -- not a badge/pill dashboard. Same group treatment as the
/// other three sections.
class _CapabilitiesGroup extends StatelessWidget {
  final RelayDeviceVm device;
  final EdgeInsetsGeometry groupSpacing;
  final EdgeInsetsGeometry rowPadding;
  final Color surfaceColor;

  const _CapabilitiesGroup({
    required this.device,
    required this.groupSpacing,
    required this.rowPadding,
    required this.surfaceColor,
  });

  @override
  Widget build(BuildContext context) {
    final entries = device.featureAvailability.entries.where((entry) => entry.value.isVisible).toList()
      ..sort((a, b) => a.key.title.compareTo(b.key.title));

    return AdwPreferencesGroup(
      title: 'Capabilities',
      margin: groupSpacing,
      rowPadding: rowPadding,
      rowMinHeight: 0,
      surfaceColor: surfaceColor,
      children: entries.isEmpty
          ? const [AdwActionRow(title: 'None reported')]
          : [
              for (final entry in entries)
                AdwActionRow(
                  title: entry.key.title,
                  trailing: _StatusValue(
                    tone: entry.value.isAvailable ? RelayPresenceTone.online : RelayPresenceTone.offline,
                    label: entry.value.isAvailable ? 'Available' : (entry.value.reason ?? 'Unavailable'),
                  ),
                ),
            ],
    );
  }
}
