enum ThemeTemperature {
  cold,
  neutral,
  warm,
}

extension ThemeTemperatureExtension on ThemeTemperature {
  String get displayName {
    switch (this) {
      case ThemeTemperature.cold:
        return 'Cold';
      case ThemeTemperature.neutral:
        return 'Neutral';
      case ThemeTemperature.warm:
        return 'Warm';
    }
  }
}
