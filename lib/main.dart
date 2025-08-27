import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'screens/home_screen.dart';
import 'screens/player_screen.dart';
import 'screens/settings_screen.dart';
import 'providers/theme_provider.dart';
import 'providers/new_music_provider.dart' as music_provider;
import 'widgets/now_playing_bottom_sheet.dart';
import 'utils/package_info_utils.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await PackageInfoUtils.init();
  runApp(const MusicPlayerApp());
}

class MusicPlayerApp extends StatelessWidget {
  const MusicPlayerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()..loadTheme()),
        ChangeNotifierProvider(create: (_) => music_provider.NewMusicProvider()),
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
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    // Load local music when the app starts
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final musicProvider = Provider.of<music_provider.NewMusicProvider>(context, listen: false);
      if (musicProvider.songs.isEmpty) {
        musicProvider.loadLocalMusic();
      }
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
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: [
          HomeScreen(
            onSettingsTap: _navigateToSettings,
          ),
          const SettingsScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) => setState(() => _currentIndex = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_filled),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
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
