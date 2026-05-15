import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';
import 'package:tsmusic/screens/home_screen.dart';
import 'package:tsmusic/screens/settings_screen.dart';
import 'package:tsmusic/screens/downloads_screen.dart';
import 'package:tsmusic/screens/sql_screen.dart';
import 'package:tsmusic/screens/introduction_screen.dart';
import 'package:tsmusic/screens/search_screen.dart';
import 'package:tsmusic/providers/theme_provider.dart';
import 'package:tsmusic/providers/music_provider.dart' as music_provider;
import 'package:tsmusic/providers/youtube_player_provider.dart';
import 'package:tsmusic/services/youtube_service.dart';
import 'package:tsmusic/providers/settings_provider.dart';
import 'package:tsmusic/localization/app_localizations.dart';
import 'package:tsmusic/utils/package_info_utils.dart';
import 'package:tsmusic/widgets/bottom_navigation_widget.dart';
import 'package:tsmusic/widgets/mini_player_widget.dart';

import 'package:tsmusic/services/download_notification_service.dart';
import 'package:tsmusic/services/home_widget_service.dart';
import 'package:tsmusic/providers/update_notification_provider.dart';
import 'package:tsmusic/widgets/update_notification_modal.dart';

final GlobalKey<MainNavigationScreenState> mainNavKey = GlobalKey();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize MediaKit for audio playback
  MediaKit.ensureInitialized();
  await PackageInfoUtils.init();

  // Initialize download notifications
  await DownloadNotificationService().initialize();

  // Initialize home screen widget
  await HomeWidgetService.init();

  final youTubeService = YouTubeService();

  final prefs = await SharedPreferences.getInstance();
  final introCompleted = prefs.getBool('intro_completed') ?? false;
  final lastSeenVersion = prefs.getString('last_seen_version') ?? '';

  runApp(
    MusicPlayerApp(
      youTubeService: youTubeService,
      introCompleted: introCompleted,
      lastSeenVersion: lastSeenVersion,
    ),
  );

  if (Platform.isMacOS) {
    await windowManager.ensureInitialized();

    final WindowOptions windowOptions = const WindowOptions(
      size: Size(1280, 720),
      center: true,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.normal,
    );

    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }
}

class MusicPlayerApp extends StatefulWidget {
  final YouTubeService youTubeService;
  final bool introCompleted;
  final String lastSeenVersion;

  const MusicPlayerApp({
    super.key,
    required this.youTubeService,
    required this.introCompleted,
    required this.lastSeenVersion,
  });

  @override
  State<MusicPlayerApp> createState() => _MusicPlayerAppState();
}

class _MusicPlayerAppState extends State<MusicPlayerApp> {
  late bool _introCompleted;

  @override
  void initState() {
    super.initState();
    _introCompleted = widget.introCompleted;
  }

  void _onIntroComplete() {
    setState(() {
      _introCompleted = true;
    });
  }

  @override
  Widget build(BuildContext context) => MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => ThemeProvider()..loadTheme()),
      ChangeNotifierProvider(
        create: (ctx) => music_provider.MusicProvider(
          notificationColor: ctx.read<ThemeProvider>().primaryColor,
        ),
      ),
      ChangeNotifierProvider(create: (_) => widget.youTubeService),
      ChangeNotifierProvider(
        create: (_) => YouTubePlayerProvider(widget.youTubeService),
      ),
      ChangeNotifierProvider(create: (_) => SettingsProvider()),
      ChangeNotifierProvider(
        create: (_) =>
            UpdateNotificationProvider(lastSeenVersion: widget.lastSeenVersion),
      ),
    ],
    child: Consumer<ThemeProvider>(
      builder: (context, themeProvider, _) {
        final lightTheme = themeProvider.getLightTheme();
        final darkTheme = themeProvider.getDarkTheme();
        final isDark = themeProvider.isDarkMode;
        final baseTextTheme = isDark
            ? ThemeData.dark().textTheme
            : ThemeData.light().textTheme;
        final textTheme = baseTextTheme.copyWith(
          headlineLarge: baseTextTheme.headlineLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
          headlineMedium: baseTextTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        );

        return Consumer<SettingsProvider>(
          builder: (context, settingsProvider, _) => MaterialApp(
              title: kDebugMode ? 'TS Music [Debug]' : 'TS Music',
              debugShowCheckedModeBanner: false,
              theme: lightTheme.copyWith(textTheme: textTheme),
              darkTheme: darkTheme.copyWith(textTheme: textTheme),
              themeMode: themeProvider.themeMode,
              locale: settingsProvider.locale,
              localizationsDelegates: const [
                AppLocalizations.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              supportedLocales: AppLocalizations.supportedLocales,
              home: _introCompleted
                  ? MainNavigationScreen(key: mainNavKey)
                  : IntroductionScreen(onComplete: _onIntroComplete),
            ),
        );
      },
    ),
  );
}

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  MainNavigationScreenState createState() => MainNavigationScreenState();
}

