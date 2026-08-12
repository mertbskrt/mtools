import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:home_widget/home_widget.dart';
import '../proxmox/proxmox_service.dart';
import '../ups/nut_service.dart';
import '../adguard/adguard_service.dart';
import '../dashboard/error_log_service.dart';
import 'notification_rule.dart';

// ─── Proxmox task type sabitleri ──────────────────────────────────────────────
// vzstart: normal start, vzrestore: backup'tan başlatma
const _ctStartTypes = {'vzstart', 'vzrestore'};
// vzstop, vzshutdown: normal/graceful durdurma
const _ctStopTypes = {'vzstop', 'vzshutdown'};
const _ctRestartTypes = {'vzreboot'};

// qmstart: normal start, qmrestore: backup'tan başlatma, qmcreate: klonlama/oluşturma
const _vmStartTypes = {'qmstart', 'qmrestore', 'qmcreate'};
// qmstop, qmshutdown: normal/graceful durdurma
const _vmStopTypes = {'qmstop', 'qmshutdown'};
const _vmRestartTypes = {'qmreboot'};

const _mtoolsTokenId = 'MToolsV2';
const _p = 'flutter.';

/// Tüm bildirimlerde (uyarılar, terminal, test) kullanılan tek, sabit
/// Android bildirim rengi (status bar ikon tonu) — kullanıcının seçtiği
/// uygulama-içi temadan bağımsız, marka kimliği için sabit tutuluyor.
const kNotificationAccent = Color(0xFF4E9C8C);

/// Bildirim gövdelerindeki standart "HH:mm" damgası — tek yerden üretiliyor
/// ki tüm bildirim tipleri aynı formatı kullansın.
String hhmm(DateTime dt) =>
    '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

// Telefonun ağ arayüzü değişimi (ör. WiFi → mobil veri) gibi anlık kesintiler
// de getNodes()'u sunucu gerçekten çökmüş gibi patlatabiliyor. Tek hatada
// hemen alarm vermek yerine art arda en az bu kadar başarısız deneme
// bekliyoruz (poll aralığı ~30 sn olduğundan false-positive penceresi ~1
// tur ile sınırlanıyor, gerçek kesinti de hâlâ hızlı yakalanıyor).
const _kConsecutiveFailuresForOffline = 2;

// ─────────────────────────────────────────────
// Servis başlatıcı
// ─────────────────────────────────────────────

Future<void> initBackgroundService() async {
  final service = FlutterBackgroundService();

  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'mtools_foreground',
    'MTools Monitör',
    description: 'Proxmox arka plan izleme servisi',
    importance: Importance.min,
    showBadge: false,
    playSound: false,
    enableVibration: false,
    enableLights: false,
  );

  // Gerçek CT/VM/node/UPS olay bildirimleri bu kanalı kullanıyor (bkz.
  // notify() içindeki plugin.show() çağrısı) — bu kanal daha önce hiç
  // oluşturulmamıştı, Android 8+'ta oluşturulmamış bir kanala bildirim
  // göndermek sessizce hiçbir şey yapmıyor. Bildirimlerin hiç gelmemesinin
  // kök nedeni buydu.
  const alertsChannel = AndroidNotificationChannel(
    'mtools_alerts',
    'MTools Uyarılar',
    description: 'Proxmox sistem uyarıları',
    importance: Importance.high,
  );

  // Terminal ekranı bağlantı/bağlantı-kesme bildirimleri için — bu kanal da
  // aynı sebeple (hiç oluşturulmamıştı) sessizce düşüyordu.
  const terminalChannel = AndroidNotificationChannel(
    'mtools_terminal',
    'Terminal',
    description: 'SSH bağlantı durumu bildirimleri',
    importance: Importance.low,
  );

  final plugin = FlutterLocalNotificationsPlugin();
  final androidPlugin = plugin.resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>();
  await androidPlugin?.createNotificationChannel(channel);
  await androidPlugin?.createNotificationChannel(alertsChannel);
  await androidPlugin?.createNotificationChannel(terminalChannel);

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      // Servis SADECE burada, uygulama açılışında başlatılır — Android'in
      // yeni bir foreground service başlatmaya izin verdiği tek güvenli an
      // budur. Bir daha asla start/stop edilmez (aşağıya bakınız).
      autoStart: true,
      isForegroundMode: true,
      notificationChannelId: 'mtools_foreground',
      // Tek satır, açıklama yok — mümkün olan en silik metin. Android,
      // foreground service bildirimini asla tamamen gizlemeye izin
      // vermiyor (OS şartı); FOREGROUND_SERVICE_IMMEDIATE/DEFERRED ayrımı
      // da sadece birkaç saniyelik kısa görevler için OS'in kendiliğinden
      // uyguladığı bir optimizasyon — sürekli çalışan bu servis için
      // geçerli değil ve flutter_background_service üzerinden manuel
      // kontrolü yok.
      initialNotificationTitle: 'MTools arka planda',
      initialNotificationContent: '',
      foregroundServiceNotificationId: 888,
      foregroundServiceTypes: [AndroidForegroundType.dataSync],
    ),
    iosConfiguration: IosConfiguration(
      autoStart: true,
      onForeground: onStart,
    ),
  );
}

// ─────────────────────────────────────────────
// Uygulama ön plan/arka plan geçişleri (bkz. main.dart)
// ─────────────────────────────────────────────
//
// ÖNEMLİ — önceki sürümde burada `startService()`/`invoke('stop')` ile
// servis her ön/arka plan geçişinde durdurulup yeniden başlatılıyordu.
// Android 8+ (özellikle 12+), UYGULAMA GÖRÜNÜR DEĞİLKEN yeni bir foreground
// service başlatılmasını kısıtlıyor — yani tam da `onPause` anında
// `startService()` çağırmak, Android'in reddettiği senaryonun ta kendisi.
// Bu, hata hiçbir yere loglanmadan sessizce başarısız oluyordu; uygulama
// kapalıyken hiç bildirim gelmemesinin gerçek sebebi buydu.
//
// Doğru çözüm: servis yalnızca `initBackgroundService()` içinde, uygulama
// açılışında (kısıtlamasız an) BİR KEZ başlatılır ve süreç yaşadığı sürece
// hiç durdurulmaz. Ön plan/arka plan geçişlerinde yalnızca zaten çalışan
// servisin foreground/background MODU değiştirilir (`setAsForegroundService`
// / `setAsBackgroundService`) — bu, halihazırda çalışan bir servis üzerinde
// çağrılan bir yöntemdir, yeni servis başlatmaz, dolayısıyla Android'in
// arka plandan servis başlatma kısıtlamasına hiç takılmaz.

/// Uygulama arka plana atıldığında çağrılır: servis ön plan moduna geçer
/// (kalıcı bildirim görünür olur) ve normal aralıklı kontrolüne devam eder.
///
/// invoke() ile anlık bir olay gönderiliyor (hızlı yol) AMA bu, ana
/// uygulama ile arka plan servisinin AYRI FlutterEngine'leri arasında bir
/// mesaj — bu oturumda başka yerlerde (sunucu ayarları, bildirim
/// tercihleri) defalarca görüldüğü gibi bu tür anlık mesajlaşma bazen
/// güvenilmez olabiliyor (dinleyici henüz hazır değilken kaybolabiliyor).
/// Bu yüzden durum AYRICA home_widget'ın (tüm oturum boyunca güvenilir
/// çalıştığı kanıtlanmış) deposuna da yazılıyor — periyodik döngü bunu
/// bir güvenlik ağı olarak kontrol edip anlık olay kaybolsa bile en geç
/// bir sonraki turda kendi kendini düzeltiyor (bkz. onStart()).
void notifyAppBackgrounded() {
  FlutterBackgroundService().invoke('app_background');
  HomeWidget.saveWidgetData('app_foreground_state', false);
}

/// Uygulama ön plana döndüğünde çağrılır: servis arka plan moduna geçer
/// (kalıcı bildirim gizlenir) ve kontrolleri durdurur — canlı veri artık
/// yine uygulama içindeki provider'lar tarafından çekiliyor, çift sorgu
/// yapılmasın diye. Bkz. notifyAppBackgrounded() içindeki güvenilirlik notu.
void notifyAppForegrounded() {
  FlutterBackgroundService().invoke('app_foreground');
  HomeWidget.saveWidgetData('app_foreground_state', true);
}

