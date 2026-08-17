import 'package:flutter/material.dart';
import 'package:localsend_app/config/relay_brand.dart';
import 'package:localsend_app/widget/relay/relay_device_silhouette.dart';
import 'package:localsend_isolates/model/device.dart';

/// The empty-state figure for the nearby field.
///
/// It reuses Relay's own endpoint/packet vocabulary — this device, the packets
/// travelling across, and the endpoint that has not appeared yet — rather than
/// a generic send glyph. Deliberately small: it states that Relay is listening
/// without becoming an illustration.
class RelayWaitingBeacon extends StatelessWidget {
  /// This machine's own category, so the solid endpoint is truthful.
  final DeviceType selfDeviceType;

  final bool compact;

  const RelayWaitingBeacon({super.key, required this.selfDeviceType, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).relayPalette;
    final tile = compact ? 62.0 : 76.0;
    return ExcludeSemantics(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Captions can outgrow their tile in a long locale, so each endpoint
          // stays flexible rather than forcing the figure past a narrow window.
          Flexible(
            child: _Endpoint(
              caption: 'This device',
              size: tile,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(tile * 0.26),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [palette.topHighlight, palette.softSurface],
                  ),
                  border: Border.all(color: palette.hairline),
                ),
                child: Center(
                  child: RelayDeviceSilhouette(
                    deviceType: selfDeviceType,
                    color: palette.accentSoft,
                    size: tile * 0.46,
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: compact ? 18 : 24),
            child: SizedBox(
              height: tile,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final opacity in const [0.9, 0.5, 0.22]) ...[
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: palette.accent.withValues(alpha: opacity),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    if (opacity != 0.22) SizedBox(width: compact ? 11 : 14),
                  ],
                ],
              ),
            ),
          ),
          Flexible(
            child: _Endpoint(
              caption: 'Waiting',
              size: tile,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(tile * 0.26),
                  border: Border.all(color: palette.accentSoft.withValues(alpha: 0.3), width: 1.5),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Endpoint extends StatelessWidget {
  final String caption;
  final double size;
  final Widget child;

  const _Endpoint({required this.caption, required this.size, required this.child});

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).relayPalette;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox.square(dimension: size, child: child),
        const SizedBox(height: 12),
        Text(
          caption.toUpperCase(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: RelayTypography.section(palette.textTertiary),
        ),
      ],
    );
  }
}
