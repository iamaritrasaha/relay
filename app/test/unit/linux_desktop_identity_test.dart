import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the pieces of Relay's Linux identity that are easy to regress and
/// impossible to notice from inside the app: GNOME only shows "Relay" and the
/// Relay icon when the desktop entry is published under the GTK application id
/// and the notification carries a human-readable app name.
void main() {
  const applicationId = 'com.foresight.app.relay';

  test('the GTK application id is the one the packaging advertises', () {
    final cmake = File('linux/CMakeLists.txt').readAsStringSync();
    expect(cmake, contains('set(APPLICATION_ID "$applicationId")'));
    expect(cmake, contains('set(BINARY_NAME "relay")'));
  });

  test('the deb package publishes a desktop entry named after the application id', () {
    final config = File('linux/packaging/deb/make_config.yaml').readAsStringSync();

    expect(config, contains('display_name: Relay'));
    expect(config, contains('/usr/share/applications/$applicationId.desktop'));
    expect(config, contains('StartupWMClass=$applicationId'));
    // The launcher entry must name the product, never the reverse-DNS id.
    expect(config, contains('s/^Name=.*/Name=Relay/'));
    // And the icon has to be resolvable under the application id.
    expect(config, contains('Icon=$applicationId'));
    expect(config, contains('gtk-update-icon-cache'));
  });

  test('native notifications identify Relay by name, not by application id', () {
    final channel = File('linux/relay_desktop_notification_channel.cc').readAsStringSync();

    // app_name is the first Notify argument and is the string GNOME prints in
    // the banner header.
    expect(channel, contains('app_name = g_strdup("Relay")'));
    expect(channel, contains('g_strdup_printf("Relay · %s", device_name)'));
    // app_icon resolves to the bundled Relay icon, falling back to the themed
    // name the packaging installs.
    expect(channel, contains('relay_notification_icon()'));
    expect(channel, contains('relay-icon-linux-512.png'));
    // The desktop-entry hint lets the shell tie the banner back to the launcher.
    expect(channel, contains('"desktop-entry", g_variant_new_string("$applicationId")'));
  });

  group('local installer', _installerTests);
}

/// The user-local development installer.
///
/// These run the real script against a throwaway HOME and a stub bundle, so the
/// assertions are about what the installer actually does rather than about what
/// it looks like it does.
void _installerTests() {
  const applicationId = 'com.foresight.app.relay';
  final script = File('linux/install-relay-local.sh');

  test('the installer never writes a user-local hicolor index.theme', () {
    final source = script.readAsStringSync();

    // An index.theme is the authoritative directory list for a theme, so a
    // generated one hides every icon in a size directory it does not name.
    // Every mention here has to be a read, never a write.
    for (final line in source.split('\n')) {
      if (!line.contains('index.theme')) {
        continue;
      }
      final code = line.split('#').first;
      if (code.trim().isEmpty) {
        continue;
      }
      expect(code, isNot(contains('> "\${ICON_ROOT}/index.theme"')), reason: 'installer must not write index.theme: $line');
      expect(
        code,
        isNot(matches(RegExp(r'''(cat|printf|echo|tee|install|cp|touch|mv)[^\n]*index\.theme'''))),
        reason: 'installer must not create index.theme: $line',
      );
      expect(code, isNot(matches(RegExp(r'''rm\s[^\n]*index\.theme'''))), reason: 'installer must not delete index.theme: $line');
    }

    // And the cache step only runs when the user already has one of their own.
    expect(source, contains(r'if [ -f "${ICON_ROOT}/index.theme" ] && command -v gtk-update-icon-cache'));
  });

  test('installing leaves an existing icon tree intact and adds no index.theme', () {
    final root = Directory.systemTemp.createTempSync('relay-installer-test-');
    addTearDown(() => root.deleteSync(recursive: true));

    // A stub checkout: the script derives every path from its own location, so
    // pointing it at a throwaway tree keeps the real bundle and any running
    // Relay completely out of this.
    final appDir = Directory('${root.path}/app')..createSync(recursive: true);
    Directory('${appDir.path}/linux').createSync(recursive: true);
    final stubScript = File('${appDir.path}/linux/install-relay-local.sh');
    stubScript.writeAsStringSync(script.readAsStringSync());
    Process.runSync('chmod', ['+x', stubScript.path]);

    Directory('${appDir.path}/assets/img').createSync(recursive: true);
    File('${appDir.path}/assets/img/relay-icon-linux.svg').writeAsStringSync('<svg xmlns="http://www.w3.org/2000/svg"/>');
    File('${appDir.path}/assets/img/relay-icon-linux-512.png').writeAsBytesSync([0x89, 0x50, 0x4e, 0x47]);

    final bundle = Directory('${appDir.path}/build/linux/x64/release/bundle')..createSync(recursive: true);
    final stubBinary = File('${bundle.path}/relay')..writeAsStringSync('#!/bin/sh\nexit 0\n');
    Process.runSync('chmod', ['+x', stubBinary.path]);

    // A foreign icon in a size directory Relay does not use: this is exactly
    // what a generated index.theme used to hide.
    final home = Directory('${root.path}/home')..createSync(recursive: true);
    final hicolor = '${home.path}/.local/share/icons/hicolor';
    Directory('$hicolor/48x48/apps').createSync(recursive: true);
    final foreignIcon = File('$hicolor/48x48/apps/some-other-app.png')..writeAsBytesSync([1, 2, 3]);

    final result = Process.runSync(stubScript.path, const [], environment: {'HOME': home.path});
    expect(result.exitCode, 0, reason: 'installer failed:\n${result.stdout}\n${result.stderr}');

    // The regression itself.
    expect(File('$hicolor/index.theme').existsSync(), isFalse, reason: 'installer created a user-local hicolor index.theme');
    expect(foreignIcon.existsSync(), isTrue, reason: 'installer disturbed an unrelated icon');

    // And it still does its actual job.
    expect(File('$hicolor/scalable/apps/$applicationId.svg').existsSync(), isTrue);
    expect(File('$hicolor/512x512/apps/$applicationId.png').existsSync(), isTrue);
    expect(File('${home.path}/.local/bin/relay').existsSync(), isTrue);
    expect(File('${home.path}/.local/opt/relay/relay').existsSync(), isTrue);

    final entry = File('${home.path}/.local/share/applications/$applicationId.desktop');
    expect(entry.existsSync(), isTrue);
    final desktop = entry.readAsStringSync();
    expect(desktop, contains('Name=Relay'));
    expect(desktop, contains('Icon=$applicationId'));
    expect(desktop, contains('StartupWMClass=$applicationId'));
    expect(desktop, contains('Exec=${home.path}/.local/opt/relay/relay'));
  });
}
