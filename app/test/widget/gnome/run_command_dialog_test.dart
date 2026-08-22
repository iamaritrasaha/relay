import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:relay_app/pages/gnome/gnome_settings_view.dart';
import 'package:relay_isolates/rust/api/kdeconnect.dart';

/// The add/edit dialog gates Save on a non-empty command line, and that gate is
/// evaluated while building. So the field must rebuild the dialog as it is typed
/// into — otherwise Save is disabled forever on a new command and the feature
/// cannot be configured at all. Found during physical testing.
void main() {
  const existing = RsRunCommand(id: 'stable-id-1', name: 'Old', command: 'echo old', enabled: true);

  Future<RsRunCommand?> openDialog(WidgetTester tester, {RsRunCommand? command}) async {
    RsRunCommand? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showDialog<RsRunCommand>(
                  context: context,
                  builder: (_) => RunCommandDialog(
                    command: command ?? const RsRunCommand(id: 'new-id', name: '', command: '', enabled: true),
                    isNew: command == null,
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return result;
  }

  Finder commandField() => find.widgetWithText(TextField, 'Command');
  Finder nameField() => find.widgetWithText(TextField, 'Name');
  Finder saveButton() => find.widgetWithText(FilledButton, 'Save');

  testWidgets('Save is dead until a command line is typed, then enables', (tester) async {
    await openDialog(tester);

    expect(tester.widget<FilledButton>(saveButton()).onPressed, isNull, reason: 'nothing to save yet');

    await tester.enterText(commandField(), 'touch /tmp/relay-marker');
    await tester.pump();

    expect(
      tester.widget<FilledButton>(saveButton()).onPressed,
      isNotNull,
      reason: 'typing a command must enable Save; without a rebuild it stays dead and the feature is unconfigurable',
    );
  });

  testWidgets('a whitespace-only command never enables Save', (tester) async {
    await openDialog(tester);
    await tester.enterText(commandField(), '   ');
    await tester.pump();
    expect(tester.widget<FilledButton>(saveButton()).onPressed, isNull);
  });

  testWidgets('editing keeps the id it was opened with', (tester) async {
    await tester.runAsync(() async {});
    RsRunCommand? captured;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                captured = await showDialog<RsRunCommand>(
                  context: context,
                  builder: (_) => const RunCommandDialog(command: existing, isNew: false),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // An existing command already has text, so Save is live immediately.
    expect(tester.widget<FilledButton>(saveButton()).onPressed, isNotNull);

    await tester.enterText(nameField(), 'Relay Test Marker');
    await tester.enterText(commandField(), 'touch /tmp/relay-marker');
    await tester.pump();
    await tester.tap(saveButton());
    await tester.pumpAndSettle();

    expect(captured, isNotNull);
    expect(captured!.id, 'stable-id-1', reason: 'editing must not mint a new id — phones cache it');
    expect(captured!.name, 'Relay Test Marker');
    expect(captured!.command, 'touch /tmp/relay-marker');
  });
}
