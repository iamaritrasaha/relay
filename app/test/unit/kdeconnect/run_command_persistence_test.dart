import 'package:flutter_test/flutter_test.dart';
import 'package:relay_app/provider/kdeconnect_provider.dart';
import 'package:relay_isolates/rust/api/kdeconnect.dart';

/// The desktop's RunCommand allow-list is the whole security boundary: a phone
/// can only ever name an id from it. These cover the persistence edge of that
/// list — ids must survive a restart unchanged, or a phone's cached ids stop
/// resolving and the feature silently breaks.
void main() {
  const marker = RsRunCommand(
    id: 'f2b1c0de-0000-4000-8000-000000000001',
    name: 'Marker',
    command: 'touch /tmp/relay-marker',
    enabled: true,
  );
  const disabled = RsRunCommand(
    id: 'f2b1c0de-0000-4000-8000-000000000002',
    name: 'Disabled',
    command: 'echo nope',
    enabled: false,
  );

  test('a command list round-trips through persistence with its ids intact', () {
    final restored = kdeRunCommandsFromJson(kdeRunCommandsToJson([marker, disabled]));

    expect(restored, [marker, disabled]);
    // The id is what a phone caches, so it is the field that must not drift.
    expect(restored.map((c) => c.id), [marker.id, disabled.id]);
    expect(restored[1].enabled, isFalse, reason: 'the disabled flag must survive too');
  });

  test('an entry with no usable id is skipped rather than dropping the whole list', () {
    final restored = kdeRunCommandsFromJson([
      {'id': marker.id, 'name': 'Marker', 'command': 'touch /tmp/relay-marker', 'enabled': true},
      {'name': 'No id', 'command': 'echo x', 'enabled': true},
      {'id': '', 'name': 'Empty id', 'command': 'echo y', 'enabled': true},
      {'id': 42, 'name': 'Wrong type', 'command': 'echo z', 'enabled': true},
    ]);

    expect(restored, hasLength(1));
    expect(restored.single.id, marker.id);
  });

  test('missing optional fields default to a safe, disabled entry', () {
    final restored = kdeRunCommandsFromJson([
      {'id': 'only-an-id'},
    ]);

    expect(restored.single.name, '');
    expect(restored.single.command, '');
    // Defaulting to enabled would make a corrupt record runnable.
    expect(restored.single.enabled, isFalse);
  });

  test('an empty stored list restores as an empty allow-list', () {
    expect(kdeRunCommandsFromJson([]), isEmpty);
    expect(kdeRunCommandsToJson([]), isEmpty);
  });

  test('the encoded form carries exactly the four configured fields', () {
    final encoded = kdeRunCommandsToJson([marker]).single;
    expect(encoded.keys.toSet(), {'id', 'name', 'command', 'enabled'});
    expect(encoded['command'], 'touch /tmp/relay-marker');
  });
}
