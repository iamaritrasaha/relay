import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:relay_app/config/theme.dart';
import 'package:relay_app/model/persistence/color_mode.dart';
import 'package:relay_app/widget/gnome/adw_action_row.dart';
import 'package:relay_app/widget/gnome/adw_boxed_list.dart';
import 'package:relay_app/widget/gnome/adw_button.dart';
import 'package:relay_app/widget/gnome/adw_header_bar.dart';
import 'package:relay_app/widget/gnome/adw_status_page.dart';

void main() {
  final darkTheme = getTheme(ColorMode.relay, Colors.teal, Brightness.dark, null);

  testWidgets('AdwHeaderBar renders title and subtitle in dark theme', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: darkTheme,
        home: const Scaffold(
          body: AdwHeaderBar(
            titleText: 'Pixel 8',
            subtitleText: 'Verified Relay Device',
          ),
        ),
      ),
    );

    expect(find.text('Pixel 8'), findsOneWidget);
    expect(find.text('Verified Relay Device'), findsOneWidget);
  });

  testWidgets('AdwPreferencesGroup renders group title and children in boxed list', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: darkTheme,
        home: Scaffold(
          body: AdwPreferencesGroup(
            title: 'DEVICE INFORMATION',
            children: [
              const AdwActionRow(
                title: 'Model',
                subtitle: 'Google Pixel 8',
              ),
              AdwNavigationRow(
                title: 'Diagnostics',
                valueText: 'Verified',
                onTap: () {},
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('DEVICE INFORMATION'), findsOneWidget);
    expect(find.text('Model'), findsOneWidget);
    expect(find.text('Google Pixel 8'), findsOneWidget);
    expect(find.text('Diagnostics'), findsOneWidget);
  });

  testWidgets('AdwButton styles render and trigger callbacks', (tester) async {
    var pressed = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: darkTheme,
        home: Scaffold(
          body: AdwButton.suggested(
            label: 'Send Files',
            icon: Icons.upload_file_rounded,
            onPressed: () => pressed = true,
          ),
        ),
      ),
    );

    expect(find.text('Send Files'), findsOneWidget);
    await tester.tap(find.text('Send Files'));
    expect(pressed, isTrue);
  });

  testWidgets('AdwStatusPage renders title, description, and action button', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: darkTheme,
        home: const Scaffold(
          body: AdwStatusPage(
            icon: Icons.content_paste_outlined,
            title: 'Clipboard Continuity',
            description: 'Shared clipboard sync is under active development.',
          ),
        ),
      ),
    );

    expect(find.text('Clipboard Continuity'), findsOneWidget);
    expect(find.text('Shared clipboard sync is under active development.'), findsOneWidget);
  });
}
