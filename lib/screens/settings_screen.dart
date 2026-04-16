import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/theme_provider.dart';
import '../providers/settings_provider.dart';
import '../models/audio_format.dart';
import '../models/player_styles.dart';
import '../utils/package_info_utils.dart';
import '../localization/app_localizations.dart';

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
            padding:
                const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Row(
              children: [
                if (icon != null) ...[
                  Icon(icon,
                      size: 20, color: Theme.of(context).colorScheme.primary),
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
          child:
              isSelected ? const Icon(Icons.check, color: Colors.white) : null,
        ),
      );
}

void _showPlayerStyleDialog(BuildContext context, ThemeProvider themeProvider) {
  final l10n = AppLocalizations.of(context);
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l10n.selectPlayerStyle),
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
                  color:
                      isSelected ? Theme.of(context).colorScheme.primary : null,
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

void _showDownloadLocationDialog(
    BuildContext context, SettingsProvider settingsProvider) {
  final l10n = AppLocalizations.of(context);
  final locations = ['internal', 'downloads', 'music'];

  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Select Download Location'),
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
                  color:
                      isSelected ? Theme.of(context).colorScheme.primary : null,
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

void _showAudioFormatDialog(
    BuildContext context, SettingsProvider settingsProvider) {
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
                  color:
                      isSelected ? Theme.of(context).colorScheme.primary : null,
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

void _showLanguageDialog(
    BuildContext context, SettingsProvider settingsProvider) {
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
                  color:
                      isSelected ? Theme.of(context).colorScheme.primary : null,
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

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final settingsProvider = Provider.of<SettingsProvider>(context);
    final isDarkMode = themeProvider.themeMode == ThemeMode.dark;
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
              SwitchListTile(
                title: Text(l10n.darkMode),
                value: isDarkMode,
                onChanged: (value) {
                  themeProvider.setThemeMode(
                    value ? ThemeMode.dark : ThemeMode.light,
                  );
                },
                secondary: const Icon(Icons.dark_mode),
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
                onTap: () {
                  _showLanguageDialog(context, settingsProvider);
                },
              ),
              const Divider(height: 1),
              Padding(
                padding:
                    const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
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
                  settingsProvider
                      .getAudioFormatName(settingsProvider.audioFormat),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                onTap: () {
                  _showAudioFormatDialog(context, settingsProvider);
                },
              ),
              const Divider(height: 1),
              ListTile(
                title: const Text('Download Location'),
                leading: const Icon(Icons.folder),
                trailing: Text(
                  settingsProvider.getDownloadLocationName(
                      settingsProvider.downloadLocation),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                onTap: () {
                  _showDownloadLocationDialog(context, settingsProvider);
                },
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
                  showAboutDialog(
                    context: context,
                    applicationName: 'TS Music',
                    applicationVersion: PackageInfoUtils.version,
                    applicationIcon: const Icon(Icons.music_note, size: 50),
                    children: const [
                      Text('A beautiful music player app'),
                      SizedBox(height: 8),
                      Text('© 2025 TS Music. All rights reserved.'),
                    ],
                  );
                },
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
          if (kDebugMode) ...[
            const Divider(height: 1),
            SettingsSection(
              title: l10n.debug,
              icon: Icons.bug_report,
              children: [
                ListTile(
                  title: Text(l10n.playerStyle),
                  leading: const Icon(Icons.style),
                  trailing: Text(
                    themeProvider.getPlayerStyleName(themeProvider.playerStyle),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  onTap: () {
                    _showPlayerStyleDialog(context, themeProvider);
                  },
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
