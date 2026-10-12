Yerel ayrıntılar için: @CLAUDE.local.md

# MTools v2 — Oturum Rehberi

Bu dosya her oturumda okunur ve repoda herkese açıktır. İç ağ adresleri, yayın paneli
adresi, sunucu ve host anahtarı ayrıntıları burada **yazılmaz**; onlar git dışındaki
`CLAUDE.local.md`'de durur. Son güncelleme: 2026-10-12.

## Geliştirme kuralları

- Kodu sıfırdan yeniden yazma, sadece değişen kısmı göster.
- Geçici çözüm üretme, doğru çözümü uygula.
- Her değişikliğin hangi dosya, hangi metot ve hangi satırlarda olduğunu açıkça yaz.
- Modüler ve adım adım ilerle.
- "Bu turda değil" denen her bulgu `DEBT.md`'ye eklenir. Borç listesi sorulursa önce oraya bak.
- Kimlik bilgileri (`MTOOLS_AUTH`, sunucu parolaları, `MTOOLS_APP_KEY`) her oturumda kullanıcıdan alınır,
  hiçbir dosyaya, commit'e ya da hafızaya yazılmaz.
- Sunucuda değişiklik ve yayın yalnızca açık onayla yapılır.
- Bu dosyaya IP, host adı, parmak izi, panel adresi ya da kimlik bilgisi yazılmaz
  (`CLAUDE.local.md`'ye yazılır). Commit'ten önce `git diff` ile kontrol edilir.

## Proje özeti

Flutter (3.41.9, stable) ile yazılmış Android-öncelikli homelab kontrol paneli:
Proxmox VE, AdGuard Home, NUT/UPS, SSH terminal, Wake-on-LAN, 4 ana ekran
widget'ı, arka plan izleme ve bildirimler, uygulama kilidi, Firebase ile
isteğe bağlı cloud sync.

- Paket adı: `com.example.mtools_v2`. compileSdk/targetSdk 36, minSdk 24
  (Flutter varsayılanları, `android/app/build.gradle.kts`).
- Release build R8 ile küçültülüyor (`isMinifyEnabled`, `isShrinkResources`).
  Dart'tan string ile çağrılan drawable'lar `res/raw/keep.xml` ile korunuyor.
- Release imzası `android/key.properties`'ten okunuyor (git'te yok). Dosya yoksa debug
  anahtarına düşüyor. Gerçek yayın APK'sı yalnızca bu makinede derlenmeli.
- Firebase dosyaları (`google-services.json`, `lib/firebase_options.dart`,
  `firebase.json`) git dışı.
- Kod yorumları ve commit mesajları ağırlıklı olarak Türkçe. README, SECURITY ve CHANGELOG
  İngilizce.

## Klasör yapısı

```
lib/
  main.dart                      Firebase init, initBackgroundService(), AppLifecycleListener, Provider ağacı
  core/
    services/                    cloud_sync_service (Firestore), connectivity_provider (DNS tabanlı),
                                 widget_service, user_data_service, security_cleanup_service,
                                 node_sensor_service, quick_auth_gate
    utils/                       connection_target (RFC1918 sınıflandırma), credential_sync
                                 (cloud yapı + local token birleştirme), deliberate_off_store
    theme/, widgets/
  features/
    notifications/               background_service.dart (arka plan isolate'ı, bildirim motoru)
                                 notification_dispatch.dart (cooldown, geçmiş, plugin.show)
                                 notification_provider.dart (UI tarafı ayar/kural, servis start/stop)
                                 notification_rule.dart (NotificationTrigger enum + varsayılanlar)
    proxmox/                     proxmox_service (Dio, API token), proxmox_provider (çoklu sunucu,
                                 composeNodeId/nodeNameFromId/matchNodeKey bileşik node kimliği)
    adguard/, ups/ (NUT TCP), terminal/ (dartssh2 + xterm), wol/
    update/                      update_service, signature_verifier, update_installer, release_history
    dashboard/                   ekranlar (auth, permission, onboarding, settings, about, error log)
  shared/                        alias/tab_config modelleri
android/app/src/main/kotlin/com/example/mtools_v2/   4 widget provider + configure activity'leri
test/                            connection_target, release_notes_lite, proxmox_node_id testleri
scripts/release.sh               APK'yı yayın paneline yükler, isteğe bağlı yayınlar
DEBT.md                          kanonik borç listesi
```

## Ana modüller

