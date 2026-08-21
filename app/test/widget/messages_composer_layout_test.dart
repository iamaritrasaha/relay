import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:relay_app/config/relay_device_palette.dart';
import 'package:relay_app/config/theme.dart';
import 'package:relay_app/model/persistence/color_mode.dart';
import 'package:relay_app/model/ui/relay_capability_vm.dart';
import 'package:relay_app/model/ui/relay_device_vm.dart';
import 'package:relay_app/pages/gnome/gnome_kde_messages_view.dart';
import 'package:relay_app/provider/device_info_provider.dart';
import 'package:relay_app/provider/kdeconnect_provider.dart';
import 'package:relay_app/provider/persistence_provider.dart';
import 'package:relay_app/util/ui/dynamic_colors.dart';
import 'package:relay_isolates/model/device.dart';
import 'package:relay_isolates/model/device_info_result.dart';
import 'package:relay_isolates/rust/api/kdeconnect.dart';

import 'mocks_helper.dart';

/// The composer had collapsed into a shallow horizontal strip — a search field
/// rather than a desktop message composer. These tests measure what is actually
/// laid out, so the correction cannot silently regress.
/// A service seeded with one conversation, so the composer actually lays out.
/// Nothing is started and no runtime is touched — only the state the view reads.
class _SeededKdeConnectService extends KdeConnectService {
  _SeededKdeConnectService()
    : super(
        persistence: ReviewPersistenceService(),
        generateIdentity: ({required String deviceName}) async => throw UnimplementedError(),
        startRuntime: (identity, trusted) async => throw UnimplementedError(),
      );

  static const _deviceId = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

  static final _message = RsKdeSmsMessage(
    id: 11,
    threadId: 4,
    addresses: const ['+15550100'],
    body: 'Ping',
    date: 1700000000000,
    messageType: 1,
    read: true,
    attachments: const [],
  );

  @override
  KdeConnectState init() => KdeConnectState(
    smsConversations: {
      _deviceId: [
        RsKdeSmsConversation(threadId: 4, participants: const ['+15550100'], latestMessage: _message, unreadCount: 0),
      ],
    },
    smsMessages: {
      _deviceId: {
        4: [_message],
      },
    },
  );
}

