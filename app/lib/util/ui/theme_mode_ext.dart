import 'package:flutter/material.dart';
import 'package:relay_app/gen/strings.g.dart';
import 'package:relay_app/model/persistence/color_mode.dart';

extension ThemeModeExt on ThemeMode {
  String get humanName => switch (this) {
    ThemeMode.system => t.settingsTab.general.brightnessOptions.system,
    ThemeMode.light => t.settingsTab.general.brightnessOptions.light,
    ThemeMode.dark => t.settingsTab.general.brightnessOptions.dark,
  };
}

extension ColorModeExt on ColorMode {
  String get humanName => switch (this) {
    ColorMode.system => t.settingsTab.general.colorOptions.system,
    ColorMode.relay => 'Relay',
    ColorMode.yaru => 'Yaru',
    ColorMode.oled => t.settingsTab.general.colorOptions.oled,
    ColorMode.custom => t.settingsTab.general.colorOptions.custom,
  };
}
