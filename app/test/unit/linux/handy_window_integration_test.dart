import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Linux runner registers Handy before realizing or showing the Flutter view', () {
    final runner = File('linux/my_application.cc').readAsStringSync();
    final addView = runner.indexOf('gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));');
    final registerPlugins = runner.indexOf('fl_register_plugins(FL_PLUGIN_REGISTRY(view));');
    final showView = runner.indexOf('gtk_widget_show(GTK_WIDGET(view));');
    final showWindow = runner.indexOf('gtk_widget_show(GTK_WIDGET(window));');

    expect(addView, greaterThanOrEqualTo(0));
    expect(registerPlugins, greaterThan(addView));
    expect(showView, greaterThan(registerPlugins));
    expect(showWindow, greaterThan(registerPlugins));
    expect(runner, contains('"hdy_window_mixin"'));
  });

  test('generated Linux registration and dependency lock include handy_window 0.4.2', () {
    final registrant = File('linux/flutter/generated_plugin_registrant.cc').readAsStringSync();
    final lockfile = File('pubspec.lock').readAsStringSync();

    expect(registrant, contains('#include <handy_window/handy_window_plugin.h>'));
    expect(registrant, contains('handy_window_plugin_register_with_registrar'));
    expect(lockfile, contains('name: handy_window'));
    expect(lockfile, contains('version: "0.4.2"'));
  });
}