// ─────────────────────────────────────────────
// Entry point
// ─────────────────────────────────────────────

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  final plugin = FlutterLocalNotificationsPlugin();
  await plugin.initialize(const InitializationSettings(
    android: AndroidInitializationSettings('@drawable/ic_notification'),
  ));

  // Servis her zaman uygulama açılışında başlatıldığı için o an uygulama
  // zaten ön plandadır — native taraf servisi oluştururken kalıcı bildirimi
  // otomatik gösterir (kısa bir an görünüp kaybolabilir), burada hemen arka
  // plan moduna alınarak gizlenir. Gerçek gösterim, uygulama fiilen arka
  // plana atıldığında ('app_background' olayında) olur.
  bool appInForeground = true;
  if (service is AndroidServiceInstance) {
    await service.setAsBackgroundService();
  }

  service.on('stop').listen((event) => service.stopSelf());

  service.on('app_foreground').listen((event) async {
    appInForeground = true;
    if (service is AndroidServiceInstance) {
      await service.setAsBackgroundService();
    }
  });

  service.on('app_background').listen((event) async {
    appInForeground = false;
    if (service is AndroidServiceInstance) {
      await service.setAsForegroundService();
    }
    // Arka plana geçildiği an bir kez hemen kontrol et — periyodik
    // zamanlayıcının ilk turunu (en fazla intervalSeconds) beklemeye gerek yok.
    if (await _guardConnectivity(plugin: plugin)) {
      await _runCheck(plugin: plugin);
    }
  });

  final initialSettings = await _loadNotifSettings();
  final intervalSeconds = initialSettings['interval'] as int;

  Timer.periodic(Duration(seconds: intervalSeconds), (_) async {
    // Uygulama ön plandayken canlı ekranlar zaten aynı veriyi çekiyor —
    // burada tekrar sorgulamak hem gereksiz hem de çift bildirime yol açar.
    if (appInForeground) return;
    // Cihazın kendi interneti yoksa hiçbir alt servis (Proxmox/UPS/AdGuard)
    // hiç denenmez — hem gereksiz batarya/veri tüketimini önler hem de her
    // birinin kendi "ulaşılamıyor" bildirimini tek tek atmasını (asıl sorun
    // tek: telefonun bağlantısı) engeller. Bkz. _guardConnectivity.
    if (await _guardConnectivity(plugin: plugin)) {
      await _runCheck(plugin: plugin);
      await _refreshAdGuardWidget(plugin: plugin);
    }
  });

  // Güvenlik ağı: notifyAppForegrounded()/notifyAppBackgrounded()'daki anlık
  // invoke() olayı bir sebeple bu servise ulaşmazsa (ör. dinleyici henüz
  // kaydolmamışken gönderildiyse), kalıcı "Arka planda izleniyor" bildirimi
  // uygulama açıkken bile ekranda takılı kalabiliyordu — kullanıcı elle
  // silmek zorunda kalıyordu. Burada sık aralıklarla (invoke()'tan çok daha
  // güvenilir olan) home_widget deposundaki gerçek durum okunup mevcut
  // durumla karşılaştırılıyor; uyuşmazlık varsa en geç birkaç saniye içinde
  // kendi kendine düzeltiliyor.
  Timer.periodic(const Duration(seconds: 3), (_) async {
    final shouldBeForeground =
        await HomeWidget.getWidgetData<bool>('app_foreground_state') ?? true;
    if (shouldBeForeground == appInForeground) return;
    appInForeground = shouldBeForeground;
    if (service is AndroidServiceInstance) {
      if (appInForeground) {
        await service.setAsBackgroundService();
      } else {
        await service.setAsForegroundService();
      }
    }
  });
}

// ─────────────────────────────────────────────
// Ana kontrol
// ─────────────────────────────────────────────

/// `_runCheck()`'in yerel `notify()` closure'ıyla aynı mantık — Proxmox/UPS
/// dışında (ör. `_refreshAdGuardWidget`) da kullanılabilsin diye üst
/// seviyeye çıkarıldı.
Future<void> _sendNotification(
  FlutterLocalNotificationsPlugin plugin,
  SharedPreferences prefs,
  bool notificationsAllowed,
  List<Map<String, dynamic>> history,
  int id,
  String title,
  String body, {
  String? cooldownKey,
  int cooldownMinutes = 0,
}) async {
  // Bildirimler kapalıysa/sessiz saatlerdeyse veya bu elle widget
  // yenilemesiyse gerçek bildirim gönderilmez — ama widget verisi (bu
  // fonksiyonun dışında) her durumda güncellenir.
  if (!notificationsAllowed) return;
  if (cooldownKey != null && cooldownMinutes > 0) {
    final lastStr = prefs.getString('notif_cooldown_$cooldownKey');
    if (lastStr != null) {
      final last = DateTime.tryParse(lastStr);
      if (last != null &&
          DateTime.now().difference(last).inMinutes < cooldownMinutes) {
        return;
      }
    }
    await prefs.setString(
        'notif_cooldown_$cooldownKey', DateTime.now().toIso8601String());
  }

  history.insert(0, {
    'title': title,
    'body': body,
    'time': DateTime.now().toIso8601String(),
  });
  if (history.length > 100) history.removeLast();

  try {
    await plugin.show(
      id,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'mtools_alerts',
          'MTools Uyarılar',
          channelDescription: 'Proxmox sistem uyarıları',
          importance: Importance.high,
          priority: Priority.high,
          icon: '@drawable/ic_notification',
          color: kNotificationAccent,
        ),
      ),
    );
  } catch (e) {
    debugPrint('[MTools BG] Bildirim gönderilemedi: $e');
    // ErrorLogService bu izolatta boş bir _logs ile başlıyor — önce
    // diskten yükleyip SONRA log() çağırmak, mevcut kayıtları _save()
    // ile ezmemek için gerekli.
    await ErrorLogService().load();
    await ErrorLogService().log(
      type: ErrorLogType.unknown,
      message: 'Bildirim gönderilemedi',
      detail: e.toString(),
    );
  }
}

