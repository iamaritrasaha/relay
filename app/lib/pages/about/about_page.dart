import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:localsend_app/config/relay_brand.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/pages/debug/debug_page.dart';
import 'package:localsend_app/provider/version_provider.dart';
import 'package:localsend_app/util/i18n.dart';
import 'package:localsend_app/widget/relay/relay_desktop_metrics.dart';
import 'package:localsend_app/widget/relay/relay_top_bar.dart';
import 'package:localsend_app/widget/relay_symbol.dart';
import 'package:localsend_app/widget/responsive_list_view.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:routerino/routerino.dart';
import 'package:url_launcher/url_launcher.dart';

part 'contributors.dart';

part 'packagers.dart';

part 'translators.dart';

final _translatorWithGithubRegex = RegExp(r'(.+) \(@([\w\-_]+)\)');

class AboutPage extends StatelessWidget {
  const AboutPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          RelayTopBar.titled(title: 'About', onBack: () => context.pop()),
          Expanded(
            child: ResponsiveListView(
              maxWidth: RelayDesktopMetrics.settingsWideFrameWidth,
              padding: const EdgeInsets.fromLTRB(22, 26, 22, 56),
              tabletPadding: const EdgeInsets.fromLTRB(
                RelayDesktopMetrics.settingsDesktopGutter,
                44,
                RelayDesktopMetrics.settingsDesktopGutter,
                64,
              ),
              children: const [RelayAboutIdentity()],
            ),
          ),
        ],
      ),
    );
  }
}

/// Relay's identity block: the mark and version on one side, the ownership,
/// upstream attribution and legal actions on the other, separated by a rule.
///
/// Relay is not co-branded with LocalSend here — the attribution is deliberately
/// tertiary and sits with the licence actions it belongs to.
class RelayAboutIdentity extends StatelessWidget {
  /// Overrides the resolved package version. Only supplied by review renders;
  /// the app always reads [versionProvider].
  final String? version;
  final String? buildNumber;

  const RelayAboutIdentity({super.key, this.version, this.buildNumber});

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).relayPalette;
    final mobile = !RelayDesktopMetrics.isDesktopWidth(MediaQuery.sizeOf(context).width);

    final identity = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        RelaySymbol(size: mobile ? 72 : 88, semanticLabel: 'Relay'),
        SizedBox(height: mobile ? 18 : 22),
        Text(
          RelayProduct.name,
          style: TextStyle(fontSize: mobile ? 31 : 38, height: 1.1, fontWeight: FontWeight.w600, letterSpacing: -0.8, color: palette.textPrimary),
        ),
        const SizedBox(height: 10),
        if (version != null && buildNumber != null)
          _AboutVersion(version: version!, buildNumber: buildNumber!)
        else
          Consumer(
            builder: (context, ref) => ref
                .watch(versionProvider)
                .maybeWhen(
                  data: (resolved) => _AboutVersion(version: resolved.version, buildNumber: resolved.buildNumber),
                  orElse: () => const SizedBox(height: 38),
                ),
          ),
      ],
    );

    final information = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Send files between your own devices over the local network.',
          style: TextStyle(fontSize: 15, height: 1.6, color: palette.textPrimary),
        ),
        const SizedBox(height: 26),
        Text(RelayProduct.copyright, style: TextStyle(fontSize: 13, height: 1.5, color: palette.textSecondary)),
        const SizedBox(height: 14),
        Text(RelayProduct.localSendAttribution, style: RelayTypography.legal(palette.textTertiary)),
        const SizedBox(height: 22),
        _AboutActions(mobile: mobile),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (!RelayDesktopMetrics.useTwoColumnAbout(constraints.maxWidth)) {
          return Column(
            key: const ValueKey('relay-about-one-column'),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [identity, const SizedBox(height: 32), information],
          );
        }
        return IntrinsicHeight(
          child: Row(
            key: const ValueKey('relay-about-two-columns'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: RelayDesktopMetrics.aboutIdentityColumnWidth,
                child: Align(alignment: Alignment.topLeft, child: identity),
              ),
              Container(width: 1, color: palette.hairline),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(left: RelayDesktopMetrics.settingsColumnGap),
                  child: Align(alignment: Alignment.topLeft, child: information),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _AboutVersion extends StatelessWidget {
  final String version;
  final String buildNumber;

  const _AboutVersion({required this.version, required this.buildNumber});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).relayPalette.textSecondary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Version $version', style: RelayTypography.value(color)),
        const SizedBox(height: 3),
        Text('Build $buildNumber', style: RelayTypography.legal(color)),
      ],
    );
  }
}

class _AboutActions extends StatelessWidget {
  final bool mobile;

  const _AboutActions({required this.mobile});

