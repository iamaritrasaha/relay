import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:relay_app/config/init.dart';
import 'package:relay_app/config/init_error.dart';
import 'package:relay_app/config/relay_brand.dart';
import 'package:relay_app/config/theme.dart';
import 'package:relay_app/gen/strings.g.dart';
import 'package:relay_app/model/persistence/color_mode.dart';
import 'package:relay_app/pages/home_page.dart';
import 'package:relay_app/provider/local_ip_provider.dart';
import 'package:relay_app/provider/settings_provider.dart';
import 'package:relay_app/util/ui/dynamic_colors.dart';
import 'package:relay_app/widget/watcher/life_cycle_watcher.dart';
import 'package:relay_app/widget/watcher/shortcut_watcher.dart';
import 'package:relay_app/widget/watcher/tray_watcher.dart';
import 'package:relay_app/widget/watcher/window_watcher.dart';
import 'package:relay_isolates/isolate.dart';
import 'package:refena_flutter/addons.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:routerino/routerino.dart';

Future<void> main(List<String> args) async {
  final RefenaContainer container;
  final NetworkBootstrapResult networkBootstrap;
  try {
    container = await preInit(args);
    networkBootstrap = await createNetworkBootstrap(container).start();
  } catch (e, stackTrace) {
    showInitErrorApp(
      error: e,
      stackTrace: stackTrace,
    );
    return;
  }

  runApp(
    RefenaScope.withContainer(
      container: container,
      child: TranslationProvider(
        child: RelayApp(networkBootstrap: networkBootstrap),
      ),
    ),
  );
}

class RelayApp extends StatelessWidget {
  final NetworkBootstrapResult networkBootstrap;

  const RelayApp({
    required this.networkBootstrap,
  });

  @override
  Widget build(BuildContext context) {
    final ref = context.ref;
    final (themeMode, colorMode, customColor) = ref.watch(
      settingsProvider.select((settings) => (settings.theme, settings.colorMode, settings.customColor)),
    );
    final dynamicColors = ref.watch(dynamicColorsProvider);
    return TrayWatcher(
      child: WindowWatcher(
        child: LifeCycleWatcher(
          onChangedState: (AppLifecycleState state) {
            switch (state) {
              case AppLifecycleState.resumed:
                ref.redux(localIpProvider).dispatch(InitLocalIpAction());
                break;
              case AppLifecycleState.detached:
                // The main isolate is only exited when all child isolates are exited.
                // https://github.com/relay/relay/issues/1568
                ref.redux(parentIsolateProvider).dispatch(IsolateDisposeAction());
                break;
              default:
                break;
            }
          },
          child: ShortcutWatcher(
            child: MaterialApp(
              title: RelayProduct.name,
              locale: TranslationProvider.of(context).flutterLocale,
              supportedLocales: AppLocaleUtils.supportedLocales,
              localizationsDelegates: GlobalMaterialLocalizations.delegates,
              debugShowCheckedModeBanner: false,
              theme: getTheme(colorMode, customColor, Brightness.light, dynamicColors),
              darkTheme: getTheme(colorMode, customColor, Brightness.dark, dynamicColors),
              themeMode: colorMode == ColorMode.oled ? ThemeMode.dark : themeMode,
              navigatorKey: context.read(navigationProvider).key,
              home: RouterinoHome(
                builder: () => HomePage(
                  initialTab: HomeTab.home,
                  appStart: true,
                  networkBootstrap: networkBootstrap,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