Future<void> _runCheck({required FlutterLocalNotificationsPlugin plugin}) async {
  final prefs = await SharedPreferences.getInstance();

  // Widget verisi (Proxmox/UPS) HER ZAMAN çekilip güncellenir — bildirim
  // tercihleri (kapalı/sessiz saatler) sadece gerçek PUSH bildirimini
  // kısıtlamalı, widget'ların arka planda güncel kalmasını engellememeli.
  // Bkz. notify() içindeki notificationsAllowed kontrolü.
  final notifSettings = await _loadNotifSettings();
  final notificationsAllowed =
      (notifSettings['serviceEnabled'] as bool) && !_isQuietNow(notifSettings);

  // shared_preferences, bu arka plan servisinin ayrı FlutterEngine'i ile ana
  // uygulama arasında güvenilmez kaldı — ana uygulama burayı yazsa bile bu
  // taraf hep boş görüyordu (aynı process olmasına rağmen). Bu yüzden sunucu
  // konfigürasyonu artık home_widget'ın kendi depolama mekanizmasından
  // okunuyor — tüm oturum boyunca güvenilir çalıştığı kanıtlandı.
  final proxmoxServersRaw =
      await HomeWidget.getWidgetData<String>('bg_proxmox_servers') ?? '';
  final nutServersRaw =
      await HomeWidget.getWidgetData<String>('bg_nut_servers') ?? '';
  final proxmoxServices = await _buildProxmoxServices(prefs, proxmoxServersRaw);
  final nutServices = await _buildNutServices(nutServersRaw);

  if (proxmoxServices.isEmpty && nutServices.isEmpty) return;

  final rulesRaw =
      await HomeWidget.getWidgetData<String>('bg_notification_rules') ?? '';
  final rules = _parseRules(rulesRaw);

  // NOT: SharedPreferences zaten HER anahtara kendi 'flutter.' prefix'ini
  // ekliyor — burada da '_p' eklemek çift prefix'e (flutter.flutter.…) yol
  // açıyordu ve bu yüzden bu turların yazdığı geçmiş, NotificationProvider'ın
  // okuduğu (düz, tek-prefix'li) anahtardan TAMAMEN farklıydı — geçmiş
  // ekrana hiç yansımıyordu. Anahtar artık NotificationProvider ile birebir
  // aynı.
  final historyRaw = prefs.getString('notification_history');
  final List<Map<String, dynamic>> history = historyRaw != null
      ? List<Map<String, dynamic>>.from((jsonDecode(historyRaw) as List)
          .map((e) => Map<String, dynamic>.from(e)))
      : [];

  // Ana ekran widget'ları (App Widget) için — uygulama kapalıyken de
  // Proxmox/UPS widget'larının güncel kalması için burada toplanıp fonksiyon
  // sonunda yazılıyor. AdGuard, bildirim kuralı değerlendirmesi (Proxmox/UPS
  // servisi hiç yoksa erken dönen) bu fonksiyonun dışında, ayrı bir
  // `_refreshAdGuardWidget()` turunda beslenir (bkz. aşağıdaki tanım).
  final widgetNodes = <Map<String, dynamic>>[];
  final widgetUps = <Map<String, dynamic>>[];

  Future<void> notify(
    int id,
    String title,
    String body, {
    String? cooldownKey,
    int cooldownMinutes = 0,
  }) =>
      _sendNotification(plugin, prefs, notificationsAllowed, history, id,
          title, body,
          cooldownKey: cooldownKey, cooldownMinutes: cooldownMinutes);

  // ── PROXMOX ──────────────────────────────────────────────────────────────
  try {
    for (int svcIndex = 0; svcIndex < proxmoxServices.length; svcIndex++) {
      final svc = proxmoxServices[svcIndex];

      final failCountKey = 'proxmox_fail_count_$svcIndex';
      final knownNodesKey = 'proxmox_known_nodes_$svcIndex';

      List<dynamic> nodes;
      try {
        nodes = await svc.getNodes();
      } catch (e) {
        final failCount = (prefs.getInt(failCountKey) ?? 0) + 1;
        await prefs.setInt(failCountKey, failCount);

        // İlk hatada hemen alarm vermiyoruz — bkz. _kConsecutiveFailuresForOffline.
        if (failCount < _kConsecutiveFailuresForOffline) continue;

        // Sadece BU servise ait, son başarılı sorguda görülen node'ları
        // etkile — birden fazla Proxmox sunucusu varken sadece biri
        // kesilirse diğer sağlıklı sunucuların node'ları yanlışlıkla
        // çevrimdışı işaretlenmesin.
        final knownNodes = prefs.getStringList(knownNodesKey) ?? const [];

        for (final nodeName in knownNodes) {
          final wasOnline =
              prefs.getString('node_online_state_$nodeName') != 'offline';
          if (wasOnline) {
            final lastSeen =
                prefs.getString('node_last_seen_$nodeName') ?? 'bilinmiyor';
            final rule = _findRule(rules, NotificationTrigger.nodeOffline);
            if (rule != null && rule.enabled) {
              await notify(6, 'Sunucu Erişilemiyor',
                  '$nodeName · Son erişim: $lastSeen',
                  cooldownKey: 'node_offline_$nodeName', cooldownMinutes: 5);
            }
            await prefs.setString('node_online_state_$nodeName', 'offline');
          }
          // UPS'teki reachable:false deseniyle aynı: sunucuya tamamen
          // ulaşılamadığında widget'ı da besle — aksi halde widgetNodes boş
          // kalır, aşağıdaki isNotEmpty guard'ı hiç çalışmaz ve widget son
          // başarılı turdan kalma haliyle sonsuza dek donuk kalır.
          widgetNodes.add({
            'name': nodeName,
            'online': false,
            'cpu': prefs.getInt('node_last_cpu_$nodeName') ?? 0,
            'mem': prefs.getInt('node_last_mem_$nodeName') ?? 0,
            'disk': prefs.getInt('node_last_disk_$nodeName') ?? 0,
            'uptime': prefs.getInt('node_last_uptime_$nodeName') ?? 0,
          });
        }
        continue;
      }

      // Başarılı çağrı: ardışık hata sayacı sıfırlanır ve bu servise ait
      // güncel node listesi kaydedilir (yukarıdaki catch bloğunun kapsam
      // sınırlaması için). "Tekrar çevrimiçi" bildirimi burada AYRICA
      // tetiklenmiyor — aşağıdaki node döngüsü zaten aynı
      // node_online_state_ değerini okuyup nodeStatus=='online' &&
      // prevState=='offline' olduğunda 'Sunucu Tekrar Çevrimiçi'
      // bildirimini gönderiyor; bu, kesintinin ağ kaynaklı mı yoksa
      // Proxmox'un kendisi mi offline dediği fark etmeksizin işliyor.
      await prefs.setInt(failCountKey, 0);
      await prefs.setStringList(
          knownNodesKey, nodes.map((n) => n['node'] as String).toList());

      for (final node in nodes) {
        final nodeName = node['node'] as String;
        final nodeStatus = (node['status'] ?? 'online') as String;
        final nowStr = hhmm(DateTime.now());

        final prevState =
            prefs.getString('node_online_state_$nodeName') ?? 'online';

        if (nodeStatus == 'offline' && prevState == 'online') {
          final rule = _findRule(rules, NotificationTrigger.nodeOffline);
          if (rule != null && rule.enabled) {
            await notify(6, 'Sunucu Çevrimdışı',
                '$nodeName · Erişilemiyor · $nowStr',
                cooldownKey: 'node_offline_$nodeName');
          }
        }

        if (nodeStatus == 'online' && prevState == 'offline') {
          final rule = _findRule(rules, NotificationTrigger.nodeOnline);
          if (rule != null && rule.enabled) {
            await notify(9, 'Sunucu Tekrar Çevrimiçi',
                '$nodeName · Erişilebilir · $nowStr',
                cooldownKey: 'node_online_$nodeName');
          }
        }

        await prefs.setString('node_online_state_$nodeName', nodeStatus);
        await prefs.setString('node_last_seen_$nodeName', nowStr);

        widgetNodes.add({
          'name': nodeName,
          'online': nodeStatus == 'online',
          'cpu': 0,
          'mem': 0,
        });

        if (nodeStatus == 'offline') continue;

        // ── TASK LOG ─────────────────────────────────────────────────────
        final ctStoppedRule =
            _findRule(rules, NotificationTrigger.containerStopped);
        final ctStartedRule =
            _findRule(rules, NotificationTrigger.containerStarted);
        final vmStoppedRule = _findRule(rules, NotificationTrigger.vmStopped);
        final vmStartedRule = _findRule(rules, NotificationTrigger.vmStarted);

        final anyTaskRule = (ctStoppedRule?.enabled ?? false) ||
            (ctStartedRule?.enabled ?? false) ||
            (vmStoppedRule?.enabled ?? false) ||
            (vmStartedRule?.enabled ?? false);

        if (anyTaskRule) {
          try {
            // ── Önce isimleri güncelle, sonra task'ları işle ──────────────
            // Böylece yeni CT/VM'ler için de doğru isim kullanılır
            await _refreshContainerNames(svc, prefs, nodeName);

            final lastTaskTimeKey = 'last_task_time_$nodeName';

            // İlk çalışmada son 2 dakikayı tara — 60 sn yetmeyebilir
            // (servis 15 sn bekliyor + API gecikmesi)
            final lastTaskTime = prefs.getInt(lastTaskTimeKey) ??
                (DateTime.now().millisecondsSinceEpoch ~/ 1000 - 120);

            final tasks = await svc.getNodeTasks(nodeName, since: lastTaskTime);
            int maxTime = lastTaskTime;

            for (final task in tasks) {
              final starttime = (task['starttime'] as int? ?? 0);
              if (starttime <= lastTaskTime) continue;
              if (starttime > maxTime) maxTime = starttime;

              final type = (task['type'] as String? ?? '').toLowerCase();
              final taskId = task['id'] as String? ?? '';
              final tokenId = task['tokenid'] as String?;
              final status = task['status'] as String? ?? '';

              // MTools kendi yaptığı işlemleri bildirim üretmez
              if (tokenId == _mtoolsTokenId) continue;

              // Proxmox devam eden task'lar için status'u '' (boş) veya
              // "RUNNING" olarak raporlayabiliyor — ikisi de "henüz
              // bitmedi" anlamına gelir. Bu durumu atlayıp tamamlanmayı
              // bekliyoruz; aksi halde örn. bir "vzstart" task'ı daha
              // status=RUNNING iken "Başlatma Başarısız" diye yanlış
              // bildirim üretiliyordu (gerçekte sadece devam ediyordu).
              final endtime = task['endtime'] as int?;
              if (endtime == null || status.isEmpty || status == 'RUNNING') {
                continue;
              }

              final isOK = status == 'OK';
              final taskTime =
                  DateTime.fromMillisecondsSinceEpoch(starttime * 1000);
              final timeStr = hhmm(taskTime);
              // Teknik kimlik bilgisi (kullanıcı/token adı) bildirimde hiç
              // gösterilmez — sadece hedef, kısa detay ve saat.
              final failDetail = !isOK && status.isNotEmpty ? 'Hata: $status' : null;

              // ── Konteyner (LXC) olayları ────────────────────────────────
              if (_ctStopTypes.contains(type) && taskId.isNotEmpty) {
                if (ctStoppedRule != null && ctStoppedRule.enabled) {
                  final name = await _getCTName(prefs, nodeName, taskId);
                  await notify(
                    // base 100 = CT stop — her vmid için benzersiz ID
                    _notifId(svcIndex, 100, int.tryParse(taskId) ?? 0),
                    isOK ? 'Konteyner Durdu' : 'Konteyner Durdurma Başarısız',
                    '$name ($nodeName) · ${failDetail ?? 'Durduruldu'} · $timeStr',
                  );
                }
              }

              if (_ctStartTypes.contains(type) && taskId.isNotEmpty) {
                if (ctStartedRule != null && ctStartedRule.enabled) {
                  final name = await _getCTName(prefs, nodeName, taskId);
                  await notify(
                    // base 200 = CT start — stop'tan ayrı, çakışmaz
                    _notifId(svcIndex, 200, int.tryParse(taskId) ?? 0),
                    isOK ? 'Konteyner Başladı' : 'Konteyner Başlatma Başarısız',
                    '$name ($nodeName) · ${failDetail ?? 'Başlatıldı'} · $timeStr',
                  );
                }
              }

              if (_ctRestartTypes.contains(type) && taskId.isNotEmpty) {
                // Yeniden başlatma → hem stopped hem started kuralına bakar;
                // ikisi de aktifse tek bildirim yeter (restart kendi mesajı)
                final showRestart = (ctStoppedRule?.enabled ?? false) ||
                    (ctStartedRule?.enabled ?? false);
                if (showRestart) {
                  final name = await _getCTName(prefs, nodeName, taskId);
                  await notify(
                    _notifId(svcIndex, 150, int.tryParse(taskId) ?? 0),
                    'Konteyner Yeniden Başlatıldı',
                    '$name ($nodeName) · $timeStr',
                  );
                }
              }

              // ── Sanal Makine (QEMU) olayları ────────────────────────────
              if (_vmStopTypes.contains(type) && taskId.isNotEmpty) {
                if (vmStoppedRule != null && vmStoppedRule.enabled) {
                  final name = await _getVMName(prefs, nodeName, taskId);
                  await notify(
                    // base 300 = VM stop
                    _notifId(svcIndex, 300, int.tryParse(taskId) ?? 0),
                    isOK ? 'Sanal Makine Durdu' : 'VM Durdurma Başarısız',
                    '$name ($nodeName) · ${failDetail ?? 'Durduruldu'} · $timeStr',
                  );
                }
              }

              if (_vmStartTypes.contains(type) && taskId.isNotEmpty) {
                if (vmStartedRule != null && vmStartedRule.enabled) {
                  final name = await _getVMName(prefs, nodeName, taskId);
                  await notify(
                    // base 400 = VM start — stop'tan ayrı
                    _notifId(svcIndex, 400, int.tryParse(taskId) ?? 0),
                    isOK ? 'Sanal Makine Başladı' : 'VM Başlatma Başarısız',
                    '$name ($nodeName) · ${failDetail ?? 'Başlatıldı'} · $timeStr',
                  );
                }
              }

              if (_vmRestartTypes.contains(type) && taskId.isNotEmpty) {
                final showRestart = (vmStoppedRule?.enabled ?? false) ||
                    (vmStartedRule?.enabled ?? false);
                if (showRestart) {
                  final name = await _getVMName(prefs, nodeName, taskId);
                  await notify(
                    _notifId(svcIndex, 350, int.tryParse(taskId) ?? 0),
                    'Sanal Makine Yeniden Başlatıldı',
                    '$name ($nodeName) · $timeStr',
                  );
                }
              }
            }

            await prefs.setInt(lastTaskTimeKey, maxTime);
          } catch (e) {
            // Bilinçli sessiz: bu node'un task log kontrolü başarısız oldu,
            // döngü diğer node'larla devam ediyor — genel bağlantı sorunu
            // zaten yukarıdaki getNodes() kontrolünde ele alınıyor.
            debugPrint('[MTools BG] Task log hatası ($nodeName): $e');
          }
        }

        // ── KAYNAK MONİTORİNG ─────────────────────────────────────────────
        Map<String, dynamic> status;
        try {
          status = await svc.getNodeStatus(nodeName);
        } catch (e) {
          // Bilinçli sessiz: sadece bu node'un kaynak metrikleri bu turda
          // eksik kalır, diğer node'lar etkilenmez.
          debugPrint('[MTools BG] Node status alınamadı ($nodeName): $e');
          continue;
        }

        final widgetMemTotal = (status['memory']?['total'] ?? 1) as int;
        final widgetMemUsed = (status['memory']?['used'] ?? 0) as int;
        final widgetDiskTotal = (status['rootfs']?['total'] ?? 1) as int;
        final widgetDiskUsed = (status['rootfs']?['used'] ?? 0) as int;
        widgetNodes.last['cpu'] = ((status['cpu'] ?? 0) * 100).round();
        widgetNodes.last['mem'] = widgetMemTotal > 0
            ? (widgetMemUsed / widgetMemTotal * 100).round()
            : 0;
        widgetNodes.last['disk'] = widgetDiskTotal > 0
            ? (widgetDiskUsed / widgetDiskTotal * 100).round()
            : 0;
        widgetNodes.last['uptime'] = (status['uptime'] ?? 0) as int;

        // Bağlantı tamamen koptuğunda (yukarıdaki knownNodes bloğu) widget'ı
        // son bilinen değerlerle besleyebilmek için burada ayrıca kalıcı
        // hale getiriliyor — bkz. UPS'teki ups_bg_last_charge_ deseni.
        await prefs.setInt('node_last_cpu_$nodeName', widgetNodes.last['cpu'] as int);
        await prefs.setInt('node_last_mem_$nodeName', widgetNodes.last['mem'] as int);
        await prefs.setInt('node_last_disk_$nodeName', widgetNodes.last['disk'] as int);
        await prefs.setInt('node_last_uptime_$nodeName', widgetNodes.last['uptime'] as int);

        final cpuRule = _findRule(rules, NotificationTrigger.cpuHigh);
        if (cpuRule != null && cpuRule.enabled) {
          final cpu = ((status['cpu'] ?? 0) * 100).toDouble();
          if (cpu >= cpuRule.threshold) {
            await notify(1, 'Yüksek CPU',
                '$nodeName · %${cpu.toStringAsFixed(0)} (eşik %${cpuRule.threshold.toInt()}) · ${hhmm(DateTime.now())}',
                cooldownKey: 'cpu_$nodeName',
                cooldownMinutes: cpuRule.cooldownMinutes);
          }
        }

        final ramRule = _findRule(rules, NotificationTrigger.ramHigh);
        if (ramRule != null && ramRule.enabled) {
          final memTotal = (status['memory']?['total'] ?? 1) as int;
          final memUsed = (status['memory']?['used'] ?? 0) as int;
          final ram = memTotal > 0 ? memUsed / memTotal * 100 : 0.0;
          if (ram >= ramRule.threshold) {
            await notify(2, 'Yüksek RAM',
                '$nodeName · %${ram.toStringAsFixed(0)} (eşik %${ramRule.threshold.toInt()}) · ${hhmm(DateTime.now())}',
                cooldownKey: 'ram_$nodeName',
                cooldownMinutes: ramRule.cooldownMinutes);
          }
        }

        final swapRule = _findRule(rules, NotificationTrigger.swapHigh);
        if (swapRule != null && swapRule.enabled) {
          final swapTotal = (status['swap']?['total'] ?? 0) as int;
          final swapUsed = (status['swap']?['used'] ?? 0) as int;
          if (swapTotal > 0) {
            final swap = swapUsed / swapTotal * 100;
            if (swap >= swapRule.threshold) {
              await notify(7, 'Yüksek Swap',
                  '$nodeName · %${swap.toStringAsFixed(0)} (eşik %${swapRule.threshold.toInt()}) · ${hhmm(DateTime.now())}',
                  cooldownKey: 'swap_$nodeName',
                  cooldownMinutes: swapRule.cooldownMinutes);
            }
          }
        }

        final diskUsageRule = _findRule(rules, NotificationTrigger.diskUsage);
        if (diskUsageRule != null && diskUsageRule.enabled) {
          final rootFs = status['rootfs'];
          if (rootFs != null) {
            final total = (rootFs['total'] ?? 1) as int;
            final used = (rootFs['used'] ?? 0) as int;
            final usage = total > 0 ? used / total * 100 : 0.0;
            if (usage >= diskUsageRule.threshold) {
              await notify(8, 'Yüksek Disk Kullanımı',
                  '$nodeName · %${usage.toStringAsFixed(0)} (eşik %${diskUsageRule.threshold.toInt()}) · ${hhmm(DateTime.now())}',
                  cooldownKey: 'disk_usage_$nodeName',
                  cooldownMinutes: diskUsageRule.cooldownMinutes);
            }
          }
        }

        final diskTempRule = _findRule(rules, NotificationTrigger.diskTemp);
        if (diskTempRule != null &&
            diskTempRule.enabled &&
            _shouldCheckDiskTemp(prefs)) {
          try {
            final disks = await svc.getNodeDisks(nodeName);
            for (final disk in disks) {
              final devpath = disk['devpath'] ?? '';
              if (devpath.isEmpty) continue;
              final smartData = await svc.getDiskSmart(nodeName, devpath);
              final temp = _parseDiskTemp(smartData);
              if (temp != null && temp >= diskTempRule.threshold) {
                await notify(3, 'Yüksek Disk Sıcaklığı',
                    '$devpath · $temp°C (eşik ${diskTempRule.threshold.toInt()}°C) · ${hhmm(DateTime.now())}',
                    cooldownKey: 'disk_temp_${nodeName}_$devpath',
                    cooldownMinutes: diskTempRule.cooldownMinutes);
              }
            }
          } catch (e) {
            // Bilinçli sessiz: sadece bu node'un disk sıcaklık kontrolü bu
            // turda atlanır, diğer node'lar/servisler etkilenmez.
            debugPrint('[MTools BG] Disk sıcaklık hatası ($nodeName): $e');
          }
          await prefs.setString(
              'last_disk_temp_check', DateTime.now().toIso8601String());
        }
      }
    }
  } catch (e) {
    // Bilinçli sessiz: döngü içi her adımın kendi catch'i zaten var — bu
    // dış katman sadece beklenmeyen bir istisnanın tüm turu düşürmesini önler.
    debugPrint('[MTools BG] Proxmox genel hata: $e');
  }

  // ── UPS ──────────────────────────────────────────────────────────────────
  try {
    for (int svcIndex = 0; svcIndex < nutServices.length; svcIndex++) {
      final nutSvc = nutServices[svcIndex];
      final failCountKey = 'nut_fail_count_$svcIndex';
      final knownUnitsKey = 'nut_known_units_$svcIndex';

      List<String> upsList;
      try {
        upsList = await nutSvc.listUps();
      } catch (e) {
        // Proxmox'taki knownNodes deseniyle aynı: NUT sunucusuna (host'un
        // kendisi mi yoksa sadece NUT servisi mi kapalı ayırt edilemiyor —
        // ikisi de aynı soket hatasını üretiyor) hiç ulaşılamadığında,
        // önceki turda bilinen birimler tek tek "ulaşılamıyor" işaretlenir.
        // Tek bir kesinti false-positive üretmesin diye ardışık başarısızlık
        // sayacı kullanılıyor (bkz. _kConsecutiveFailuresForOffline).
        debugPrint('[MTools BG] NUT listesi alınamadı: $e');
        final failCount = (prefs.getInt(failCountKey) ?? 0) + 1;
        await prefs.setInt(failCountKey, failCount);
        if (failCount < _kConsecutiveFailuresForOffline) continue;

        final knownUnits = prefs.getStringList(knownUnitsKey) ?? const [];
        for (final unitName in knownUnits) {
          final upsKey = '${nutSvc.host}_${nutSvc.port}_$unitName';
          final wasReachable =
              prefs.getString('ups_bg_reachable_$upsKey') != 'false';
          if (wasReachable) {
            final rule =
                _findRule(rules, NotificationTrigger.upsUnreachable);
            if (rule != null && rule.enabled) {
              await notify(506, 'UPS\'e Ulaşılamıyor',
                  '$unitName · Sunucuya bağlanılamıyor · ${hhmm(DateTime.now())}',
                  cooldownKey: 'ups_unreachable_$upsKey',
                  cooldownMinutes: rule.cooldownMinutes);
            }
            await prefs.setString('ups_bg_reachable_$upsKey', 'false');
          }
          // Widget'ın "veri bayat/erişilemiyor" gösterebilmesi için — bkz.
          // ana ekran widget'ı güncelleme bloğu, aşağıdaki isNotEmpty guard'ı
          // artık bu girişler sayesinde de tetiklenir. Son bilinen sayısal
          // değerler (varsa) korunuyor ki widget "%0" gibi yanlış bir şey
          // göstermesin — sadece "bağlantı yok" bayrağı yeni bilgi.
          widgetUps.add({
            'name': unitName,
            'reachable': false,
            'charge': prefs.getInt('ups_bg_last_charge_$upsKey') ?? 0,
            'onBattery': prefs.getBool('ups_bg_last_onbattery_$upsKey') ?? false,
          });
        }
        continue;
      }

      await prefs.setInt(failCountKey, 0);
      await prefs.setStringList(knownUnitsKey, upsList);

      for (final upsName in upsList) {
        final upsKey = '${nutSvc.host}_${nutSvc.port}_$upsName';
        Map<String, String> vars;
        try {
          vars = await nutSvc.getUpsVars(upsName);
        } catch (e) {
          // NUT sunucusunun kendisi yanıt verdi (listUps() başarılı) ama bu
          // BİRİMİN sorgusu başarısız — aynı "ulaşılamıyor" muamelesi, tek
          // birime özel, sunucu genelini etkilemez.
          debugPrint('[MTools BG] NUT vars alınamadı ($upsName): $e');
          final wasReachable =
              prefs.getString('ups_bg_reachable_$upsKey') != 'false';
          if (wasReachable) {
            final rule =
                _findRule(rules, NotificationTrigger.upsUnreachable);
            if (rule != null && rule.enabled) {
              await notify(506, 'UPS\'e Ulaşılamıyor',
                  '$upsName · Sunucuya bağlanılamıyor · ${hhmm(DateTime.now())}',
                  cooldownKey: 'ups_unreachable_$upsKey',
                  cooldownMinutes: rule.cooldownMinutes);
            }
            await prefs.setString('ups_bg_reachable_$upsKey', 'false');
          }
          widgetUps.add({
            'name': upsName,
            'reachable': false,
            'charge': prefs.getInt('ups_bg_last_charge_$upsKey') ?? 0,
            'onBattery': prefs.getBool('ups_bg_last_onbattery_$upsKey') ?? false,
          });
          continue;
        }

        // Bu birim başarıyla yanıt verdi — daha önce "ulaşılamıyor"
        // işaretlenmişse şimdi geri döndüğünü bildir (nodeOnline deseniyle
        // simetrik).
        if (prefs.getString('ups_bg_reachable_$upsKey') == 'false') {
          final reconnectRule =
              _findRule(rules, NotificationTrigger.upsUnreachable);
          if (reconnectRule != null && reconnectRule.enabled) {
            await notify(507, 'UPS\'e Yeniden Ulaşıldı',
                '$upsName · Bağlantı geri geldi · ${hhmm(DateTime.now())}',
                cooldownKey: 'ups_reachable_$upsKey', cooldownMinutes: 0);
          }
        }
        await prefs.setString('ups_bg_reachable_$upsKey', 'true');

        final upsStatus = vars['ups.status'] ?? '';
        final batteryCharge =
            double.tryParse(vars['battery.charge'] ?? '0') ?? 0;
        final upsLoad = double.tryParse(vars['ups.load'] ?? '0') ?? 0;
        final upsTemp = double.tryParse(vars['ups.temperature'] ?? '0') ?? 0;
        final runtimeSec = int.tryParse(vars['battery.runtime'] ?? '0') ?? 0;
        final runtimeMin = runtimeSec ~/ 60;

        // UpsData, foreground'daki NutProvider'ın widget'a yazdığı tam
        // şemayla (runtimeLabel/load/temperature/voltage/statusLabel — bkz.
        // WidgetService.updateUps) aynı alanları üretmek için burada da
        // kullanılıyor. Bu alanlar eksik bırakılırsa uygulama kapalıyken
        // arka plan servisi widget'ı güncellediğinde büyük/detaylı görünüm
        // sessizce yük/voltaj/sıcaklık/durum bilgisini kaybediyordu.
        final upsData =
            UpsData(name: upsName, vars: vars, updatedAt: DateTime.now());

        widgetUps.add({
          'name': upsName,
          'reachable': true,
          'charge': batteryCharge.round(),
          'onBattery': upsStatus.toUpperCase().contains('OB'),
          'runtimeLabel': upsData.runtimeLabel,
          'load': upsLoad.round(),
          'temperature': upsTemp.round(),
          'voltage': upsData.batteryVoltage,
          'statusLabel': upsData.statusLabel,
        });

        // Durum her zaman izlenir (hangi kural açık olursa olsun) — aksi
        // halde ör. sadece "Şebekeye Döndü" açıkken "Bataryaya Geçti" kapalı
        // olsaydı, geçiş durumu hiç güncellenmediği için "Şebekeye Döndü"
        // de asla doğru tetiklenemezdi.
        final lastStatus = prefs.getString('ups_bg_status_$upsKey') ?? '';
        final isOnBattery = upsStatus.toUpperCase().contains('OB');
        final wasOnBattery = lastStatus.toUpperCase().contains('OB');

        // Bağlantı koptuğunda widget'ta "%0" gibi yanlış bir değer yerine
        // son bilinen değeri gösterebilmek için ayrıca saklanıyor (bkz.
        // yukarıdaki reachable:false girişleri).
        await prefs.setInt('ups_bg_last_charge_$upsKey', batteryCharge.round());
        await prefs.setBool('ups_bg_last_onbattery_$upsKey', isOnBattery);

        final onBattRule = _findRule(rules, NotificationTrigger.upsOnBattery);
        if (onBattRule != null &&
            onBattRule.enabled &&
            isOnBattery &&
            !wasOnBattery) {
          await notify(500, 'UPS Bataryaya Geçti',
              '$upsName · Elektrik kesildi · ${hhmm(DateTime.now())}',
              cooldownKey: 'ups_onbattery_$upsKey',
              cooldownMinutes: onBattRule.cooldownMinutes);
        }

        final onlineRule = _findRule(rules, NotificationTrigger.upsOnline);
        if (onlineRule != null &&
            onlineRule.enabled &&
            !isOnBattery &&
            wasOnBattery) {
          await notify(505, 'UPS Şebekeye Döndü',
              '$upsName · Elektrik geldi · ${hhmm(DateTime.now())}',
              cooldownKey: 'ups_online_$upsKey',
              cooldownMinutes: onlineRule.cooldownMinutes);
        }

        await prefs.setString('ups_bg_status_$upsKey', upsStatus);

        final lowBattRule = _findRule(rules, NotificationTrigger.upsBatteryLow);
        if (lowBattRule != null &&
            lowBattRule.enabled &&
            batteryCharge > 0 &&
            batteryCharge <= lowBattRule.threshold) {
          final runtimeLabel =
              runtimeMin > 0 ? ', kalan ${runtimeMin}dk' : '';
          await notify(501, 'UPS Düşük Batarya',
              '$upsName · %${batteryCharge.toStringAsFixed(0)} (eşik %${lowBattRule.threshold.toInt()}$runtimeLabel) · ${hhmm(DateTime.now())}',
              cooldownKey: 'ups_lowbat_$upsKey',
              cooldownMinutes: lowBattRule.cooldownMinutes);
        }

        final loadRule = _findRule(rules, NotificationTrigger.upsLoadHigh);
        if (loadRule != null &&
            loadRule.enabled &&
            upsLoad >= loadRule.threshold) {
          await notify(502, 'UPS Yüksek Yük',
              '$upsName · %${upsLoad.toStringAsFixed(0)} (eşik %${loadRule.threshold.toInt()}) · ${hhmm(DateTime.now())}',
              cooldownKey: 'ups_load_$upsKey',
              cooldownMinutes: loadRule.cooldownMinutes);
        }

        final offlineRule = _findRule(rules, NotificationTrigger.upsOffline);
        if (offlineRule != null && offlineRule.enabled) {
          final lastStatus =
              prefs.getString('ups_bg_offline_$upsKey') ?? 'online';
          final isOffline =
              upsStatus.isEmpty || upsStatus.toUpperCase().contains('OFF');
          final wasOffline =
              lastStatus.isEmpty || lastStatus.toUpperCase().contains('OFF');
          if (isOffline && !wasOffline) {
            await notify(503, 'UPS Kapatıldı',
                '$upsName · UPS kapalı raporlandı · ${hhmm(DateTime.now())}');
          }
          await prefs.setString('ups_bg_offline_$upsKey', upsStatus);
        }

        final tempRule = _findRule(rules, NotificationTrigger.upsTempHigh);
        if (tempRule != null &&
            tempRule.enabled &&
            upsTemp > 0 &&
            upsTemp >= tempRule.threshold) {
          await notify(504, 'UPS Aşırı Isındı',
              '$upsName · ${upsTemp.toStringAsFixed(1)}°C (eşik ${tempRule.threshold.toInt()}°C) · ${hhmm(DateTime.now())}',
              cooldownKey: 'ups_temp_$upsKey',
              cooldownMinutes: tempRule.cooldownMinutes);
        }
      }
    }
  } catch (e) {
    // Bilinçli sessiz: döngü içi her adımın kendi catch'i zaten var — bu dış
    // katman sadece beklenmeyen bir istisnanın tüm turu düşürmesini önler.
    debugPrint('[MTools BG] UPS genel hata: $e');
  }

  await prefs.setString('notification_history', jsonEncode(history));

  // Ana ekran widget'larını güncelle (bkz. üstteki not) — sessizce başarısız
  // olabilir, widget güncellemesi bildirim akışını bloklamamalı.
  try {
    // "configured" burada servis listesinin kendisinden (proxmoxServices/
    // nutServices) geliyor, widgetNodes/widgetUps'un o turda dolu olup
    // olmamasından DEĞİL — aksi halde "sunucu ekli ama tamamen erişilemiyor
    // ve hiç bilinen node/UPS kaydı yok" durumu yanlışlıkla "hiç
    // yapılandırılmadı" gibi görünürdü (bkz. AdGuard'daki aynı 3-durumlu
    // desen).
    if (proxmoxServices.isNotEmpty) {
      await HomeWidget.saveWidgetData(
          'proxmox_nodes_json',
          jsonEncode({'configured': true, 'nodes': widgetNodes}));
      await HomeWidget.saveWidgetData(
          'proxmox_updated_at', DateTime.now().millisecondsSinceEpoch);
      await HomeWidget.updateWidget(
        androidName: 'ProxmoxWidgetProvider',
        qualifiedAndroidName: 'com.example.mtools_v2.ProxmoxWidgetProvider',
      );
    }
    if (nutServices.isNotEmpty) {
      await HomeWidget.saveWidgetData(
          'ups_units_json',
          jsonEncode({'configured': true, 'units': widgetUps}));
      await HomeWidget.saveWidgetData(
          'ups_updated_at', DateTime.now().millisecondsSinceEpoch);
      await HomeWidget.updateWidget(
        androidName: 'UpsWidgetProvider',
        qualifiedAndroidName: 'com.example.mtools_v2.UpsWidgetProvider',
      );
    }
  } catch (e) {
    // Bilinçli sessiz: ana ekran widget'ı güncellenemese bile uygulama içi
    // deneyimi etkilemez, sadece OS ana ekranındaki widget bayat kalır.
    debugPrint('[MTools BG] Widget güncelleme hatası: $e');
  }
}