class MainNavigationScreenState extends State<MainNavigationScreen> {
  int _selectedIndex = 0;
  final PageController _pageController = PageController();
  static const _navigationChannel = MethodChannel(
    'com.veciata.tsmusic/navigation',
  );

  final List<Widget> _pages = [
    const HomeScreen(),
    const DownloadsScreen(),
    const SettingsScreen(),
    if (kDebugMode) const SqlScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _requestNotificationPermission();
    _navigationChannel.setMethodCallHandler((call) {
      switch (call.method) {
        case 'openSearch':
          final query = call.arguments as String?;
          _openSearch(query);
          return Future.value(true);
        default:
          return Future.value(false);
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final musicProv = Provider.of<music_provider.MusicProvider>(
        context,
        listen: false,
      );
      // Set up widget auto-update — fires on every notifyListeners
      musicProv.setOnWidgetUpdateNeeded(() => _onWidgetUpdate(musicProv));
      // Load from database first, then scan for new music in background
      _initializeMusic(musicProv);
      // Check for GitHub releases and show update modal if new ones found.
      _checkForUpdates();
    });
  }

  void _openSearch([String? query]) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SearchScreen(initialQuery: query),
      ),
    );
  }

  Future<void> _initializeMusic(music_provider.MusicProvider musicProv) async {
    try {
      // First load from database
      await musicProv.loadFromDatabaseOnly();

      // If no music found, trigger a scan
      if (musicProv.songs.isEmpty) {
        debugPrint('No music in database, scanning for music...');
        await musicProv.scanForNewMusic();
      }
    } catch (e) {
      debugPrint('Error initializing music: $e');
      // Try scanning anyway
      try {
        await musicProv.scanForNewMusic();
      } catch (scanError) {
        debugPrint('Error during music scan: $scanError');
      }
    }
  }

  Future<void> _checkForUpdates() async {
    try {
      final provider = Provider.of<UpdateNotificationProvider>(
        context,
        listen: false,
      );
      final hasUpdates = await provider.checkForUpdates();
      if (hasUpdates && mounted) {
        await showUpdateNotificationModal(context);
      }
    } catch (e) {
      debugPrint('Update check error: $e');
    }
  }

  Future<void> _requestNotificationPermission() async {
    if (Platform.isAndroid || Platform.isIOS) {
      final status = await Permission.notification.status;
      if (status.isDenied) {
        await Permission.notification.request();
      }
    }
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
      _pageController.animateToPage(
        index,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    });
  }

  void goToDownloads() {
    _onItemTapped(1);
  }

  String _getTitle() {
    final l10n = AppLocalizations.of(context);
    switch (_selectedIndex) {
      case 0:
        return l10n.home;
      case 1:
        return l10n.downloads;
      case 2:
        return l10n.settings;
      case 3:
        return l10n.sql;
      default:
        return l10n.tsMusic;
    }
  }

  void _onWidgetUpdate(music_provider.MusicProvider musicProv) {
    try {
      final youTubeService = Provider.of<YouTubeService>(
        context,
        listen: false,
      );
      final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
      final isDarkMode = themeProvider.isDarkMode;
      HomeWidgetService.updatePlayerWidget(
        currentSong: musicProv.currentSong,
        isPlaying: musicProv.isPlaying,
        isOnlinePlaying: youTubeService.isPlaying,
        onlineTitle: youTubeService.currentAudio?.title,
        onlineAuthor: youTubeService.currentAudio?.author,
        isDarkMode: isDarkMode,
      );
      HomeWidgetService.updateSearchWidget(isDarkMode: isDarkMode);

    } catch (e) {
      debugPrint('Widget update error: $e');
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(_getTitle()),
      centerTitle: true,
      actions: [
        if (_selectedIndex == 0)
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SearchScreen()),
              );
            },
            tooltip: AppLocalizations.of(context).search,
          ),
      ],
    ),
    body: Column(
      children: [
        Expanded(
          child: PageView(
            controller: _pageController,
            physics: const NeverScrollableScrollPhysics(),
            children: _pages,
          ),
        ),
        // Persistent mini player — always visible above bottom nav
        const MiniPlayerWidget(),
      ],
    ),
    bottomNavigationBar: BottomNavigationWidget(
      currentIndex: _selectedIndex,
      onTap: _onItemTapped,
    ),
  );
}
