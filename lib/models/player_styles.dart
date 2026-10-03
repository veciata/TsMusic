export 'classic_style.dart';
export 'modern_style.dart';
export 'minimal_style.dart';
export 'square_style.dart';
export 'glass_style.dart';

enum PlayerStyle { classic, modern, minimal, square, glass }

extension PlayerStyleExtension on PlayerStyle {
  String get displayName {
    switch (this) {
      case PlayerStyle.classic:
        return 'Classic';
      case PlayerStyle.modern:
        return 'Modern';
      case PlayerStyle.minimal:
        return 'Minimal';
      case PlayerStyle.square:
        return 'Square';
      case PlayerStyle.glass:
        return 'Glass';
    }
  }
}
