import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:localsend_app/config/relay_brand.dart';
import 'package:localsend_app/provider/version_provider.dart';
import 'package:localsend_app/util/ui/nav_bar_padding.dart';
import 'package:localsend_app/widget/relay/relay_top_bar.dart';
import 'package:localsend_app/widget/relay_components.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:routerino/routerino.dart';

const _relayReleaseNotesAsset = 'CHANGELOG_RELAY.md';
const _upstreamHistoryAsset = 'assets/CHANGELOG.md';

class ChangelogPage extends StatelessWidget {
  /// Test/review overrides. Production always resolves both values from the
  /// package metadata and bundled Relay release-notes asset.
  final VersionData? version;
  final String? releaseNotes;

  const ChangelogPage({super.key, this.version, this.releaseNotes});

  @override
  Widget build(BuildContext context) {
    if (version != null) {
      return _RelayReleaseNotesPage(version: version!, releaseNotes: releaseNotes);
    }
    return Consumer(
      builder: (context, ref) => ref
          .watch(versionProvider)
          .maybeWhen(
            data: (resolved) => _RelayReleaseNotesPage(version: resolved),
            orElse: () => const _ReleaseNotesScaffold(child: Center(child: CircularProgressIndicator())),
          ),
    );
  }
}

class _RelayReleaseNotesPage extends StatelessWidget {
  final VersionData version;
  final String? releaseNotes;

  const _RelayReleaseNotesPage({required this.version, this.releaseNotes});

  @override
  Widget build(BuildContext context) {
    final notes = releaseNotes != null ? Future.value(releaseNotes!) : rootBundle.loadString(_relayReleaseNotesAsset);
    return _ReleaseNotesScaffold(
      child: FutureBuilder<String>(
        future: notes,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final palette = Theme.of(context).relayPalette;
          final body = snapshot.data!.replaceFirst(RegExp(r'^# Relay [^\n]+\n+'), '');
          return SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(20, 30, 20, 42 + getNavBarPadding(context)),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('CURRENT RELEASE', style: RelayTypography.section(palette.textTertiary)),
                    const SizedBox(height: 10),
                    Text(version.version, style: RelayTypography.pageTitle(palette.textPrimary)),
                    const SizedBox(height: 28),
                    RelayGroupedSurface(
                      padding: const EdgeInsets.fromLTRB(22, 18, 22, 20),
                      child: MarkdownBody(
                        data: body,
                        styleSheet: MarkdownStyleSheet(
                          p: TextStyle(fontSize: 14, height: 1.55, color: palette.textSecondary),
                          listBullet: TextStyle(fontSize: 14, height: 1.55, color: palette.accentSoft),
                          h2: TextStyle(fontSize: 17, height: 1.35, fontWeight: FontWeight.w600, color: palette.textPrimary),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () async => context.push(() => const UpstreamProjectHistoryPage()),
                        icon: const Icon(Icons.history_rounded, size: 18),
                        label: const Text('Upstream project history'),
                        style: TextButton.styleFrom(foregroundColor: palette.textSecondary),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ReleaseNotesScaffold extends StatelessWidget {
  final Widget child;

  const _ReleaseNotesScaffold({required this.child});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          RelayTopBar.titled(title: 'Relay release notes', onBack: () => context.pop()),
          Expanded(child: child),
        ],
      ),
    );
  }
}

/// The preserved LocalSend history remains available only as explicitly
/// upstream material; it is never presented as Relay's release history.
class UpstreamProjectHistoryPage extends StatelessWidget {
  const UpstreamProjectHistoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          RelayTopBar.titled(title: 'Upstream project history', onBack: () => context.pop()),
          Expanded(
            child: FutureBuilder<String>(
              future: rootBundle.loadString(_upstreamHistoryAsset),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                return Markdown(
                  padding: EdgeInsets.fromLTRB(20, 24, 20, 36 + getNavBarPadding(context)),
                  data: snapshot.data!,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
