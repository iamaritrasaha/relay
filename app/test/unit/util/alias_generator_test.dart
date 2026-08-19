import 'package:flutter/foundation.dart';
import 'package:relay_app/util/alias_generator.dart';
import 'package:test/test.dart';

void main() {
  test('uses the device model for a new default alias', () {
    expect(defaultAliasForDevice(deviceModel: ' Redmi ', platform: TargetPlatform.android), 'Redmi');
  });

  test('uses a stable platform name when no device model is available', () {
    expect(defaultAliasForDevice(platform: TargetPlatform.linux), 'Linux');
    expect(defaultAliasForDevice(platform: TargetPlatform.android), 'Android');
  });
}
