import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nija/core/build_info.dart';
import 'package:nija/core/platform_info.dart';
import 'package:nija/core/relative_time.dart';
import 'package:nija/features/downloads/release_info.dart';
import 'package:nija/features/downloads/release_service.dart';
import 'package:nija/ui/app_theme.dart';
import 'package:nija/ui/widgets/brand_mark.dart';
import 'package:nija/ui/widgets/empty_state.dart';
import 'package:nija/ui/widgets/section_card.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

/// Download links for every platform, so a user standing in front of one
/// device can get the app onto the next one without hunting for the repo.
class DownloadsPage extends ConsumerWidget {
  /// Creates the page.
  const DownloadsPage({super.key});

  /// Where the fallbacks point when GitHub cannot be reached.
  static const releasesUrl = '${BuildInfo.repoUrl}/releases';

  /// Systems the App Store build covers itself.
  static const Set<DownloadPlatform> appStorePlatforms = {
    DownloadPlatform.macos,
    DownloadPlatform.ios,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final release = ref.watch(latestReleaseProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Get Nija'),
        actions: [
          IconButton(
            tooltip: 'Check again',
            onPressed: () => ref.invalidate(latestReleaseProvider),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: ContentColumn(
          child: switch (release) {
            AsyncData(:final value) when value.assets.isEmpty => const _Failed(
              message:
                  'The latest release has no installers attached yet. The '
                  'releases page has every build.',
            ),
            AsyncData(:final value) => _Downloads(release: value),
            AsyncError(:final error) => _Failed(
              message: error is ReleaseLookupException
                  ? error.message
                  : 'Could not read the latest release. Open the releases '
                        'page instead.',
              onRetry: () => ref.invalidate(latestReleaseProvider),
            ),
            _ => const _Checking(),
          },
        ),
      ),
    );
  }

  static Future<void> open(String url) =>
      launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
}

class _Checking extends StatelessWidget {
  const _Checking();

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const CircularProgressIndicator(),
        const SizedBox(height: 16),
        Text(
          'Checking GitHub for the newest release…',
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: context.colors.muted),
        ),
      ],
    ),
  );
}

class _Failed extends StatelessWidget {
  const _Failed({required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => EmptyState(
    icon: Icons.cloud_off_rounded,
    title: 'No download list right now',
    message: message,
    action: Wrap(
      spacing: 8,
      children: [
        FilledButton.icon(
          onPressed: () => DownloadsPage.open(DownloadsPage.releasesUrl),
          icon: const Icon(Icons.open_in_new_rounded, size: 18),
          label: const Text('Open releases page'),
        ),
        if (onRetry != null)
          TextButton(onPressed: onRetry, child: const Text('Try again')),
      ],
    ),
  );
}

class _Downloads extends StatelessWidget {
  const _Downloads({required this.release});

  final ReleaseInfo release;

  /// The platform this app is running on, so its card can be labelled.
  DownloadPlatform? get _here =>
      DownloadPlatform.fromOperatingSystem(PlatformInfo.name);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = context.colors;
    // The App Store updates this build and already covers Apple devices:
    // list only the other systems, and never offer a newer copy of itself.
    const store = BuildInfo.storeBuild;
    final updatable = !store && release.isNewerThan(BuildInfo.version);
    final platforms = [
      for (final p in release.platforms)
        if (!store || !DownloadsPage.appStorePlatforms.contains(p)) p,
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                const BrandMark(size: 48),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Nija ${release.version}',
                        style: theme.textTheme.titleMedium,
                      ),
                      Text(
                        release.publishedAt == null
                            ? 'Latest release'
                            : 'Released ${RelativeTime.ago(release.publishedAt!)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: c.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () => DownloadsPage.open(
                    release.htmlUrl.isEmpty
                        ? DownloadsPage.releasesUrl
                        : release.htmlUrl,
                  ),
                  child: const Text('Notes'),
                ),
              ],
            ),
          ),
        ),
        if (updatable) ...[
          const SizedBox(height: 12),
          _UpdateBanner(version: release.version),
        ],
        const SizedBox(height: 20),
        Text(
          store
              ? 'Nija runs on Windows, Linux and Android too. Install it there '
                    'from GitHub: every device syncs through the same database, '
                    'so the history follows you.'
              : 'Install it on your other devices: every one of them syncs '
                    'through the same database, so the history follows you.',
          style: theme.textTheme.bodyMedium?.copyWith(color: c.muted),
        ),
        const SizedBox(height: 20),
        for (final platform in platforms)
          SectionCard(
            title: platform.label,
            trailing: platform == _here
                ? Chip(
                    label: const Text('This device'),
                    visualDensity: VisualDensity.compact,
                    side: BorderSide(color: c.border),
                  )
                : null,
            children: [
              for (final asset in release.forPlatform(platform))
                _AssetRow(asset: asset),
            ],
          ),
        Center(
          child: TextButton.icon(
            key: const ValueKey('downloads-releases'),
            onPressed: () => DownloadsPage.open(DownloadsPage.releasesUrl),
            icon: const Icon(Icons.open_in_new_rounded, size: 18),
            label: const Text('All releases on GitHub'),
          ),
        ),
        if (release.checksumsUrl != null)
          Center(
            child: TextButton.icon(
              onPressed: () => DownloadsPage.open(release.checksumsUrl!),
              icon: const Icon(Icons.verified_outlined, size: 18),
              label: const Text('SHA256SUMS.txt'),
            ),
          ),
        const SizedBox(height: 8),
        Text(
          'Opening this page asks github.com for the newest release. Nothing '
          'else leaves this device.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(color: c.muted),
        ),
      ],
    );
  }
}

