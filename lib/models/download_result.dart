import 'package:tsmusic/models/song.dart' as ts;

/// The outcome of a successful download: where the audio landed, and the song
/// record that was written for it.
class DownloadResult {
  DownloadResult({required this.filePath, required this.song});

  final String filePath;
  final ts.Song song;
}
