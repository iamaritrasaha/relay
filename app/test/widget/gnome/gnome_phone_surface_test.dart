import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:relay_app/config/relay_brand.dart';
import 'package:relay_app/config/theme.dart';
import 'package:relay_app/model/persistence/color_mode.dart';
import 'package:relay_app/model/ui/relay_device_vm.dart';
import 'package:relay_app/pages/gnome/gnome_kde_phone_view.dart';
import 'package:relay_app/provider/animation_provider.dart';
import 'package:relay_app/provider/kdeconnect_provider.dart';
import 'package:relay_app/widget/gnome/adw_boxed_list.dart';
import 'package:relay_isolates/model/device.dart';
import 'package:yaru/yaru.dart';

import '../mocks_helper.dart';

const _deviceId = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

class _PhoneKdeService extends KdeConnectService {
  final KdeConnectState initialState;

  _PhoneKdeService(this.initialState)
    : super(
        persistence: ReviewPersistenceService(),
        generateIdentity: ({required String deviceName}) async => throw UnimplementedError(),
        startRuntime: (identity, trusted) async => throw UnimplementedError(),
      );

  @override
  KdeConnectState init() => initialState;

  void showCall(KdeTelephonyState? call) {
    redux.dispatch(_SetPhoneCallAction(call));
  }
}

class _SetPhoneCallAction extends ReduxAction<KdeConnectService, KdeConnectState> {
  final KdeTelephonyState? call;

  _SetPhoneCallAction(this.call);

  @override
  KdeConnectState reduce() => state.copyWith(activeCalls: {_deviceId: call});
}

