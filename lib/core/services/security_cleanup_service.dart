import 'dart:async';
import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'cloud_sync_service.dart';
import '../utils/credential_sync.dart';

/// v3.1.0 öncesi kullanıcıların Firestore dokümanında düz metin olarak
/// duran kimlik bilgilerini (SSH şifreleri, Proxmox token'ları, AdGuard/NUT
/// kullanıcı adı-şifresi) tek seferlik olarak temizler. Yapı alanları
/// (isim/host/port/URL) korunur — sadece kimlik bilgisi alanları gider.
///
/// Bu temizlik, uygulamanın artık hiçbir zaman bu alanları cloud'a
/// yazmayacağı (bkz. credential_sync.dart entegrasyonları) YÜRÜRLÜĞE
/// GİRDİKTEN SONRA çalıştırılmalıdır — auth_screen.dart'ta bu, provider'ların
/// `_initProviders()` çağrısından ÖNCE, `runOnce()`'un tamamlanmasıyla
/// garanti edilir.
class SecurityCleanupService {
  static const _flagKey = 'security_cleanup_v1_done';

  /// Açılışı asla bloklamaz — 10 saniye içinde bitmezse ya da herhangi bir
  /// adım başarısız olursa (örn. offline) bayrak yazılmaz, bir sonraki
  /// açılışta/girişte tekrar denenir.
  static Future<void> runOnce() async {
    try {
      await _run().timeout(const Duration(seconds: 10));
    } catch (_) {
      // Bilinçli sessiz: offline/timeout/Firestore hatası — bayrak
      // yazılmadığı için bir sonraki denemede tekrar çalışacak.
    }
  }

  static Future<void> _run() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_flagKey) ?? false) return;
    if (FirebaseAuth.instance.currentUser == null) return;

    final cloud = CloudSyncService();
    final data = await cloud.getAllSettings();
    final updates = <String, dynamic>{};

    void sanitizeListField(String key, List<String> credentialFields) {
      final raw = data[key] as String?;
      if (raw == null) return;
      final list = (jsonDecode(raw) as List)
          .map((e) => stripCredentialFields(
              Map<String, dynamic>.from(e), credentialFields))
          .toList();
      updates[key] = jsonEncode(list);
    }

    sanitizeListField('ssh_servers', ['password']);
    sanitizeListField('proxmox_servers', ['tokenId', 'tokenSecret']);
    sanitizeListField('nut_servers', ['username', 'password']);

    if (data.containsKey('adguard_username') ||
        data.containsKey('adguard_password')) {
      final hadCredentials = (data['adguard_username'] as String? ?? '')
          .isNotEmpty;
      updates['adguard_has_credentials'] = hadCredentials;
      updates['adguard_username'] = FieldValue.delete();
      updates['adguard_password'] = FieldValue.delete();
    }

    if (updates.isNotEmpty) {
      await cloud.saveSettings(updates);
    }
    // _save()'in bellek cache'i FieldValue.delete() sentinel'ini olduğu gibi
    // tutar — sonraki okumaların temiz bir fetch yapması için geçersiz kıl.
    cloud.invalidateCache();

    await prefs.setBool(_flagKey, true);
  }
}
