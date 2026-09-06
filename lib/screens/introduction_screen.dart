import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsmusic/core/theme/app_theme.dart' as app_theme;
import 'package:tsmusic/localization/app_localizations.dart';
import 'package:tsmusic/providers/settings_provider.dart';
import 'package:tsmusic/providers/theme_provider.dart';
import 'package:tsmusic/services/permission_service.dart';

class IntroductionScreen extends StatefulWidget {
  final VoidCallback onComplete;

  const IntroductionScreen({super.key, required this.onComplete});

  @override
  State<IntroductionScreen> createState() => _IntroductionScreenState();
}

class _IntroductionScreenState extends State<IntroductionScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  List<_IntroPage> _pages = [];
  bool _storageGranted = false;
  bool _notificationGranted = false;
  bool _locationInitialized = false;
  String _downloadLocation = 'internal';
  bool _themeInitialized = false;
  Color _selectedColor = const Color(0xFF1DB954);
  ThemeMode _selectedThemeMode = ThemeMode.system;
  bool get _permissionsGranted => _storageGranted && _notificationGranted;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _initPages();
    _checkPermissions();
    if (!_locationInitialized) {
      _locationInitialized = true;
      try {
        _downloadLocation = context.read<SettingsProvider>().downloadLocation;
      } catch (_) {
        _downloadLocation = 'internal';
      }
    }
    if (!_themeInitialized) {
      _themeInitialized = true;
      try {
        final theme = context.read<ThemeProvider>();
        _selectedColor = theme.primaryColor;
        _selectedThemeMode = theme.themeMode;
      } catch (_) {}
    }
  }

  void _initPages() {
    final l10n = AppLocalizations.of(context);
    _pages = [
      _IntroPage(
        icon: Icons.music_note_rounded,
        title: l10n.introWelcomeTitle,
        description: l10n.introWelcomeDesc,
        color: Colors.blue,
      ),
      _IntroPage(
        icon: Icons.folder_rounded,
        title: l10n.introStorageTitle,
        description: l10n.introStorageDesc,
        color: Colors.orange,
        isPermissionPage: true,
        permissionType: _PermissionType.storage,
      ),
      _IntroPage(
        icon: Icons.notifications_rounded,
        title: l10n.introNotificationTitle,
        description: l10n.introNotificationDesc,
        color: Colors.red,
        isPermissionPage: true,
        permissionType: _PermissionType.notification,
      ),
      _IntroPage(
        icon: Icons.drive_folder_upload_rounded,
        title: l10n.introStorageLocationTitle,
        description: l10n.introStorageLocationDesc,
        color: Colors.indigo,
        isDownloadLocationPage: true,
      ),
      _IntroPage(
        icon: Icons.palette_outlined,
        title: l10n.introThemeTitle,
        description: l10n.introThemeDesc,
        color: Colors.pinkAccent,
        isThemePage: true,
      ),
      _IntroPage(
        icon: Icons.search_rounded,
        title: l10n.introSearchTitle,
        description: l10n.introSearchDesc,
        color: Colors.green,
      ),
      _IntroPage(
        icon: Icons.download_rounded,
        title: l10n.introDownloadTitle,
        description: l10n.introDownloadDesc,
        color: Colors.purple,
      ),
      _IntroPage(
        icon: Icons.queue_music_rounded,
        title: l10n.introQueueTitle,
        description: l10n.introQueueDesc,
        color: Colors.teal,
      ),
    ];
  }

  Future<void> _checkPermissions() async {
    final permissionService = PermissionService();
    final hasStorage = await permissionService.hasStoragePermission();
    final hasNotification = await permissionService.hasNotificationPermission();
    if (mounted) {
      setState(() {
        _storageGranted = hasStorage;
        _notificationGranted = hasNotification;
      });
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _nextPage() async {
    final currentPageData = _pages[_currentPage];

    if (currentPageData.isPermissionPage) {
      final permissionService = PermissionService();
      final granted = currentPageData.permissionType == _PermissionType.storage
          ? await permissionService.requestStoragePermission()
          : await permissionService.requestNotificationPermission();
      if (granted) {
        setState(() {
          if (currentPageData.permissionType == _PermissionType.storage) {
            _storageGranted = true;
          } else {
            _notificationGranted = true;
          }
        });
        _goToNextPage();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                currentPageData.permissionType == _PermissionType.storage
                    ? AppLocalizations.of(context).permissionRequired
                    : AppLocalizations.of(
                        context,
                      ).notificationPermissionRequired,
              ),
              action: SnackBarAction(
                label: AppLocalizations.of(context).retry,
                onPressed: _nextPage,
              ),
            ),
          );
        }
      }
    } else if (currentPageData.isDownloadLocationPage) {
      final settings = context.read<SettingsProvider>();
      await settings.setDownloadLocation(_downloadLocation);
      _goToNextPage();
    } else if (currentPageData.isThemePage) {
      final theme = context.read<ThemeProvider>();
      await theme.setPrimaryColor(_selectedColor);
      await theme.setThemeMode(_selectedThemeMode);
      _goToNextPage();
    } else {
      _goToNextPage();
    }
  }

  void _goToNextPage() {
    if (_currentPage < _pages.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      _completeIntroduction();
    }
  }

  Future<void> _completeIntroduction() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('intro_completed', true);
    widget.onComplete();
  }

  @override
  Widget build(BuildContext context) {
    if (_pages.isEmpty) {
      return const SizedBox.shrink();
    }

    final currentPageData = _pages[_currentPage];
    final isPermissionPage = currentPageData.isPermissionPage;
    final canSkip = _permissionsGranted && !isPermissionPage;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            if (canSkip)
              Align(
                alignment: Alignment.topRight,
                child: TextButton(
                  onPressed: _completeIntroduction,
                  child: Text(
                    AppLocalizations.of(context).skip,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
              ),
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                onPageChanged: (index) {
                  setState(() {
                    _currentPage = index;
                  });
                },
                itemCount: _pages.length,
                itemBuilder: (context, index) {
                  final page = _pages[index];
                  if (page.isPermissionPage) {
                    return _PermissionPageView(
                      page: page,
                      onRequestPermission: _nextPage,
                      isGranted: page.permissionType == _PermissionType.storage
                          ? _storageGranted
                          : _notificationGranted,
                    );
                  }
                  if (page.isDownloadLocationPage) {
                    return _DownloadLocationPageView(
                      page: page,
                      selected: _downloadLocation,
                      onChanged: (value) {
                        setState(() {
                          _downloadLocation = value;
                        });
                      },
                    );
                  }
                  if (page.isThemePage) {
                    return _ThemePageView(
                      page: page,
                      selectedColor: _selectedColor,
                      selectedMode: _selectedThemeMode,
                      onColorChanged: (color) {
                        setState(() {
                          _selectedColor = color;
                        });
                      },
                      onModeChanged: (mode) {
                        setState(() {
                          _selectedThemeMode = mode;
                        });
                      },
                    );
                  }
                  return _IntroPageView(page: page);
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: List.generate(
                      _pages.length,
                      (index) => _DotIndicator(
                        isActive: index == _currentPage,
                        color: _pages[index].color,
                      ),
                    ),
                  ),
                  ElevatedButton(
                    onPressed: _nextPage,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                    ),
                    child: Text(
                      _currentPage == _pages.length - 1
                          ? AppLocalizations.of(context).getStarted
                          : (isPermissionPage
                                ? (_permissionsGranted
                                      ? AppLocalizations.of(context).next
                                      : AppLocalizations.of(
                                          context,
                                        ).grantPermission)
                                : AppLocalizations.of(context).next),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _PermissionType { storage, notification }

class _IntroPage {
  final IconData icon;
  final String title;
  final String description;
  final Color color;
  final bool isPermissionPage;
  final bool isDownloadLocationPage;
  final bool isThemePage;
  final _PermissionType? permissionType;

  _IntroPage({
    required this.icon,
    required this.title,
    required this.description,
    required this.color,
    this.isPermissionPage = false,
    this.isDownloadLocationPage = false,
    this.isThemePage = false,
    this.permissionType,
  });
}

class _IntroPageView extends StatelessWidget {
  final _IntroPage page;

  const _IntroPageView({required this.page});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(32),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 120,
          height: 120,
          decoration: BoxDecoration(
            color: page.color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(60),
          ),
          child: Icon(page.icon, size: 60, color: page.color),
        ),
        const SizedBox(height: 48),
        Text(
          page.title,
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        Text(
          page.description,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    ),
  );
}

class _ThemePageView extends StatelessWidget {
  final _IntroPage page;
  final Color selectedColor;
  final ThemeMode selectedMode;
  final ValueChanged<Color> onColorChanged;
  final ValueChanged<ThemeMode> onModeChanged;

  const _ThemePageView({
    required this.page,
    required this.selectedColor,
    required this.selectedMode,
    required this.onColorChanged,
    required this.onModeChanged,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color: selectedColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(60),
            ),
            child: Icon(page.icon, size: 60, color: selectedColor),
          ),
          const SizedBox(height: 32),
          Text(
            page.title,
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            page.description,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: app_theme.availableColors.map((color) {
              final isSelected = color == selectedColor;
              return Expanded(
                child: Center(
                  child: GestureDetector(
                    onTap: () => onColorChanged(color),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isSelected
                              ? Theme.of(context).colorScheme.onSurface
                              : Colors.transparent,
                          width: 3,
                        ),
                        boxShadow: isSelected
                            ? [
                                BoxShadow(
                                  color: color.withValues(alpha: 0.4),
                                  blurRadius: 8,
                                ),
                              ]
                            : null,
                      ),
                      child: isSelected
                          ? const Icon(Icons.check, color: Colors.white)
                          : null,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 24),
          SegmentedButton<ThemeMode>(
            segments: [
              ButtonSegment(
                value: ThemeMode.light,
                icon: const Icon(Icons.light_mode),
                label: Text(l10n.lightMode),
              ),
              ButtonSegment(
                value: ThemeMode.dark,
                icon: const Icon(Icons.dark_mode),
                label: Text(l10n.darkMode),
              ),
              ButtonSegment(
                value: ThemeMode.system,
                icon: const Icon(Icons.settings_brightness),
                label: Text(l10n.followSystem),
              ),
            ],
            selected: {selectedMode},
            onSelectionChanged: (selection) => onModeChanged(selection.first),
          ),
        ],
      ),
    );
  }
}

class _DownloadLocationPageView extends StatelessWidget {
  final _IntroPage page;
  final String selected;
  final ValueChanged<String> onChanged;

  const _DownloadLocationPageView({
    required this.page,
    required this.selected,
    required this.onChanged,
  });

  static const _locations = ['internal', 'downloads', 'music'];

  @override
  Widget build(BuildContext context) {
    final settings = context.read<SettingsProvider>();
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color: page.color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(60),
            ),
            child: Icon(page.icon, size: 60, color: page.color),
          ),
          const SizedBox(height: 32),
          Text(
            page.title,
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            page.description,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          RadioGroup<String>(
            groupValue: selected,
            onChanged: (value) {
              if (value != null) onChanged(value);
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ..._locations.map((location) {
                  final isSelected = location == selected;
                  return ListTile(
                    leading: Icon(
                      location == 'internal'
                          ? Icons.phone_android
                          : location == 'downloads'
                          ? Icons.download_for_offline_outlined
                          : Icons.library_music_outlined,
                      color: isSelected
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    title: Text(
                      settings.getDownloadLocationName(location),
                      style: TextStyle(
                        fontWeight: isSelected
                            ? FontWeight.bold
                            : FontWeight.normal,
                        color: isSelected
                            ? Theme.of(context).colorScheme.primary
                            : null,
                      ),
                    ),
                    trailing: Radio<String>(value: location),
                    onTap: () => onChanged(location),
                  );
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PermissionPageView extends StatelessWidget {
  final _IntroPage page;
  final VoidCallback onRequestPermission;
  final bool isGranted;

  const _PermissionPageView({
    required this.page,
    required this.onRequestPermission,
    required this.isGranted,
  });

  @override
  Widget build(BuildContext context) {
    final isStorage = page.permissionType == _PermissionType.storage;
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color: page.color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(60),
            ),
            child: Icon(
              isGranted ? Icons.check_circle : page.icon,
              size: 60,
              color: isGranted ? Colors.green : page.color,
            ),
          ),
          const SizedBox(height: 48),
          Text(
            isGranted ? l10n.permissionGranted : page.title,
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Text(
            isGranted
                ? (isStorage
                      ? l10n.permissionGrantedDesc
                      : l10n.notificationPermissionGrantedDesc)
                : page.description,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _DotIndicator extends StatelessWidget {
  final bool isActive;
  final Color color;

  const _DotIndicator({required this.isActive, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.symmetric(horizontal: 4),
    width: isActive ? 24 : 8,
    height: 8,
    decoration: BoxDecoration(
      color: isActive ? color : color.withValues(alpha: 0.3),
      borderRadius: BorderRadius.circular(4),
    ),
  );
}