/// Cihazın (telefonun) kendi internet erişimi var mı — WiFi/mobil veri
/// arayüzünün "bağlı" görünmesi yetmez, gerçek bir DNS sorgusuyla doğrulanır
/// (bkz. `ConnectivityProvider`, ön plan tarafındaki aynı teknik — arka plan
/// izole ayrı bir FlutterEngine olduğu için o provider'ı doğrudan kullanamaz,
/// aynı tekniği burada bağımsız olarak tekrarlıyoruz).
Future<bool> _hasDeviceInternet() async {
  try {
    final result = await InternetAddress.lookup('one.one.one.one')
        .timeout(const Duration(seconds: 4));
    return result.isNotEmpty && result.first.rawAddress.isNotEmpty;
  } catch (_) {
    return false;
  }
}

/// Proxmox/NUT/AdGuard'ın kendi ardışık-hata sayaçlarını sıfırlar — cihaz
/// bağlantısı geri geldiğinde çağrılır ki bağlantı kopukken (zaten hiç
/// denenmedikleri için) sayaçlarında birikmiş OLMAYAN, ama kopmadan HEMEN
/// ÖNCE genuine bir sebeple birikmiş olabilecek eski bir değer, yeniden
/// bağlanır bağlanmaz "1 eski + 1 yeni = eşik aşıldı" şeklinde yanlışlıkla
/// erken bir servis-özel bildirime yol açmasın — her üç servis de
/// bağlantı sonrası tam iki temiz denemeye sahip olsun.
Future<void> _resetServiceFailCounters(SharedPreferences prefs) async {
  final keys = prefs.getKeys().where((k) =>
      k.startsWith('proxmox_fail_count_') ||
      k.startsWith('nut_fail_count_') ||
      k == 'adguard_fail_count');
  for (final key in keys.toList()) {
    await prefs.remove(key);
  }
}