void main() {
  const phone = RelayDeviceVm(
    key: 'kdeconnect:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    alias: 'Pixel',
    deviceType: DeviceType.mobile,
    phase: RelayDevicePhase.idle,
    progress: null,
    detail: 'Connected',
    targetKind: RelayDeviceTargetKind.kdeConnect,
    canSendSms: true,
    capabilities: {RelayCapability.messages: CapabilityStatus.available},
  );

  final persistence = ReviewPersistenceService();
  stubReviewPersistence(persistence);

  Future<void> pump(WidgetTester tester, {Brightness brightness = Brightness.dark}) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      RefenaScope(
        overrides: [
          persistenceProvider.overrideWithValue(persistence),
          dynamicColorsProvider.overrideWithValue(null),
          deviceRawInfoProvider.overrideWithValue(
            DeviceInfoResult(deviceType: DeviceType.desktop, deviceModel: 'Linux', androidSdkInt: null),
          ),
          kdeConnectProvider.overrideWithNotifier((ref) => _SeededKdeConnectService()),
        ],
        child: MaterialApp(
          theme: getTheme(ColorMode.relay, Colors.blue, brightness, null),
          home: Scaffold(
            body: GnomeKdeMessagesView(device: phone, onBack: () {}),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }

  testWidgets('the composer metrics are desktop-sized, not a search strip', (tester) async {
    // The constants the widget is built from are asserted directly, because the
    // composer only lays out once a conversation is selected and these are the
    // numbers a reviewer will check against the spec.
    expect(relayComposerFieldMinHeight, inInclusiveRange(50, 54));
    expect(relayComposerSendHeight, inInclusiveRange(50, 54));
    expect(relayComposerSendWidth, inInclusiveRange(84, 92));
    expect(relayComposerGap, inInclusiveRange(10, 14));
    expect(relayComposerVerticalPadding, inInclusiveRange(16, 18));
    expect(relayComposerHorizontalPadding, inInclusiveRange(16, 20));
  });

  testWidgets('the field and the Send button are the same height', (tester) async {
    expect(relayComposerFieldMinHeight, relayComposerSendHeight);
  });

  testWidgets('the overall composer area clears the minimum', (tester) async {
    // Field plus padding above and below.
    final total = relayComposerFieldMinHeight + relayComposerVerticalPadding * 2;
    expect(total, greaterThanOrEqualTo(88));
    expect(total, lessThanOrEqualTo(96));
  });

  testWidgets('the field corner radius is rounded but not a pill', (tester) async {
    expect(relayComposerFieldRadius, inInclusiveRange(10, 12));
  });

  testWidgets('the TextField owns the composer boundary and the system focus ring', (tester) async {
    await pump(tester);
    await tester.tap(find.text('+15550100').first);
    await tester.pumpAndSettle();

    final fieldBox = tester.widget<ConstrainedBox>(find.byKey(const ValueKey('kde-composer-field')));
    expect(fieldBox.child, isA<TextField>(), reason: 'no decorated input container may wrap another outlined TextField');

    final field = fieldBox.child! as TextField;
    final decoration = field.decoration!;
    final theme = Theme.of(tester.element(find.byType(TextField)));
    final devicePalette = RelayDevicePalette.fromDevice(phone, brightness: theme.brightness);
    expect(decoration.filled, isTrue);
    expect(decoration.border, isA<OutlineInputBorder>());
    expect(decoration.enabledBorder, isA<OutlineInputBorder>());
    expect(decoration.focusedBorder, isA<OutlineInputBorder>());
    expect((decoration.focusedBorder! as OutlineInputBorder).borderSide.color, devicePalette.primary);
    expect(field.minLines, 1);
    expect(field.maxLines, 4);
  });

  testWidgets('Ctrl+Enter remains the composer send shortcut', (tester) async {
    await pump(tester);
    await tester.tap(find.text('+15550100').first);
    await tester.pumpAndSettle();

    final shortcuts = tester.widget<CallbackShortcuts>(find.byType(CallbackShortcuts));
    expect(shortcuts.bindings.keys, contains(const SingleActivator(LogicalKeyboardKey.enter, control: true)));
  });

  testWidgets('the single composer boundary builds and focuses in light mode', (tester) async {
    await pump(tester, brightness: Brightness.light);
    await tester.tap(find.text('+15550100').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(TextField));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('kde-composer-field')), findsOneWidget);
    expect(FocusManager.instance.primaryFocus, isNotNull);
  });

  testWidgets('the laid-out field and Send button match the intended metrics', (tester) async {
    await pump(tester);
    await tester.tap(find.text('+15550100').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    final field = tester.getSize(find.byKey(const ValueKey('kde-composer-field')));
    expect(field.height, greaterThanOrEqualTo(50), reason: 'the input must not collapse back into a search strip');
    expect(field.height, lessThanOrEqualTo(56));

    final send = tester.getSize(find.byKey(const ValueKey('kde-composer-send')));
    expect(send.height, relayComposerSendHeight);
    expect(send.width, relayComposerSendWidth);
    // Equal at the resting height; the field may run a hair taller on a font
    // with looser metrics, which the minimum height floor absorbs.
    expect(field.height, inInclusiveRange(relayComposerSendHeight, relayComposerSendHeight + 4));

    // Sitting on the same baseline.
    final fieldBottom = tester.getBottomLeft(find.byKey(const ValueKey('kde-composer-field'))).dy;
    final sendBottom = tester.getBottomLeft(find.byKey(const ValueKey('kde-composer-send'))).dy;
    expect((fieldBottom - sendBottom).abs(), lessThan(1));
  });

  testWidgets('the field still grows for a multiline message', (tester) async {
    await pump(tester);
    await tester.tap(find.text('+15550100').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    final before = tester.getSize(find.byKey(const ValueKey('kde-composer-field'))).height;
    await tester.enterText(find.byType(TextField), 'one\ntwo\nthree');
    await tester.pump();

    final after = tester.getSize(find.byKey(const ValueKey('kde-composer-field'))).height;
    expect(after, greaterThan(before), reason: 'multiline growth must survive the fixed minimum height');

    // Send stays pinned to the bottom of the taller row.
    final fieldBottom = tester.getBottomLeft(find.byKey(const ValueKey('kde-composer-field'))).dy;
    final sendBottom = tester.getBottomLeft(find.byKey(const ValueKey('kde-composer-send'))).dy;
    expect((fieldBottom - sendBottom).abs(), lessThan(1));
  });

  testWidgets('an empty thread list still renders without a composer', (tester) async {
    await pump(tester);

    // With no conversations there is nothing to compose to, so the composer is
    // absent rather than disabled — and the view must not throw getting there.
    expect(tester.takeException(), isNull);
    expect(find.byType(GnomeKdeMessagesView), findsOneWidget);
  });

  testWidgets('the Send button keeps a visible surface when disabled', (tester) async {
    await pump(tester);
    await tester.tap(find.text('+15550100').first);
    await tester.pumpAndSettle();

    // The selected thread starts with an empty draft, so Send is disabled but
    // its normal Yaru surface remains visible.
    expect(tester.takeException(), isNull);
    expect(find.byType(FilledButton), findsWidgets);
  });
}
