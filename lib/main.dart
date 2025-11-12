import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:window_manager/window_manager.dart';
import 'screens/home_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/downloads_screen.dart';
import 'screens/sql_screen.dart';
import 'screens/now_playing_screen.dart';
import 'screens/welcome_screen.dart';
import 'screens/search_screen.dart';
import 'providers/theme_provider.dart';
import 'providers/music_provider.dart' as music_provider;
import 'services/permission_service.dart';
import 'services/youtube_service.dart';
import 'utils/package_info_utils.dart';

final GlobalKey<MainNavigationScreenState> mainNavKey = GlobalKey();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await PackageInfoUtils.init();

  final youTubeService = YouTubeService();
  final permissionService = PermissionService();
  final hasPermission = await permissionService.hasStoragePermission();

  runApp(MusicPlayerApp(
    youTubeService: youTubeService,
    hasPermission: hasPermission,
  ));

  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    await windowManager.ensureInitialized();

    WindowOptions windowOptions = const WindowOptions(
      size: Size(1280, 720),
      center: true,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.normal,
    );

    windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }
}

class MusicPlayerApp extends StatefulWidget {
  final YouTubeService youTubeService;
  final bool hasPermission;

  const MusicPlayerApp({
    super.key,
    required this.youTubeService,
    required this.hasPermission,
  });

  @override
  State<MusicPlayerApp> createState() => _MusicPlayerAppState();
}

class _MusicPlayerAppState extends State<MusicPlayerApp> {
  late bool _hasPermission;

  @override
  void initState() {
    super.initState();
    _hasPermission = widget.hasPermission;
  }

  void _onPermissionGranted() {
    setState(() {
      _hasPermission = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()..loadTheme()),
        ChangeNotifierProvider(create: (_) => music_provider.MusicProvider()),
        ChangeNotifierProvider(create: (_) => widget.youTubeService),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, _) {
          final lightTheme = themeProvider.getLightTheme();
          final darkTheme = themeProvider.getDarkTheme();
          final isDark = themeProvider.isDarkMode;
          final baseTextTheme =
              isDark ? ThemeData.dark().textTheme : ThemeData.light().textTheme;
          final textTheme = GoogleFonts.poppinsTextTheme(baseTextTheme);

          return MaterialApp(
            title: 'TS Music',
            debugShowCheckedModeBanner: false,
            theme: lightTheme.copyWith(textTheme: textTheme),
            darkTheme: darkTheme.copyWith(textTheme: textTheme),
            themeMode: themeProvider.themeMode,
            home: _hasPermission
                ? const MainNavigationScreen()
                : WelcomeScreen(onPermissionGranted: _onPermissionGranted),
          );
        },
      ),
    );
  }
}

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  MainNavigationScreenState createState() => MainNavigationScreenState();
}

class MainNavigationScreenState extends State<MainNavigationScreen> {
  int _selectedIndex = 0;
  final PageController _pageController = PageController();

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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final musicProv =
          Provider.of<music_provider.MusicProvider>(context, listen: false);
      // Load from database first, then scan for new music in background
      _initializeMusic(musicProv);
    });
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
      _pageController.jumpToPage(index);
    });
  }

  String _getTitle() {
    switch (_selectedIndex) {
      case 0:
        return 'Home';
      case 1:
        return 'Downloads';
      case 2:
        return 'Settings';
      case 3:
        return 'Sql';
      default:
        return 'TS Music';
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_getTitle()),
        centerTitle: true,
        actions: [
          if (_selectedIndex == 0) // Sadece Home ekranında göster
            IconButton(
              icon: const Icon(Icons.search),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => SearchScreen()),
                );
              },
            ),
        ],
      ),
      body: PageView(
        controller: _pageController,
        physics: const NeverScrollableScrollPhysics(),
        children: _pages,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        type: BottomNavigationBarType.fixed,
        items: [
          const BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: 'Home',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.download),
            label: 'Downloads',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.settings),
            label: 'Settings',
          ),
          if (kDebugMode)
            const BottomNavigationBarItem(
              icon: Icon(Icons.storage),
              label: 'Sql',
            ),
        ],
      ),
      bottomSheet: Consumer<music_provider.MusicProvider>(
        builder: (context, musicProv, _) {
          final currentSong = musicProv.currentSong;
          return GestureDetector(
            onTap: () {
              if (currentSong != null) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (context) => const NowPlayingScreen()),
                );
              }
            },
            child: Container(
              height: 70,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceVariant,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 4,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .primary
                          .withOpacity(0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Icon(Icons.music_note, size: 30),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          currentSong?.title ?? 'Not Playing',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 16),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          currentSong?.artists.isNotEmpty == true ? currentSong!.artists.join(' & ') : 'Select a song to play',
                          style: TextStyle(
                            color:
                                Theme.of(context).textTheme.bodySmall?.color,
                            fontSize: 14,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  if (currentSong != null)
                    IconButton(
                      icon: Icon(
                        musicProv.isPlaying ? Icons.pause : Icons.play_arrow,
                        size: 32,
                      ),
                      onPressed: musicProv.togglePlayPause,
                    )
                  else
                    IconButton(
                      icon: const Icon(Icons.music_note, size: 32),
                      onPressed: () {
                        if (musicProv.songs.isNotEmpty) {
                          musicProv.playSong(musicProv.songs.first);
                        }
                      },
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
