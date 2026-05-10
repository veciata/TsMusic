import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:tsmusic/localization/app_localizations.dart';
import 'package:tsmusic/models/github_release.dart';
import 'package:tsmusic/providers/update_notification_provider.dart';
import 'package:tsmusic/utils/package_info_utils.dart';

/// Shows the "What's New" update notification modal as a full-screen dialog.
///
/// Call after [UpdateNotificationProvider.checkForUpdates] returns `true`.
Future<void> showUpdateNotificationModal(BuildContext context) {
  final provider = Provider.of<UpdateNotificationProvider>(
    context,
    listen: false,
  );
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _UpdateNotificationModal(provider: provider),
  );
}

class _UpdateNotificationModal extends StatefulWidget {
  final UpdateNotificationProvider provider;

  const _UpdateNotificationModal({required this.provider});

  @override
  State<_UpdateNotificationModal> createState() =>
      _UpdateNotificationModalState();
}

class _UpdateNotificationModalState extends State<_UpdateNotificationModal> {
  @override
  void initState() {
    super.initState();
    // Subscribe to provider changes so loading/loaded/error states re-render.
    widget.provider.addListener(_onProviderChange);
  }

  @override
  void dispose() {
    widget.provider.removeListener(_onProviderChange);
    super.dispose();
  }

  void _onProviderChange() {
    if (mounted) setState(() {});
  }

  Future<void> _openRelease(GitHubRelease release) async {
    final uri = Uri.tryParse(release.htmlUrl);
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final state = widget.provider.state;
    final releases = widget.provider.newReleases;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // -- Header --
          _buildHeader(theme, l10n),
          // -- Body --
          Flexible(child: _buildBody(state, releases, theme, l10n)),
          // -- Footer actions --
          _buildActions(theme, l10n),
        ],
      ),
    );
  }

  Widget _buildHeader(ThemeData theme, AppLocalizations l10n) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
      ),
      child: Column(
        children: [
          Icon(
            Icons.new_releases_rounded,
            size: 40,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: 8),
          Text(
            '${l10n.whatsNew} ✨',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${PackageInfoUtils.appName} v${PackageInfoUtils.version}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(
    UpdateCheckState state,
    List<GitHubRelease> releases,
    ThemeData theme,
    AppLocalizations l10n,
  ) {
    switch (state) {
      case UpdateCheckState.loading:
        return const Padding(
          padding: EdgeInsets.all(48),
          child: Center(child: CircularProgressIndicator()),
        );

      case UpdateCheckState.error:
        return Padding(
          padding: const EdgeInsets.all(48),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off, size: 48, color: theme.colorScheme.error),
              const SizedBox(height: 12),
              Text(
                l10n.updateCheckFailed,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
            ],
          ),
        );

      case UpdateCheckState.loaded:
      case UpdateCheckState.idle:
        if (releases.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(48),
            child: Center(child: Text('No updates available.')),
          );
        }
        return _buildReleaseList(releases, theme, l10n);
    }
  }

  Widget _buildReleaseList(
    List<GitHubRelease> releases,
    ThemeData theme,
    AppLocalizations l10n,
  ) {
    // Show releases in reverse chronological order (newest first).
    final sorted = List<GitHubRelease>.from(releases)
      ..sort((a, b) => b.publishedAt.compareTo(a.publishedAt));

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      shrinkWrap: true,
      children: [
        Text(
          '${releases.length} ${l10n.newUpdates}',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.primary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        ...sorted.map((release) => _buildReleaseCard(release, theme)),
      ],
    );
  }

  Widget _buildReleaseCard(GitHubRelease release, ThemeData theme) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Version tag + date row
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    release.tagName,
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  _formatDate(release.publishedAt),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
            if (release.name.isNotEmpty && release.name != release.tagName) ...[
              const SizedBox(height: 4),
              Text(
                release.name,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            // Release body
            if (release.body.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withValues(
                    alpha: 0.3,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SelectableText(
                  release.body,
                  style: theme.textTheme.bodySmall?.copyWith(height: 1.5),
                ),
              ),
            ],
            // View on GitHub
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => _openRelease(release),
                icon: const Icon(Icons.open_in_new, size: 16),
                label: const Text('GitHub'),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActions(ThemeData theme, AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: () {
              widget.provider.acknowledgeUpdates();
              Navigator.of(context).pop();
            },
            child: Text(l10n.gotIt),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }
}
