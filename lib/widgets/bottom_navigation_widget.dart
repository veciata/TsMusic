import 'package:flutter/material.dart';
import '../localization/app_localizations.dart';

class BottomNavigationWidget extends StatelessWidget {
  final int currentIndex;
  final Function(int) onTap;

  const BottomNavigationWidget({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);

    return BottomNavigationBar(
      currentIndex: currentIndex < 0 ? 0 : currentIndex,
      onTap: onTap,
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

