import 'package:flutter/material.dart';

class HomeScreen extends StatelessWidget {
  final List<Map<String, String>> songs;
  final Function(int) onSongTap;
  final Function() onSettingsTap;

  const HomeScreen({
    super.key,
    required this.songs,
    required this.onSongTap,
    required this.onSettingsTap,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('TS Music'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: onSettingsTap,
          ),
        ],
      ),
      body: ListView.builder(
        itemCount: songs.length,
        itemBuilder: (context, index) {
          final song = songs[index];
          return ListTile(
            leading: const Icon(Icons.music_note, size: 40),
            title: Text(song['title']!),
            subtitle: Text(song['artist']!),
            trailing: Text(song['duration']!),
            onTap: () => onSongTap(index),
          );
        },
      ),
    );
  }
}
