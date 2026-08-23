import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:relay_app/provider/relay_clipboard_service.dart';

/// The clipboard service is deliberately dumb: it reports every local change and
/// applies what it is told, because only `relay_core` can see both directions
/// and decide. What it *must* get right is the size bound and never dropping a
/// legitimate value.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.foresight.app.relay/clipboard');
  final calls = <MethodCall>[];
  String? clipboardText;

  setUp(() {
    calls.clear();
    clipboardText = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'getText') return clipboardText;
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  /// Simulates the native side reporting a local clipboard change.
  Future<void> emitLocalChange(String text) async {
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(MethodCall('clipboardChanged', {'text': text})),
      (_) {},
    );
  }

  test('a local clipboard change is reported once, verbatim', () async {
    final seen = <String>[];
    RelayClipboardService(platform: TargetPlatform.linux, onLocalChange: (text) async => seen.add(text));

    await emitLocalChange('hello');
    await emitLocalChange('héllo\nwörld 🎉');

    expect(seen, ['hello', 'héllo\nwörld 🎉'], reason: 'Unicode and newlines must survive intact');
  });

  test('an oversized local change is dropped rather than forwarded', () async {
    final seen = <String>[];
    RelayClipboardService(platform: TargetPlatform.linux, onLocalChange: (text) async => seen.add(text));

    await emitLocalChange('x' * (maxClipboardBytes + 1));

    expect(seen, isEmpty);
  });

  test('an empty local change is ignored', () async {
    final seen = <String>[];
    RelayClipboardService(platform: TargetPlatform.linux, onLocalChange: (text) async => seen.add(text));
    await emitLocalChange('');
    expect(seen, isEmpty);
  });

  test('a throwing handler does not break later changes', () async {
    final seen = <String>[];
    RelayClipboardService(
      platform: TargetPlatform.linux,
      onLocalChange: (text) async {
        seen.add(text);
        if (text == 'boom') throw StateError('handler failed');
      },
    );

    await emitLocalChange('boom');
    await emitLocalChange('after');

    expect(seen, ['boom', 'after'], reason: 'one failure must not stop the watcher');
  });

  test('applying a remote value writes it through the native channel', () async {
    final service = RelayClipboardService(platform: TargetPlatform.linux);

    expect(await service.applyRemote('hello'), isTrue);

    final setText = calls.singleWhere((call) => call.method == 'setText');
    expect(setText.arguments['text'], 'hello');
  });

  test('an empty or oversized remote value is refused and never written', () async {
    final service = RelayClipboardService(platform: TargetPlatform.linux);

    expect(await service.applyRemote(''), isFalse);
    expect(await service.applyRemote('x' * (maxClipboardBytes + 1)), isFalse);

    expect(
      calls.where((call) => call.method == 'setText'),
      isEmpty,
      reason: 'the local clipboard must be preserved',
    );
  });

  test('exactly the bound is still accepted', () async {
    final service = RelayClipboardService(platform: TargetPlatform.linux);
    expect(await service.applyRemote('x' * maxClipboardBytes), isTrue);
  });

  test('start and stop drive the native watcher exactly once each', () async {
    final service = RelayClipboardService(platform: TargetPlatform.linux);

    await service.start();
    await service.start();
    expect(calls.where((call) => call.method == 'startWatching'), hasLength(1));

    await service.stop();
    expect(calls.where((call) => call.method == 'stopWatching'), hasLength(1));
  });

  test('on a non-Linux platform the service stays inert', () async {
    final service = RelayClipboardService(platform: TargetPlatform.android);

    expect(service.isSupported, isFalse);
    await service.start();
    expect(await service.applyRemote('hello'), isFalse);
    expect(await service.currentText(), isNull);
    expect(calls, isEmpty);
  });

  _autoSyncTests();

  test('currentText returns what the platform reports', () async {
    clipboardText = 'from gtk';
    final service = RelayClipboardService(platform: TargetPlatform.linux);
    expect(await service.currentText(), 'from gtk');
  });
}

/// The Wayland limitation is measured, not assumed: a background client is
/// never offered the clipboard there. These pin how Relay reports that.
void _autoSyncTests() {
  test('a Wayland session reports that unattended sync is unavailable', () {
    final service = RelayClipboardService(platform: TargetPlatform.linux)
      ..environmentOverride = {'XDG_SESSION_TYPE': 'wayland'};
    expect(service.autoSyncAvailable, isFalse);
  });

  test('an X11 session reports unattended sync as available', () {
    final service = RelayClipboardService(platform: TargetPlatform.linux)
      ..environmentOverride = {'XDG_SESSION_TYPE': 'x11'};
    expect(service.autoSyncAvailable, isTrue);
  });

  test('a non-Linux platform never claims unattended sync', () {
    final service = RelayClipboardService(platform: TargetPlatform.android)
      ..environmentOverride = {'XDG_SESSION_TYPE': 'x11'};
    expect(service.autoSyncAvailable, isFalse);
  });
}
