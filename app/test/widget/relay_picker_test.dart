import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:relay_app/config/relay_brand.dart';
import 'package:relay_app/config/theme.dart';
import 'package:relay_app/model/persistence/color_mode.dart';
import 'package:relay_app/util/native/file_picker.dart';
import 'package:relay_app/widget/dialogs/add_file_dialog.dart';

void main() {
  const desktopOptions = [FilePickerOption.file, FilePickerOption.folder, FilePickerOption.text, FilePickerOption.clipboard];

  Future<void> pump(WidgetTester tester, {required Size size, required bool mobile, ValueChanged<FilePickerOption>? onSelected}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: getTheme(ColorMode.relay, Colors.blue, Brightness.dark, null),
        home: Scaffold(
          body: Align(
            alignment: mobile ? Alignment.bottomCenter : Alignment.center,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: mobile ? size.width : 560),
              child: AddFileDialog(options: desktopOptions, mobile: mobile, onOptionSelected: onSelected),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('desktop Add to selection uses the Relay surface and neutral tiles', (tester) async {
    await pump(tester, size: const Size(1000, 700), mobile: false);

    expect(find.byKey(const ValueKey('relay-add-selection-surface')), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    for (final option in desktopOptions) {
      final material = tester.widget<Material>(
        find.descendant(of: find.byKey(ValueKey('relay-picker-${option.name}')), matching: find.byType(Material)).first,
      );
      expect(material.color, RelayPalette.dark.softSurface);
      expect(material.color, isNot(anyOf(Colors.teal, Colors.green, Colors.lightGreen)));
    }
  });

  testWidgets('File Folder Text and Paste callbacks remain wired', (tester) async {
    final selected = <FilePickerOption>[];
    await pump(tester, size: const Size(1000, 700), mobile: false, onSelected: selected.add);

    for (final option in desktopOptions) {
      await tester.tap(find.byKey(ValueKey('relay-picker-${option.name}')));
      await tester.pump();
    }

    expect(selected, desktopOptions);
  });

  testWidgets('Android selection surface fits 360x800', (tester) async {
    await pump(tester, size: const Size(360, 800), mobile: true);

    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('relay-add-selection-surface')), findsOneWidget);
    expect(find.byKey(const ValueKey('relay-picker-file')), findsOneWidget);
    expect(find.byKey(const ValueKey('relay-picker-clipboard')), findsOneWidget);
  });
}