const _kDeviceOfflineKey = 'device_connectivity_offline';
const _kDeviceFailCountKey = 'device_connectivity_fail_count';

/// Proxmox/UPS/AdGuard sorgularından ÖNCE çağrılır. Cihazın kendi interneti
/// yoksa `false` döner — çağıran taraf o turda HİÇBİR alt servisi
/// denemeMELİdir (hem gereksiz batarya/veri tüketimini önler hem de "asıl
/// sorun tek: telefonun bağlantısı" durumunda üç ayrı servis-özel
/// "ulaşılamıyor" bildirimi atılmasını engeller). Servis-özel bildirimler
/// (upsUnreachable, adguardUnreachable, nodeOffline vb.) bu fonksiyona hiç
/// dokunulmuyor, aynen çalışmaya devam ediyor — bu sadece bir ön-kontrol
/// katmanı.
/// Proxmox/UPS/AdGuard'ın SON BİLİNEN widget verisine, servis-özel parse
/// akışlarına hiç dokunmadan, ortak bir `deviceOffline: true` alanı ekler —
/// üç *WidgetProvider.kt bunu kendi mevcut "ulaşılamıyor" render yolunda
/// farklı bir sebep metniyle ("cihazın interneti yok" vs "sunucuya
/// ulaşılamıyor") gösterir. Sadece cihaz-çevrimdışı geçişinde (bkz.
/// _guardConnectivity) çağrılır; bağlantı geri gelince ayrıca "false"
/// yazmaya gerek yok — _runCheck/_refreshAdGuardWidget normale dönünce bu
/// alanı hiç içermeyen taze bir obje yazıyorlar, Kotlin tarafında
/// optBoolean(..., false) otomatik false'a düşüyor.
Future<void> _markWidgetsDeviceOffline() async {
  const keys = ['proxmox_nodes_json', 'ups_units_json', 'adguard_stats_json'];
  for (final key in keys) {
    final raw = await HomeWidget.getWidgetData<String>(key);
    if (raw == null) continue;
    try {
      final obj = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      obj['deviceOffline'] = true;
      await HomeWidget.saveWidgetData(key, jsonEncode(obj));
    } catch (_) {
      // Bilinçli sessiz: JSON bozuksa dokunma — bir sonraki başarılı yazım
      // (bağlantı dönünce) zaten taze, doğru bir obje yazacak.
    }
  }
  try {
    await HomeWidget.updateWidget(
      androidName: 'ProxmoxWidgetProvider',
      qualifiedAndroidName: 'com.example.mtools_v2.ProxmoxWidgetProvider',
    );
    await HomeWidget.updateWidget(
      androidName: 'UpsWidgetProvider',
      qualifiedAndroidName: 'com.example.mtools_v2.UpsWidgetProvider',
    );
    await HomeWidget.updateWidget(
      androidName: 'AdGuardWidgetProvider',
      qualifiedAndroidName: 'com.example.mtools_v2.AdGuardWidgetProvider',
    );
  } catch (_) {
    // Bilinçli sessiz: widget güncellemesi opsiyonel, ana akışı bloklamaz.
  }
}

