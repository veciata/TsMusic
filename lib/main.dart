import 'dart:async';
import 'dart:io' show Platform, exit;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/foundation.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:window_manager/window_manager.dart';
import 'package:just_audio/just_audio.dart';
import 'screens/home_screen.dart';
import 'screens/player_screen.dart';
import 'screens/now_playing_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/downloads_screen.dart';
import 'screens/sql_screen.dart';
import 'providers/theme_provider.dart';
import 'providers/new_music_provider.dart' as music_provider;
import 'services/youtube_service.dart';
import 'services/audio_notification_service.dart';
import 'widgets/now_playing_bottom_sheet.dart';
import 'utils/package_info_utils.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await PackageInfoUtils.init();
  
  // Initialize the YouTube service instance
  final youTubeService = YouTubeService();
  
  // Audio notifications handled by provider-level AudioNotificationService init
  
  // Run the app
  runApp(MusicPlayerApp(youTubeService: youTubeService));
  
  // Set up window close handler for desktop platforms
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

// AudioService.init removed; using internal AudioNotificationService from provider

class MusicPlayerApp extends StatefulWidget {
  final YouTubeService youTubeService;
  
  const MusicPlayerApp({super.key, required this.youTubeService});
  
  @override
  State<MusicPlayerApp> createState() => _MusicPlayerAppState();
}

class _MusicPlayerAppState extends State<MusicPlayerApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
  
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      // This will be called when the app is being terminated
      _handleAppTermination();
    }
  }
  
  Future<void> _handleAppTermination() async {
    try {
      // Give the service a chance to complete any pending downloads
      await YouTubeService.close();
    } catch (e) {
      debugPrint('Error during app termination: $e');
    } finally {
      // Force exit if needed (for desktop platforms)
      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        exit(0);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()..loadTheme()),
        ChangeNotifierProvider(create: (_) => music_provider.NewMusicProvider()),
        ChangeNotifierProvider(create: (_) => widget.youTubeService),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, _) {
          final lightTheme = themeProvider.getLightTheme();
          final darkTheme = themeProvider.getDarkTheme();
          final isDark = themeProvider.isDarkMode;
          final baseTextTheme = isDark
              ? ThemeData.dark().textTheme
              : ThemeData.light().textTheme;
          final textTheme = GoogleFonts.poppinsTextTheme(baseTextTheme);

          return MaterialApp(
            title: 'TS Music',
            debugShowCheckedModeBanner: false,
            theme: lightTheme.copyWith(textTheme: textTheme),
            darkTheme: darkTheme.copyWith(textTheme: textTheme),
            themeMode: themeProvider.themeMode,
            home: const MainNavigationScreen(),
          );
        },
      ),
    );
  }
}

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _selectedIndex = 0;
  final PageController _pageController = PageController();

  List<Widget> get _pages => [
        const HomeScreen(),
        const DownloadsScreen(),
        const SettingsScreen(),
        if (kDebugMode) const SqlScreen(),
      ];

  @override
  void initState() {
    super.initState();
    // Request notification permission on app start
    _requestNotificationPermission();
    
    // Load local music when the app starts
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final musicProvider = Provider.of<music_provider.NewMusicProvider>(
        context, 
        listen: false,
      );
      if (musicProvider.songs.isEmpty) {
        musicProvider.loadSongsFromStorage();
      }
    });
  }

  Future<void> _requestNotificationPermission() async {
    if (kIsWeb) return;
    
    try {
      // Only request notification permission on mobile platforms
      if (Platform.isAndroid || Platform.isIOS) {
        final status = await Permission.notification.status;
        if (status.isDenied) {
          await Permission.notification.request();
        }
      }
    } catch (e) {
      // Ignore MissingPluginException on platforms where notification permission is not supported
      if (e.toString().contains('MissingPluginException')) {
        debugPrint('Notification permission not supported on this platform');
      } else {
        rethrow;
      }
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
      _pageController.jumpToPage(index);
    });
  }

  void _navigateToSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const SettingsScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final musicProvider = Provider.of<music_provider.NewMusicProvider>(context);
    final currentSong = musicProvider.currentSong;
    final isPlaying = musicProvider.isPlaying;

    return Scaffold(
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
      bottomSheet: Consumer<music_provider.NewMusicProvider>(
        builder: (context, musicProvider, _) {
          final currentSong = musicProvider.currentSong;
          
          return GestureDetector(
            onTap: () {
              if (currentSong != null) {
                NowPlayingBottomSheet.show(context);
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
                  // Album art or placeholder
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Icon(Icons.music_note, size: 30),
                  ),
                  
                  const SizedBox(width: 12),
                  
                  // Song info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          currentSong?.title ?? 'Not Playing',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          currentSong?.artist ?? 'Select a song to play',
                          style: TextStyle(
                            color: Theme.of(context).textTheme.bodySmall?.color,
                            fontSize: 14,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  
                  // Play/Pause button
                  if (currentSong != null)
                    IconButton(
                      icon: Icon(
                        musicProvider.isPlaying ? Icons.pause : Icons.play_arrow,
                        size: 32,
                      ),
                      onPressed: musicProvider.togglePlayPause,
                    )
                  else
                    IconButton(
                      icon: const Icon(Icons.music_note, size: 32),
                      onPressed: () {
                        // This will be handled by the music provider
                        if (musicProvider.songs.isNotEmpty) {
                          musicProvider.playSong(musicProvider.songs.first);
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
