import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:relay_app/config/theme.dart';
import 'package:relay_app/model/persistence/color_mode.dart';

import 'relay_desktop_fixtures.dart';

/// Renders the five desktop review images at the approved 1440x900 viewport.
///
/// Run with `--update-goldens` to regenerate them for visual review. The
/// renders exist to be looked at, so they load a real text face — the test
/// environment otherwise draws every glyph as a filled box, which hides
/// exactly the typography this composition is judged on.
void main() {
  const viewport = Size(1440, 900);
  const reviewFontFamily = 'RelayReview';

  const textFonts = [
    '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
    '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf',
  ];

  // Buttons carry their own text style, and icons resolve through the icon
  // font, so both need a face registered under the family they actually ask
  // for rather than the review family alone.
  const iconFonts = ['fonts/MaterialIcons-Regular.otf', 'build/unit_test_assets/fonts/MaterialIcons-Regular.otf'];

  Future<bool> loadFamily(String family, List<String> paths) async {
    final loader = FontLoader(family);
    var loaded = 0;
    for (final path in paths) {
      final file = File(path);
      if (file.existsSync()) {
        loader.addFont(file.readAsBytes().then((bytes) => ByteData.view(Uint8List.fromList(bytes).buffer)));
        loaded++;
      }
    }
    if (loaded == 0) {
      return false;
    }
    await loader.load();
    return true;
  }

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadFamily(reviewFontFamily, textFonts);
    // Also the family a null fontFamily falls back to, so button labels render.
    await loadFamily('Roboto', textFonts);
    await loadFamily('MaterialIcons', iconFonts);
  });

  Future<void> render(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = viewport;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final theme = getTheme(ColorMode.relay, Colors.blue, Brightness.dark, null);
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: theme.copyWith(
            textTheme: theme.textTheme.apply(fontFamily: reviewFontFamily),
            primaryTextTheme: theme.primaryTextTheme.apply(fontFamily: reviewFontFamily),
          ),
          home: child,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }

  testWidgets('desktop home empty', (tester) async {
    await render(tester, RelayDesktopFixtures.home(state: RelayHomeState.empty));
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/relay_desktop/home_empty.png'));
  });

  testWidgets('desktop home nearby', (tester) async {
    await render(tester, RelayDesktopFixtures.home(state: RelayHomeState.nearby));
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/relay_desktop/home_nearby.png'));
  });

  testWidgets('desktop home sending', (tester) async {
    await render(tester, RelayDesktopFixtures.home(state: RelayHomeState.sending));
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/relay_desktop/home_sending.png'));
  });

  testWidgets('desktop settings', (tester) async {
    await render(tester, RelayDesktopFixtures.settings());
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/relay_desktop/settings.png'));
  });

  testWidgets('desktop about', (tester) async {
    await render(tester, RelayDesktopFixtures.about());
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/relay_desktop/about.png'));
  });
}