Future<bool> _guardConnectivity({
  required FlutterLocalNotificationsPlugin plugin,
}) async {
  final prefs = await SharedPreferences.getInstance();
  final online = await _hasDeviceInternet();

  if (online) {
    final wasOffline = prefs.getBool(_kDeviceOfflineKey) ?? false;
    await prefs.setInt(_kDeviceFailCountKey, 0);
    if (wasOffline) {
      await prefs.setBool(_kDeviceOfflineKey, false);
      // Servislerin kendi sayaçları, bağlantı kopukken zaten hiç
      // ilerlemedi (bu fonksiyon false döndüğü sürece _runCheck/
      // _refreshAdGuardWidget hiç çağrılmıyor) — ama kopmadan hemen önce
      // birikmiş olabilecek eski bir değeri de temizleyip her üç servise
      // tam temiz bir başlangıç veriyoruz.
      await _resetServiceFailCounters(prefs);

      final notifSettings = await _loadNotifSettings();
      final notificationsAllowed = (notifSettings['serviceEnabled'] as bool) &&
          !_isQuietNow(notifSettings);
      final rulesRaw =
          await HomeWidget.getWidgetData<String>('bg_notification_rules') ?? '';
      final rules = _parseRules(rulesRaw);
      final historyRaw = prefs.getString('notification_history');
      final List<Map<String, dynamic>> history = historyRaw != null
          ? List<Map<String, dynamic>>.from((jsonDecode(historyRaw) as List)
              .map((e) => Map<String, dynamic>.from(e)))
          : [];

      final rule = _findRule(rules, NotificationTrigger.connectivityLost);
      if (rule != null && rule.enabled) {
        await _sendNotification(
          plugin,
          prefs,
          notificationsAllowed,
          history,
          511,
          'İnternet Bağlantınız Geri Geldi',
          'İzleme devam ediyor · ${hhmm(DateTime.now())}',
          cooldownKey: 'connectivity_restored',
          cooldownMinutes: 0,
        );
      }
      await prefs.setString('notification_history', jsonEncode(history));
    }
    return true;
  }

  // Çevrimdışı: alt servisleri bu turda hiç deneme — sayaçları donduruyoruz.
  final failCount = (prefs.getInt(_kDeviceFailCountKey) ?? 0) + 1;
  await prefs.setInt(_kDeviceFailCountKey, failCount);

  // İlk hatada hemen bildirim atmıyoruz — bkz. _kConsecutiveFailuresForOffline
  // (kısa bir tünelden geçip hemen geri gelmek false-positive üretmesin).
  // Ama alt servisleri denemeyi bu turdan itibaren zaten durduruyoruz.
  if (failCount >= _kConsecutiveFailuresForOffline &&
      !(prefs.getBool(_kDeviceOfflineKey) ?? false)) {
    await prefs.setBool(_kDeviceOfflineKey, true);
    await _markWidgetsDeviceOffline();

    final notifSettings = await _loadNotifSettings();
    final notificationsAllowed =
        (notifSettings['serviceEnabled'] as bool) && !_isQuietNow(notifSettings);
    final rulesRaw =
        await HomeWidget.getWidgetData<String>('bg_notification_rules') ?? '';
    final rules = _parseRules(rulesRaw);
    final historyRaw = prefs.getString('notification_history');
    final List<Map<String, dynamic>> history = historyRaw != null
        ? List<Map<String, dynamic>>.from((jsonDecode(historyRaw) as List)
            .map((e) => Map<String, dynamic>.from(e)))
        : [];

    final rule = _findRule(rules, NotificationTrigger.connectivityLost);
    if (rule != null && rule.enabled) {
      await _sendNotification(
        plugin,
        prefs,
        notificationsAllowed,
        history,
        509,
        'İnternet Bağlantınız Yok',
        'İzleme geçici olarak duraklatıldı · ${hhmm(DateTime.now())}',
        cooldownKey: 'connectivity_lost',
        cooldownMinutes: rule.cooldownMinutes,
      );
    }
    await prefs.setString('notification_history', jsonEncode(history));
  }

  return false;
}

