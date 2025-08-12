import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';

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
  Widget build(BuildContext context) {
    return Column(
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
  Widget build(BuildContext context) {
    return GestureDetector(
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
        child: isSelected
            ? const Icon(Icons.check, color: Colors.white)
            : null,
      ),
    );
  }
}

void _showPlayerStyleDialog(BuildContext context, ThemeProvider themeProvider) {
  showDialog(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: const Text('Select Player Style'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: PlayerStyle.values.map((style) {
            return RadioListTile<PlayerStyle>(
              title: Text(themeProvider.getPlayerStyleName(style)),
              value: style,
              groupValue: themeProvider.playerStyle,
              onChanged: (PlayerStyle? value) {
                if (value != null) {
                  themeProvider.setPlayerStyle(value);
                  Navigator.of(context).pop();
                }
              },
            );
          }).toList(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('CANCEL'),
          ),
        ],
      );
    },
  );
}

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDarkMode = themeProvider.isDarkMode;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        centerTitle: true,
      ),
      body: ListView(
        children: [
          // Appearance Section
          SettingsSection(
            title: 'Appearance',
            icon: Icons.palette,
            children: [
              SwitchListTile(
                title: const Text('Dark Mode'),
                subtitle: Text(isDarkMode ? 'On' : 'Off'),
                secondary: Icon(
                  isDarkMode ? Icons.dark_mode : Icons.light_mode,
                  color: Theme.of(context).colorScheme.primary,
                ),
                value: isDarkMode,
                onChanged: (_) => themeProvider.toggleTheme(),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Theme Color', style: TextStyle(fontSize: 16)),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 50,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: themeProvider.availableColors.map((color) {
                          return ColorSelector(
                            color: color,
                            isSelected: themeProvider.primaryColor.value == color.value,
                            onTap: () => themeProvider.setPrimaryColor(color),
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              ListTile(
                title: const Text('Player Style'),
                subtitle: Text(themeProvider.getPlayerStyleName(themeProvider.playerStyle)),
                leading: const Icon(Icons.style),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _showPlayerStyleDialog(context, themeProvider),
              ),
            ],
          ),
          // Audio Section
          SettingsSection(
            title: 'Audio',
            icon: Icons.volume_up,
            children: [
              ListTile(
                title: const Text('Audio Quality'),
                subtitle: const Text('High (320 kbps)'),
                leading: const Icon(Icons.equalizer),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  // TODO: Show audio quality options
                },
              ),
            ],
          ),
          // Storage Section
          SettingsSection(
            title: 'Storage',
            icon: Icons.storage,
            children: [
              ListTile(
                title: const Text('Offline Storage'),
                subtitle: const Text('Manage downloaded content'),
                leading: const Icon(Icons.download_done),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  // TODO: Navigate to storage management
                },
              ),
              const Divider(height: 1),
              ListTile(
                title: const Text('Clear Cache'),
                subtitle: const Text('Free up storage space'),
                leading: const Icon(Icons.cleaning_services),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  // TODO: Clear cache
                },
              ),
            ],
          ),
          // About Section
          SettingsSection(
            title: 'About',
            icon: Icons.info_outline,
            children: [
              ListTile(
                title: const Text('Version'),
                subtitle: const Text('1.0.0'),
                leading: const Icon(Icons.info_outline),
                onTap: () {
                  showAboutDialog(
                    context: context,
                    applicationName: 'TS Music',
                    applicationVersion: '1.0.0',
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
                title: const Text('Help & Support'),
                leading: const Icon(Icons.help_outline),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  // TODO: Show help & support
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}
