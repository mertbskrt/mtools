# Borç Listesi

Bu dosya, geliştirme oturumlarında bilinçli olarak kapsam dışı bırakılan,
ertelenen ya da gerçek cihaz/sunucu testi bekleyen açık kalemleri takip
eder. Önceki oturumlarda bu liste sadece sohbet içinde ad-hoc olarak
tutuluyordu (numaralama tur tur kaydı) — bu dosya, o dağınık geçmişin
2026-08-28 itibarıyla derlenmiş, tek ve kanonik hâlidir.

**Kural:** Bundan sonra "bu turda değil" kararı verilen her yeni bulgu
buraya da eklenmeli. Bir oturum "borç listesi nedir?" diye sorduğunda
önce bu dosyaya bakılmalı.

---

## Mimari / kod borcu

### 1. `background_service.dart` node-adı çakışması
Ana uygulama tarafında (`proxmox_provider.dart`) node kimliği artık
sunucu+node bileşik anahtarına taşındı (bkz. commit `9249b60`) — iki
farklı Proxmox sunucusu aynı node adını raporlarsa (özellikle muhtemel:
Proxmox kurulum varsayılanı "pve") artık karışmıyorlar. Ama
`background_service.dart` (bildirim motoru arka plan servisi) hâlâ
kendi SharedPreferences tercihlerini (online/offline durumu, son-görülme,
son CPU/mem/disk, görev zaman damgası, bildirim cooldown'ları — ör.
`node_online_state_$nodeName`, `node_last_seen_$nodeName`) çıplak node
adıyla anahtalıyor.
**Neden bu turda değil:** Ayrı bir isolate/mimari (arka plan servisi,
ana uygulamadan bağımsız state yönetimi) kullanıyor — ana uygulamadaki
geçiş deseni (composeNodeId/nodeNameFromId/matchNodeKey) doğrudan
kopyalanamaz, o dosyaya özgü bir adaptasyon gerektiriyor. Kullanıcı
tarafından bir sonraki büyük bakım/hata-tarama turunda **ilk sırada**
ele alınması istendi.

### 2. WOL widget'ında SSH-only cihazlar için spesifik-cihaza deep-link yok
`method:'ssh'` olan bir WOL cihazının widget butonuna dokunulduğunda,
widget genel WOL ekranını açıyor — o cihazı önceden seçili/vurgulu
getirmiyor.
**Neden bu turda değil:** Böyle bir "derin bağlantı" (deep link) kurmak
`home_widget` paketinin URI-tabanlı launch API'sini, `main.dart`'ın
başlangıç rotası işleyişini, `HomeScreen`'in sekme geçişini ve
`WolScreen`'in (sekme önbelleğinde canlı tutulan) "şu cihazı vurgula"
durumunu sonradan enjekte edebilmesini gerektiriyor — dört ayrı katmana
dokunan, kolayca yanlış gidebilecek yeni bir altyapı. Şu anki davranış
(genel ekranı açmak) kullanıcı tarafından kabul edilebilir bulundu.

### 3. Native widget'lar için merkezi `dimens.xml` yok
Dört ana ekran widget'ının (Proxmox/UPS/AdGuard/WOL) her biri kendi
sabit dp değerlerini (padding, ikon boyutu, dokunma hedefi vb.) ayrı
ayrı tekrarlıyor — tutarlı ama merkezi değil. Flutter tarafında
`AppSpace`/`AppRadius` token'larının native karşılığı yok.
**Neden bu turda değil:** Saf kozmetik/hijyen — davranışı etkilemiyor,
düşük öncelikli.

### 4. Widget'ların `previewImage`'ı Android 12 öncesi cihazlarda jenerik
Dört widget da `android:previewLayout` (Android 12+, canlı XML tabanlı,
otomatik güncel) kullanıyor — ama `previewImage` (Android 12 öncesi
fallback) hepsinde sadece `@mipmap/ic_launcher` (uygulama ikonu, gerçek
bir önizleme değil).
**Neden bu turda değil:** Sadece Android 12 öncesi cihazlarda görülen
bir fallback — gerçek statik PNG önizlemeleri üretmek (4 widget × birden
fazla boyut varyantı) opsiyonel bir iyileştirme olarak not edildi, kaç
kullanıcının bu eşiğin altında olduğu bilinmiyor.