/// AdGuard, Proxmox/UPS'in paylaştığı `_runCheck()` içinde SORGULANMIYOR
/// (o fonksiyon Proxmox/NUT servisi hiç yoksa erken dönüyor) — bu yüzden
/// ayrı, kendi kendine yeten bir kontrol turu. Ama artık Proxmox/UPS'teki
/// AYNI desen: sunucuya tamamen ulaşılamadığında (a) ardışık-hata sayacıyla
/// debounce edilmiş bir "ulaşılamıyor" bildirimi atılır, (b) widget'a
/// connected:false yazılır — böylece sessizce donmak yerine gerçek durumu
/// yansıtır.
Future<void> _refreshAdGuardWidget({
  required FlutterLocalNotificationsPlugin plugin,
}) async {
  // shared_preferences bu arka plan servisinin ayrı FlutterEngine'i ile
  // güvenilmez kaldığı için (bkz. AdGuardProvider._loadConfig'deki not)
  // yapılandırma home_widget'ın depolama mekanizmasından okunuyor.
  final raw = await HomeWidget.getWidgetData<String>('bg_adguard_config');
  if (raw == null) return;

  Map<String, dynamic> config;
  try {
    config = jsonDecode(raw) as Map<String, dynamic>;
  } catch (_) {
    return;
  }
  final primaryUrl = config['primaryUrl'] as String? ?? '';
  final secondaryUrl = config['secondaryUrl'] as String? ?? '';
  final username = config['username'] as String? ?? '';
  final password = config['password'] as String? ?? '';
  if (primaryUrl.isEmpty) return;

  final prefs = await SharedPreferences.getInstance();
  final notifSettings = await _loadNotifSettings();
  final notificationsAllowed =
      (notifSettings['serviceEnabled'] as bool) && !_isQuietNow(notifSettings);
  final rulesRaw =
      await HomeWidget.getWidgetData<String>('bg_notification_rules') ?? '';
  final rules = _parseRules(rulesRaw);
  final historyRaw = prefs.getString('notification_history');
  final List<Map<String, dynamic>> history = historyRaw != null
      ? List<Map<String, dynamic>>.from((jsonDecode(historyRaw) as List)
          .map((e) => Map<String, dynamic>.from(e)))
      : [];

  final service = AdGuardService();
  service.configure(
    primaryUrl: primaryUrl,
    secondaryUrl: secondaryUrl,
    username: username,
    password: password,
  );

  const failCountKey = 'adguard_fail_count';
  const reachableKey = 'adguard_bg_reachable';

  Map<String, dynamic> stats;
  Map<String, dynamic> status;
  try {
    stats = await service.getStats();
    status = await service.getStatus();
  } catch (e) {
    debugPrint('[MTools BG] AdGuard sorgusu başarısız: $e');
    final failCount = (prefs.getInt(failCountKey) ?? 0) + 1;
    await prefs.setInt(failCountKey, failCount);

    // İlk hatada hemen alarm vermiyoruz — bkz. _kConsecutiveFailuresForOffline.
    if (failCount < _kConsecutiveFailuresForOffline) return;

    final wasReachable = prefs.getString(reachableKey) != 'false';
    if (wasReachable) {
      final rule = _findRule(rules, NotificationTrigger.adguardUnreachable);
      if (rule != null && rule.enabled) {
        await _sendNotification(
          plugin,
          prefs,
          notificationsAllowed,
          history,
          508,
          'AdGuard\'a Ulaşılamıyor',
          'Sunucuya bağlanılamıyor · ${hhmm(DateTime.now())}',
          cooldownKey: 'adguard_unreachable',
          cooldownMinutes: rule.cooldownMinutes,
        );
      }
      await prefs.setString(reachableKey, 'false');
    }
    await prefs.setString('notification_history', jsonEncode(history));

    try {
      // Son bilinen sayısal değerleri taşımaya gerek yok — Kotlin tarafı
      // connected:false görünce zaten "Bağlantı yok" gösterip diğer
      // alanları hiç okumuyor (bkz. AdGuardWidgetProvider.kt).
      await HomeWidget.saveWidgetData('adguard_stats_json',
          jsonEncode({'configured': true, 'connected': false}));
      await HomeWidget.saveWidgetData(
          'adguard_updated_at', DateTime.now().millisecondsSinceEpoch);
      await HomeWidget.updateWidget(
        androidName: 'AdGuardWidgetProvider',
        qualifiedAndroidName: 'com.example.mtools_v2.AdGuardWidgetProvider',
      );
    } catch (_) {
      // Bilinçli sessiz: ana ekran widget'ı güncellenemese bile uygulama içi
      // deneyimi etkilemez, sadece OS ana ekranındaki widget bayat kalır.
    }
    return;
  }

  await prefs.setInt(failCountKey, 0);
  // Not: reachable → false geçişinde bildirim atılıyor ama false → reachable
  // geçişinde bilinçli olarak atılmıyor (AdGuard için "tekrar ulaşıldı"
  // bildirimi henüz yok). Bayrak yine de burada sıfıra çekiliyor ki bir
  // sonraki gerçek kesintide "wasReachable" doğru okunsun.
  await prefs.setString(reachableKey, 'true');

  try {
    final total = (stats['num_dns_queries'] ?? 0) as num;
    final blocked = (stats['num_blocked_filtering'] ?? 0) as num;
    final pct = total > 0 ? (blocked / total * 100) : 0.0;
    final avgMs = ((stats['avg_processing_time'] ?? 0.0) as num) * 1000;
    final topClientsRaw = (stats['top_clients'] as List?) ?? [];
    final topClientNames =
        topClientsRaw.take(3).map((e) => (e as Map).keys.first as String).toList();
    final safeBrowsing = (stats['num_replaced_safebrowsing'] ?? 0) as num;
    final parental = (stats['num_replaced_parental'] ?? 0) as num;

    final data = {
      'configured': true,
      'connected': true,
      'protected': status['protection_enabled'] ?? true,
      'total': total.round(),
      'blockedPct': pct.round(),
      'avgMs': avgMs.round(),
      'clients': topClientsRaw.length,
      'topClients': topClientNames,
      'securityBlocked': (safeBrowsing + parental).round(),
    };

    await HomeWidget.saveWidgetData('adguard_stats_json', jsonEncode(data));
    await HomeWidget.saveWidgetData(
        'adguard_updated_at', DateTime.now().millisecondsSinceEpoch);
    await HomeWidget.updateWidget(
      androidName: 'AdGuardWidgetProvider',
      qualifiedAndroidName: 'com.example.mtools_v2.AdGuardWidgetProvider',
    );
  } catch (e) {
    // Bilinçli sessiz: ana ekran widget'ı güncellenemese bile uygulama içi
    // deneyimi etkilemez, sadece OS ana ekranındaki widget bayat kalır.
    debugPrint('[MTools BG] AdGuard widget güncelleme hatası: $e');
  }
}

// ─────────────────────────────────────────────
// Yardımcılar
// ─────────────────────────────────────────────

Future<String> _getCTName(
    SharedPreferences prefs, String node, String vmid) async {
  return prefs.getString('ct_name_${node}_$vmid') ?? 'CT $vmid';
}

