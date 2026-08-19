import 'dart:async';
import 'dart:io';

import 'package:dart_mappable/dart_mappable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_displaymode/flutter_displaymode.dart';
import 'package:localsend_app/config/refena.dart';
import 'package:localsend_app/config/theme.dart';
import 'package:localsend_app/pages/home_page.dart';
import 'package:localsend_app/pages/home_page_controller.dart';
import 'package:localsend_app/pages/whats_new_page.dart';
import 'package:localsend_app/provider/animation_provider.dart';
import 'package:localsend_app/provider/app_arguments_provider.dart';
import 'package:localsend_app/provider/continuity/continuity_provider.dart';
import 'package:localsend_app/provider/device_info_provider.dart';
import 'package:localsend_app/provider/network/nearby_devices_provider.dart';
import 'package:localsend_app/provider/network/server/server_provider.dart';
import 'package:localsend_app/provider/network/webrtc/signaling_provider.dart';
import 'package:localsend_app/provider/persistence_provider.dart';
// [FOSS_REMOVE_START]
import 'package:localsend_app/provider/purchase_provider.dart';
// [FOSS_REMOVE_END]
import 'package:localsend_app/provider/relay_anywhere_listener_provider.dart';
import 'package:localsend_app/provider/selection/selected_sending_files_provider.dart';
import 'package:localsend_app/provider/settings_provider.dart';
import 'package:localsend_app/provider/tv_provider.dart';
import 'package:localsend_app/provider/version_provider.dart';
import 'package:localsend_app/provider/window_dimensions_provider.dart';
import 'package:localsend_app/util/i18n.dart';
import 'package:localsend_app/util/native/autostart_helper.dart';
import 'package:localsend_app/util/native/cache_helper.dart';
import 'package:localsend_app/util/native/channel/android_channel.dart';
import 'package:localsend_app/util/native/context_menu_helper.dart';
import 'package:localsend_app/util/native/cross_file_converters.dart';
import 'package:localsend_app/util/native/device_info_helper.dart';
import 'package:localsend_app/util/native/macos_channel.dart';
import 'package:localsend_app/util/native/platform_check.dart';
import 'package:localsend_app/util/native/tray_helper.dart';
import 'package:localsend_app/util/notification_strings.dart';
import 'package:localsend_app/util/ui/dynamic_colors.dart';
import 'package:localsend_app/util/ui/snackbar.dart';
import 'package:localsend_app/widget/dialogs/local_network_dialog.dart';
import 'package:localsend_isolates/isolate.dart';
import 'package:localsend_isolates/model/dto/file_dto.dart';
import 'package:localsend_isolates/model/dto/multicast_dto.dart';
import 'package:localsend_isolates/rust/api/logging.dart' as rust_logging;
import 'package:localsend_isolates/rust/frb_generated.dart';
import 'package:localsend_isolates/util/logger.dart';
import 'package:localsend_isolates/util/show_instance.dart';
import 'package:localsend_isolates/util/transfer_notification.dart';
import 'package:logging/logging.dart';
import 'package:refena_flutter/addons.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:routerino/routerino.dart';
import 'package:share_handler/share_handler.dart';
import 'package:window_manager/window_manager.dart';

final _logger = Logger('Init');

