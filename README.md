# MTools

MTools, ev/homelab sunucularınızı (Proxmox, AdGuard Home, NUT/UPS) tek bir
Flutter uygulamasından yönetmenizi sağlayan bir mobil kontrol paneli.
Kendi ağınızdaki cihazları yöneten hobi kullanıcıları ve homelab
meraklıları için yazıldı.

> Bu proje kişisel bir homelab aracıdır; kurumsal/production kullanım için
> test edilmemiştir.

This repository contains source code only. For pre-built, signed APK
releases, see: [mertbskrt/mtools-releases](https://github.com/mertbskrt/mtools-releases).

## Özellikler

- **Proxmox VE yönetimi** — node/VM/container durumu, başlat/durdur/yeniden
  başlat, yeni VM/container oluşturma, disk/CPU/RAM/sıcaklık izleme.
- **AdGuard Home kontrolü** — koruma aç/kapa, filtre listesi yönetimi,
  sorgu istatistikleri.
- **UPS izleme (NUT)** — bağlı UPS cihazlarının durumu, batarya/yük bilgisi.
- **SSH Terminal** — kayıtlı sunuculara doğrudan terminal erişimi.
- **Wake on LAN** — ağdaki cihazları uzaktan uyandırma.
- **Arka plan izleme ve bildirimler** — belirlediğiniz eşiklere göre
  (CPU/RAM/disk/UPS vb.) push bildirimleri, uygulama içi bildirim geçmişi.
- **Uygulama kilidi** — PIN ve/veya biyometrik kilit.
- **Bulut senkronizasyonu (opsiyonel)** — Google hesabınızla giriş yaparak
  sunucu listeleri/ayarları cihazlar arası senkronize edilebilir (Firebase
  Firestore üzerinden — kendi Firebase projenizi bağlamanız gerekir,
  aşağıya bakın).

## Ekran Görüntüleri

| Ana Ekran | Proxmox | Terminal |
|---|---|---|
| _placeholder_ | _placeholder_ | _placeholder_ |

_(Ekran görüntüleri yakında eklenecek.)_

## Kurulum

### Gereksinimler

- Flutter **3.41.9** veya üzeri (stable channel)
- Android Studio / Xcode (platforma göre)
- Bir Firebase projesi (bulut senkronizasyonu ve Google ile giriş için —
  bu adım olmadan uygulama Proxmox/AdGuard/UPS/Terminal/WOL özelliklerini
  yerel modda çalıştırabilir, ancak giriş ekranı ve bulut senkronu
  çalışmaz)

```bash
git clone <bu-repo>
cd mtools_v2
flutter pub get
```

### Kendi Firebase Projenizi Bağlama

This repository does not include `google-services.json`,
`firebase_options.dart`, or `firebase.json` (excluded via `.gitignore`) —
these are specific to each developer's own Firebase project. For an
example of what `firebase.json` looks like, see `firebase.json.example`;
the real file is generated automatically after the steps below.

1. [Firebase Console](https://console.firebase.google.com)'da yeni bir
   proje oluşturun.
2. Projeye bir **Android uygulaması** ekleyin — paket adı olarak
   `android/app/build.gradle.kts` içindeki `applicationId` değerini kullanın.
3. İndirilen `google-services.json` dosyasını `android/app/` klasörüne koyun.
4. [FlutterFire CLI](https://firebase.google.com/docs/flutter/setup)'yi
   kurup proje kökünde çalıştırın:
   ```bash
   dart pub global activate flutterfire_cli
   flutterfire configure
   ```
   Bu komut `lib/firebase_options.dart` dosyasını sizin projenize göre
   otomatik oluşturur.
5. Firebase Console'da **Authentication → Google** sağlayıcısını
   etkinleştirin.
6. Firestore'u oluşturun ve güvenlik kurallarını gözden geçirin (bu
   uygulama kullanıcı başına ayar/sunucu-listesi senkronu için
   `users/{uid}` altında okuma/yazma yapar — kuralları buna göre
   kısıtlamanız önerilir).

### Çalıştırma

```bash
flutter run
```

## Ağ / Güvenlik Notu

MTools, yönettiğiniz sunuculara (Proxmox API, AdGuard Home API, SSH, NUT)
**doğrudan yerel ağınız üzerinden** bağlanır — bu trafik uygulamanın kendi
sunucusundan geçmez. Proxmox/AdGuard bağlantıları için kendi sunucularınızda
geçerli bir TLS sertifikası kullanmanız önerilir; SSH bağlantıları
standart SSH protokolüyle şifrelenir. Kimlik bilgilerinin nasıl
saklandığı ve güvenlik bulgusu bildirme adresi için bkz.
[SECURITY.md](SECURITY.md).

## Yol Haritası

- **`flutter_secure_storage` migrasyonu** — kimlik bilgileri şu an
  standart SharedPreferences'ta duruyor (uygulamaya özel, düz metin);
  işletim sisteminin donanım destekli şifrelemesini kullanan bir depoya
  taşınması planlanıyor.
- **İstemci tarafı şifreli bulut senkronu** — şu an kimlik bilgileri
  buluta hiç senkronize edilmiyor (sadece sunucu yapısı gider); ileride
  kimlik bilgilerinin de, sunucuda hiç düz metin görünmeyecek şekilde
  istemci tarafında şifrelenip senkronize edilmesi değerlendirilebilir.

## Lisans

MIT — bkz. [LICENSE](LICENSE).
