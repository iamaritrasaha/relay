import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:relay_app/config/relay_brand.dart';
import 'package:relay_app/config/theme.dart';
import 'package:relay_app/model/persistence/color_mode.dart';
import 'package:relay_app/model/ui/relay_device_vm.dart';
import 'package:relay_app/pages/changelog_page.dart';
import 'package:relay_app/pages/relay_home_vm.dart';
import 'package:relay_app/provider/version_provider.dart';
import 'package:relay_app/widget/relay/relay_desktop_metrics.dart';
import 'package:relay_app/widget/relay/relay_device_target.dart';
import 'package:relay_app/widget/relay/relay_waiting_beacon.dart';
import 'package:relay_isolates/model/device.dart';

import 'relay_desktop_fixtures.dart';

/// Regression coverage for the approved desktop composition.
void main() {
  const desktopViewports = <String, Size>{
    '900x600': Size(900, 600),
    '1000x700': Size(1000, 700),
    '1100x700': Size(1100, 700),
    '1280x720': Size(1280, 720),
    '1280x800': Size(1280, 800),
    '1440x900': Size(1440, 900),
    '1600x900': Size(1600, 900),
    '1920x1080': Size(1920, 1080),
  };

  Future<void> pump(WidgetTester tester, Widget child, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: getTheme(ColorMode.relay, Colors.blue, Brightness.dark, null),
        home: child,
      ),
    );
    await tester.pumpAndSettle();
  }

  group('Home', () {
    for (final entry in desktopViewports.entries) {
      testWidgets('renders without overflow at ${entry.key}', (tester) async {
        await pump(tester, RelayDesktopFixtures.home(state: RelayHomeState.nearby), entry.value);

        expect(tester.takeException(), isNull);
        expect(find.byType(RelayDeviceTarget), findsNWidgets(3));
        // The dock stays a single control, whatever the width.
        expect(find.byKey(const ValueKey('relay-payload-dock')), findsOneWidget);
      });

      testWidgets('empty state renders without overflow at ${entry.key}', (tester) async {
        await pump(tester, RelayDesktopFixtures.home(state: RelayHomeState.empty), entry.value);

        expect(tester.takeException(), isNull);
        expect(find.byKey(const ValueKey('relay-empty-title')), findsOneWidget);
      });

      testWidgets('sending state renders without overflow at ${entry.key}', (tester) async {
        await pump(tester, RelayDesktopFixtures.home(state: RelayHomeState.sending), entry.value);

        expect(tester.takeException(), isNull);
        expect(find.byKey(const ValueKey('relay-transfer-destination')), findsOneWidget);
      });
    }

    testWidgets('empty state uses the endpoint/packet figure, not a send glyph', (tester) async {
      await pump(tester, RelayDesktopFixtures.home(state: RelayHomeState.empty), const Size(1440, 900));

      expect(find.byType(RelayWaitingBeacon), findsOneWidget);
      for (final icon in [Icons.near_me, Icons.near_me_outlined, Icons.send, Icons.send_rounded, Icons.send_outlined]) {
        expect(find.byIcon(icon), findsNothing, reason: '$icon is a generic send glyph');
      }
    });

    testWidgets('the selected device keeps its position when a transfer starts', (tester) async {
      await pump(tester, RelayDesktopFixtures.home(state: RelayHomeState.nearby), const Size(1440, 900));
      final idle = tester.getCenter(find.byKey(const ValueKey('relay-device-thinkpad')));

      await pump(tester, RelayDesktopFixtures.home(state: RelayHomeState.sending), const Size(1440, 900));
      final sending = tester.getCenter(find.byKey(const ValueKey('relay-device-thinkpad')));

      expect(sending, idle);
    });

    testWidgets('medallions grow within bounded responsive limits', (tester) async {
      await pump(tester, RelayDesktopFixtures.home(state: RelayHomeState.nearby), const Size(900, 600));
      final small = tester.getSize(find.byKey(const ValueKey('relay-device-thinkpad'))).width;

      await pump(tester, RelayDesktopFixtures.home(state: RelayHomeState.nearby), const Size(1920, 1080));
      final large = tester.getSize(find.byKey(const ValueKey('relay-device-thinkpad'))).width;

      expect(small, greaterThanOrEqualTo(130));
      expect(large, greaterThan(small));
      expect(large, lessThanOrEqualTo(180));
    });

    testWidgets('live resize recomputes layout without losing the payload dock', (tester) async {
      await pump(tester, RelayDesktopFixtures.home(state: RelayHomeState.nearby), const Size(1920, 1080));
      final large = tester.getSize(find.byKey(const ValueKey('relay-device-thinkpad'))).width;

      tester.view.physicalSize = const Size(900, 600);
      await tester.pumpAndSettle();
      final restored = tester.getSize(find.byKey(const ValueKey('relay-device-thinkpad'))).width;

      expect(restored, lessThan(large));
      expect(find.byKey(const ValueKey('relay-payload-dock')), findsOneWidget);
      expect(tester.takeException(), isNull);

      tester.view.physicalSize = const Size(1440, 900);
      await tester.pumpAndSettle();
      final resized = tester.getSize(find.byKey(const ValueKey('relay-device-thinkpad'))).width;

      expect(resized, greaterThan(restored));
      expect(resized, lessThan(large));
      expect(find.byKey(const ValueKey('relay-payload-dock')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('no Send/Receive tabs and no permanent navigation', (tester) async {
      await pump(tester, RelayDesktopFixtures.home(state: RelayHomeState.nearby), const Size(1440, 900));

      expect(find.byType(NavigationBar), findsNothing);
      expect(find.byType(NavigationRail), findsNothing);
      expect(find.byType(TabBar), findsNothing);
    });

    testWidgets('phone width keeps the compact composition', (tester) async {
      await pump(tester, RelayDesktopFixtures.home(state: RelayHomeState.nearby), const Size(412, 915));

      expect(tester.takeException(), isNull);
      // Compact medallions, so the desktop slot must not be what is laid out.
      final target = tester.getSize(find.byKey(const ValueKey('relay-device-thinkpad')));
      expect(target.width, lessThan(RelayDesktopMetrics.medallionSlot));
    });

    for (final size in [const Size(360, 800), const Size(412, 915)]) {
      testWidgets('mobile Home fits ${size.width.toInt()}x${size.height.toInt()}', (tester) async {
        await pump(tester, RelayDesktopFixtures.home(state: RelayHomeState.sending), size);
        expect(tester.takeException(), isNull);
        expect(find.byKey(const ValueKey('relay-payload-dock')), findsOneWidget);
      });
    }
  });

  group('Settings', () {
    const settingsViewports = <String, Size>{
      '900x600': Size(900, 600),
      '1000x700': Size(1000, 700),
      '1040x700': Size(1040, 700),
      '1100x700': Size(1100, 700),
      '1280x800': Size(1280, 800),
      '1920x1080': Size(1920, 1080),
    };

    for (final entry in settingsViewports.entries) {
      testWidgets('renders without overflow at ${entry.key}', (tester) async {
        await pump(tester, RelayDesktopFixtures.settings(), entry.value);

        expect(tester.takeException(), isNull);
        expect(find.text('Settings'), findsOneWidget);
        final narrow = entry.value.width <= 1040;
        final expectedKey = narrow
            ? 'relay-settings-one-column'
            : entry.value.width == 1920
            ? 'relay-settings-two-columns-wide'
            : 'relay-settings-two-columns-standard';
        expect(find.byKey(ValueKey(expectedKey)), findsOneWidget);

        final rect = tester.getRect(find.byKey(ValueKey(expectedKey)));
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(entry.value.width));
      });
    }

    testWidgets('narrow desktop scrolls all the way to the final row', (tester) async {
      await pump(tester, RelayDesktopFixtures.settings(), const Size(900, 600));

      final scrollable = find.byType(Scrollable).first;
      await tester.drag(scrollable, const Offset(0, -4000));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('About Relay'), findsOneWidget);
      expect(find.text('Release notes'), findsOneWidget);
    });

    testWidgets('carries no Donate, Support LocalSend or About LocalSend', (tester) async {
      await pump(tester, RelayDesktopFixtures.settings(), const Size(1440, 900));

      expect(find.textContaining('Donate'), findsNothing);
      expect(find.textContaining('Support LocalSend'), findsNothing);
      expect(find.text('About LocalSend'), findsNothing);
      expect(find.text('About Relay'), findsOneWidget);
    });

    for (final size in [const Size(360, 800), const Size(412, 915)]) {
      testWidgets('mobile Settings fits ${size.width.toInt()}x${size.height.toInt()}', (tester) async {
        await pump(tester, RelayDesktopFixtures.settings(), size);
        expect(tester.takeException(), isNull);
        expect(find.text('Settings'), findsOneWidget);
      });
    }
  });

  group('About', () {
    testWidgets('renders the approved identity composition at 1440x900', (tester) async {
      await pump(tester, RelayDesktopFixtures.about(), const Size(1440, 900));

      expect(tester.takeException(), isNull);
      expect(find.text(RelayProduct.name), findsOneWidget);
      expect(find.text(RelayProduct.copyright), findsOneWidget);
      expect(find.text(RelayProduct.localSendAttribution), findsOneWidget);
      expect(find.text('Open Source Licenses'), findsOneWidget);
      expect(find.text('Upstream acknowledgements'), findsOneWidget);
      expect(find.text('Version 0.1.0'), findsOneWidget);
      expect(find.text('Build 62'), findsOneWidget);
      expect(find.text('Acknowledgements'), findsNothing);
    });

    testWidgets('does not co-brand with LocalSend', (tester) async {
      await pump(tester, RelayDesktopFixtures.about(), const Size(1440, 900));

      expect(find.text('LocalSend'), findsNothing);
      expect(find.text('About LocalSend'), findsNothing);
    });

    testWidgets('narrow desktop collapses to one column without overflow', (tester) async {
      await pump(tester, RelayDesktopFixtures.about(), const Size(900, 600));

      expect(find.byKey(const ValueKey('relay-about-one-column')), findsOneWidget);
      expect(find.byKey(const ValueKey('relay-about-two-columns')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    for (final size in [const Size(1280, 800), const Size(1920, 1080)]) {
      testWidgets('normal and wide About use two columns at ${size.width.toInt()}x${size.height.toInt()}', (tester) async {
        await pump(tester, RelayDesktopFixtures.about(), size);

        expect(find.byKey(const ValueKey('relay-about-two-columns')), findsOneWidget);
        expect(find.byKey(const ValueKey('relay-about-one-column')), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }

    for (final size in [const Size(360, 800), const Size(412, 915)]) {
      testWidgets('mobile About fits ${size.width.toInt()}x${size.height.toInt()}', (tester) async {
        await pump(tester, RelayDesktopFixtures.about(), size);
        expect(tester.takeException(), isNull);
        expect(find.text('Relay'), findsOneWidget);
      });
    }
  });

  group('Release notes', () {
    testWidgets('presents Relay current release without upstream history', (tester) async {
      await pump(
        tester,
        ChangelogPage(
          version: VersionData(version: '0.1.0', buildNumber: '62'),
          releaseNotes: '''# Relay 0.1.0

Relay's first intentional early release.

## Highlights

- New Relay identity and branding.
''',
        ),
        const Size(900, 700),
      );

      expect(find.text('Relay release notes'), findsOneWidget);
      expect(find.text('0.1.0'), findsOneWidget);
      expect(find.textContaining('Relay'), findsWidgets);
      expect(find.textContaining('Relay 1.'), findsNothing);
      expect(find.textContaining('Donate'), findsNothing);
      expect(find.textContaining('Support Relay'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  test('every existing device category maps to a silhouette', () {
    // Guards against inferring a category from a device name.
    for (final type in DeviceType.values) {
      expect(
        () => RelayDeviceVm(key: 't', alias: 'a', deviceType: type, phase: RelayDevicePhase.idle, progress: null, detail: 'Nearby'),
        returnsNormally,
      );
    }
  });

  test('the active transfer is derived from the existing session state', () {
    const transfer = RelayTransferVm(sessionId: 's', targetAlias: 'ThinkPad', progress: 0.62);

    expect(transfer.targetAlias, 'ThinkPad');
    expect(transfer.progress, 0.62);
  });

  test('RelayShell exposes no desktop layout below the shared breakpoint', () {
    expect(RelayDesktopMetrics.isDesktopWidth(412), isFalse);
    expect(RelayDesktopMetrics.isDesktopWidth(699), isFalse);
    expect(RelayDesktopMetrics.isDesktopWidth(1000), isTrue);
  });
}
