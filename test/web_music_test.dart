// import 'package:flutter/material.dart';
// import 'package:flutter_test/flutter_test.dart';
// import 'package:mockito/annotations.dart';
// import 'package:mockito/mockito.dart';
// import 'package:sqflite_common_ffi/sqflite_ffi.dart';
// import 'package:tsmusic/models/song.dart';
// import 'package:tsmusic/providers/music_provider.dart';
// import 'package:tsmusic/services/youtube_service.dart';
// import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yt;

// import 'web_music_test.mocks.dart';

// @GenerateMocks([
//   yt.YoutubeExplode,
//   yt.SearchClient,
//   yt.VideoClient,
//   yt.StreamClient,
//   yt.Video,
// ])
// void main() {
//   // Initialize sqflite for ffi
//   sqfliteFfiInit();
//   databaseFactory = databaseFactoryFfi;

//   TestWidgetsFlutterBinding.ensureInitialized();

//   group('Web Music Tests', () {
//     late YouTubeService youTubeService;
//     late MusicProvider musicProvider;
//     late MockYoutubeExplode mockYoutubeExplode;
//     late MockSearchClient mockSearchClient;
//     late MockVideoClient mockVideoClient;
//     late MockStreamClient mockStreamClient;

//     setUp(() {
//       mockYoutubeExplode = MockYoutubeExplode();
//       mockSearchClient = MockSearchClient();
//       mockVideoClient = MockVideoClient();
//       mockStreamClient = MockStreamClient();

//       when(mockYoutubeExplode.search).thenReturn(mockSearchClient);
//       when(mockYoutubeExplode.videos).thenReturn(mockVideoClient);
//       when(mockVideoClient.streamsClient).thenReturn(mockStreamClient);

//       youTubeService = YouTubeService.test(mockYoutubeExplode);
//       musicProvider = MusicProvider();
//     });

//     Song _songFromYouTubeAudio(YouTubeAudio audio) {
//       return Song(
//         id: audio.id,
//         title: audio.title,
//         artists: audio.artists,
//         album: audio.author,
//         albumArtUrl: audio.thumbnailUrl,
//         url: 'https://www.youtube.com/watch?v=${audio.id}',
//         duration: audio.duration?.inMilliseconds ?? 0,
//         isFavorite: false,
//         isDownloaded: false,
//         tags: ['youtube'],
//       );
//     }

//     test('Search for a video on YouTube', () async {
//       final query = 'Never Gonna Give You Up';
//       final videoId = yt.VideoId('dQw4w9WgXcQ');
//       final mockVideo = MockVideo();
//       when(mockVideo.id).thenReturn(videoId);
//       when(mockVideo.title).thenReturn('Rick Astley - Never Gonna Give You Up (Official Music Video)');
//       when(mockVideo.author).thenReturn('Rick Astley');
//       when(mockVideo.duration).thenReturn(Duration(minutes: 3, seconds: 32));
//       when(mockVideo.thumbnails).thenReturn(yt.ThumbnailSet(videoId.value));

//       final searchList = yt.VideoSearchList([mockVideo], 1, 1);

//       when(mockSearchClient.search(query)).thenAnswer((_) async => searchList);

//       final videos = await youTubeService.searchAudio(query);
//       expect(videos, isNotEmpty);
//       expect(videos.first.title, contains('Never Gonna Give You Up'));
//     });

//     test('Playback of a YouTube video', () async {
//       final query = 'Never Gonna Give You Up';
//       final videoId = yt.VideoId('dQw4w9WgXcQ');
//       final mockVideo = MockVideo();
//       when(mockVideo.id).thenReturn(videoId);
//       when(mockVideo.title).thenReturn('Rick Astley - Never Gonna Give You Up (Official Music Video)');
//       when(mockVideo.author).thenReturn('Rick Astley');
//       when(mockVideo.duration).thenReturn(Duration(minutes: 3, seconds: 32));
//       when(mockVideo.thumbnails).thenReturn(yt.ThumbnailSet(videoId.value));
//       final searchList = yt.VideoSearchList([mockVideo], 1, 1);

//       when(mockSearchClient.search(query)).thenAnswer((_) async => searchList);

//       final streamManifest = yt.StreamManifest([]);
//       when(mockStreamClient.getManifest(videoId)).thenAnswer((_) async => streamManifest);

//       final videos = await youTubeService.searchAudio(query);
//       final video = videos.first;
//       final song = _songFromYouTubeAudio(video);

//       await musicProvider.playSong(song);

//       // In a test environment, we can't truly test playback,
//       // but we can check if the song is set correctly.
//       expect(musicProvider.currentSong, isNotNull);
//       expect(musicProvider.currentSong!.id, song.id);
//     });

//     test('Get a download stream for a YouTube video', () async {
//       final videoId = yt.VideoId('dQw4w9WgXcQ');
//       final audioOnlyStreamInfo = yt.AudioOnlyStreamInfo(
//           1, yt.Container.mp4, 128000, 'en', 'https://example.com/audio.mp4');
//       final streamManifest = yt.StreamManifest([audioOnlyStreamInfo]);

//       when(mockStreamClient.getManifest(videoId)).thenAnswer((_) async => streamManifest);

//       final streamUrl = await youTubeService.getAudioStreamUrl(videoId.value);

//       expect(streamUrl, isNotNull);
//       expect(streamUrl, startsWith('https'));
//     });
//   });
// }