| Modül | Dosyalar | Not |
|---|---|---|
| Proxmox | `features/proxmox/*` | API token ile. Node kimliği sunucu+node bileşik anahtar (`9249b60`). CT/VM işlemleri task sonucuyla doğrulanıyor (`c40ea48`). MTools'un kendi işlemleri `tokenid == 'MToolsV2'` ile işaretli, arka planda bildirim üretmiyor. |
| AdGuard | `features/adguard/*` | Birincil/ikincil URL. Arka plan için config `bg_adguard_config` olarak home_widget deposuna yazılıyor. |
| UPS (NUT) | `features/ups/*` | TCP 3493, 8 sn connect timeout. Arka plan için `bg_nut_servers`. |
| SSH Terminal | `features/terminal/*` | dartssh2. Bağlantı hatası bildirimi `dispatchRuleNotification` üzerinden gidiyor. |
| WoL | `features/wol/wol_screen.dart` + `WolWidget*.kt` | UDP veya SSH relay. Relay eşleşmesi host/IP değişikliğine dayanıklı (`becd839`). |
| Cloud sync | `core/services/cloud_sync_service.dart` | Firestore. Sunucu yapısı cloud'da, token'lar sadece local'de (`credential_sync.dart`). |
| Güncelleme | `features/update/*` | Aşağıda "Uygulama içi güncelleme" bölümüne bak. |
| Widget'lar | `core/services/widget_service.dart` + Kotlin provider'lar | home_widget 0.9.x. Veri JSON anahtarları: `proxmox_nodes_json`, `ups_units_json`, `adguard_stats_json`. |

## Bildirim ve arka plan servisi akışı

Paket: `flutter_background_service` 5.x (Android impl. 6.3.1), `flutter_local_notifications` 17.x.

1. **Başlatma.** `main.dart` → `initBackgroundService()` (`background_service.dart:49`).
   Kanallar oluşturulur: `mtools_foreground` (Importance.min), `mtools_alerts` (high),
   `mtools_terminal` (low). `configure()` ayarları: `autoStart: !alreadyRunning`, `isForegroundMode: true`,
   başlık `'MTools'`, içerik `'Sunucularınız arka planda izleniyor'`, id 888, tip **`specialUse`**
   (manifestte `FOREGROUND_SERVICE_SPECIAL_USE` ve `PROPERTY_SPECIAL_USE_FGS_SUBTYPE` var).
   Eklentinin varsayılanı `autoStartOnBoot = true`.
2. **Giriş noktası ve foreground durumu.** Servis, uygulama açılışında foreground olarak başlar ve
   **ömrü boyunca foreground'da kalır**; `setAsForegroundService`/`setAsBackgroundService`
   hiç çağrılmaz (`ea6475e`). `onStart` sırası: `DartPluginRegistrant.ensureInitialized()` →
   `PlatformDispatcher.onError` → plugin initialize (try/catch). Hatalar
   `_logBackgroundError` ile ErrorLogService'e yazılır (aynı yer ve hata tipi için en fazla
   10 dakikada bir).
3. **Lifecycle.** `main.dart` içindeki `AppLifecycleListener(onPause: notifyAppBackgrounded,
   onResume: notifyAppForegrounded)` `invoke('app_background'/'app_foreground')` gönderir ve
   `app_foreground_state` değerini home_widget deposuna yazar. Bu olaylar **yalnızca
   `appInForeground` bayrağını** günceller. `app_background` ayrıca anında bir kontrol turu yapar.
   3 sn'lik güvenlik ağı timer'ı bayrağı home_widget'tan okur; değer yoksa `false` kabul edilir
   (servis boot'ta, uygulama açılmadan başlamışsa).
   Proxmox, NUT ve AdGuard provider'larının 30 sn'lik canlı yoklaması uygulama paused olunca
   durur, resume'da hemen yenileyip devam eder (`core/utils/foreground_polling.dart`,
   `ForegroundPolling` mixin; `f692657`, `9c667d8`). Bildirim için gereken tüm kontroller
   arka plan servisinde provider'lardan bağımsız yapılır: terminal dışındaki 21 tetikleyicinin hepsi.
4. **Döngü.** `Timer.periodic(interval)` (`:232`). Interval yalnızca `onStart`'ta bir kez okunur.
   Her tur `_guardConnectivity` çalışır (DNS: one.one.one.one). Uygulama ön plandaysa
   `_runCheck` atlanır (`:247`). Arka plandaysa `_runCheck` (Proxmox + UPS) ve
   `_refreshAdGuardWidget` çalışır.
