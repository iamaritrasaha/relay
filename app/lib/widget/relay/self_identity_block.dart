import 'package:flutter/material.dart';
import 'package:localsend_app/pages/relay_home_vm.dart';

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
    final colors = Theme.of(context).colorScheme;
    final (label, color) = switch (presence) {
      RelayPresence.offline => ('Offline', colors.onSurfaceVariant),
      RelayPresence.ready => ('Ready', colors.primary),
      RelayPresence.discovering => ('Discovering', colors.primary),
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Text(label, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: color)),
        const SizedBox(width: 4),
        Text('as', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant)),
        const SizedBox(width: 4),
        Text(
          alias,
          key: const ValueKey('relay-self-alias'),
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}