void main() {
  const phone = RelayDeviceVm(
    key: 'kdeconnect:$_deviceId',
    alias: 'My Phone',
    deviceType: DeviceType.mobile,
    phase: RelayDevicePhase.idle,
    progress: null,
    detail: 'Connected',
    targetKind: RelayDeviceTargetKind.kdeConnect,
    canMuteRinger: true,
  );

  late _PhoneKdeService service;

  Future<void> pumpPhone(
    WidgetTester tester, {
    KdeConnectState state = const KdeConnectState(),
    bool animationsEnabled = true,
    bool reducedMotion = false,
    Brightness brightness = Brightness.dark,
  }) async {
    service = _PhoneKdeService(state);
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      RefenaScope(
        overrides: [
          kdeConnectProvider.overrideWithNotifier((ref) => service),
          animationProvider.overrideWithBuilder((ref) => animationsEnabled),
        ],
        child: MaterialApp(
          theme: getTheme(ColorMode.relay, Colors.orange, brightness, null),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: reducedMotion),
            child: child!,
          ),
          home: Scaffold(
            body: GnomeKdePhoneView(device: phone, onBack: () {}),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('Phone uses one compact status group and an inline information note', (tester) async {
    await pumpPhone(tester);

    expect(find.text('Call Status'), findsOneWidget);
    expect(find.text('My Phone'), findsOneWidget);
    expect(find.text('No active call'), findsOneWidget);
    expect(find.text('Recent Calls'), findsOneWidget);
    expect(find.text('This session'), findsOneWidget);
    expect(find.text('Recent Call Activity (This Session)'), findsNothing);
    expect(find.text('No Active Call'), findsNothing);
    expect(find.byType(YaruBorderContainer), findsNothing, reason: 'Phone must not fall back to a stack of outlined cards');

    final document = tester.widget<ConstrainedBox>(find.byKey(const ValueKey('phone-document')));
    expect(document.constraints.maxWidth, 760);

    final status = find.byKey(const ValueKey('phone-call-status-section'));
    final statusGroup = find.descendant(of: status, matching: find.byType(AdwBoxedList));
    expect(statusGroup, findsOneWidget);
    expect(
      find.descendant(of: statusGroup, matching: find.text('Call Status')),
      findsNothing,
      reason: 'section title stays outside the filled group',
    );
    expect(tester.getSize(statusGroup).height, inInclusiveRange(68, 80));

    final statusMaterial = tester.widget<Material>(find.descendant(of: statusGroup, matching: find.byType(Material)).first);
    final statusShape = statusMaterial.shape! as RoundedRectangleBorder;
    expect(statusShape.borderRadius, BorderRadius.circular(RelayRadius.panel));
    expect(statusShape.side, BorderSide.none);

    final note = find.byKey(const ValueKey('phone-inline-info-note'));
    expect(note, findsOneWidget);
    expect(find.descendant(of: note, matching: find.byType(YaruBorderContainer)), findsNothing);
    expect(find.descendant(of: note, matching: find.byType(Material)), findsNothing);
  });

  testWidgets('Recent Calls is one joined group with compact aligned rows', (tester) async {
    const first = KdeTelephonyState(event: 'missedCall', contactName: 'Ada', phoneNumber: '+15550101', timestamp: 1700000000000);
    const second = KdeTelephonyState(event: 'talking', contactName: 'Grace', phoneNumber: '+15550102', timestamp: 1700000060000);
    await pumpPhone(
      tester,
      state: const KdeConnectState(
        recentTelephonyEvents: {
          _deviceId: [first, second],
        },
      ),
    );

    final recent = find.byKey(const ValueKey('phone-recent-calls-section'));
    final group = find.descendant(of: recent, matching: find.byType(AdwBoxedList));
    final firstRow = find.byKey(const ValueKey('phone-call-history-1700000000000-missedCall'));
    final secondRow = find.byKey(const ValueKey('phone-call-history-1700000060000-talking'));

    expect(group, findsOneWidget);
    expect(find.descendant(of: group, matching: firstRow), findsOneWidget);
    expect(find.descendant(of: group, matching: secondRow), findsOneWidget);
    expect(tester.getSize(firstRow).height, inInclusiveRange(58, 64));
    expect(tester.getSize(secondRow).height, inInclusiveRange(58, 64));
    expect(tester.getTopRight(firstRow).dx, closeTo(tester.getTopRight(secondRow).dx, 0.01));
    expect(find.text('Missed call'), findsOneWidget);
    expect(find.text('Call connected'), findsOneWidget);

    final material = tester.widget<Material>(find.descendant(of: group, matching: find.byType(Material)).first);
    expect((material.shape! as RoundedRectangleBorder).side, BorderSide.none);
    expect(material.clipBehavior, Clip.antiAlias);
  });

  testWidgets('call state and ringing acknowledgement are finite', (tester) async {
    await pumpPhone(tester);
    const ringing = KdeTelephonyState(event: 'ringing', contactName: 'Ada', phoneNumber: '+15550101', timestamp: 1700000000000);

    service.showCall(ringing);
    await tester.pump();

    final switcher = tester.widget<AnimatedSwitcher>(find.byKey(const ValueKey('phone-call-state-switcher')));
    expect(switcher.duration, const Duration(milliseconds: 200));
    expect(switcher.reverseDuration, const Duration(milliseconds: 180));
    expect(find.byType(FadeTransition), findsWidgets);
    expect(find.byType(SlideTransition), findsWidgets);
    expect(find.text('Ada'), findsOneWidget);
    expect(find.text('Incoming call · +15550101'), findsOneWidget);
    expect(find.text('Mute'), findsOneWidget, reason: 'the existing ringer capability remains available');

    final indicator = tester.widget<TweenAnimationBuilder<double>>(
      find.byKey(const ValueKey('phone-call-indicator-ringing-1700000000000')),
    );
    expect(indicator.duration, const Duration(milliseconds: 750));

    await tester.pump(const Duration(milliseconds: 751));
    expect(tester.binding.hasScheduledFrame, isFalse, reason: 'the ringing acknowledgement must settle rather than loop');
  });

  testWidgets('system reduced motion removes call translation and pulse', (tester) async {
    const ringing = KdeTelephonyState(event: 'ringing', contactName: 'Ada', timestamp: 1700000000000);
    await pumpPhone(
      tester,
      state: const KdeConnectState(activeCalls: {_deviceId: ringing}),
      reducedMotion: true,
    );

    final switcher = tester.widget<AnimatedSwitcher>(find.byKey(const ValueKey('phone-call-state-switcher')));
    final indicator = tester.widget<TweenAnimationBuilder<double>>(
      find.byKey(const ValueKey('phone-call-indicator-ringing-1700000000000')),
    );
    expect(switcher.duration, Duration.zero);
    expect(switcher.reverseDuration, Duration.zero);
    expect(indicator.duration, Duration.zero);
  });

  testWidgets('Spatial animations off produces the same static call status', (tester) async {
    const ringing = KdeTelephonyState(event: 'ringing', contactName: 'Ada', timestamp: 1700000000000);
    await pumpPhone(
      tester,
      state: const KdeConnectState(activeCalls: {_deviceId: ringing}),
      animationsEnabled: false,
    );

    expect(tester.widget<AnimatedSwitcher>(find.byKey(const ValueKey('phone-call-state-switcher'))).duration, Duration.zero);
    expect(
      tester.widget<TweenAnimationBuilder<double>>(find.byKey(const ValueKey('phone-call-indicator-ringing-1700000000000'))).duration,
      Duration.zero,
    );
  });

  for (final brightness in Brightness.values) {
    testWidgets('Phone builds without legacy borders in ${brightness.name} mode', (tester) async {
      await pumpPhone(tester, brightness: brightness);
      expect(tester.takeException(), isNull);
      expect(find.byType(YaruBorderContainer), findsNothing);
      expect(find.byKey(const ValueKey('phone-call-status-section')), findsOneWidget);
      expect(find.byKey(const ValueKey('phone-recent-calls-section')), findsOneWidget);
    });
  }
}
