# TS Music

A modern, cross-platform music player with local library support and YouTube integration, built with Flutter.

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
- Internationalization support

## Getting Started

### Prerequisites

- Flutter SDK (latest stable version)
- Dart SDK (latest stable version)
- Android Studio / Xcode (for mobile development)
- VS Code or Android Studio (recommended IDEs)

### Installation

1. **Clone the repository**
   ```bash
   git clone https://github.com/your-username/tsmusic.git
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
│   ├── home/           # Home screen components
│   ├── settings/       # Settings screen components
│   └── ...
├── widgets/            # Reusable UI components
├── routes/             # Navigation routes
└── localization/       # Internationalization files
```

## Tech Stack

- **Framework**: Flutter
- **Language**: Dart
- **State Management**: Provider
- **Audio Playback**: just_audio
- **Database**: sqflite
- **Networking**: http
- **YouTube Integration**: youtube_explode_dart
- **UI**: Material 3, FlexColorScheme

## Code Style

This project follows the [Effective Dart](https://dart.dev/guides/language/effective-dart) style guide. Please ensure your code adheres to these guidelines before submitting pull requests.

Key points:
- Use `camelCase` for variables and functions
- Use `PascalCase` for class names
- Use `UPPER_CASE` for constants
- Use `_private` for private members
- Always include documentation for public APIs
- Keep methods short and focused on a single responsibility

## Contributing

Contributions are welcome! Please read our [contributing guidelines](CONTRIBUTING.md) before submitting pull requests.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- [Flutter](https://flutter.dev/) team for the amazing framework
- [just_audio](https://pub.dev/packages/just_audio) for audio playback
- [youtube_explode_dart](https://pub.dev/packages/youtube_explode_dart) for YouTube integration
- All contributors who have helped improve this project

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
