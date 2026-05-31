# Changelog

## [1.2.1] - 2026-05-31

### Fixed / Düzeltildi
- YouTube song no longer triggers local audio simultaneously — online and local players are properly isolated.  
  YouTube şarkısı başlatıldığında yerel şarkı da çalmıyor artık — çevrimiçi ve yerel oynatıcı tamamen ayrıştırıldı.

### Added / Eklendi
- Separate system notification for online (YouTube) playback with "YouTube Music" album label and streamlined controls (play/pause/stop).  
  Çevrimiçi (YouTube) oynatma için ayrı sistem bildirimi: "YouTube Music" albüm etiketi ve sade kontroller (oynat/durdur/duraklat).
- Auto-download thumbnail when playing a local song; falls back to artist cover image if the song has no YouTube ID or the thumbnail fails.  
  Yerel şarkı çalarken küçük resmi otomatik indirir; YouTube ID'si yoksa veya küçük resim alınamazsa sanatçı kapağını kullanır.
- Artist cover thumbnails are cached and fetched once per artist.  
  Sanatçı kapak resimleri önbelleğe alınır ve her sanatçı için yalnızca bir kez getirilir.

### Changed / Değiştirildi
- Player style cleanup: replaced "Compact" style with "Square" and "Glass" styles for a modern look.  
  Oynatıcı stili güncellendi: "Kompakt" stil kaldırıldı, yerine "Kare" ve "Cam" stilleri eklendi.
- Now Playing screen: removed volume slider for a cleaner layout.  
  Şu Anda Çalan ekranı: daha sade bir düzen için ses kaydırıcısı kaldırıldı.
- Search screen: YouTube loading indicator shows immediately on text input.  
  Arama ekranı: metin girildiğinde YouTube yükleniyor göstergesi anında görünüyor.
- Android home widgets: updated to use gradient backgrounds with consistent margins for a polished appearance.  
  Android ana ekran widget'ları: gradient arka plan ve tutarlı kenar boşlukları ile görsel olarak iyileştirildi.

## [1.2.0] - 2026-05-22

### Added
- Language support — Turkish (Türkçe) and English localization
- Language selection in Settings
- Home screen widget with dynamic playlist and full-height layout
- Adaptive widget layout for 4x1, 4x2, and 4x3+ sizes

### Fixed
- Widget `setSelected(boolean)` crash on Android 12+
- Widget `<View>` divider InflateException on some launchers
- Queue JSON encoding bug in home widget service
- Widget `setColorFilter` guarded for API 29+

## [1.1.12] - 2026-05-22

### Added
- Adaptive player widget layout

## [1.1.11] - 2026-05-22

- Maintenance release

## [1.1.10] - 2026-05-11

### Added
- Redesigned search widget with transparent background
- Accent color support for widgets
- Sliding text animation for long titles

## [1.1.9] - 2026-05-10

### Added
- Changelog modal in settings
- Search widget layout improvements

## [1.1.8] - 2026-01-15

- Release build

## [1.1.7] - 2026-01-15

- Maintenance release

## [1.1.6] - 2025-08-09

### Added
- Animations and multi-select features

## [1.1.5] - 2025-08-07

### Added
- Download notifications and local thumbnail support

## [1.1.4] - 2025-08-05

### Added
- Notification player controls with proper skip/next and play/pause
- MediaKit notification integration

## [1.1.3] - 2025-08-04

- Initial notification integration
