import 'package:flutter/material.dart';
import 'package:localsend_app/config/relay_brand.dart';
import 'package:localsend_app/widget/relay_symbol.dart';

/// Shared Relay symbol and wordmark treatment for normal product surfaces.
class RelayLogo extends StatelessWidget {
  final bool withText;
  final double symbolSize;

  const RelayLogo({super.key, required this.withText, this.symbolSize = 96});

  @override
  Widget build(BuildContext context) {
    final symbol = RelaySymbol(size: symbolSize, semanticLabel: 'Relay');
    if (!withText) {
      return symbol;
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        symbol,
        const SizedBox(height: 10),
        Text(RelayProduct.name, style: RelayTypography.wordmark(Theme.of(context).colorScheme.onSurface), textAlign: TextAlign.center),
      ],
    );
  }
}
