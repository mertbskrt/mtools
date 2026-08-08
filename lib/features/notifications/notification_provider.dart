import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:home_widget/home_widget.dart';
import 'notification_rule.dart';
import '../../core/services/cloud_sync_service.dart';
import 'background_service.dart' show kNotificationAccent;

class NotificationProvider extends ChangeNotifier {
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  List<NotificationRule> rules = NotificationRule.defaults();
  bool _initialized = false;

  final List<Map<String, dynamic>> history = [];

  bool serviceEnabled = true;
  int checkIntervalSeconds = 30;
  bool quietHoursEnabled = false;
  int quietStart = 23;
  int quietEnd = 7;

  // initBackgroundService()'teki autoStart:true ile eşleşen varsayım —
  // her uygulama açılışında servis önce başlar, aşağıdaki senkron
  // gerekirse hemen durdurur (bkz. _syncServiceRunningState).
  bool _serviceRunning = true;

  Future<void> init() async {
    if (_initialized) return;
    const android = AndroidInitializationSettings('@drawable/ic_notification');
    const settings = InitializationSettings(android: android);
    await _plugin.initialize(settings);
    await _loadRules();
    await _loadHistory();
    await _loadSettings();
    _initialized = true;
    // Uygulama açılışında hiçbir kural aktif değilse ya da kullanıcı arka
    // plan izlemeyi daha önce kapattıysa, autoStart:true ile başlamış olan
    // servisi burada (uygulama kesin ön plandayken, güvenli bağlamda) durdur.
    await _syncServiceRunningState();
  }

  /// Oturum içi hesap değişiminde (misafirden Google'a bağlanma vb.)
  /// çağrılır — init()'in `_initialized` erken-dönüşünü atlayıp kuralları/
  /// geçmişi/ayarları YENİ hesabın cloud verisiyle yeniden yükler.
  Future<void> reload() async {
    _initialized = false;
    await init();
  }

  /// Arka plan servisinin fiilen çalışıp çalışmaması gerektiğini "ana
  /// anahtar açık VE en az bir kural aktif" olarak belirler, gerçek durumla
  /// karşılaştırıp farkı varsa start/stop tetikler. Hem [setServiceEnabled]
  /// hem [updateRule] tarafından çağrılır — tek karar noktası.
  Future<void> _syncServiceRunningState() async {
    final shouldRun = serviceEnabled && rules.any((r) => r.enabled);
    if (shouldRun == _serviceRunning) return;
    final svc = FlutterBackgroundService();
    if (shouldRun) {
      // Bu metod her zaman kullanıcının doğrudan bir anahtara dokunduğu
      // (dolayısıyla uygulama kesin ön planda olduğu) bir çağrı yolundan
      // tetiklenir — Android'in yeni bir foreground service başlatmaya
      // izin verdiği güvenli bağlamlardan biri budur (bkz.
      // background_service.dart üstündeki not).
      await svc.startService();
      svc.invoke('app_foreground');
    } else {
      svc.invoke('stop');
    }
    _serviceRunning = shouldRun;
  }

  void reset() {
    rules = NotificationRule.defaults();
    history.clear();
    serviceEnabled = true;
    checkIntervalSeconds = 30;
    quietHoursEnabled = false;
    quietStart = 23;
    quietEnd = 7;
    _initialized = false;
    notifyListeners();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    serviceEnabled = prefs.getBool('notif_service_enabled') ?? true;
    checkIntervalSeconds = prefs.getInt('notif_interval') ?? 30;
    quietHoursEnabled = prefs.getBool('notif_quiet_enabled') ?? false;
    quietStart = prefs.getInt('notif_quiet_start') ?? 23;
    quietEnd = prefs.getInt('notif_quiet_end') ?? 7;
    notifyListeners();
    await _saveSettings();
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('notif_service_enabled', serviceEnabled);
    await prefs.setInt('notif_interval', checkIntervalSeconds);
    await prefs.setBool('notif_quiet_enabled', quietHoursEnabled);
    await prefs.setInt('notif_quiet_start', quietStart);
    await prefs.setInt('notif_quiet_end', quietEnd);
    // shared_preferences arka plan servisinin ayrı motoruna güvenilmez
    // ulaşıyor (bkz. _syncRulesToBackgroundService) — bu ayarlar da
    // home_widget üzerinden ayrıca yazılıyor.
    await HomeWidget.saveWidgetData(
      'bg_notif_settings',
      jsonEncode({
        'serviceEnabled': serviceEnabled,
        'interval': checkIntervalSeconds,
        'quietEnabled': quietHoursEnabled,
        'quietStart': quietStart,
        'quietEnd': quietEnd,
      }),
    );
  }

