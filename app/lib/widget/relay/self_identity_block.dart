import 'package:flutter/material.dart';
import 'package:localsend_app/config/relay_brand.dart';
import 'package:localsend_app/pages/relay_home_vm.dart';

/// Relay's own presence, sitting quietly beside the wordmark.
class SelfIdentityBlock extends StatelessWidget {
  final String alias;
  final RelayPresence presence;

  const SelfIdentityBlock({
    required this.alias,
    required this.presence,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).relayPalette;
    final (label, color) = switch (presence) {
      RelayPresence.offline => ('Offline', palette.textTertiary),
      RelayPresence.ready => ('Ready', palette.success),
      RelayPresence.discovering => ('Discovering', palette.accentSoft),
    };
    const base = TextStyle(fontSize: 13, height: 1.2);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: label,
                  style: base.copyWith(color: color),
                ),
                TextSpan(
                  text: ' as ',
                  style: base.copyWith(color: palette.textSecondary),
                ),
                TextSpan(
                  text: alias,
                  style: base.copyWith(color: palette.textPrimary, fontWeight: FontWeight.w500),
                ),
              ],
            ),
            key: const ValueKey('relay-self-alias'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
