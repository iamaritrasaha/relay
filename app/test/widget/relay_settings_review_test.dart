import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:relay_app/config/theme.dart';
import 'package:relay_app/model/persistence/color_mode.dart';
import 'package:relay_app/pages/about/about_page.dart';
import 'package:relay_app/pages/gnome/gnome_settings_view.dart';
import 'package:relay_app/provider/device_info_provider.dart';
import 'package:relay_app/provider/persistence_provider.dart';
import 'package:relay_app/util/ui/dynamic_colors.dart';
import 'package:relay_app/widget/relay_carbon/relay_surface.dart';
import 'package:relay_isolates/isolate.dart';
import 'package:relay_isolates/model/device.dart';
import 'package:relay_isolates/model/device_info_result.dart';

import 'mocks_helper.dart';

/// Review renders of Relay's Settings and About surfaces.
///
/// These live apart from the overview renders because Settings resolves the
/// local IP on build, which opens a platform subscription the test binding
/// never completes; keeping it here means the rest of the review suite shuts
/// down promptly.
/// Rendering Settings leaves plugin state behind that makes the Dart test
/// isolate take minutes to shut down, which is not worth paying on every run.
/// These renders are therefore opt-in:
///
///     RELAY_SETTINGS_RENDERS=1 fvm flutter test test/widget/relay_settings_review_test.dart --update-goldens
final _enabled = Platform.environment['RELAY_SETTINGS_RENDERS'] == '1';

void main() {
  const reviewFontFamily = 'RelayReview';

  const textFonts = [
    '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
    '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf',
  ];
  const iconFonts = ['fonts/MaterialIcons-Regular.otf', 'build/unit_test_assets/fonts/MaterialIcons-Regular.otf'];

  Future<void> loadFamily(String family, List<String> paths) async {
    final loader = FontLoader(family);
    var loaded = 0;
    for (final path in paths) {
      final file = File(path);
      if (file.existsSync()) {
        loader.addFont(file.readAsBytes().then((bytes) => ByteData.view(Uint8List.fromList(bytes).buffer)));
        loaded++;
      }
    }
    if (loaded > 0) {
      await loader.load();
    }
  }

  setUpAll(() async {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();

    // Settings resolves the local IP and the package version on build. Neither
    // plugin exists under the test binding, and the unanswered calls both fail
    // the render and keep the isolate from shutting down, so answer them here.
    final messenger = binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      (call) async => <String>['wifi'],
    );
    messenger.setMockStreamHandler(
      const EventChannel('dev.fluttercommunity.plus/connectivity_status'),
      MockStreamHandler.inline(onListen: (arguments, sink) => sink.endOfStream()),
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/package_info'),
      (call) async => <String, String>{
        'appName': 'Relay',
        'packageName': 'com.foresight.app.relay',
        'version': '0.1.0',
        'buildNumber': '62',
      },
    );

    await loadFamily(reviewFontFamily, textFonts);
    await loadFamily('Roboto', textFonts);
    await loadFamily('Geist', textFonts);
    await loadFamily('MaterialIcons', iconFonts);
  });

  late ReviewPersistenceService persistence;

  setUp(() {
    persistence = ReviewPersistenceService();
    stubReviewPersistence(persistence);
  });

  /// Releases the platform stream subscriptions the settings tree opens. It has
  /// to happen while the tester is still live, or the suite cannot shut down.
  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }

  Future<void> renderWidget(WidgetTester tester, Widget child, Size viewport, {double scrollBy = 0}) async {
    tester.view.physicalSize = viewport;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final theme = getTheme(ColorMode.relay, Colors.blue, Brightness.dark, null);

    await tester.pumpWidget(
      RefenaScope(
        overrides: [
          persistenceProvider.overrideWithValue(persistence),
          dynamicColorsProvider.overrideWithValue(null),
          deviceRawInfoProvider.overrideWithValue(
            DeviceInfoResult(deviceType: DeviceType.desktop, deviceModel: 'Linux', androidSdkInt: null),
          ),
          parentIsolateProvider.overrideWithNotifier((ref) => ReviewIsolateController()),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: theme.copyWith(
            textTheme: theme.textTheme.apply(fontFamily: reviewFontFamily),
            primaryTextTheme: theme.primaryTextTheme.apply(fontFamily: reviewFontFamily),
          ),
          home: Scaffold(body: RelayCanvas(child: child)),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    if (scrollBy != 0) {
      final scrollable = tester.widget<Scrollable>(find.byType(Scrollable).first);
      scrollable.controller?.jumpTo(scrollBy);
      await tester.pump();
    }
    tester.takeException();
  }

  testWidgets(skip: !_enabled, 'carbon settings 1440x900', (tester) async {
    await renderWidget(tester, const GnomeSettingsView(), const Size(1440, 900));
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/relay_carbon/settings_1440x900.png'));
    await unmount(tester);
  });

  testWidgets(skip: !_enabled, 'carbon settings lower sections 1440x900', (tester) async {
    await renderWidget(tester, const GnomeSettingsView(), const Size(1440, 900), scrollBy: 640);
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/relay_carbon/settings_privacy_1440x900.png'));
    await unmount(tester);
  });

  testWidgets(skip: !_enabled, 'carbon about 1440x900', (tester) async {
    await renderWidget(
      tester,
      const Padding(
        padding: EdgeInsets.fromLTRB(64, 56, 64, 56),
        child: RelayAboutIdentity(version: '0.1.0', buildNumber: '62'),
      ),
      const Size(1440, 900),
    );
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/relay_carbon/about_1440x900.png'));
    await unmount(tester);
  });
}
