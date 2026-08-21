import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:relay_app/config/relay_brand.dart';
import 'package:relay_app/gen/strings.g.dart';
import 'package:relay_app/provider/animation_provider.dart';
import 'package:relay_app/util/native/platform_check.dart';
import 'package:tray_manager/tray_manager.dart' as tm;
import 'package:window_manager/window_manager.dart';

final _logger = Logger('TrayHelper');

enum TrayEntry {
  open,
  close,
}

Future<void> initTray({bool suppressed = false}) async {
  if (!checkPlatformHasTray()) {
    return;
  }
  if (suppressed) {
    _trayIconHidden = true;
    return;
  }
  try {
    if (checkPlatform([TargetPlatform.windows])) {
      await tm.trayManager.setIcon('assets/img/relay-icon.ico');
    } else if (checkPlatform([TargetPlatform.macOS])) {
      // The menu bar icon will created in AppDelegate.swift
      return;
    } else if (checkPlatform([TargetPlatform.linux])) {
      String icon;
      if (await File('/.flatpak-info').exists()) {
        // Icon for Flatpak, which must exist in /app/share/icons/hicolor/*x*/apps.
        icon = 'com.foresight.app.relay-tray';
      } else {
        icon = 'assets/img/relay-tray-white.png';
      }
      _logger.info('Using "$icon" as path of system tray icon');
      await tm.trayManager.setIcon(icon);
    } else {
      await tm.trayManager.setIcon('assets/img/relay-icon-linux-512.png');
    }

    final items = [
      tm.MenuItem(
        key: TrayEntry.open.name,
        label: t.tray.open,
      ),
      tm.MenuItem(
        key: TrayEntry.close.name,
        label: defaultTargetPlatform == TargetPlatform.windows ? t.tray.closeWindows : t.tray.close,
      ),
    ];
    await tm.trayManager.setContextMenu(tm.Menu(items: items));
    // No Linux implementation for setToolTip available as of tray_manager 0.2.2
    // https://pub.dev/packages/tray_manager#api
    if (!checkPlatform([TargetPlatform.linux])) {
      await tm.trayManager.setToolTip(RelayProduct.name);
    }
    _trayIconHidden = false;
  } catch (e) {
    _logger.warning('Failed to init tray', e);
    rethrow;
  }
}

/// During pre-runApp bootstrap the container is not yet mounted in
/// [RefenaScope]. The initial sleep value is supplied as a container override,
/// so updating it through `defaultRef` here would race the scope mount.
Future<void> hideToTray({bool updateSleepState = true}) async {
  await windowManager.hide();
  if (checkPlatform([TargetPlatform.macOS])) {
    // This will crash on Windows
    // https://github.com/relay/relay/issues/32
    await windowManager.setSkipTaskbar(true);
  }

  if (updateSleepState) {
    RefenaScope.defaultRef.notifier(sleepProvider).setState((_) => true);
  }
}

Future<void> showFromTray({bool updateSleepState = true}) async {
  await windowManager.show();
  await windowManager.focus();
  if (checkPlatform([TargetPlatform.macOS])) {
    // This will crash on Windows
    // https://github.com/relay/relay/issues/32
    await windowManager.setSkipTaskbar(false);
  }

  if (updateSleepState) {
    RefenaScope.defaultRef.notifier(sleepProvider).setState((_) => false);
  }
}

Future<void> destroyTray() async {
  if (!checkPlatform([TargetPlatform.linux])) {
    await tm.trayManager.destroy();
  }
}

bool _trayIconHidden = false;

/// Removes Relay from the notification area.
///
/// Used when a desktop shell surface already presents Relay, so the user is not
/// given two Relay entry points in the same panel. Only the icon goes away: the
/// app keeps running exactly as before.
Future<void> hideTrayIcon() async {
  if (!checkPlatformHasTray() || _trayIconHidden) {
    return;
  }
  _trayIconHidden = true;
  try {
    await tm.trayManager.destroy();
  } catch (e) {
    _trayIconHidden = false;
    _logger.warning('Failed to hide the tray icon', e);
  }
}

/// Puts Relay back in the notification area after [hideTrayIcon].
Future<void> restoreTrayIcon() async {
  if (!checkPlatformHasTray() || !_trayIconHidden) {
    return;
  }
  try {
    // tray_manager's Linux destroy() sets AppIndicator PASSIVE, while setIcon()
    // explicitly sets the same indicator ACTIVE again. Re-running initTray is
    // therefore the supported re-registration path; no Relay restart is needed.
    await initTray();
  } catch (e) {
    _logger.warning('Failed to restore the tray icon', e);
  }
}