/// Will be called before the MaterialApp started
Future<RefenaContainer> preInit(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  initLogger(args.contains('-v') || args.contains('--verbose') ? Level.ALL : Level.INFO);
  MapperContainer.globals.use(const FileDtoMapper());

  await RustLib.init();

  if (kDebugMode) {
    try {
      await rust_logging.enableDebugLogging();
    } catch (e) {
      _logger.warning('Enabling debug logging failed', e);
    }
  }

  final dynamicColors = await getDynamicColors();

  final persistenceService = await PersistenceService.initialize(
    supportsDynamicColors: dynamicColors != null,
  );

  if (persistenceService.isFirstAppStart && !persistenceService.isPortableMode()) {
    await enableContextMenu();
  }

  await initI18n();

  TransferNotification.init(notificationStrings);

  bool startHidden = false;
  if (checkPlatformIsDesktop()) {
    // Check if this app is already open and let it "show up".
    // If this is the case, then exit the current instance.

    final handedOver = await notifyRunningInstance(
      securityContext: persistenceService.getSecurityContext(),
      port: persistenceService.getPort(),
      https: persistenceService.isHttps(),
      showToken: persistenceService.getShowToken(),
      args: args,
    );
    if (handedOver) {
      exit(0); // Another instance does exist
    }

    // initialize tray AFTER i18n has been initialized
    try {
      await initTray();
    } catch (e) {
      _logger.warning('Initializing tray failed: $e');
    }

    // initialize size and position
    await WindowManager.instance.ensureInitialized();
    await WindowDimensionsController(persistenceService).initDimensionsConfiguration();
    if (args.contains(startHiddenFlag)) {
      // keep this app hidden
      startHidden = true;
    } else if (defaultTargetPlatform == TargetPlatform.macOS) {
      startHidden = await isLaunchedAsLoginItem() && await getLaunchAtLoginMinimized();
    }

    if (startHidden) {
      unawaited(hideToTray());
    } else {
      unawaited(showFromTray());
    }

    if (defaultTargetPlatform == TargetPlatform.macOS) {
      await setupStatusBar();
    }
  }

  setDefaultRouteTransition();

  final container = RefenaContainer(
    observers: kDebugMode ? [CustomRefenaObserver()] : [],
    overrides: [
      persistenceProvider.overrideWithValue(persistenceService),
      deviceRawInfoProvider.overrideWithValue(await getDeviceInfo()),
      appArgumentsProvider.overrideWithValue(args),
      tvProvider.overrideWithValue(await checkIfTv()),
      dynamicColorsProvider.overrideWithValue(dynamicColors),
      sleepProvider.overrideWithInitialState((ref) => startHidden),
    ],
    platformHint: RefenaScope.getPlatformHint(), // help Refena know the correct platform
  );

  // compatibility for Routerino. TODO: Remove Routerino
  Routerino.navigatorKey = container.read(navigationProvider).key;

  // initialize multi-threading
  container.set(
    parentIsolateProvider.overrideWithNotifier((ref) {
      final settings = ref.read(settingsProvider);
      return IsolateController(
        initialState: ParentIsolateState.initial(
          SyncState(
            rootIsolateToken: RootIsolateToken.instance!,
            securityContext: persistenceService.getSecurityContext(),
            deviceInfo: ref.read(deviceInfoProvider),
            alias: settings.alias,
            port: settings.port,
            networkWhitelist: settings.networkWhitelist,
            networkBlacklist: settings.networkBlacklist,
            protocol: settings.https ? ProtocolType.https : ProtocolType.http,
            multicastGroup: settings.multicastGroup,
            discoveryTimeout: settings.discoveryTimeout,
            serverRunning: true,
            download: false,
          ),
        ),
      );
    }),
  );

  await container.redux(parentIsolateProvider).dispatchAsync(IsolateSetupAction());

  return container;
}

StreamSubscription? _sharedMediaSubscription;

/// Starts networking after the child isolates have been created.
///
/// This is intentionally independent from [HomePage] so desktop apps started
/// hidden can receive files before a window is shown.
class NetworkBootstrap {
  final Future<bool> Function()? _requestLocalNetworkPermission;
  final Future<void> Function() _startServer;
  final void Function() _startDiscoveryListener;
  final Future<void> Function()? _startRemoteListener;

  Future<NetworkBootstrapResult>? _startFuture;

  NetworkBootstrap({
    Future<bool> Function()? requestLocalNetworkPermission,
    required Future<void> Function() startServer,
    required void Function() startDiscoveryListener,
    Future<void> Function()? startRemoteListener,
  }) : _requestLocalNetworkPermission = requestLocalNetworkPermission,
       _startServer = startServer,
       _startDiscoveryListener = startDiscoveryListener,
       _startRemoteListener = startRemoteListener;

  Future<NetworkBootstrapResult> start() async {
    final existingStart = _startFuture;
    if (existingStart != null) {
      return existingStart;
    }

    final start = _start();
    _startFuture = start;
    final result = await start;
    if (!result.localNetworkGranted && identical(_startFuture, start)) {
      _startFuture = null;
    }
    return result;
  }

