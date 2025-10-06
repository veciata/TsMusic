import 'package:flutter/material.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsmusic/main.dart';
import 'package:tsmusic/providers/new_music_provider.dart' as music_provider;
import 'package:tsmusic/utils/permission_helper.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  bool _permissionGranted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkFirstLaunch();
    });
  }

  Future<void> _checkFirstLaunch() async {
    final prefs = await SharedPreferences.getInstance();
    final isFirstLaunch = prefs.getBool('is_first_launch') ?? true;

    if (!isFirstLaunch) {
      // Uygulama daha önce açıldıysa doğrudan ana ekrana yönlendir
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => const MainNavigationScreen(),
          ),
        );
      }
      return;
    }

    // İlk açılışsa izinleri kontrol et
    _checkPermissionAndScan();
  }

  Future<void> _checkPermissionAndScan() async {
    final granted = await PermissionHelper.requestStoragePermission();
    if (!mounted) return;
    setState(() {
      _permissionGranted = granted;
    });

    if (granted) {
      _startMusicScan();
    }
  }

  Future<void> _startMusicScan() async {
    try {
      final musicProvider = Provider.of<music_provider.NewMusicProvider>(
        context,
        listen: false,
      );
      await musicProvider.loadLocalMusic(forceRescan: true);
      
      // Tarama bittiğinde, bir daha ilk açılış ekranını gösterme
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('is_first_launch', false);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Müzik tarama hatası: $e'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final musicProvider = Provider.of<music_provider.NewMusicProvider>(context);

    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'TS Music\'e Hoş Geldiniz',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 30),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 40),
              child: Text(
                'Müzik dünyanıza hoş geldiniz. En sevdiğiniz şarkıları dinlemeye hemen başlayın!',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16),
              ),
            ),
            const SizedBox(height: 20),
            if (!_permissionGranted)
              const Text(
                'Müzik dosyalarına erişim izni bekleniyor...',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Colors.grey),
              )
            else if (musicProvider.isLoading)
              Column(
                children: [
                  const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Müzikler taranıyor...\nLütfen bekleyiniz',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                ],
              ),
            const SizedBox(height: 20),
            if (_permissionGranted)
              ElevatedButton(
                onPressed: () async {
                  // İlk açılış işaretini kaydet
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setBool('is_first_launch', false);
                  
                  if (mounted) {
                    Navigator.of(context).pushReplacement(
                      MaterialPageRoute(
                        builder: (context) => const MainNavigationScreen(),
                      ),
                    );
                  }
                },
                style: ElevatedButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                  textStyle: const TextStyle(fontSize: 18),
                ),
                child: const Text('Başla'),
              ),
          ],
        ),
      ),
    );
  }
}
