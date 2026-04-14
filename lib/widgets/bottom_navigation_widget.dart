import 'package:flutter/material.dart';
import '../localization/app_localizations.dart';
import '../screens/home_screen.dart';
import '../screens/downloads_screen.dart';
import '../screens/settings_screen.dart';

class BottomNavigationWidget extends StatelessWidget {
  final int currentIndex;
  final Function(int) onTap;

  const BottomNavigationWidget({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  void _navigateToScreen(BuildContext context, int index) {
    if (index == currentIndex) return;

    switch (index) {
      case 0:
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const HomeScreen()),
          (route) => false,
        );
        break;
      case 1:
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const DownloadsScreen()),
          (route) => false,
        );
        break;
      case 2:
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const SettingsScreen()),
          (route) => false,
        );
        break;
    }
    onTap(index);
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);

    return BottomNavigationBar(
      currentIndex: currentIndex < 0 ? 0 : currentIndex,
      onTap: (index) => _navigateToScreen(context, index),
      type: BottomNavigationBarType.fixed,
      selectedItemColor: currentIndex < 0 ? Colors.grey : null,
      items: [
        BottomNavigationBarItem(
          icon: const Icon(Icons.home),
          label: localizations.home,
        ),
        BottomNavigationBarItem(
          icon: const Icon(Icons.download),
          label: localizations.downloads,
        ),
        BottomNavigationBarItem(
          icon: const Icon(Icons.settings),
          label: localizations.settings,
        ),
      ],
    );
  }
}
