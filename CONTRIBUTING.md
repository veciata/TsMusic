# Contributing to TsMusic

First off, thank you for considering contributing to TsMusic! It's people like you that make this project a great music player.

## Where to Start

- Check out [existing issues](https://github.com/veciata/TsMusic/issues), especially those labeled `good first issue` or `help wanted`
- Join our discussions to share ideas and ask questions
- Read our [Code of Conduct](CODE_OF_CONDUCT.md)

## How to Contribute

### Reporting Bugs

Before creating a bug report, please check if the issue already exists. When creating a bug report:

- **Use a clear and descriptive title**
- **Describe the exact steps to reproduce the problem**
- **Provide specific examples** (device model, OS version, app version)
- **Describe the behavior you observed** and the behavior you expected
- **Include screenshots** if applicable

### Suggesting Enhancements

Enhancement suggestions are tracked as GitHub issues. When creating an enhancement suggestion:

- **Use a clear and descriptive title**
- **Provide a step-by-step description** of the suggested enhancement
- **Provide specific examples** to demonstrate the enhancement
- **Explain why this enhancement would be useful**

### Pull Requests

1. Fork the repository
2. Create a new branch (`git checkout -b feature/amazing-feature`)
3. Make your changes
4. Run tests and ensure they pass
5. Commit your changes (`git commit -m 'feat: Add amazing feature'`)
6. Push to the branch (`git push origin feature/amazing-feature`)
7. Open a Pull Request

#### Commit Message Guidelines

We follow [Conventional Commits](https://www.conventionalcommits.org/):

- `feat:` - New feature
- `fix:` - Bug fix
- `docs:` - Documentation changes
- `style:` - Code style changes (formatting, semicolons, etc)
- `refactor:` - Code refactoring
- `perf:` - Performance improvements
- `test:` - Adding or updating tests
- `chore:` - Build process or auxiliary tool changes
- `ci:` - CI/CD changes

Examples:
```
feat: add dark mode support
fix: resolve playback stuttering on low memory devices
docs: update API documentation
```

### Development Setup

```bash
# Clone the repository
git clone https://github.com/veciata/TsMusic.git
cd TsMusic

# Install dependencies
flutter pub get

# Run the app
flutter run
```

### Project Structure

```
lib/
├── core/           # Core functionality (theme, constants, utils)
├── database/       # Database helper and models
├── localization/   # App localizations (tr, en)
├── models/         # Data models (Song, Artist, etc.)
├── providers/      # State management (MusicProvider, ThemeProvider)
├── screens/        # UI screens
├── services/       # Background services
└── widgets/        # Reusable widgets
```

## Style Guidelines

### Dart/Flutter Style

- Follow [Effective Dart](https://dart.dev/guides/language/effective-dart)
- Use `const` constructors where possible
- Prefer single quotes for strings
- Format code with `dart format`
- Analyze with `flutter analyze`

### UI Guidelines

- Follow Material Design 3 guidelines
- Support both light and dark themes
- Ensure responsive layouts
- Use localization for all user-facing text

## Testing

- Write unit tests for business logic
- Write widget tests for UI components
- Ensure all tests pass before submitting PR

## Questions?

Feel free to open an issue with your question or contact the maintainers.

Thank you for contributing! 🎵
