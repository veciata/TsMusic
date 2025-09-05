
---

# TS Music – App Plan

## Overview
TS Music is a modern audio player that combines local library playback with YouTube sourcing and rich metadata enrichment. It is designed to work across mobile and desktop platforms with a clean, Material 3-inspired UI.

## Core Features (MVP)
- Local music library scan and playback
- Mini player with quick controls; full Now Playing screen
- Now Playing Queue (view, reorder, remove, jump-to)
- Favorites management
- Background playback with system notifications
- YouTube import/stream support (via `YouTubeService`)
- Basic search, sorting, and metadata display

## Architecture
- UI Screens: `lib/screens/`
  - `home_screen.dart` – library and discovery
  - `now_playing_screen.dart` – full-screen player
  - `queue_screen.dart` – Now Playing queue management
  - `downloads_screen.dart`, `settings_screen.dart`, `sql_screen.dart`
- Widgets: `lib/widgets/`
  - `now_playing_bottom_sheet.dart` – mini player sheet
- State: `lib/providers/new_music_provider.dart` (Provider + ChangeNotifier)
- Services: `lib/services/`
  - `youtube_service.dart` – YouTube integration
  - `audio_notification_service.dart` – background controls/notifications
  - `metadata_enrichment_service.dart` – enrich unknown artists/genres
- Data: `lib/database/` – `database_helper.dart` for persistence
- Models: `lib/models/song.dart`

## State Management
`NewMusicProvider` controls playback and library state. Key APIs used by the UI:
- Playback: `play()`, `pause()`, `togglePlayPause()`, `seek()`, `previous()`, `next()`
- Current: `currentSong`, `currentIndex`, `isPlaying`, `position`, `duration`
- Queue: `queue`, `playAt(index)`, `removeFromQueue(index)`, `moveInQueue(oldIndex, newIndex)`
- Library: `songs`, `loadSongsFromStorage()`, `sortSongs()`, `filterSongs()`
- Favorites: `isFavorite(id)`, `toggleFavorite(id)`

## Queue Interactions
- Reorder songs by dragging the handle.
- Swipe left/right to remove a song.
- Tap an item to play it immediately.

## Permissions
- Storage access (Android) to scan local files
- Notifications (Android/iOS) for audio controls

## Build & Run
1. Flutter: 3.x+
2. Run `flutter pub get`
3. Start app: `flutter run`

## Roadmap (Next Steps)
- Playlists (user-defined) separate from queue
- Shuffle/Repeat modes and UI indicators
- Enhanced search and filtering
- Artwork caching and improved error handling for images
- Queue persistence across sessions
- Download management and offline YouTube handling

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
