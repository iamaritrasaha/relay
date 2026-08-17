import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/util/native/device_info_helper.dart';

Future<String> generateDefaultAlias() async {
  try {
    return defaultAliasForDevice(deviceModel: (await getDeviceInfo()).deviceModel);
  } catch (_) {
    // Fall through to a stable platform name when device information is unavailable.
    return generatePlatformAlias();
  }
}

String defaultAliasForDevice({String? deviceModel, TargetPlatform? platform}) {
  final normalizedModel = deviceModel?.trim();
  return normalizedModel != null && normalizedModel.isNotEmpty ? normalizedModel : generatePlatformAlias(platform: platform);
}

String generatePlatformAlias({TargetPlatform? platform}) {
  return switch (platform ?? defaultTargetPlatform) {
    TargetPlatform.android => 'Android',
    TargetPlatform.iOS => 'iPhone',
    TargetPlatform.linux => 'Linux',
    TargetPlatform.macOS => 'macOS',
    TargetPlatform.windows => 'Windows',
    TargetPlatform.fuchsia => 'Fuchsia',
  };
}

String generateRandomAlias() {
  final random = Random();
  final adj = t.aliasGenerator.adjectives;
  final fruits = t.aliasGenerator.fruits;

  // The combination of both is locale dependent too.
  return t.aliasGenerator.combination(
    adjective: adj[random.nextInt(adj.length)],
    fruit: fruits[random.nextInt(fruits.length)],
  );
}