  Future<NetworkBootstrapResult> _start() async {
    var localNetworkGranted = true;
    if (_requestLocalNetworkPermission != null) {
      try {
        localNetworkGranted = await _requestLocalNetworkPermission();
      } catch (e) {
        localNetworkGranted = false;
        _logger.warning('Requesting local network permission failed', e);
      }
    }

    if (!localNetworkGranted) {
      // Remote Relay uses a separate user-enabled transport. Android's LAN
      // permission must not silently disable an already configured remote
      // listener, and this call remains a no-op unless the setting is on.
      try {
        await _startRemoteListener?.call();
      } catch (e) {
        _logger.warning('Starting remote Relay listener failed', e);
      }
      return const NetworkBootstrapResult(
        localNetworkGranted: false,
        serverError: null,
      );
    }

    Object? serverError;
    try {
      await _startServer();
    } catch (e) {
      serverError = e;
      _logger.warning('Starting server failed', e);
    }

    try {
      _startDiscoveryListener();
    } catch (e) {
      _logger.warning('Starting discovery listener failed', e);
    }

    try {
      await _startRemoteListener?.call();
    } catch (e) {
      // Remote capability must never make the normal LAN bootstrap fail.
      _logger.warning('Starting remote Relay listener failed', e);
    }

    return NetworkBootstrapResult(
      localNetworkGranted: localNetworkGranted,
      serverError: serverError,
    );
  }
}

class NetworkBootstrapResult {
  final bool localNetworkGranted;
  final Object? serverError;

  const NetworkBootstrapResult({
    required this.localNetworkGranted,
    required this.serverError,
  });
}

NetworkBootstrap createNetworkBootstrap(RefenaContainer container) {
  return NetworkBootstrap(
    requestLocalNetworkPermission: checkPlatform([TargetPlatform.android]) ? requestLocalNetworkPermissionAndroid : null,
    startServer: () async {
      await container.notifier(serverProvider).startServerFromSettings();
    },
    startDiscoveryListener: () {
      unawaited(container.redux(nearbyDevicesProvider).dispatchAsync(StartDiscoveryListener()));
    },
    startRemoteListener: () async {
      await container
          .read(relayAnywhereListenerServiceProvider)
          .startIfEnabled(
            enabled: container.read(settingsProvider).remoteRelayEnabled || container.read(persistenceProvider).getRelayPairedAddresses().isNotEmpty,
            alias: container.read(settingsProvider).alias,
          );
    },
  );
}

