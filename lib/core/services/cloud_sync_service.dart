import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class CloudSyncService {
  static final CloudSyncService _instance = CloudSyncService._internal();
  factory CloudSyncService() {
    _instance._ensureAuthListener();
    return _instance;
  }
  CloudSyncService._internal();

  final _db = FirebaseFirestore.instance;

  // ── Bellek cache'i (oturum boyunca tekrar çekmez) ─────────────────────────
  Map<String, dynamic>? _cache;

  // Hesap değişikliğini (giriş/çıkış/hesap değiştirme) otomatik yakalayıp
  // cache'i geçersiz kılar. Önceden bu yoktu — aynı uygulama süreci içinde
  // çıkış yapıp başka bir hesapla (ya da misafir olarak) tekrar girildiğinde
  // önceki hesabın önbelleklenmiş verisi hâlâ dönüyordu.
  bool _listening = false;
  String? _lastUid;

  void _ensureAuthListener() {
    if (_listening) return;
    _listening = true;
    _lastUid = FirebaseAuth.instance.currentUser?.uid;
    FirebaseAuth.instance.authStateChanges().listen((user) {
      final newUid = user?.uid;
      if (newUid != _lastUid) {
        _lastUid = newUid;
        _cache = null;
      }
    });
  }

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  DocumentReference? get _userDoc {
    final uid = _uid;
    if (uid == null) return null;
    return _db.collection('users').doc(uid);
  }

  // ── Tek seferinde tüm veriyi çek, cache'e al ─────────────────────────────

  Future<Map<String, dynamic>> _fetchAll({bool forceRefresh = false}) async {
    if (_cache != null && !forceRefresh) return _cache!;
    try {
      final doc = await _userDoc?.get();
      if (doc == null || !doc.exists) {
        _cache = {};
        return _cache!;
      }
      _cache = (doc.data() as Map<String, dynamic>?) ?? {};
      return _cache!;
    } catch (e) {
      // Hata sessizce yutulmaz – üst katman görebilir
      _cache = {};
      return _cache!;
    }
  }

  /// Cache'i temizle (ayar kaydedince çağır)
  void invalidateCache() => _cache = null;

  // ── Proxmox Sunucuları ────────────────────────────────────────────────────

  Future<String?> getProxmoxServers() async {
    final data = await _fetchAll();
    return data['proxmox_servers'] as String?;
  }

  Future<void> saveProxmoxServers(String serversJson) async {
    await _save({'proxmox_servers': serversJson});
  }

  // ── Node Sıralaması ───────────────────────────────────────────────────────

  Future<String?> getNodeOrder() async {
    final data = await _fetchAll();
    return data['node_order'] as String?;
  }

  Future<void> saveNodeOrder(String orderJson) async {
    await _save({'node_order': orderJson});
  }

  // ── Genel Ayarlar ─────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> getAllSettings() => _fetchAll();

  Future<String?> getSetting(String key) async {
    final data = await _fetchAll();
    return data[key] as String?;
  }

  Future<void> saveSetting(String key, dynamic value) async {
    await _save({key: value});
  }

  /// Birden fazla ayarı tek Firestore yazmasında kaydet
  Future<void> saveSettings(Map<String, dynamic> fields) async {
    await _save(fields);
  }

  // ── Tema Ayarları ─────────────────────────────────────────────────────────

  Future<Map<String, dynamic>?> getThemeSettings() async {
    final data = await _fetchAll();
    final styleId = data['theme_style'] as String?;
    if (styleId == null) return null;
    return {
      'style': styleId,
      'dark': data['theme_dark'] as bool? ?? false,
    };
  }

  Future<void> saveThemeSettings(String styleId, bool isDark) async {
    await _save({'theme_style': styleId, 'theme_dark': isDark});
  }

  // ── Sekme Konfigürasyonu ──────────────────────────────────────────────────

  Future<String?> getTabConfig() async {
    final data = await _fetchAll();
    return data['tab_config'] as String?;
  }

  Future<void> saveTabConfig(String tabConfigJson) async {
    await _save({'tab_config': tabConfigJson});
  }

  // ── Ortak kaydetme (cache günceller + Firestore'a yazar) ──────────────────

  Future<void> _save(Map<String, dynamic> fields) async {
    try {
      // Önce local cache'i güncelle (UI anında tepki verir)
      _cache = {...?_cache, ...fields};
      await _userDoc?.set(fields, SetOptions(merge: true));
    } catch (e) {
      // Başarısız olursa cache kirlenmesin
      invalidateCache();
      rethrow; // üst katman hatayı görsün
    }
  }

  // ── Kullanıcı Verisi Temizle ──────────────────────────────────────────────

  Future<void> clearUserData() async {
    try {
      _cache = null;
      await _userDoc?.delete();
    } catch (e) {
      rethrow;
    }
  }
}