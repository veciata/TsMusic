import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:tsmusic/providers/theme_provider.dart';
import 'package:tsmusic/providers/settings_provider.dart';
import 'package:tsmusic/models/audio_format.dart';
import 'package:tsmusic/models/player_styles.dart';
import 'package:tsmusic/utils/package_info_utils.dart';
import 'package:tsmusic/localization/app_localizations.dart';

class SettingsSection extends StatelessWidget {
  final String title;
  final List<Widget> children;
  final IconData? icon;

  const SettingsSection({
    super.key,
    required this.title,
    required this.children,
    this.icon,
  });

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 8),
                ],
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
          ),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
            child: Column(children: children),
          ),
          const SizedBox(height: 8),
        ],
      );
}

class ColorSelector extends StatelessWidget {
  final Color color;
  final bool isSelected;
  final VoidCallback onTap;

  const ColorSelector({
    super.key,
    required this.color,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          margin: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: isSelected ? Colors.white : Colors.transparent,
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: isSelected ? const Icon(Icons.check, color: Colors.white) : null,
        ),
      );
}

void _showPlayerStyleDialog(BuildContext context, ThemeProvider themeProvider) {
  final l10n = AppLocalizations.of(context);
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l10n.playerStyle),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView(
          shrinkWrap: true,
          children: PlayerStyle.values.map((style) {
            final isSelected = style == themeProvider.playerStyle;
            return ListTile(
              title: Text(
                themeProvider.getPlayerStyleName(style),
                style: TextStyle(
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  color: isSelected ? Theme.of(context).colorScheme.primary : null,
                ),
              ),
              leading: Radio<PlayerStyle>(
                value: style,
                groupValue: themeProvider.playerStyle,
                onChanged: (PlayerStyle? newStyle) {
                  if (newStyle != null) {
                    themeProvider.setPlayerStyle(newStyle);
                    Navigator.of(context).pop();
                  }
                },
              ),
              onTap: () {
                themeProvider.setPlayerStyle(style);
                Navigator.of(context).pop();
              },
            );
          }).toList(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
      ],
    ),
  );
}

void _showDownloadLocationDialog(BuildContext context, SettingsProvider settingsProvider) {
  final l10n = AppLocalizations.of(context);
  final locations = ['internal', 'downloads', 'music'];
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l10n.selectDownloadLocation),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView(
          shrinkWrap: true,
          children: locations.map((location) {
            final isSelected = location == settingsProvider.downloadLocation;
            return ListTile(
              title: Text(
                settingsProvider.getDownloadLocationName(location),
                style: TextStyle(
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  color: isSelected ? Theme.of(context).colorScheme.primary : null,
                ),
              ),
              leading: Radio<String>(
                value: location,
                groupValue: settingsProvider.downloadLocation,
                onChanged: (String? newLocation) {
                  if (newLocation != null) {
                    settingsProvider.setDownloadLocation(newLocation);
                    Navigator.of(context).pop();
                  }
                },
              ),
              onTap: () {
                settingsProvider.setDownloadLocation(location);
                Navigator.of(context).pop();
              },
            );
          }).toList(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
      ],
    ),
  );
}

void _showAudioFormatDialog(BuildContext context, SettingsProvider settingsProvider) {
  final l10n = AppLocalizations.of(context);
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l10n.selectAudioFormat),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView(
          shrinkWrap: true,
          children: AudioFormat.values.map((format) {
            final isSelected = format == settingsProvider.audioFormat;
            return ListTile(
              title: Text(
                settingsProvider.getAudioFormatName(format),
                style: TextStyle(
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  color: isSelected ? Theme.of(context).colorScheme.primary : null,
                ),
              ),
              leading: Radio<AudioFormat>(
                value: format,
                groupValue: settingsProvider.audioFormat,
                onChanged: (AudioFormat? newFormat) {
                  if (newFormat != null) {
                    settingsProvider.setAudioFormat(newFormat);
                    Navigator.of(context).pop();
                  }
                },
              ),
              onTap: () {
                settingsProvider.setAudioFormat(format);
                Navigator.of(context).pop();
              },
            );
          }).toList(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
      ],
    ),
  );
}

