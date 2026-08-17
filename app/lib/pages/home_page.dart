import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:localsend_app/config/init.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/pages/home_page_controller.dart';
import 'package:localsend_app/pages/receive_history_page.dart';
import 'package:localsend_app/pages/relay_home_page.dart';
import 'package:localsend_app/pages/tabs/receive_tab.dart';
import 'package:localsend_app/pages/tabs/send_tab.dart';
import 'package:localsend_app/pages/tabs/settings_tab.dart';
import 'package:localsend_app/provider/selection/selected_sending_files_provider.dart';
import 'package:localsend_app/util/native/cross_file_converters.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:routerino/routerino.dart';

enum HomeTab {
  home(Icons.near_me_outlined),

  /// Preserved as the incoming-transfer fallback surface.
  receive(Icons.file_download_outlined),

  /// Preserved for legacy call sites; [ChangeTabAction] normalizes it to home.
  send(Icons.send),
  settings(Icons.settings)
  ;

  const HomeTab(this.icon);

  final IconData icon;

  String get label {
    switch (this) {
      case HomeTab.home:
        return 'Relay';
      case HomeTab.receive:
        return 'Receive';
      case HomeTab.send:
        return 'Share';
      case HomeTab.settings:
        return 'Settings';
    }
  }
}

class HomePage extends StatefulWidget {
  final HomeTab initialTab;
  final NetworkBootstrapResult? networkBootstrap;

  /// It is important for the initializing step
  /// because the first init clears the cache
  final bool appStart;

  const HomePage({
    required this.initialTab,
    required this.appStart,
    this.networkBootstrap,
    super.key,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with Refena {
  bool _dragAndDropIndicator = false;

  @override
  void initState() {
    super.initState();

    ensureRef((ref) async {
      ref.redux(homePageControllerProvider).dispatch(ChangeTabAction(widget.initialTab));
      await postInit(context, ref, widget.appStart, widget.networkBootstrap);
    });
  }

  @override
  Widget build(BuildContext context) {
    Translations.of(context); // rebuild on locale change
    final vm = context.watch(homePageControllerProvider);

    return DropTarget(
      onDragEntered: (_) {
        setState(() {
          _dragAndDropIndicator = true;
        });
      },
      onDragExited: (_) {
        setState(() {
          _dragAndDropIndicator = false;
        });
      },
      onDragDone: (event) async {
        if (event.files.length == 1 && Directory(event.files.first.path).existsSync()) {
          // user dropped a directory
          await ref.redux(selectedSendingFilesProvider).dispatchAsync(AddDirectoryAction(event.files.first.path));
        } else {
          // user dropped one or more files
          await ref
              .redux(selectedSendingFilesProvider)
              .dispatchAsync(
                AddFilesAction(
                  files: event.files,
                  converter: CrossFileConverters.convertXFile,
                ),
              );
        }
        vm.changeTab(HomeTab.home);
      },
      child: Scaffold(
        body: SafeArea(
          child: Stack(
            children: [
              PageView(
                controller: vm.controller,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  RelayHomePage(
                    onOpenHistory: () => context.push(() => const ReceiveHistoryPage()),
                    onOpenSettings: () => vm.changeTab(HomeTab.settings),
                  ),
                  const ReceiveTab(),
                  const SendTab(),
                  SettingsTab(onClose: () => vm.changeTab(HomeTab.home)),
                ],
              ),
              if (_dragAndDropIndicator)
                ColoredBox(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  child: const Center(child: Icon(Icons.add_to_drive_outlined, size: 68)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
