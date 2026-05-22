# TS Music

A modern, cross-platform music player with local library support, YouTube integration, and home screen widgets, built with Flutter.

[![Flutter](https://img.shields.io/badge/Flutter-02569B?style=for-the-badge&logo=flutter&logoColor=white)](https://flutter.dev/)
[![Dart](https://img.shields.io/badge/Dart-0175C2?style=for-the-badge&logo=dart&logoColor=white)](https://dart.dev/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=for-the-badge)](https://opensource.org/licenses/MIT)

## Features

- Local music library scanning and playback
- Background audio playback with system controls
- YouTube music streaming and import
- Favorites management
- Queue management with drag-to-reorder
- Search and filter your music library
- Material 3 design with dynamic theming
- Responsive layout for mobile and desktop
- **Internationalization** — Turkish (Türkçe) and English support
- **Home screen widgets** — dynamic player widget with queue display
- R8-optimized release builds with resource shrinking

## Screenshots

![TS Music Screenshot](screenshot.png)

## Getting Started

### Prerequisites

- Flutter SDK (latest stable version)
- Dart SDK (latest stable version)
- Android Studio / Xcode (for mobile development)
- VS Code or Android Studio (recommended IDEs)

### Installation

1. **Clone the repository**
   ```bash
   git clone https://github.com/veciata/TsMusic.git
   cd tsmusic
   ```

2. **Install dependencies**
   ```bash
   flutter pub get
   ```

3. **Run the app**
   ```bash
   flutter run
   ```

### Release Build

```bash
# Build a release APK with R8 shrinking
flutter build apk --release

# For a smaller APK per architecture
flutter build apk --release --split-per-abi
```

## Project Structure

```
lib/
├── core/
│   ├── constants/      # App constants, enums, and configurations
│   ├── services/       # Business logic and API services
│   ├── theme/          # App theming and styling
│   └── utils/          # Helper functions and extensions
├── models/             # Data models and DTOs
├── providers/          # State management
├── screens/            # App screens/pages
├── widgets/            # Reusable UI components
├── routes/             # Navigation routes
└── localization/       # Internationalization (en, tr)
```

## Tech Stack

- **Framework**: Flutter
- **Language**: Dart + Kotlin (Android)
- **State Management**: Provider
- **Audio Playback**: media_kit
- **Database**: sqflite
- **Networking**: http
- **YouTube Integration**: youtube_explode_dart
- **UI**: Material 3, FlexColorScheme
- **Home Widgets**: home_widget (Android)
- **Localization**: Flutter intl, custom l10n

## Code Style

This project follows the [Effective Dart](https://dart.dev/guides/language/effective-dart) style guide.

## License

This project is licensed under the MIT License.
