import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:home_widget/home_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../dashboard/error_log_service.dart';
import 'notification_rule.dart';

/// Tüm bildirimlerde (uyarılar, terminal, test) kullanılan tek, sabit
/// Android bildirim rengi (status bar ikon tonu) — kullanıcının seçtiği
/// uygulama-içi temadan bağımsız, marka kimliği için sabit tutuluyor.
const kNotificationAccent = Color(0xFF4E9C8C);

/// Bildirim gövdelerindeki standart "HH:mm" damgası — tek yerden üretiliyor
/// ki tüm bildirim tipleri aynı formatı kullansın.
String hhmm(DateTime dt) =>
    '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

NotificationRule? findRule(
    List<NotificationRule> rules, NotificationTrigger trigger) {
  try {
    return rules.firstWhere((r) => r.trigger.index == trigger.index);
  } catch (_) {
    return null;
  }
}

bool isQuietNow(Map<String, dynamic> notifSettings) {
  final enabled = notifSettings['quietEnabled'] as bool;
  if (!enabled) return false;
  final start = notifSettings['quietStart'] as int;
  final end = notifSettings['quietEnd'] as int;
  final hour = DateTime.now().hour;
  if (start < end) return hour >= start && hour < end;
  return hour >= start || hour < end;
}

/// Genel bildirim ayarları (açık/kapalı, kontrol aralığı, sessiz saatler).
/// shared_preferences arka plan servisinin ayrı FlutterEngine'i ile
/// güvenilmez kaldığı için home_widget'ın depolama mekanizmasından
/// okunuyor — bu, hem ön plan hem arka plandan güvenle çağrılabilir.
Future<Map<String, dynamic>> loadNotifSettings() async {
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

/// Düşük seviye gönderim — cooldown kontrolü, geçmişe ekleme ve gerçek
/// `plugin.show()` çağrısı. `background_service.dart`'ın periyodik turu
/// history/notificationsAllowed'ı bir kez yükleyip birçok bildirim için
/// tekrar kullandığından, bu imza (parametre olarak alma) bilinçli olarak
/// korunuyor — her çağrıda yeniden okumak gereksiz SharedPreferences
/// trafiği üretirdi.
Future<void> sendDispatchedNotification(
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

/// Ön plandan (foreground UI) tetiklenen, kural motoruna bağlı bir bildirim
/// göndermek için üst-seviye yardımcı. `background_service.dart`'ın
/// periyodik turunun aksine kendi başına history/ayar okuyup [trigger]'ın
/// [rules] içindeki enabled/cooldown durumunu kontrol eder — Terminal
/// ekranındaki `terminalConnectionFailed` bildirimi bunu kullanır, böylece
/// diğer 21 tetikleyiciyle (cooldown, geçmiş, sessiz saatler, genel
/// açık/kapalı) aynı garantilere sahip olur.
Future<void> dispatchRuleNotification(
  FlutterLocalNotificationsPlugin plugin, {
  required NotificationTrigger trigger,
  required List<NotificationRule> rules,
  required int id,
  required String title,
  required String body,
  String? cooldownKey,
}) async {
  final rule = findRule(rules, trigger);
  if (rule == null || !rule.enabled) return;

  final prefs = await SharedPreferences.getInstance();
  final notifSettings = await loadNotifSettings();
  final notificationsAllowed =
      (notifSettings['serviceEnabled'] as bool) && !isQuietNow(notifSettings);

  final historyRaw = prefs.getString('notification_history');
  final List<Map<String, dynamic>> history = historyRaw != null
      ? List<Map<String, dynamic>>.from((jsonDecode(historyRaw) as List)
          .map((e) => Map<String, dynamic>.from(e)))
      : [];

  await sendDispatchedNotification(
    plugin,
    prefs,
    notificationsAllowed,
    history,
    id,
    title,
    body,
    cooldownKey: cooldownKey,
    cooldownMinutes: rule.cooldownMinutes,
  );

  await prefs.setString('notification_history', jsonEncode(history));
}
