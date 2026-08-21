import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:relay_app/config/theme.dart';
import 'package:relay_app/model/persistence/color_mode.dart';
import 'package:relay_app/util/native/file_picker.dart';
import 'package:relay_app/widget/dialogs/add_file_dialog.dart';

import 'relay_desktop_fixtures.dart';

/// Readable, intentionally small review set for this product-quality pass.
void main() {
  const reviewFontFamily = 'RelayProductReview';
  const textFonts = [
    '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
    '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf',
  ];
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
    if (loaded == 0) return false;
    await loader.load();
    return true;
  }

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadFamily(reviewFontFamily, textFonts);
    await loadFamily('Roboto', textFonts);
    await loadFamily('MaterialIcons', iconFonts);
  });

  Future<void> render(WidgetTester tester, Size size, Widget child, String path) async {
    tester.view.physicalSize = size;
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
    await expectLater(find.byType(MaterialApp), matchesGoldenFile(path));
  }

  Widget picker({required bool mobile}) {
    const options = [
      FilePickerOption.file,
      FilePickerOption.folder,
      FilePickerOption.media,
      FilePickerOption.text,
      FilePickerOption.clipboard,
      FilePickerOption.app,
    ];
    return Scaffold(
      body: Align(
        alignment: mobile ? Alignment.bottomCenter : Alignment.center,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: mobile ? double.infinity : 560),
          child: AddFileDialog(
            options: mobile ? options : options.where((option) => option != FilePickerOption.media && option != FilePickerOption.app).toList(),
            mobile: mobile,
            onOptionSelected: (_) {},
          ),
        ),
      ),
    );
  }

  testWidgets('desktop Home 1000x700', (tester) async {
    await render(
      tester,
      const Size(1000, 700),
      RelayDesktopFixtures.home(state: RelayHomeState.empty),
      'goldens/relay_product_review/desktop_home_1000x700.png',
    );
  });

  testWidgets('desktop Home 1440x900', (tester) async {
    await render(
      tester,
      const Size(1440, 900),
      RelayDesktopFixtures.home(state: RelayHomeState.empty),
      'goldens/relay_product_review/desktop_home_1440x900.png',
    );
  });

  testWidgets('desktop Home 1920x1080', (tester) async {
    await render(
      tester,
      const Size(1920, 1080),
      RelayDesktopFixtures.home(state: RelayHomeState.empty),
      'goldens/relay_product_review/desktop_home_1920x1080.png',
    );
  });

  testWidgets('desktop Home nearby', (tester) async {
    await render(
      tester,
      const Size(1440, 900),
      RelayDesktopFixtures.home(state: RelayHomeState.nearby),
      'goldens/relay_product_review/desktop_home_nearby.png',
    );
  });

  testWidgets('desktop Home sending', (tester) async {
    await render(
      tester,
      const Size(1440, 900),
      RelayDesktopFixtures.home(state: RelayHomeState.sending),
      'goldens/relay_product_review/desktop_home_sending.png',
    );
  });

  testWidgets('desktop Add to selection', (tester) async {
    await render(tester, const Size(1000, 700), picker(mobile: false), 'goldens/relay_product_review/desktop_add_selection.png');
  });

  testWidgets('desktop Settings', (tester) async {
    await render(tester, const Size(1440, 900), RelayDesktopFixtures.settings(), 'goldens/relay_product_review/desktop_settings.png');
  });

  testWidgets('desktop About', (tester) async {
    await render(tester, const Size(1440, 900), RelayDesktopFixtures.about(), 'goldens/relay_product_review/desktop_about.png');
  });
}
