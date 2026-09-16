# Changelog

## [1.3.5] - 2026-09-16

### Fixed / Düzeltildi
- Playing songs online no longer gets stuck when your connection restricts large downloads; playback uses a smarter streaming method that works even on restricted networks.
  İnternet bağlantınız büyük indirmeleri kısıtladığında çevrimiçi şarkı çalma takılmıyor artık; oynatma, kısıtlı ağlarda bile çalışan daha akıllı bir yöntem kullanıyor.

### Improved / Geliştirildi
- Downloads are faster: each song is fetched in 6 parts at the same time instead of one after another.
  İndirmeler daha hızlı: her şarkı tek tek yerine aynı anda 6 parça halinde indiriliyor.
- Artist pictures are remembered on your device. Once a picture loads, it shows instantly next time — no repeated downloads.
  Sanatçı fotoğrafları cihazınızda saklanıyor. Bir kez yüklendikten sonra bir daha ki sefere anında gösteriliyor — tekrar tekrar indirilmiyor.

## [1.3.4] - 2026-09-15

### Fixed / Düzeltildi
- Fixed audio downloads stopping at ~1 MiB on networks where YouTube enforces a range cap on unsigned DASH streams; downloads now use VOD HLS (m3u8) which bypasses the limitation entirely.
  YouTube DASH akışlarının imzasız istekleri 1 MiB civarında kısıtlayan ağlarda ses indirmelerin takılması düzeltildi; artık HLS (m3u8) kullanılarak bu sınırlama tamamen aşılıyor.
- Bumped `youtube_explode_dart` to ^3.1.0 and applied safe dependency updates within current majors.
  `youtube_explode_dart` ^3.1.0'a güncellendi ve ana major sınırlar içinde güvenli bağımlılık güncellemeleri uygulandı.

## [1.3.3] - 2026-09-06

### Changed / Değiştirildi
- Android build toolchain modernized: Gradle 9.1.0, Android Gradle Plugin 9.0.1, Kotlin 2.3.20.  
  Android derleme araçları güncellendi: Gradle 9.1.0, Android Gradle Plugin 9.0.1, Kotlin 2.3.20.
- Migrated all deprecated Flutter APIs to their modern replacements (RadioGroup, ReorderableListView.onReorderItem, PopScope, platformDispatcher, Color.toARGB32, Color.withValues).  
  Kullanımdan kaldırılan Flutter API'leri modern karşılıklarıyla değiştirildi (RadioGroup, ReorderableListView.onReorderItem, PopScope, platformDispatcher, Color.toARGB32, Color.withValues).
- Full static-analysis cleanup: 196 analyzer issues resolved down to zero.  
  Statik analiz temizliği tamamlandı: 196 analizci sorunu sıfıra indirildi.

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
