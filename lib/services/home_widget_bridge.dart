import 'package:flutter/services.dart';
import 'package:tsmusic/providers/music_provider.dart' as music_provider;

class HomeWidgetBridge {
  static const MethodChannel _channel =
      MethodChannel('com.veciata.tsmusic/widget');

  static void init(music_provider.MusicProvider musicProv) {
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'togglePlayPause':
          await musicProv.togglePlayPause();
          break;
        case 'next':
          await musicProv.next();
          break;
        case 'previous':
          await musicProv.previous();
          break;
      }
    });
  }
}
