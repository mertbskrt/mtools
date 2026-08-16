import 'dart:convert';

/// Bir node/konteynerin kullanıcı tarafından BİLİNÇLİ olarak kapatıldığını/
/// yeniden başlatıldığını kaydeder. Ana izole (UI, [ProxmoxProvider]) ile
/// arka plan izolesi ([background_service.dart]) tarafından ORTAK olarak
/// kullanılır — bu yüzden saf Dart'tır, Flutter/provider bağımlılığı yoktur
/// ve iki tarafın da bire bir aynı kodyola/TTL mantığını kullanması sağlanır.
class DeliberateOffEntry {
  final String action; // 'shutdown' | 'reboot'
  final DateTime at;

  DeliberateOffEntry(this.action, this.at);

  Map<String, dynamic> toJson() => {
        'action': action,
        'at': at.toIso8601String(),
      };

  static DeliberateOffEntry? tryFromJson(dynamic json) {
    if (json is! Map) return null;
    final action = json['action'];
    final at = json['at'];
    if (action is! String || at is! String) return null;
    final parsed = DateTime.tryParse(at);
    if (parsed == null) return null;
    return DeliberateOffEntry(action, parsed);
  }
}

/// Reboot kendiliğinden birkaç dakikada tamamlanması beklenen bir işlemdir —
/// bu süre içinde node geri gelmediyse artık gerçek bir sorun var demektir,
/// bayrak süresi dolar ve alarmlar otomatik devam eder.
const kRebootFlagMaxAge = Duration(minutes: 20);

/// Shutdown'ın doğal bir süresi yoktur (kullanıcı makineyi günlerce kapalı
/// bırakabilir) — bayrak normalde SADECE node tekrar online görüldüğünde
/// temizlenir. Bu süre sadece sızıntı önleyici bir güvenlik ağıdır.
const kShutdownSafetyMaxAge = Duration(hours: 48);

bool isDeliberateOffActive(DeliberateOffEntry? e) {
  if (e == null) return false;
  final age = DateTime.now().difference(e.at);
  return age < (e.action == 'reboot' ? kRebootFlagMaxAge : kShutdownSafetyMaxAge);
}

Map<String, DeliberateOffEntry> decodeDeliberateOffMap(String? raw) {
  if (raw == null || raw.isEmpty) return {};
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return {};
    final result = <String, DeliberateOffEntry>{};
    for (final entry in decoded.entries) {
      final parsed = DeliberateOffEntry.tryFromJson(entry.value);
      if (parsed != null) result[entry.key as String] = parsed;
    }
    return result;
  } catch (_) {
    return {};
  }
}

String encodeDeliberateOffMap(Map<String, DeliberateOffEntry> map) {
  return jsonEncode(map.map((key, value) => MapEntry(key, value.toJson())));
}