5. **Ön planda Proxmox/UPS olay bildirimi üreten başka kod yok.** Ön planda yalnızca
   bağlantı bildirimleri, test bildirimi ve terminal bildirimi üretilir.
6. **Durma.** Lifecycle'a bağlı durma yok. Sadece `NotificationProvider._syncServiceRunningState`
   (`notification_provider.dart:58`): ana anahtar kapalıysa ya da hiç kural açık değilse
   `invoke('stop')`. Açılırsa `startService()`.
7. **Ana isolate ile arka plan isolate'ı arasında veri aktarımı.** shared_preferences arka plan
   motorunda güvenilmez kaldığı için (isolate başına önbellek) ayarlar home_widget deposu
   üzerinden geçer:
   `bg_proxmox_servers` (proxmox_provider.dart:314, :509), `bg_nut_servers`, `bg_adguard_config`,
   `bg_notification_rules` (notification_provider.dart:172), `bg_notif_settings` (:110),
   `bg_deliberate_off_nodes/containers`, `app_foreground_state`.
   Arka plan servisinin kendi durumu (node online/offline, cooldown, `last_task_time_*`,
   `notification_history`) kendi isolate'ının SharedPreferences önbelleğinde tutulur.
8. **Kurallar.** `_parseRules` (`background_service.dart:1638`) ve `NotificationProvider._loadRules`
   `trigger.index` anahtarlı Map ile birleştirir. Gönderim `sendDispatchedNotification`
   (`notification_dispatch.dart:79`) üzerinden yapılır: ana anahtar ve sessiz saat → cooldown → geçmiş → `plugin.show`.
9. **Native eklenti davranışı (6.3.1).** `setForegroundMode` sadece `SecurityException` yakalar.
   Watchdog alarmı tek seferliktir: yalnızca `onStartCommand`, `onDestroy` ve `onTaskRemoved`'da
   kurulur, API 33+ cihazlarda inexact'tır. Servis `START_NOT_STICKY` döner, `onTimeout` yoktur.
   Bu yüzden servis koddaki eski yorumda yazdığı gibi "5 saniyede bir" yeniden başlatılmaz.

**Çözülen teşhis (2026-10-12, `ea6475e`):** "Uygulama kapalıyken bildirim gelmiyor" sorununun
kök nedeni, servisin yalnızca arka plana geçiş anında foreground'a yükseltilmesiydi. Android 12+
bunu reddedebiliyordu; Android 15+'ta da dataSync süre limiti doluyordu. Çözüm: servis kalıcı
foreground, tip specialUse. Ayarlar'a pil optimizasyonu muafiyeti kartı eklendi; muafiyet
watchdog'un arka plandan yeniden başlatabilmesi için de gerekli. **Gerçek cihazda henüz test edilmedi.**

## Bekleyen işler (sıradaki sürüm, muhtemelen 3.4.0+24)

Sıra: A (Sistem ekranı çökmesi, `a235b22`, onaylandı) → B (bildirim çözümü, `ea6475e` + `f692657` +
`aedf6c4` + `9c667d8`, onaylandı) → loader entegrasyonu (`75f1f51`; yükleme
göstergeleri artık `lib/widgets/mtools_loader.dart` → `MToolsLoader`; yeni yüklemelerde
`CircularProgressIndicator` değil bu kullanılır) → **D (iletişim ve geri bildirim, yapıldı,
onay ve cihaz testi bekliyor)**. D'nin kodu: `lib/features/feedback/` (`FeedbackService`,
`FeedbackScreen`, `FeedbackScreen.forError`), Hakkında → Bağlantılar kartı, hata ekranındaki
"Bu hatayı bildir" (`GlobalErrorFallback.onReport` → `main.dart` `_openErrorReport`,
kök navigator anahtarı `core/utils/app_navigator.dart`). Eski kişisel e-posta adresi kodda ve
SECURITY.md'de `contact@mtools.tr` ile değiştirildi. Her adımın sonunda kısa rapor
verilir, kullanıcı onaylamadan sonrakine geçilmez. Hepsi tek sürüm olarak çıkacak.
Sürüm numarası ve notları en sonda konuşulacak.