Future<String> _getVMName(
    SharedPreferences prefs, String node, String vmid) async {
  return prefs.getString('vm_name_${node}_$vmid') ?? 'VM $vmid';
}

Future<void> _refreshContainerNames(
    ProxmoxService svc, SharedPreferences prefs, String nodeName) async {
  final lastRefreshStr = prefs.getString('names_refreshed_$nodeName');
  if (lastRefreshStr != null) {
    final last = DateTime.tryParse(lastRefreshStr);
    // Cache süresi 3 dakikaya indirildi (5 dk'dan), yeni CT/VM'ler daha hızlı tanınır
    if (last != null && DateTime.now().difference(last).inMinutes < 3) return;
  }
  try {
    final lxcs = await svc.getLXCs(nodeName);
    for (final ct in lxcs) {
      final vmid = ct['vmid']?.toString() ?? '';
      final name = ct['name'] as String? ?? 'CT $vmid';
      if (vmid.isNotEmpty) {
        await prefs.setString('ct_name_${nodeName}_$vmid', name);
      }
    }
  } catch (_) {
    // Bilinçli sessiz: bu sadece bildirim metnindeki CT ismini zenginleştirir
    // (ör. "CT 105" yerine "MyContainer") — başarısız olursa bildirim yine
    // gönderilir, sadece isim yerine numara görünür.
  }
  try {
    final vms = await svc.getVMs(nodeName);
    for (final vm in vms) {
      final vmid = vm['vmid']?.toString() ?? '';
      final name = vm['name'] as String? ?? 'VM $vmid';
      if (vmid.isNotEmpty) {
        await prefs.setString('vm_name_${nodeName}_$vmid', name);
      }
    }
  } catch (_) {
    // Bilinçli sessiz: aynı sebep, VM ismi zenginleştirmesi için.
  }
  await prefs.setString(
      'names_refreshed_$nodeName', DateTime.now().toIso8601String());
}

bool _isQuietNow(Map<String, dynamic> notifSettings) {
  final enabled = notifSettings['quietEnabled'] as bool;
  if (!enabled) return false;
  final start = notifSettings['quietStart'] as int;
  final end = notifSettings['quietEnd'] as int;
  final hour = DateTime.now().hour;
  if (start < end) return hour >= start && hour < end;
  return hour >= start || hour < end;
}

/// Genel bildirim ayarları (açık/kapalı, kontrol aralığı, sessiz saatler).
/// shared_preferences bu arka plan servisinin ayrı FlutterEngine'i ile
/// güvenilmez kaldığı için (bkz. NotificationProvider._syncRulesToBackgroundService
/// yorumu) home_widget'ın depolama mekanizmasından okunuyor.
Future<Map<String, dynamic>> _loadNotifSettings() async {
  final raw = await HomeWidget.getWidgetData<String>('bg_notif_settings');
  if (raw == null) {
    return {
      'serviceEnabled': true,
      'interval': 30,
      'quietEnabled': false,
      'quietStart': 23,
      'quietEnd': 7,
    };
  }
  try {
    final map = jsonDecode(raw) as Map<String, dynamic>;
    return {
      'serviceEnabled': map['serviceEnabled'] as bool? ?? true,
      'interval': map['interval'] as int? ?? 30,
      'quietEnabled': map['quietEnabled'] as bool? ?? false,
      'quietStart': map['quietStart'] as int? ?? 23,
      'quietEnd': map['quietEnd'] as int? ?? 7,
    };
  } catch (_) {
    return {
      'serviceEnabled': true,
      'interval': 30,
      'quietEnabled': false,
      'quietStart': 23,
      'quietEnd': 7,
    };
  }
}

bool _shouldCheckDiskTemp(SharedPreferences prefs) {
  final lastStr = prefs.getString('last_disk_temp_check');
  if (lastStr == null) return true;
  final last = DateTime.tryParse(lastStr);
  if (last == null) return true;
  return DateTime.now().difference(last).inMinutes >= 5;
}

Future<List<ProxmoxService>> _buildProxmoxServices(
    SharedPreferences prefs, String serversRaw) async {
  final List<ProxmoxService> services = [];
  if (serversRaw.isNotEmpty) {
    try {
      final List list = jsonDecode(serversRaw);
      for (final server in list) {
        final host = server['address'] ?? '';
        final port = (server['port'] ?? '8006').toString();
        final tokenId = server['tokenId'] ?? '';
        final tokenSecret = server['tokenSecret'] ?? '';
        if (host.isEmpty || tokenId.isEmpty) continue;
        final svc = ProxmoxService();
        svc.configure(host, port, tokenId, tokenSecret);
        services.add(svc);
      }
    } catch (e) {
      // Bozuk sunucu listesi JSON'u: bu turda Proxmox izleme tamamen
      // atlanır (aşağıdaki legacy fallback boşsa) — bu, kullanıcı hiç
      // bildirim almamaya başlar gibi görünebileceğinden günlüğe düşüyor.
      debugPrint('[MTools BG] Proxmox parse hatası: $e');
      await ErrorLogService().load();
      await ErrorLogService().log(
        type: ErrorLogType.unknown,
        message: 'Arka plan: Proxmox sunucu listesi okunamadı',
        detail: e.toString(),
      );
    }
  }
  if (services.isEmpty) {
    // Bilinçli çift prefix — legacy tekli-sunucu verisi bu adreste;
    // "düzeltme", eski kurulumdan yükseltmeyi bozar.
    final host = prefs.getString('${_p}proxmox_host') ?? '';
    final port = prefs.getString('${_p}proxmox_port') ?? '8006';
    final tokenId = prefs.getString('${_p}proxmox_token_id') ?? '';
    final tokenSecret = prefs.getString('${_p}proxmox_token_secret') ?? '';
    if (host.isNotEmpty && tokenId.isNotEmpty) {
      final svc = ProxmoxService();
      svc.configure(host, port, tokenId, tokenSecret);
      services.add(svc);
    }
  }
  return services;
}

Future<List<NutService>> _buildNutServices(String serversRaw) async {
  if (serversRaw.isEmpty) return [];
  try {
    final List list = jsonDecode(serversRaw);
    return list
        .map((e) {
          final svc = NutService();
          svc.configure(
            host: e['host'] as String? ?? '',
            port: e['port'] as int? ?? 3493,
            username: e['username'] as String? ?? '',
            password: e['password'] as String? ?? '',
          );
          return svc;
        })
        .where((s) => s.host.isNotEmpty)
        .toList();
  } catch (e) {
    // Bozuk UPS sunucu listesi JSON'u — bu turda UPS izleme tamamen
    // atlanır, kullanıcı hiç bildirim almamaya başlar gibi görünebileceğinden
    // günlüğe düşüyor.
    debugPrint('[MTools BG] NUT parse hatası: $e');
    await ErrorLogService().load();
    await ErrorLogService().log(
      type: ErrorLogType.unknown,
      message: 'Arka plan: UPS sunucu listesi okunamadı',
      detail: e.toString(),
    );
    return [];
  }
}

int? _parseDiskTemp(Map<String, dynamic> smartData) {
  final type = smartData['type'] ?? '';
  if (type == 'text') {
    final text = smartData['text'] as String? ?? '';
    final m = RegExp(r'Temperature:\s+(\d+)').firstMatch(text);
    if (m != null) return int.tryParse(m.group(1)!);
  } else {
    final attrs = smartData['attributes'] as List? ?? [];
    final tempAttr = attrs.firstWhere(
      (a) =>
          ['190', '194'].contains(a['id']?.toString().trim()) ||
          a['name'] == 'Temperature_Celsius' ||
          a['name'] == 'Airflow_Temperature_Cel',
      orElse: () => null,
    );
    if (tempAttr != null) {
      return int.tryParse(tempAttr['raw'].toString().split(' ').first);
    }
  }
  return null;
}

NotificationRule? _findRule(
    List<NotificationRule> rules, NotificationTrigger trigger) {
  try {
    return rules.firstWhere((r) => r.trigger.index == trigger.index);
  } catch (_) {
    return null;
  }
}

List<NotificationRule> _parseRules(String raw) {
  final defaults = NotificationRule.defaults();
  if (raw.isEmpty) return defaults;
  try {
    final List savedList = jsonDecode(raw);
    final Map<int, Map<String, dynamic>> savedByTrigger = {};
    for (final item in savedList) {
      final triggerIndex = item['trigger'] as int?;
      if (triggerIndex != null) {
        savedByTrigger[triggerIndex] = Map<String, dynamic>.from(item);
      }
    }
    return defaults.map((defaultRule) {
      final saved = savedByTrigger[defaultRule.trigger.index];
      if (saved == null) return defaultRule;
      return NotificationRule.fromJson(saved, defaultRule);
    }).toList();
  } catch (_) {
    return defaults;
  }
}

// ── Bildirim ID formülü ───────────────────────────────────────────────────────
// Her (server, eventType, vmid) üçlüsü için benzersiz int ID üretir.
//
// Örnek base değerleri:
//   100 = CT stop   200 = CT start   150 = CT restart
//   300 = VM stop   400 = VM start   350 = VM restart
//
// Formül: (serverIndex * 10_000) + base + (vmid % 100)
// serverIndex 0-9 arası, base 0-999 arası olduğu sürece çakışma olmaz.
// vmid % 100: aynı sunucuda aynı anda 100'den az eşzamanlı olay olur.
int _notifId(int serverIndex, int base, int vmid) {
  return (serverIndex * 10000) + base + (vmid % 100);
}