/// Will be called when home page has been initialized
Future<void> postInit(BuildContext context, Ref ref, bool appStart, NetworkBootstrapResult? networkBootstrap) async {
  await updateSystemOverlayStyle(context);

  if (checkPlatform([TargetPlatform.android])) {
    try {
      await FlutterDisplayMode.setHighRefreshRate();
    } catch (e) {
      _logger.warning('Setting high refresh rate failed', e);
    }

    if (networkBootstrap?.localNetworkGranted == false) {
      _logger.warning('Local network permission denied. Discovery and transfers may not work.');
      if (context.mounted) {
        await context.pushBottomSheet(() => const LocalNetworkDialog());
      }
    }
  }

  if (networkBootstrap?.serverError != null && context.mounted) {
    context.showSnackBar(networkBootstrap!.serverError.toString());
  }

  // ignore: dead_code
  if (webRTCEnabled) {
    ref.redux(signalingProvider).dispatch(SetupSignalingConnection());
  }

  if (appStart) {
    if (defaultTargetPlatform == TargetPlatform.macOS) {
      // handle dropped files
      pendingFilesStream.listen((files) async {
        await ref.global.dispatchAsync(
          _HandleAppStartArgumentsAction(
            args: files,
          ),
        );
      });

      // handle dropped strings
      pendingStringsStream.listen((pendingStrings) {
        for (final string in pendingStrings) {
          ref.redux(selectedSendingFilesProvider).dispatch(AddMessageAction(message: string));
        }
        ref.redux(homePageControllerProvider).dispatch(ChangeTabAction(HomeTab.send));
      });

      await setupMethodCallHandler();
    } else {
      final args = ref.read(appArgumentsProvider);
      await ref.global.dispatchAsync(
        _HandleAppStartArgumentsAction(
          args: args,
        ),
      );
    }
  }

  bool hasInitialShare = false;

  if (checkPlatformCanReceiveShareIntent()) {
    final shareHandler = ShareHandlerPlatform.instance;

    if (appStart) {
      final initialSharedPayload = await shareHandler.getInitialSharedMedia();
      if (initialSharedPayload != null) {
        hasInitialShare = true;
        // ignore: unawaited_futures
        ref.global.dispatchAsync(
          _HandleShareIntentAction(
            payload: initialSharedPayload,
          ),
        );
      }
    }

    _sharedMediaSubscription?.cancel(); // ignore: unawaited_futures
    _sharedMediaSubscription = shareHandler.sharedMediaStream.listen((SharedMedia payload) async {
      await ref.global.dispatchAsync(
        _HandleShareIntentAction(
          payload: payload,
        ),
      );
    });

    if (checkPlatform([TargetPlatform.android])) {
      // Both messages above travel through the same messenger in order, so the stream is
      // guaranteed to be attached natively before MainActivity replays held-back intents.
      await flushPendingShareIntentsAndroid();
    }
  }

  if (appStart && !hasInitialShare && (checkPlatformWithGallery() || checkPlatformCanReceiveShareIntent())) {
    // Clear cache on every app start.
    // If we received a share intent, then don't clear it, otherwise the shared file will be lost.
    ref.global.dispatchAsync(ClearCacheAction()); // ignore: unawaited_futures
  }

  if (!ref.read(persistenceProvider).isFirstAppStart) {
    WhatsNewPage? whatsNew = WhatsNewPage.fromLastVersion(lastVersion: ref.read(persistenceProvider).getWhatsNew());
    if (whatsNew != null) {
      // ignore: unawaited_futures
      ref.global.dispatchAsync(NavigateAction.push(whatsNew));
    }
  }

  await ref.future(versionProvider).then((version) async {
    await ref.read(persistenceProvider).setWhatsNew(version.version);
  });

  // Continuity reads its persisted consent and publishes what this device can
  // actually do. On a fresh install nothing is enabled, so this ends there: no
  // observation, no background service and no connection.
  unawaited(
    ref
        .redux(continuityProvider)
        .dispatchAsync(ContinuityInitAction(deviceLabel: ref.read(settingsProvider).alias)),
  );

  // [FOSS_REMOVE_START]
  if (checkPlatformSupportPayment()) {
    // ignore: unawaited_futures
    ref.redux(purchaseProvider).dispatchAsync(InitPurchaseStream());
  }
  // [FOSS_REMOVE_END]
}

class _HandleShareIntentAction extends AsyncGlobalAction {
  final SharedMedia payload;

  _HandleShareIntentAction({
    required this.payload,
  });

  @override
  Future<void> reduce() async {
    final message = payload.content;
    if (message != null && message.trim().isNotEmpty) {
      ref.redux(selectedSendingFilesProvider).dispatch(AddMessageAction(message: message));
    }
    await ref
        .redux(selectedSendingFilesProvider)
        .dispatchAsync(
          AddFilesAction(
            files: payload.attachments?.where((a) => a != null).cast<SharedAttachment>() ?? <SharedAttachment>[],
            converter: CrossFileConverters.convertSharedAttachment,
          ),
        );

    ref.redux(homePageControllerProvider).dispatch(ChangeTabAction(HomeTab.send));
  }
}

class _HandleAppStartArgumentsAction extends AsyncGlobalAction {
  final List<String> args;

  _HandleAppStartArgumentsAction({
    required this.args,
  });

  @override
  Future<void> reduce() async {
    final filesAdded = await ref.redux(selectedSendingFilesProvider).dispatchAsyncTakeResult(LoadSelectionFromArgsAction(args));
    if (filesAdded) {
      ref.redux(homePageControllerProvider).dispatch(ChangeTabAction(HomeTab.send));
    }
  }
}
