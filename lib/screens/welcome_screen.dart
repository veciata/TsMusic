import 'package:flutter/material.dart';
import 'package:tsmusic/services/permission_service.dart';

class WelcomeScreen extends StatelessWidget {
  final VoidCallback onPermissionGranted;

  const WelcomeScreen({super.key, required this.onPermissionGranted});

  @override
  Widget build(BuildContext context) {
    final permissionService = PermissionService();

    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'Welcome to TS Music',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            const Text(
              'To get started, please grant storage access to find your music.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () async {
                final granted = await permissionService.requestStoragePermission();
                if (granted) {
                  onPermissionGranted();
                }
              },
              child: const Text('Grant Permission'),
            ),
          ],
        ),
      ),
    );
  }
}
