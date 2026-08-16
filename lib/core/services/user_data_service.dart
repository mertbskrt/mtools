import 'package:shared_preferences/shared_preferences.dart';

/// Çıkış yapıldığında tüm kullanıcıya ait yerel verileri siler.
/// Yeni bir veri anahtarı eklediğinde buraya da ekle.
class UserDataService {
  UserDataService._();
  static final UserDataService instance = UserDataService._();

  /// SharedPreferences'taki kullanıcıya ait tüm anahtarlar.
  /// 'intentional_' gibi prefix'li olanlar ayrıca taranır.
  static const _exactKeys = [
    'disk_aliases',
    'tab_config',
    'notification_rules',
    'notification_history',
    'proxmox_servers',
    'proxmox_host',
    'proxmox_port',
    'proxmox_token_id',
    'proxmox_token_secret',
    'nut_servers',
    'wol_devices',
    'ssh_servers',
    'proxmox_ssh_user',
    'proxmox_ssh_pass',
    'proxmox_ssh_port',
    'app_pin',
    'lock_enabled',
    'lock_type',
    'lock_scope_power_ops',
    'lock_scope_terminal',
    'quick_auth_kill_switch',
    'guest_mode',
    // NOT: 'onboarding_seen' bilinçli olarak burada YOK — tanıtım/onboarding
    // cihaz bazında yalnızca bir kez gösterilmeli, sign-out/hesap değişimi
    // bunu sıfırlamamalı (yalnızca uygulama verisi silinirse/yeniden kurulumda
    // döner).
    // NOT: tema tercihi (gerçek SharedPreferences anahtarları 'app_style'/
    // 'app_dark' — bkz. app_theme.dart) bilinçli olarak burada YOK; bu
    // listede önceden duran 'theme_style'/'theme_dark' isimleri hiçbir zaman
    // gerçek anahtarlarla eşleşmiyordu (o isimler sadece
    // cloud_sync_service.dart'ın Firestore alan adları) — düzeltmek
    // sign-out'ta temayı sıfırlayan YENİ bir davranış olacağından burada
    // sadece ölü kayıt olarak temizlendi, doğru anahtarlar eklenmedi.
    'node_order',
    'adguard_primary_url',
    'adguard_secondary_url',
    'adguard_username',
    'adguard_password',
    'notif_service_enabled',
    'notif_interval',
    'notif_quiet_enabled',
    'notif_quiet_start',
    'notif_quiet_end',
    'node_expanded_states',
    'node_section_visibility',
    'container_sort_by',
    'container_sort_asc',
  ];

  /// Bu prefix ile başlayan tüm anahtarları da sil
  static const _prefixes = [
    'intentional_',   // ProxmoxService VM/LXC işlem kayıtları
    'notif_last_',    // Bildirim cooldown zaman damgaları
  ];

  /// Çıkış yapılırken çağır — tüm yerel kullanıcı verisini siler.
  Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    final allKeys = prefs.getKeys();

    final toRemove = <String>{};

    // Tam eşleşen anahtarlar
    for (final key in _exactKeys) {
      if (allKeys.contains(key)) toRemove.add(key);
    }

    // Prefix ile eşleşen anahtarlar
    for (final key in allKeys) {
      for (final prefix in _prefixes) {
        if (key.startsWith(prefix)) {
          toRemove.add(key);
          break;
        }
      }
    }

    await Future.wait(toRemove.map((key) => prefs.remove(key)));
  }
}