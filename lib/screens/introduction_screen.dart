import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsmusic/localization/app_localizations.dart';
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
  bool _permissionsGranted = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _initPages();
    _checkPermissions();
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
    final hasPermission = await permissionService.hasStoragePermission();
    if (mounted) {
      setState(() {
        _permissionsGranted = hasPermission;
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
      if (currentPageData.permissionType == _PermissionType.storage) {
        final permissionService = PermissionService();
        final granted = await permissionService.requestStoragePermission();
        if (granted) {
          setState(() {
            _permissionsGranted = true;
          });
          _goToNextPage();
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(AppLocalizations.of(context).permissionRequired),
                action: SnackBarAction(
                  label: AppLocalizations.of(context).retry,
                  onPressed: _nextPage,
                ),
              ),
            );
          }
        }
      }
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
                      isGranted: _permissionsGranted,
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

enum _PermissionType { storage }

class _IntroPage {
  final IconData icon;
  final String title;
  final String description;
  final Color color;
  final bool isPermissionPage;
  final _PermissionType? permissionType;

  _IntroPage({
    required this.icon,
    required this.title,
    required this.description,
    required this.color,
    this.isPermissionPage = false,
    this.permissionType,
  });
}

class _IntroPageView extends StatelessWidget {
  final _IntroPage page;

  const _IntroPageView({required this.page});

  @override
  Widget build(BuildContext context) {
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
            isGranted
                ? AppLocalizations.of(context).permissionGranted
                : page.title,
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Text(
            isGranted
                ? AppLocalizations.of(context).permissionGrantedDesc
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
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      width: isActive ? 24 : 8,
      height: 8,
      decoration: BoxDecoration(
        color: isActive ? color : color.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}
