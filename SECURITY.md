# Güvenlik

MTools kişisel bir homelab aracıdır. Bu belge, hangi verinin nerede
saklandığını ve bir güvenlik sorunu bulursanız ne yapmanız gerektiğini
dürüstçe anlatır.

## Kimlik bilgileri nerede saklanır

Proxmox API token'ları, SSH şifreleri, AdGuard Home ve NUT/UPS kullanıcı
adı-şifreleri **sadece cihazınızda**, standart Android SharedPreferences
üzerinde saklanır — düz metin olarak, uygulamaya özel (diğer uygulamaların
erişemediği) depoda. Bu veriler **buluta senkronize edilmez**: Google ile
giriş yaptığınızda cihazlar arası senkronize olan tek şey sunucu *yapısı*
(isim, host, port, URL) — şifre/token alanları hiçbir zaman Firestore'a
yazılmaz.

`flutter_secure_storage` (işletim sisteminin donanım destekli
şifrelemesini kullanan bir depo) henüz kullanılmıyor — bu, bilinen bir
yol haritası maddesi (bkz. README).

## Bulut senkronu

Google hesabınızla giriş yaptığınızda, Firestore'daki `users/{uid}`
dokümanınıza sadece şu veriler yazılır: sunucu yapısı (kimlik bilgisi
hariç), tema tercihi, sekme düzeni, node sıralaması, bildirim kuralları,
Wake-on-LAN cihaz listesi. Firestore erişimi **uid bazlı kilitlidir** —
her kullanıcı sadece kendi dokümanını okuyup yazabilir.

## Bir güvenlik sorunu mu buldunuz?

Lütfen bir GitHub issue açmak yerine doğrudan
**mertbaskurt14@gmail.com** adresine yazın. Elinizden geldiğince ayrıntı
verin (adımlar, etkilenen sürüm) — makul bir sürede yanıt vermeye
çalışacağım.
