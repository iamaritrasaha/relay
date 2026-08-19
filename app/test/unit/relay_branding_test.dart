import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('product localization sources do not restore the previous product name', () {
    final sources = Directory(
      'assets/i18n',
    ).listSync().whereType<File>().where((file) => file.path.endsWith('.json')).where((file) => !file.uri.pathSegments.last.startsWith('_'));

    for (final source in sources) {
      expect(source.readAsStringSync(), isNot(contains('Relay')), reason: source.path);
    }
  });
}