### 5. Captive portal senaryosunda DNS-only bağlantı kontrolü yanılabilir
`ConnectivityProvider`/`background_service.dart`'ın "cihazın interneti
var mı" kontrolü saf bir DNS sorgusuna (`InternetAddress.lookup`)
dayanıyor — otel/havaalanı gibi captive-portal WiFi'lerinde DNS
çalışabilir ama gerçek internet erişimi olmayabilir, bu durumda kontrol
yanlış "internet var" sonucu verebilir.
**Neden bu turda değil:** Bilinçli bir tasarım kararı — her kontrolde
bir HTTP isteği de eklemek gecikme/pil maliyeti getiriyor, düşük
öncelikli/nadir bir senaryo için bu maliyet şimdilik gerekçelendirilmedi.

---

## Cihaz / gerçek-sunucu testi bekleyen maddeler

Aşağıdakilerin hepsi kod seviyesinde tamamlandı, `flutter analyze`/
`flutter test`/debug build ile doğrulandı — ama bu sandbox ortamında
gerçek bir Android cihaza veya gerçek Proxmox/AdGuard/UPS sunucusuna
hiç bağlanılamadığı için görsel/canlı-veri doğrulaması yapılamadı.

### 6. Node kimliği (sunucu+node bileşik anahtar) refactoru — gerçek çift-sunucu senaryosu
Bu oturumun en büyük değişikliği (commit `9249b60`): node kimliği artık
host+node bileşik anahtar. Mantık kod incelemesiyle uçtan uca izlendi
ama **gerçekten aynı node adını raporlayan iki ayrı Proxmox sunucusuyla**
hiç test edilmedi — CT/VM işlemlerinin doğru sunucuya gittiği, node
kartlarının çakışmadığı, WOL relay/host-değişikliği eşleşmesinin
gerçek senaryoda çalıştığı gerçek donanımda doğrulanmalı.

### 7. Yedekten geri yükleme özelliği — gerçek Proxmox yedeğiyle test
Yeni "Yedekler" bölümü (depolama detay sayfası) ve düzeltilen
`restoreBackup` API çağrısı, gerçek bir Proxmox sunucusundaki gerçek
bir CT/VM yedeğiyle hiç denenmedi.

### 8. Sistem Özeti bannerı — 3 stil + animasyonlu geçiş görsel doğrulaması
Şerit/Dairesel/Kartlar stilleri ve aralarındaki `AnimatedSize`/
`AnimatedSwitcher` geçişi kod seviyesinde doğru görünüyor ama geçişin
gerçekten akıcı hissettirip hissettirmediği sadece cihazda görülebilir.

### 9. Dört widget'ın boyut geçişleri — gerçek launcher'da parmak jestiyle
Proxmox/UPS/AdGuard/WOL widget'larının kademeli boyut eşikleri
(`onAppWidgetOptionsChanged`) statik olarak doğru görünüyor, ama bazı
launcher'ların (ör. Samsung One UI) resize sırasında bu API'yi
güvenilir tetiklemediği zaten biliniyor — gerçek bir parmak-sürükleme
resize testi hiç yapılmadı.

### 10. Açık temada UPS/AdGuard bayat-veri kontrastı — gerçek sunucu senaryosu
Bağlantı kesintisi sırasında gösterilen "bayat veri" göstergelerinin
açık temadaki renk kontrastı, gerçek bir sunucu kesintisi senaryosuyla
(sadece kod/tema token inceleme ile değil) görsel olarak hiç
doğrulanmadı.

### 11. PIN klavyesi (dairesel tuşlar + onay butonu) — görsel/etkileşim
Uygulama Kilidi PIN kurulumu/doğrulaması klavyesinin yeniden tasarımı
(dairesel tuşlar, ayrı onayla butonu, otomatik-ilerlemenin kaldırılması)
statik analizle doğrulandı ama dokunma hedefleri/hizalama gerçek
cihazda hiç görülmedi.

### 12. Kesinti senaryosu (outage) düzeltmelerinin genel doğrulaması
Bir önceki emülatör turunda (Android 14, API 34) bağlantı-kaybı bildirimi
ve `ForegroundServiceDidNotStartInTimeException` çökmesi gibi gerçek
sorunlar bulunup düzeltildi ve doğrulandı — ama o tur SADECE o ikisine
odaklıydı. Emülatör o zamandan beri "kredi tasarrufu için" devre dışı;
bu oturumdaki sonraki tüm değişiklikler (widget denetimleri, bildirim
motoru denetimi, Sistem/Proxmox hata taraması, node-kimliği refactoru)
hiçbirinin ayrıca canlı bir cihaz/emülatör turu görmedi.
