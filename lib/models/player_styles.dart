export 'classic_style.dart';
export 'modern_style.dart';
export 'compact_style.dart';
export 'minimal_style.dart';

enum PlayerStyle {
  classic,
  modern,
  compact,
  minimal,
}

extension PlayerStyleExtension on PlayerStyle {
  String get displayName {
    switch (this) {
      case PlayerStyle.classic:
        return 'Classic';
      case PlayerStyle.modern:
        return 'Modern';
      case PlayerStyle.compact:
        return 'Compact';
      case PlayerStyle.minimal:
        return 'Minimal';
    }
  }
}
