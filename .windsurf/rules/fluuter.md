---
trigger: always_on
---

# Flutter Proje Standartları

## 1. Resmî Dokümantasyon ve Kaynaklar
Aşağıdaki siteler her zaman referans alınmalıdır:
- [Flutter resmi dokümantasyonu](https://docs.flutter.dev)
- [Dart resmi dokümantasyonu](https://dart.dev/guides)
- [pub.dev paket deposu](https://pub.dev)
- [Flutter API referansı](https://api.flutter.dev)
- [Material Design rehberi](https://m3.material.io)
- [Effective Dart rehberi](https://dart.dev/guides/language/effective-dart)

## 2. Proje Dosya Yapısı

### Ana Yapı
```
lib/
 ├── main.dart
 ├── core/
 │   ├── constants/
 │   ├── utils/
 │   ├── services/
 │   └── theme/
 ├── models/
 ├── providers/
 ├── screens/
 │   ├── home/
 │   ├── settings/
 │   ├── profile/
 │   └── ...
 ├── widgets/
 ├── routes/
 └── localization/
```

### Açıklama
- **core/**: Temel yapılar (tema, sabitler, servisler, yardımcı fonksiyonlar)
- **models/**: Veri modelleri
- **providers/**: State management dosyaları
- **screens/**: Uygulama sayfaları
- **widgets/**: Tekrar kullanılabilir bileşenler
- **routes/**: Navigasyon yönetimi
- **localization/**: Çoklu dil desteği
- **assets/**: Görseller, ikonlar, çeviri dosyaları

## 3. İsimlendirme Kuralları

### Dosya ve Klasörler
- snake_case: `user_profile_screen.dart`

### Sınıf, Enum, Extension
- PascalCase: `UserProfileScreen`

### Değişken, Fonksiyon, Metod
- camelCase: `playAudio()`, `fetchUserData()`

### Sabitler
- UPPER_SNAKE_CASE: `API_BASE_URL`

## 4. Kod Organizasyonu

- Her widget ayrı dosyada olmalı.
- build() fonksiyonu sade tutulmalı.
- Stateless ve Stateful gerekliliğe göre kullanılmalı.
- Servisler `services/` içinde, tek sorumluluğa sahip olmalı.
- Hatalar merkezi yönetilmeli.

## 5. Performans Kuralları

- `const` kullan.
- Uzun listelerde `ListView.builder` kullan.
- Ağ çağrıları try-catch ile yönet.
- dispose() içinde tüm controller ve listener’lar kapatılmalı.

## 6. Stil ve Tema Yönetimi

- Tema `theme/` altında.
- Dark ve Light temalar ayrı.
- Widget içinde doğrudan renk kullanılmamalı.

## 7. Test Kuralları

- Her servis ve provider test edilmeli.
- Widget testleri temel ekranları kapsamalı.
- Test yapısı:
```
test/
 ├── models/
 ├── providers/
 ├── services/
 └── widgets/
```

## 8. Linter ve Formatlama

- `flutter_lints` eklenmeli.
- `analysis_options.yaml` kullanılmalı.
- Satır uzunluğu 100 karakteri geçmemeli.


## 10. UI/UX ve Material Kuralları

- Material 3 standardı kullanılmalı.
- Responsive yapı `LayoutBuilder` veya `MediaQuery` ile sağlanmalı.

## 11. Dokümantasyon ve README

- Her modül doc-comment içermeli.
- Proje kök dizininde:
  - README.md