class _UpdateBanner extends StatelessWidget {
  const _UpdateBanner({required this.version});

  final String version;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppTokens.radius),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(Icons.upgrade_rounded, color: scheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Version $version is out; this device runs '
              '${BuildInfo.version}.',
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

class _AssetRow extends StatelessWidget {
  const _AssetRow({required this.asset});

  final DownloadAsset asset;

  static const Map<DownloadPlatform, IconData> _icons = {
    DownloadPlatform.macos: Icons.laptop_mac_rounded,
    DownloadPlatform.windows: Icons.desktop_windows_rounded,
    DownloadPlatform.linux: Icons.terminal_rounded,
    DownloadPlatform.android: Icons.android_rounded,
    DownloadPlatform.ios: Icons.phone_iphone_rounded,
  };

  static const Map<DownloadPlatform, Color> _tints = {
    DownloadPlatform.macos: AppTokens.slate700,
    DownloadPlatform.windows: AppTokens.blue600,
    DownloadPlatform.linux: AppTokens.amber600,
    DownloadPlatform.android: AppTokens.green700,
    DownloadPlatform.ios: AppTokens.slate500,
  };

  @override
  Widget build(BuildContext context) {
    final subtitle = [
      if (asset.sizeLabel.isNotEmpty) asset.sizeLabel,
      ?asset.note,
    ].join(' · ');

    return SettingRow(
      icon: _icons[asset.platform]!,
      tint: _tints[asset.platform],
      title: asset.label,
      subtitle: subtitle.isEmpty ? null : subtitle,
      onTap: () => DownloadsPage.open(asset.url),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Show a QR code for this link',
            onPressed: () => _showQr(context, asset),
            icon: const Icon(Icons.qr_code_rounded),
          ),
          Icon(Icons.download_rounded, color: context.colors.muted),
        ],
      ),
    );
  }
}

Future<void> _showQr(BuildContext context, DownloadAsset asset) {
  final theme = Theme.of(context);
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      key: const ValueKey('download-qr-dialog'),
      title: Text('${asset.platform.label} · ${asset.label}'),
      // A fixed width keeps AlertDialog from measuring the intrinsic width of
      // the QR painter, which is a LayoutBuilder and cannot answer that.
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Scan this from the device you want to install on.',
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(AppTokens.radius),
              ),
              child: SizedBox(
                width: 200,
                height: 200,
                child: QrImageView(
                  key: const ValueKey('download-qr'),
                  data: asset.url,
                  size: 200,
                  errorCorrectionLevel: QrErrorCorrectLevel.M,
                ),
              ),
            ),
            const SizedBox(height: 16),
            SelectableText(
              asset.url,
              style: theme.textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: asset.url));
            if (ctx.mounted) Navigator.pop(ctx);
          },
          icon: const Icon(Icons.copy_rounded, size: 18),
          label: const Text('Copy link'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Done'),
        ),
      ],
    ),
  );
}