void _showLanguageDialog(BuildContext context, SettingsProvider settingsProvider) {
  final l10n = AppLocalizations.of(context);
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l10n.selectLanguage),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView(
          shrinkWrap: true,
          children: AppLocalizations.supportedLocales.map((locale) {
            final isSelected = locale == settingsProvider.locale;
            return ListTile(
              title: Text(
                settingsProvider.getLanguageName(locale),
                style: TextStyle(
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  color: isSelected ? Theme.of(context).colorScheme.primary : null,
                ),
              ),
              leading: Radio<Locale>(
                value: locale,
                groupValue: settingsProvider.locale,
                onChanged: (Locale? newLocale) {
                  if (newLocale != null) {
                    settingsProvider.setLanguage(newLocale);
                    Navigator.of(context).pop();
                  }
                },
              ),
              onTap: () {
                settingsProvider.setLanguage(locale);
                Navigator.of(context).pop();
              },
            );
          }).toList(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
      ],
    ),
  );
}

void _showChangelogDialog(BuildContext context, AppLocalizations l10n) {
  final entries = [
    _ChangelogEntry('1.1.12', '2026-05-18', [
      'Player widget: adaptive layout (horizontal for 4x1, vertical for 4x2+)',
      'Player widget: buttons use accent/theme color',
      'Player widget: larger 32dp buttons in vertical layout, right-aligned',
      'Search widget: fills available width, more height in 4x2 layout',
      'Player widget: wrap_content height for proper sizing',
    ]),
    _ChangelogEntry('1.1.11', '2026-05-18', [
      'Player widget: improved UI with accent color support',
      'Fixed sliding text animation',
    ]),
    _ChangelogEntry('1.1.10', '2026-05-15', [
      'Search widget: redesigned with transparent background',
    ]),
    _ChangelogEntry('1.1.9', '2026-05-15', [
      'Settings: version shows changelog modal, licenses moved to separate modal',
      'Settings: added changelog and licenses localization strings',
      'Search widget: fixed layout issues (TextView instead of EditText)',
      'Search widget: proper padding and resizing to 3x1 default',
      'Player widget: tapping thumbnail or song name opens the app',
    ]),
    _ChangelogEntry('1.1.8', '2026-05-15', [
      'Search widget: 4x1 layout with search bar + button',
      'Search widget: 2x1 compact icon-only layout',
      'Search widget: resizable (3x1 default, down to 1x1)',
      'Player widget: thumbnail and title now open the app on tap',
    ]),
    _ChangelogEntry('1.1.7', '2026-05-10', [
      'Added SQL Explorer debug screen',
      'Fixed path normalization for duplicate detection',
      'Improved database cleaning utilities',
    ]),
    _ChangelogEntry('1.1.6', '2026-05-05', [
      'Home screen: always show search bar at top',
      'Settings: added player style selection (Modern / Compact)',
      'Fixed brightness toggle in fullscreen player',
    ]),
    _ChangelogEntry('1.1.5', '2026-04-28', [
      'Player widget: play/pause, prev/next controls',
      'Flutter-rendered widget backgrounds (dark/light mode)',
      'Auto-update player widget on song change',
    ]),
  ];

  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.history, size: 24),
          const SizedBox(width: 8),
          Expanded(child: Text(l10n.changelog)),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(ctx),
          ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final entry in entries) ...[
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 4),
                child: Row(
                  children: [
                    Text(
                      entry.version,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      entry.date,
                      style: TextStyle(
                        color: Theme.of(context).textTheme.bodySmall?.color,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              for (final line in entry.lines)
                Padding(
                  padding: const EdgeInsets.only(left: 8, top: 2, bottom: 2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('• ', style: TextStyle(fontSize: 14)),
                      Expanded(
                        child: Text(line,
                            style: const TextStyle(fontSize: 14)),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(l10n.gotIt),
        ),
      ],
    ),
  );
}

class _ChangelogEntry {
  final String version;
  final String date;
  final List<String> lines;
  _ChangelogEntry(this.version, this.date, this.lines);
}

String _getThemeModeName(AppLocalizations l10n, ThemeMode mode) {
  switch (mode) {
    case ThemeMode.light:
      return l10n.lightMode;
    case ThemeMode.dark:
      return l10n.darkMode;
    case ThemeMode.system:
      return l10n.followSystem;
  }
}

void _showThemeModeDialog(BuildContext context, ThemeProvider themeProvider) {
  final l10n = AppLocalizations.of(context);
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l10n.themeMode),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: ThemeMode.values.map((mode) {
          final isSelected = mode == themeProvider.themeMode;
          return ListTile(
            leading: Icon(
              mode == ThemeMode.light
                  ? Icons.light_mode
                  : mode == ThemeMode.dark
                      ? Icons.dark_mode
                      : Icons.settings_brightness,
            ),
            title: Text(
              _getThemeModeName(l10n, mode),
              style: TextStyle(
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? Theme.of(context).colorScheme.primary : null,
              ),
            ),
            trailing: isSelected ? const Icon(Icons.check) : null,
            onTap: () {
              themeProvider.setThemeMode(mode);
              Navigator.of(context).pop();
            },
          );
        }).toList(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
      ],
    ),
  );
}

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final settingsProvider = Provider.of<SettingsProvider>(context);
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.settings),
      ),
      body: ListView(
        children: [
          // Appearance Section
          SettingsSection(
            title: l10n.appearance,
            icon: Icons.palette,
            children: [
              ListTile(
                title: Text(l10n.themeMode),
                leading: Icon(
                  themeProvider.themeMode == ThemeMode.light
                      ? Icons.light_mode
                      : themeProvider.themeMode == ThemeMode.dark
                          ? Icons.dark_mode
                          : Icons.settings_brightness,
                ),
                trailing: Text(
                  _getThemeModeName(l10n, themeProvider.themeMode),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                onTap: () => _showThemeModeDialog(context, themeProvider),
              ),
              const Divider(height: 1),
              ListTile(
                title: Text(l10n.language),
                leading: const Icon(Icons.language),
                trailing: Text(
                  settingsProvider.getLanguageName(settingsProvider.locale),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                onTap: () => _showLanguageDialog(context, settingsProvider),
              ),
              const Divider(height: 1),
              ListTile(
                title: Text(l10n.playerStyle),
                leading: const Icon(Icons.style),
                subtitle: Text(
                  themeProvider.getPlayerStyleDescription(themeProvider.playerStyle),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                trailing: Text(
                  themeProvider.getPlayerStyleName(themeProvider.playerStyle),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                onTap: () => _showPlayerStyleDialog(context, themeProvider),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
                child: Text(l10n.accentColor),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: themeProvider.availableColors
                      .map((color) => ColorSelector(
                            color: color,
                            isSelected:
                                themeProvider.primaryColor.value == color.value,
                            onTap: () => themeProvider.setPrimaryColor(color),
                          ))
                      .toList(),
                ),
              ),
            ],
          ),
          // Downloads Section
          SettingsSection(
            title: l10n.downloads,
            icon: Icons.download,
            children: [
              ListTile(
                title: Text(l10n.audioDownloadFormat),
                leading: const Icon(Icons.audiotrack),
                trailing: Text(
                  settingsProvider.getAudioFormatName(settingsProvider.audioFormat),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                onTap: () => _showAudioFormatDialog(context, settingsProvider),
              ),
              const Divider(height: 1),
              ListTile(
                title: Text(l10n.selectDownloadLocation),
                leading: const Icon(Icons.folder),
                trailing: Text(
                  settingsProvider.getDownloadLocationName(
                      settingsProvider.downloadLocation),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                onTap: () =>
                    _showDownloadLocationDialog(context, settingsProvider),
              ),
            ],
          ),
          // About Section
          SettingsSection(
            title: l10n.about,
            icon: Icons.info_outline,
            children: [
              ListTile(
                title: Text(l10n.version),
                subtitle: Text(PackageInfoUtils.version),
                leading: const Icon(Icons.info_outline),
                onTap: () {
                  _showChangelogDialog(context, l10n);
                },
              ),
              const Divider(height: 1),
              ListTile(
                title: Text(l10n.licenses),
                leading: const Icon(Icons.description),
                onTap: () => showLicensePage(context: context),
              ),
              const Divider(height: 1),
              ListTile(
                title: Text(l10n.helpSupport),
                leading: const Icon(Icons.help_outline),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  showDialog(
                    context: context,
                    builder: (dialogContext) => AlertDialog(
                      title: const Text('TsMusic'),
                      content: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(l10n.createdBy),
                          const SizedBox(height: 16),
                          Text(
                            l10n.supportFeedback,
                            style: const TextStyle(fontSize: 14),
                          ),
                        ],
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(dialogContext),
                          child: Text(l10n.cancel),
                        ),
                        TextButton(
                          onPressed: () async {
                            final uri = Uri.parse(
                                'https://github.com/veciata/TsMusic/issues');
                            if (await canLaunchUrl(uri)) {
                              await launchUrl(uri,
                                  mode: LaunchMode.externalApplication);
                            }
                            if (dialogContext.mounted) {
                              Navigator.pop(dialogContext);
                            }
                          },
                          child: Text(l10n.openGitHub),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}