**D) İletişim ve geri bildirim.** B ve loader bitmeden başlanmaz. Ayrı commit'te yapılır, sonunda rapor verilir.
1. Kod, çeviri dosyaları ve README'deki eski ürün adresleri (kişisel site alanındaki `/mtools` yolu, bkz. `CLAUDE.local.md`), eski e-posta adresleri ve iletişim
   bağlantıları listelenir. Ürünle ilgili olanlar `https://mtools.tr` ve `contact@mtools.tr` olur.
   Kişisel siteye bilerek giden bir bağlantı varsa kullanıcıya sorulur.
2. Ayarlar → Hakkında'ya şunlar eklenir: web sitesi (https://mtools.tr), iletişim (`mailto:contact@mtools.tr`),
   kaynak kod (GitHub), gizlilik (https://mtools.tr/gizlilik/), lisanslar (`showLicensePage`).
3. Ayarlar → "Geri bildirim gönder" ekranı:
   - Tür: Hata bildirimi / Öneri / Soru / Diğer (değerler `hata`, `oneri`, `soru`, `diger`).
   - Ad isteğe bağlı. E-posta zorunlu. Mesaj zorunlu, 10–3000 karakter, sayaçlı.
   - "Hata günlüğünü ekle" kutusu varsayılan olarak kapalı. İşaretlenirse ErrorLogService'teki son 50 kayıt
     metin olarak eklenir, en fazla 15.000 karakter. Kutunun altında
     "Günlükte sunucu adları ve IP adresleri bulunabilir." yazar.
   - İstek: `POST https://mtools.tr/api/uygulama`, `Content-Type: application/json`, başlık `X-MTools-App: <anahtar>`.
     Anahtar bu dosyaya yazılmaz; uygulanırken kullanıcıdan alınır.
     Gövde: `{tur, ad, eposta, mesaj, surum: "3.4.0 (24)", cihaz: "Samsung SM-S918B", android: "14", dil: "tr"|"en", gunluk}`.
     Sürüm `package_info_plus`'tan, cihaz ve Android sürümü `device_info_plus`'tan alınır.
   - Yanıtlar:
     - `{ok:true}` → "Mesajınız alındı. E-posta adresinize bir onay gönderdik."
     - `{ok:false, hata}` → `hata` metni gösterilir.
     - 429 → "Çok fazla deneme yapıldı, lütfen biraz sonra tekrar deneyin."
     - Ağ hatası → "Gönderilemedi. İnternet bağlantınızı kontrol edin ya da contact@mtools.tr adresine yazın."
   - Gönderirken buton pasif olur ve içinde `MToolsLoader(size: 18)` döner. Tüm metinler TR ve EN.
4. `error_fallback.dart`'a "Bu hatayı bildir" butonu eklenir. Buton geri bildirim ekranını şu durumda açar:
   tür=`hata`, günlük kutusu işaretli, mesaj alanında "Ekran: X · Kod: ABC-1234".
   Not: `ErrorWidget` alt ağaçta render edildiği için oradan navigasyon dikkat ister
   (Navigator/Provider bağlamı olmayabilir).
5. Ayrı commit, sonunda rapor.

D kararları (2026-10-12, kullanıcı onayladı):
- **Dil:** Geri bildirim ekranı, uygulamanın geri kalanı gibi sadece Türkçe olacak; metin tablosu
  kurulmayacak. Gövdedeki `dil` alanı cihaz dilinden gelir: Türkçe ise `"tr"`, değilse `"en"`.
  (Yukarıdaki "Tüm metinler TR ve EN" maddesi bununla geçersiz.)
- **Anahtar:** Kodda `const String.fromEnvironment('MTOOLS_APP_KEY')` kullanılır. Değer koda ya da
  repoya girmez. Anahtar boşsa geri bildirim ekranı form yerine "contact@mtools.tr adresine yazın"
  mesajı ve mailto butonu gösterir, uygulama çökmez.

**Tam çeviri desteği (ayrı iş, bu sürümde değil):** Projede `.arb` dosyası, `flutter_localizations`
ve `intl` yok; tüm arayüz sabit Türkçe. TR/EN desteği için `gen-l10n` kurulumu ayrıca ele alınacak.

## SharedPreferences önek notu

`SharedPreferences` her anahtara `flutter.` önekini kendisi ekler. Kodda `'flutter.'` eklemek
diskte `flutter.flutter.x` oluşturur. Bu hata `notification_history` için düzeltildi.
Tek bilinçli istisna `background_service.dart:1552-1557`'deki eski tek-sunucu fallback'i
(`${_p}proxmox_host` vb.). Eski kurulumlardan yükseltme bu anahtarlara bağlı olduğu için dokunma.

## scripts/

- `scripts/release.sh <apk> ["notlar"]`: `MTOOLS_PANEL` (panel adresi, bkz. `CLAUDE.local.md`) ve
  `MTOOLS_AUTH=kullanıcı:parola` ortam değişkenlerini gerektirir; `curl` ve `jq` kullanır.
  1. `POST $PANEL/api/upload` (multipart `apk=`) → `{filename, versionName, versionCode}`.
  2. Not verilmezse burada durur ve yayın panelden yapılır.
  3. Not verilirse `POST $PANEL/api/publish` gönderir: `{filename, version, versionCode, notes}`.
     Panel GitHub release'i oluşturur, imzalı `manifest.json`'u da ekler. Release URL'sini ya da hatayı yazdırır.

## Sürüm ve yayın süreci

1. `pubspec.yaml`'da `version: x.y.z+N` güncellenir. **N her sürümde artar** (şu an `3.3.2+23`).
2. "Bump" commit'i üç dosyaya dokunur (bkz. `8cb1547`, `c619297`):
   - `pubspec.yaml`
   - `CHANGELOG.md`: en üste `## [x.y.z] — YYYY-MM-DD` (em dash) bölümü
   - `lib/features/dashboard/about_screen.dart` → `_releaseNotes` listesi: kısa, **Türkçe**
     cümleler; uygulama içi "yenilikler" bölümü.
3. `flutter build apk --release --dart-define=MTOOLS_APP_KEY=$MTOOLS_APP_KEY` → `build/app/outputs/flutter-apk/app-release.apk`
   (`android/key.properties` gerekir).
4. `MTOOLS_PANEL=<panel adresi> MTOOLS_AUTH=... scripts/release.sh <apk> "<notlar>"`
   (panel adresi `CLAUDE.local.md`'de).
5. Doğrulama (`gh` kurulu değil):
   `curl -s https://api.github.com/repos/mertbskrt/mtools-releases/releases/tags/vX.Y.Z`
   Manifest repo dosyası değil, release asset'idir:
   `https://github.com/mertbskrt/mtools-releases/releases/download/vX.Y.Z/manifest.json`

### Release notu biçimi (GitHub release body = CHANGELOG bölümünün gövdesi)

- Dil **İngilizce**, kullanıcıya dönük, teknik iç ayrıntı yok.
- Başlıklar `### Fixed`, `### New`, gerekirse `### New: <Konu>`, `### Reliability`, `### Design`,
  `### Consistency: <konu>`.
- Maddeler `- ` ile başlar. Her madde geçmiş zamanla başlar ("Fixed …", "Added …") ve önce
  belirtiyi, sonra yeni davranışı anlatır. Gerekirse em dash (—) ile açıklama eklenir.
- 3.3.2'de her madde tek satır; daha eski sürümlerde ~72 sütunda satır kırılmış. Yeni sürümlerde
  tek satır biçimi kullanılır.
- Asset'ler: `mtools-x.y.z.apk`, `manifest.json`, `manifest.json.sig`. Tag biçimi: `vX.Y.Z`.

Son 5 sürüm: v3.3.2 (2026-08-28), v3.3.1 (2026-08-19; CHANGELOG'da 08-17), v3.3.0 (2026-08-16),
v3.2.2 (2026-08-14), v3.2.1 (2026-08-12).

### Uygulama içi güncelleme

- `update_service.dart:21-24`: `releases/latest/download/manifest.json` ve `.sig`.
- `signature_verifier.dart:15`: gömülü Ed25519 public key
  (`+k98A4Q8ZH6APguuahVq7mdCHd8f1cj6oYoGiNpU2yc=`). Manifest imzası doğrulanır.
- Manifest alanları (`update_manifest.dart`): `latestVersion`, `versionCode`, `minVersion`, `apkUrl`,
  `sha256`, `releaseNotes`, `releaseDate`, `mandatory`. İndirilen APK'nın sha256'sı da doğrulanır.
- Sürüm geçmişi ekranı `releases?per_page=100` uç noktasını 1 saat önbellekle okur.

## Yayın ortamı

Yayın paneli kullanıcının kendi ağında çalışır. Adresi, sunucu ayrıntıları ve doğrulama durumu
`CLAUDE.local.md`'dedir.

**Ortam değişkenleri (her oturumda kullanıcıdan alınır, dosyaya yazılmaz):**

| Değişken | Not |
|---|---|
| `MTOOLS_PANEL` | Yayın paneli adresi. `release.sh` bu olmadan çalışmaz (`:?` kontrolü). |
| `MTOOLS_AUTH` | Panel HTTP Basic Auth (`kullanıcı:parola`). |
| `MTOOLS_APP_KEY` | Geri bildirim API'sinin `X-MTools-App` başlığı; derlemede `--dart-define` ile verilir. |

Release build komutu (3.4.0'dan itibaren):
`flutter build apk --release --dart-define=MTOOLS_APP_KEY=$MTOOLS_APP_KEY`
Anahtar verilmeden derlenen APK'da geri bildirim formu yerine mailto seçeneği görünür.

## Git geçmişi (son 40 commit özeti)

- **v3.2.0** (`2e4bc48`): ilk açık kaynak sürüm. Ardından README/SECURITY İngilizceye çevrildi.
- **3.2.1** (`6a371a2`): WoL widget'ı, widget'ta Proxmox sunucu seçimi, cihaz-bağlantı kaybı ayrımı.
- **3.2.2**: widget configure/tema düzeltmeleri, sürüm geçmişi ekranı, WoL gönderim teyidi,
  `ForegroundServiceDidNotStartInTimeException` düzeltmesi (`70f2cc1`).
- **3.3.0** (`580476d`): App Lock, elektrik kesintisi senaryosu, widget yeniden tasarımı.
- **3.3.1** (`c619297`): yeniden giriş korumalı bağlantı kontrolü, markdown release notları,
  "sunucuya ulaşılamıyor" ekranlarının birleştirilmesi, WoL SSH widget düzeltmesi.
- **3.3.2** (`8cb1547`): cooldown kablolama düzeltmeleri, widget düzeltmeleri, Sistem Özeti için 3 stil,
  task tabanlı CT/VM doğrulama, sunucu+node bileşik anahtar, yedekten geri yükleme,
  `DEBT.md`, node-id unit testleri.

## TODO / yarım kalmış yerler

Kodda `TODO`/`FIXME`/`HACK` işareti yok. Yorumlarda belirtilen yarım ya da tutarsız noktalar:

- `background_service.dart` → `_refreshAdGuardWidget`: AdGuard için "tekrar ulaşıldı" bildirimi yok (bilinçli).
- `background_service.dart` → `onStart`: kontrol aralığı yalnızca servis başlarken okunuyor.
  Ayarlardan değiştirilen aralık servis yeniden başlayana kadar uygulanmıyor (ayrı iş, 3.4.0'a girmeyecek).
- `notification_history` iki isolate'tan ayrı önbelleklerle yazılıyor, biri diğerinin
  kaydını ezebilir.
- Eklenti `PARTIAL_WAKE_LOCK`'u `runService()` içinde süresiz alıyor ve hiç bırakmıyor.

## Borç listesi (DEBT.md özeti)

Mimari/kod borcu:
1. **`background_service.dart` node adı çakışması.** Anahtarlar çıplak node adıyla tutuluyor:
   `node_online_state_$nodeName`, `node_last_seen_`, `node_last_cpu/mem/disk/uptime_`,
   `last_task_time_`, `names_refreshed_`, `ct_name_/vm_name_${node}_`, cooldown'lar
   `node_offline_`, `cpu_`, `ram_` vb. Aynı adlı iki node (ör. iki sunucuda da "pve")
   durum, cooldown ve task zaman damgasını paylaşıyor. **Bir sonraki bakım turunda ilk sırada
   ele alınacak.** Not: bu madde DEBT.md'de **#1**. Eski hafıza notu ve kullanıcı ona "#10"
   diyor; DEBT.md'de #10 açık tema kontrastı maddesi.
2. SSH-only WoL cihazı için widget'tan cihaza özel deep link yok.
3. Native widget'lar için merkezi `dimens.xml` yok.
4. Android 12 öncesi widget `previewImage` jenerik.
5. Captive portal'da DNS-only bağlantı kontrolü yanılabilir.

Cihaz ya da gerçek sunucu testi bekleyenler (6–13): bileşik node kimliği (gerçek çift sunucu),
yedekten geri yükleme, Sistem Özeti stilleri, widget resize, açık temada bayat veri kontrastı,
PIN klavyesi, kesinti senaryosu genel doğrulaması (emülatör testleri durduruldu),
task tabanlı doğrulamanın başarısızlık dalı.
