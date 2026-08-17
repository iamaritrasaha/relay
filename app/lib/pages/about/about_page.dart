import 'package:collection/collection.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:localsend_app/config/relay_brand.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/pages/debug/debug_page.dart';
import 'package:localsend_app/provider/version_provider.dart';
import 'package:localsend_app/util/i18n.dart';
import 'package:localsend_app/widget/relay_components.dart';
import 'package:localsend_app/widget/relay_logo.dart';
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
    final primaryColor = Theme.of(context).colorScheme.primary;
    return Scaffold(
      appBar: AppBar(title: const Text('About Relay')),
      body: ResponsiveListView(
        maxWidth: 840,
        padding: const EdgeInsets.fromLTRB(22, 26, 22, 56),
        children: [
          RelayGroupedSurface(
            padding: const EdgeInsets.fromLTRB(28, 38, 28, 30),
            child: Column(
              children: [
                const RelayLogo(withText: true, symbolSize: 100),
                const SizedBox(height: 20),
                Consumer(
                  builder: (context, ref) => ref
                      .watch(versionProvider)
                      .maybeWhen(
                        data: (version) => Text(
                          'Version ${version.combinedString}',
                          style: RelayTypography.value(Theme.of(context).relayPalette.textSecondary),
                        ),
                        orElse: () => const SizedBox(height: 17),
                      ),
                ),
                const SizedBox(height: 14),
                Text(RelayProduct.copyright, style: RelayTypography.legal(Theme.of(context).relayPalette.textSecondary)),
                const SizedBox(height: 20),
                Text(
                  RelayProduct.localSendAttribution,
                  style: RelayTypography.legal(Theme.of(context).relayPalette.textTertiary),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          const SizedBox(height: 26),
          RelaySectionHeading('Open source'),
          const SizedBox(height: 8),
          RelayGroupedSurface(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextButton.icon(
                  onPressed: () async => context.push(() => const LicensePage()),
                  icon: const Icon(Icons.article_outlined),
                  label: const Text('Open Source Licenses'),
                ),
                TextButton.icon(
                  onPressed: () async => launchUrl(Uri.parse('https://www.apache.org/licenses/LICENSE-2.0')),
                  icon: const Icon(Icons.open_in_new_rounded),
                  label: const Text('Apache License 2.0'),
                ),
                TextButton.icon(
                  onPressed: () async => launchUrl(
                    Uri.parse('https://github.com/localsend/localsend'),
                    mode: LaunchMode.externalApplication,
                  ),
                  icon: const Icon(Icons.code_rounded),
                  label: const Text('Upstream source'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          RelaySectionHeading('Acknowledgements'),
          const SizedBox(height: 8),
          Text(t.aboutPage.description.join('\n\n'), style: RelayTypography.value(Theme.of(context).relayPalette.textSecondary)),
          const SizedBox(height: 20),
          Text(t.aboutPage.author, style: const TextStyle(fontWeight: FontWeight.bold)),
          Text.rich(
            _buildContributor(
              label: 'Tien Do Nam (@Tienisto)',
              primaryColor: primaryColor,
            ),
          ),
          const SizedBox(height: 20),
          Text(t.aboutPage.contributors, style: const TextStyle(fontWeight: FontWeight.bold)),
          ..._contributors.map((contributor) {
            return Text.rich(
              _buildContributor(
                label: contributor,
                primaryColor: primaryColor,
              ),
            );
          }),
          const SizedBox(height: 20),
          Text(t.aboutPage.packagers, style: const TextStyle(fontWeight: FontWeight.bold)),
          Table(
            columnWidths: const {
              0: IntrinsicColumnWidth(),
              1: FlexColumnWidth(),
            },
            children: [
              ..._packagers.entries.map(
                (e) => TableRow(
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: Text(e.key),
                    ),
                    Text.rich(
                      TextSpan(
                        children: e.value.mapIndexed(
                          (index, translator) {
                            return _buildContributor(
                              label: translator,
                              primaryColor: primaryColor,
                              newLine: index != 0,
                            );
                          },
                        ).toList(),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(t.aboutPage.translators, style: const TextStyle(fontWeight: FontWeight.bold)),
          Table(
            columnWidths: const {
              0: IntrinsicColumnWidth(),
              1: FlexColumnWidth(),
            },
            children: [
              ..._translators.entries.map(
                (e) => TableRow(
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: Text(e.key.getLocaleName()),
                    ),
                    Text.rich(
                      TextSpan(
                        children: e.value.mapIndexed(
                          (index, translator) {
                            return _buildContributor(
                              label: translator,
                              primaryColor: primaryColor,
                              newLine: index != 0,
                            );
                          },
                        ).toList(),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          TextButton.icon(
            onPressed: () async => context.push(() => const DebugPage()),
            icon: const Icon(Icons.bug_report_outlined),
            label: const Text('Diagnostics'),
          ),
          const SizedBox(height: 50),
        ],
      ),
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