  Future<void> _loadRules() async {
    final prefs = await SharedPreferences.getInstance();
    String? raw = await CloudSyncService().getSetting('notification_rules');
    raw ??= prefs.getString('notification_rules');

    final defaults = NotificationRule.defaults();

    if (raw == null) {
      rules = defaults;
      notifyListeners();
      await _syncRulesToBackgroundService();
      return;
    }

    try {
      final List savedList = jsonDecode(raw);

      // Kayıtlı kuralları trigger index → Map olarak indeksle
      final Map<int, Map<String, dynamic>> savedByTrigger = {};
      for (final item in savedList) {
        final triggerIndex = item['trigger'] as int?;
        if (triggerIndex != null) {
          savedByTrigger[triggerIndex] = Map<String, dynamic>.from(item);
        }
      }

      // Her default kural için kayıtlı ayarları uygula
      rules = defaults.map((defaultRule) {
        final saved = savedByTrigger[defaultRule.trigger.index];
        if (saved == null) return defaultRule;
        return NotificationRule.fromJson(saved, defaultRule);
      }).toList();
    } catch (_) {
      rules = defaults;
    }

    notifyListeners();
    await _syncRulesToBackgroundService();
  }

  /// Arka plan servisi ayrı bir FlutterEngine'de çalışıyor ve
  /// shared_preferences bu iki motor arasında güvenilmez kaldı (veri cloud'dan
  /// geldiğinde local'e hiç yazılmıyordu, bu yüzden arka plan servisi her
  /// zaman varsayılan kurallara düşüyordu — örn. kullanıcı "Konteyner
  /// Başladı" bildirimini açsa bile arka planda hep kapalıymış gibi
  /// davranıyordu). Etkin kural seti burada hem local'e hem de tüm oturum
  /// boyunca güvenilir çalıştığı kanıtlanmış home_widget deposuna yazılıyor.
  Future<void> _syncRulesToBackgroundService() async {
    final prefs = await SharedPreferences.getInstance();
    final rulesJson = jsonEncode(rules.map((r) => r.toJson()).toList());
    await prefs.setString('notification_rules', rulesJson);
    await HomeWidget.saveWidgetData('bg_notification_rules', rulesJson);
  }

  Future<void> _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('notification_history');
    if (raw == null) return;
    final List list = jsonDecode(raw);
    history.clear();
    history.addAll(list.cast<Map<String, dynamic>>());
    notifyListeners();
  }

  Future<void> _saveHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('notification_history', jsonEncode(history));
  }

  Future<void> reloadHistory() async {
    await _loadHistory();
  }

  /// Ayarlar'daki "Test bildirimi gönder" butonu — arka plan servisine hiç
  /// gitmeden, ana uygulamadan anında bir bildirim gönderir ve geçmişe
  /// ekler. Bildirim ulaşım hattının uçtan uca çalıştığını 10 saniyede
  /// doğrulamak için.
  Future<void> sendTestNotification() async {
    const title = 'Test Bildirimi';
    const body = 'Bildirimler doğru çalışıyor.';
    await _plugin.show(
      DateTime.now().millisecondsSinceEpoch.remainder(100000),
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
    history.insert(0, {
      'title': title,
      'body': body,
      'time': DateTime.now().toIso8601String(),
    });
    if (history.length > 100) history.removeLast();
    await _saveHistory();
    notifyListeners();
  }

  Future<void> saveRules() async {
    final rulesJson = jsonEncode(rules.map((r) => r.toJson()).toList());
    await CloudSyncService().saveSetting('notification_rules', rulesJson);
    await _syncRulesToBackgroundService();
  }

  void updateRule(int index,
      {bool? enabled, double? threshold, int? cooldownMinutes}) {
    rules[index] = rules[index].copyWith(
      enabled: enabled,
      threshold: threshold,
      cooldownMinutes: cooldownMinutes,
    );
    saveRules();
    // Bu son kural da kapatıldıysa (ya da ilk kural yeniden açıldıysa)
    // servisin çalışıp çalışmaması gerektiği değişmiş olabilir.
    _syncServiceRunningState();
    notifyListeners();
  }

  Future<void> setServiceEnabled(bool value) async {
    serviceEnabled = value;
    await _saveSettings();
    notifyListeners();
    await _syncServiceRunningState();
  }

  Future<void> setCheckInterval(int seconds) async {
    checkIntervalSeconds = seconds;
    await _saveSettings();
    notifyListeners();
  }

  Future<void> setQuietHoursEnabled(bool value) async {
    quietHoursEnabled = value;
    await _saveSettings();
    notifyListeners();
  }

  Future<void> setQuietStart(int hour) async {
    quietStart = hour;
    await _saveSettings();
    notifyListeners();
  }

  Future<void> setQuietEnd(int hour) async {
    quietEnd = hour;
    await _saveSettings();
    notifyListeners();
  }

  bool get isQuietNow {
    if (!quietHoursEnabled) return false;
    final hour = DateTime.now().hour;
    if (quietStart < quietEnd) {
      return hour >= quietStart && hour < quietEnd;
    } else {
      return hour >= quietStart || hour < quietEnd;
    }
  }

  void removeHistory(int index) {
    history.removeAt(index);
    _saveHistory();
    notifyListeners();
  }

  void clearHistory() {
    history.clear();
    _saveHistory();
    notifyListeners();
  }
}