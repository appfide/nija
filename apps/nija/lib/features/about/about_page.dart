import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:nija/core/build_info.dart';
import 'package:nija/ui/app_theme.dart';
import 'package:nija/ui/widgets/brand_mark.dart';
import 'package:nija/ui/widgets/section_card.dart';
import 'package:url_launcher/url_launcher.dart';

/// About Nija and Appfide, the studio behind it.
class AboutPage extends StatelessWidget {
  /// Creates the page.
  const AboutPage({super.key});

  static const _site = 'https://appfide.com';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final c = context.colors;
    return Scaffold(
      body: SafeArea(
        child: ContentColumn(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
            children: [
              Text('About', style: theme.textTheme.headlineSmall),
              const SizedBox(height: 16),
              // ---- Other devices ------------------------------------------
              Card(
                clipBehavior: Clip.antiAlias,
                child: SettingRow(
                  icon: Icons.devices_rounded,
                  title: 'Get it on your other devices',
                  subtitle: BuildInfo.storeBuild
                      ? 'Windows, Linux and Android installers on GitHub'
                      : 'Installers for macOS, Windows, Linux, Android and iOS',
                  onTap: () => context.push('/about/downloads'),
                ),
              ),
              const SizedBox(height: 16),
              // ---- App ----------------------------------------------------
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const BrandMark(size: 56),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Nija',
                                  style: theme.textTheme.titleLarge,
                                ),
                                Text(
                                  'Self-hosted clipboard',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: c.muted,
                                  ),
                                ),
                                Text(
                                  'Version ${BuildInfo.version} · build ${BuildInfo.gitSha}',
                                  style: theme.textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Your clipboard history, synced across devices through a database you own. '
                        'No accounts, no middleman: the app talks directly to your Supabase, PocketBase, '
                        'CouchDB, Firestore or MongoDB, with optional end-to-end encryption.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: c.muted,
                        ),
                      ),
                      const SizedBox(height: 20),
                      const _NameMeaning(),
                      const SizedBox(height: 16),
                      const Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _LinkChip(
                            Icons.code_rounded,
                            'Source on GitHub',
                            BuildInfo.repoUrl,
                          ),
                          _LinkChip(
                            Icons.new_releases_outlined,
                            'Releases',
                            '${BuildInfo.repoUrl}/releases',
                          ),
                          _LinkChip(
                            Icons.bug_report_outlined,
                            'Report an issue',
                            '${BuildInfo.repoUrl}/issues/new/choose',
                          ),
                          _LinkChip(
                            Icons.security_rounded,
                            'Security policy',
                            '${BuildInfo.repoUrl}/security/policy',
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'MIT License · Inter typeface © The Inter Project Authors and Noto Sans '
                        'Devanagari © The Noto Project Authors (both SIL OFL 1.1)',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              // ---- Appfide ------------------------------------------------
              Text('Made by Appfide', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              Card(
                clipBehavior: Clip.antiAlias,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            scheme.primary.withValues(alpha: 0.14),
                            scheme.primary.withValues(alpha: 0.02),
                          ],
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Building from Kerala,\nfor the World',
                            style: theme.textTheme.headlineSmall,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Appfide is an app studio that builds great products and ships them all over the world. '
                            'Our team brings 12+ years of combined experience in crafting high-quality iOS, Android, '
                            'and cross-platform applications using Swift, Kotlin, Flutter, and React Native.',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: c.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                      child: Text(
                        'What we do',
                        style: theme.textTheme.titleSmall,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: const [
                          'Mobile apps',
                          'Web applications',
                          'AI & ML solutions',
                          'UI/UX design',
                          'Backend & APIs',
                          'Cloud & DevOps',
                          'AR/VR experiences',
                          'App monetization & analytics',
                        ].map((s) => Chip(label: Text(s))).toList(),
                      ),
                    ),
                    const Divider(),
                    SettingRow(
                      icon: Icons.apps_rounded,
                      title: 'Our products',
                      subtitle:
                          'Catholic AI, Quran AI, Grandpa Stories, DND Reporter, ZenSphere, SoundScribe AI, Tap n Pop, FlyTicket',
                      onTap: () => _open(_site),
                    ),
                    const Divider(),
                    const SettingRow(
                      icon: Icons.place_outlined,
                      title: 'Kochi, Kerala, India',
                      subtitle:
                          'Kerala Startup Mission, Kerala Technology Innovation Zone, Kinfra Hi-Tech Park, Kalamassery 683503',
                      tint: AppTokens.green700,
                    ),
                    const Divider(),
                    const SettingRow(
                      icon: Icons.verified_outlined,
                      title:
                          'Recognised by Startup India and Kerala Startup Mission',
                      subtitle: 'Founded by Dhipin K Das',
                      tint: AppTokens.amber600,
                    ),
                    const Divider(),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          FilledButton.icon(
                            onPressed: () => _open(_site),
                            icon: const Icon(Icons.language_rounded, size: 18),
                            label: const Text('appfide.com'),
                          ),
                          const _LinkChip(
                            Icons.open_in_new_rounded,
                            'LinkedIn',
                            'https://linkedin.com/company/appfide',
                          ),
                          const _LinkChip(
                            Icons.open_in_new_rounded,
                            'X',
                            'https://x.com/appfide',
                          ),
                          const _LinkChip(
                            Icons.open_in_new_rounded,
                            'Instagram',
                            'https://instagram.com/appfide',
                          ),
                          const _LinkChip(
                            Icons.open_in_new_rounded,
                            'YouTube',
                            'https://youtube.com/appfide',
                          ),
                          const _LinkChip(
                            Icons.open_in_new_rounded,
                            'Discord',
                            'https://discord.gg/7qC7d696AP',
                          ),
                          const _LinkChip(
                            Icons.open_in_new_rounded,
                            'Reddit',
                            'https://www.reddit.com/r/appfide',
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: Wrap(
                  spacing: 16,
                  children: [
                    TextButton(
                      onPressed: () => _open('$_site/privacy-policy'),
                      child: const Text('Privacy Policy'),
                    ),
                    TextButton(
                      onPressed: () => _open('$_site/terms'),
                      child: const Text('Terms & Conditions'),
                    ),
                  ],
                ),
              ),
              Center(
                child: Text(
                  '© ${DateTime.now().year} Appfide',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Future<void> _open(String url) =>
      launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
}

/// Explains the app's name: निज (nija), Sanskrit for "one's own".
///
/// Inter ships no Devanagari, so the script is drawn through a fallback stack.
/// The sentence still reads if every fallback is missing.
class _NameMeaning extends StatelessWidget {
  const _NameMeaning();

  /// Devanagari faces that ship with macOS, iOS, Windows, Android and most
  /// desktop Linux distributions, in that order.
  static const _devanagari = <String>[
    'Noto Sans Devanagari',
    'Devanagari Sangam MN',
    'Nirmala UI',
    'Noto Sans',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                'निज',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontFamilyFallback: _devanagari,
                  color: scheme.primary,
                ),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  'nija · Sanskrit',
                  style: theme.textTheme.titleSmall?.copyWith(color: c.muted),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Sanskrit for "one\'s own": what is innate to you and belongs to '
            'nobody else. That is the whole idea of the app: your clipboard, '
            'on your database, under your keys. No Appfide server sits in the '
            'middle, and no account stands between you and your own history.',
            style: theme.textTheme.bodyMedium?.copyWith(color: c.muted),
          ),
        ],
      ),
    );
  }
}

class _LinkChip extends StatelessWidget {
  const _LinkChip(this.icon, this.label, this.url);
  final IconData icon;
  final String label;
  final String url;

  @override
  Widget build(BuildContext context) => ActionChip(
    avatar: Icon(icon, size: 16, color: context.colors.muted),
    label: Text(label),
    onPressed: () => AboutPage._open(url),
  );
}