  @override
  Widget build(BuildContext context) {
    final actions = [
      _AboutAction(label: 'Open Source Licenses', icon: Icons.article_outlined, onPressed: () async => context.push(() => const LicensePage())),
      _AboutAction(
        label: 'Upstream acknowledgements',
        icon: Icons.people_outline_rounded,
        onPressed: () async => context.push(() => const UpstreamAcknowledgementsPage()),
      ),
      _AboutAction(
        label: 'Upstream source',
        icon: Icons.code_rounded,
        onPressed: () async => launchUrl(Uri.parse('https://github.com/localsend/localsend'), mode: LaunchMode.externalApplication),
      ),
      _AboutAction(
        label: 'Apache License 2.0',
        icon: Icons.open_in_new_rounded,
        onPressed: () async => launchUrl(Uri.parse('https://www.apache.org/licenses/LICENSE-2.0')),
      ),
      _AboutAction(label: 'Diagnostics', icon: Icons.bug_report_outlined, onPressed: () async => context.push(() => const DebugPage())),
    ];
    if (mobile) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [for (final action in actions) Padding(padding: const EdgeInsets.only(bottom: 8), child: action)],
      );
    }
    return Wrap(spacing: 10, runSpacing: 10, children: actions);
  }
}

class _AboutAction extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  const _AboutAction({required this.label, required this.icon, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).relayPalette;
    return OutlinedButton.icon(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 44),
        foregroundColor: palette.textPrimary,
        side: BorderSide(color: palette.textTertiary.withValues(alpha: 0.32)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
        padding: const EdgeInsets.symmetric(horizontal: 15),
      ),
      icon: Icon(icon, size: 17),
      label: Text(label, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500)),
    );
  }
}

/// Detailed upstream credits remain available without turning Relay's primary
/// About page into an upstream product page.
class UpstreamAcknowledgementsPage extends StatelessWidget {
  const UpstreamAcknowledgementsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).relayPalette.accentSoft;
    return Scaffold(
      body: Column(
        children: [
          RelayTopBar.titled(title: 'Upstream acknowledgements', onBack: () => context.pop()),
          Expanded(
            child: ResponsiveListView(
              maxWidth: 760,
              padding: const EdgeInsets.fromLTRB(20, 28, 20, 52),
              tabletPadding: const EdgeInsets.fromLTRB(0, 40, 0, 60),
              children: [
                Text(RelayProduct.localSendAttribution, style: RelayTypography.value(Theme.of(context).relayPalette.textSecondary)),
                const SizedBox(height: 24),
                Text(t.aboutPage.description.join('\n\n')),
                const SizedBox(height: 20),
                Text(t.aboutPage.author, style: const TextStyle(fontWeight: FontWeight.bold)),
                Text.rich(_buildContributor(label: 'Tien Do Nam (@Tienisto)', primaryColor: primaryColor)),
                const SizedBox(height: 20),
                Text(t.aboutPage.contributors, style: const TextStyle(fontWeight: FontWeight.bold)),
                ..._contributors.map((contributor) => Text.rich(_buildContributor(label: contributor, primaryColor: primaryColor))),
                const SizedBox(height: 20),
                Text(t.aboutPage.packagers, style: const TextStyle(fontWeight: FontWeight.bold)),
                _CreditsTable(entries: _packagers, primaryColor: primaryColor),
                const SizedBox(height: 20),
                Text(t.aboutPage.translators, style: const TextStyle(fontWeight: FontWeight.bold)),
                _CreditsTable(entries: _translators.map((key, value) => MapEntry(key.getLocaleName(), value)), primaryColor: primaryColor),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CreditsTable extends StatelessWidget {
  final Map<String, List<String>> entries;
  final Color primaryColor;

  const _CreditsTable({required this.entries, required this.primaryColor});

  @override
  Widget build(BuildContext context) {
    return Table(
      columnWidths: const {0: IntrinsicColumnWidth(), 1: FlexColumnWidth()},
      children: [
        for (final entry in entries.entries)
          TableRow(
            children: [
              Padding(padding: const EdgeInsets.only(right: 14), child: Text(entry.key)),
              Text.rich(
                TextSpan(
                  children: [
                    for (final (index, contributor) in entry.value.indexed)
                      _buildContributor(label: contributor, primaryColor: primaryColor, newLine: index != 0),
                  ],
                ),
              ),
            ],
          ),
      ],
    );
  }
}

/// Displays the contributor name and links to their github profile.
InlineSpan _buildContributor({required String label, required Color primaryColor, bool newLine = false}) {
  final newLineStr = newLine ? '\n' : '';

  if (label.startsWith('@')) {
    // Only github name
    return TextSpan(
      text: '$newLineStr$label',
      style: TextStyle(color: primaryColor),
      recognizer: TapGestureRecognizer()
        ..onTap = () async {
          await launchUrl(Uri.parse('https://github.com/${label.substring(1)}'), mode: LaunchMode.externalApplication);
        },
    );
  }

  final match = _translatorWithGithubRegex.firstMatch(label);
  if (match != null) {
    // Full name and github name
    final fullName = match.group(1)!;
    final githubName = match.group(2)!;
    return TextSpan(
      children: [
        TextSpan(text: '$newLineStr$fullName'),
        const TextSpan(text: ' '),
        TextSpan(
          text: '@$githubName',
          style: TextStyle(color: primaryColor),
          recognizer: TapGestureRecognizer()
            ..onTap = () async {
              await launchUrl(Uri.parse('https://github.com/$githubName'), mode: LaunchMode.externalApplication);
            },
        ),
      ],
    );
  }

  // Only full name
  return TextSpan(text: '$newLineStr$label');
}
