import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'providers/theme_provider.dart';
import 'screens/home_screen.dart';
import 'screens/settings_screen.dart';

void main() => runApp(const MusicPlayerApp());

class MusicPlayerApp extends StatelessWidget {
  const MusicPlayerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => ThemeProvider()..loadTheme(),
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, _) {
          final lightTheme = themeProvider.getLightTheme();
          final darkTheme = themeProvider.getDarkTheme();
          
          return MaterialApp(
            title: 'TS Music',
            debugShowCheckedModeBanner: false,
            theme: lightTheme.copyWith(
              textTheme: GoogleFonts.poppinsTextTheme(
                Theme.of(context).textTheme,
              ),
              appBarTheme: AppBarTheme(
                backgroundColor: lightTheme.colorScheme.primary,
                foregroundColor: lightTheme.colorScheme.onPrimary,
                elevation: 0,
              ),
            ),
            darkTheme: darkTheme.copyWith(
              textTheme: GoogleFonts.poppinsTextTheme(
                ThemeData.dark().textTheme,
              ),
              appBarTheme: AppBarTheme(
                backgroundColor: darkTheme.colorScheme.primary,
                foregroundColor: darkTheme.colorScheme.onPrimary,
                elevation: 0,
              ),
            ),
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
  final List<Map<String, String>> _songs = [
    {'title': 'Blinding Lights', 'artist': 'The Weeknd', 'duration': '3:20'},
    {'title': 'Save Your Tears', 'artist': 'The Weeknd', 'duration': '3:35'},
    {'title': 'Starboy', 'artist': 'The Weeknd, Daft Punk', 'duration': '3:50'},
    {'title': 'After Hours', 'artist': 'The Weeknd', 'duration': '4:01'},
    {'title': 'Die For You', 'artist': 'The Weeknd', 'duration': '4:20'},
  ];

  void _onSongSelected(int index) {
    // TODO: Implement song playback
    debugPrint('Selected song: ${_songs[index]['title']}');
  }

  void _navigateToSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const SettingsScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: [
          HomeScreen(
            songs: _songs,
            onSongTap: _onSongSelected,
            onSettingsTap: _navigateToSettings,
          ),
          // Add more screens here if needed
          const Center(child: Text('Library')),
          const SettingsScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() => _currentIndex = index);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.library_music_outlined),
            selectedIcon: Icon(Icons.library_music),
            label: 'Library',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
      bottomSheet: Container(
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
            const Icon(Icons.music_note, size: 40),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('Not Playing', style: TextStyle(fontWeight: FontWeight.bold)),
                  Text('Select a song to play'),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.play_arrow, size: 32),
              onPressed: () {},
            ),
          ],
        ),
      ),
    );
  }
}
