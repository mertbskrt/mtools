import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:home_widget/home_widget.dart';
import 'adguard_service.dart';
import '../../core/services/cloud_sync_service.dart';
import '../../core/services/widget_service.dart';

class AdGuardProvider extends ChangeNotifier {
  final AdGuardService _service = AdGuardService();
  Timer? _timer;

  bool isConfigured = false;
  bool isLoading = false;
  bool isConnected = false;
  String? error;

  /// Daha önce başarılı bir yükleme oldu ama bağlantı şimdi koptu — stats/
  /// status TEMİZLENMİYOR (eski veri hâlâ faydalı bağlam), sadece ekranın
  /// bunu "bayat" olarak işaretlemesi için bu bayrak set ediliyor (bkz.
  /// UPS'teki isStale deseni).
  bool isStale = false;
  DateTime? lastSuccessAt;

  /// URL başka bir cihazdan senkronize oldu, kullanıcı adı/şifre başka bir
  /// cihazda girilmiş ama bu cihazda henüz yoksa true olur (bkz.
  /// credential_sync.dart). Boş kimlik bilgisi her zaman "eksik" demek
  /// değildir — auth'suz AdGuard Home için bilinçli boş bırakılmışsa bu
  /// false kalır ve sorgu normal atılır.
  bool needsCredentials = false;

  /// "Yanlış ağdasın" ayrımı için — en son hangi host'un hata verdiği.
  String? get lastFailedHost => _service.lastFailedHost;

  Map<String, dynamic> stats = {};
  Map<String, dynamic> status = {};

  List<dynamic> queryLog = [];
  bool queryLogLoading = false;
  int queryLogOffset = 0;
  bool queryLogHasMore = true;
  String _queryLogFilter = 'all';
  String _queryLogSearch = '';

  String get queryLogFilter => _queryLogFilter;
  String get queryLogSearch => _queryLogSearch;

  void setQueryLogFilter(String filter) {
    if (_queryLogFilter == filter) return;
    _queryLogFilter = filter;
    loadQueryLog(reset: true);
  }

  void setQueryLogSearch(String search) {
    if (_queryLogSearch == search) return;
    _queryLogSearch = search;
    loadQueryLog(reset: true);
  }

  Map<String, dynamic> filteringStatus = {};
  List<dynamic> filters = [];
  List<dynamic> whitelistFilters = [];
  List<String> userRules = [];

  bool safeBrowsing = false;
  bool parentalControl = false;
  Map<String, dynamic> safeSearch = {};
  Map<String, dynamic> dnsConfig = {};
  Map<String, dynamic> clients = {};

  Future<void> init() async {
    await _loadConfig();
    if (isConfigured) {
      await refresh();
      _startTimer();
    }
  }

  Future<void> _loadConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final cloud = CloudSyncService();
    final cloudSettings = await cloud.getAllSettings();

    final primaryUrl = cloudSettings['adguard_primary_url'] as String?
        ?? prefs.getString('adguard_primary_url') ?? '';
    final secondaryUrl = cloudSettings['adguard_secondary_url'] as String?
        ?? prefs.getString('adguard_secondary_url') ?? '';
    // Kullanıcı adı/şifre artık cloud'a hiç YAZILMIYOR (bkz.
    // credential_sync.dart) — ama local boşsa (ör. cihaz verisi silindi/
    // yeniden kuruldu) ve cloud'da temizlik henüz çalışmadan kalan ESKİ
    // formatlı gerçek bir değer duruyorsa, onu sessizce yok saymak yerine
    // burada geri kazanılır; sessizce atmak "kimlik bilgisi gerekli"
    // durumuna düşürüp kullanıcının hâlâ var olan bilgiyi yeniden elle
    // girmesini gerektirirdi.
    final username = prefs.getString('adguard_username') ??
        (cloudSettings['adguard_username'] as String? ?? '');
    final password = prefs.getString('adguard_password') ??
        (cloudSettings['adguard_password'] as String? ?? '');

    // URL'ler (yapı) local'e de yazılır — ayar ekranının prefill'i local
    // SharedPreferences'tan okuyor, cloud'dan geldiyse orada da görünmeli.
    if (primaryUrl.isNotEmpty) {
      await prefs.setString('adguard_primary_url', primaryUrl);
      await prefs.setString('adguard_secondary_url', secondaryUrl);
    }

    if (primaryUrl.isEmpty) {
      isConfigured = false;
      needsCredentials = false;
      // notifyListeners kaldırıldı — init() ardından refresh() çağırıyor,
      // gereksiz double notify önlendi
      return;
    }

    // Başka bir cihazda kimlik bilgisi girilmiş ama bu cihazda yoksa —
    // boş kimlik bilgisi burada "eksik" sayılır (auth'suz AdGuard Home
    // ihtimali için bkz. `adguard_has_credentials` bayrağı).
    final hadCredentialsElsewhere =
        cloudSettings['adguard_has_credentials'] as bool? ?? false;
    if (username.isEmpty && hadCredentialsElsewhere) {
      isConfigured = false;
      needsCredentials = true;
      return;
    }
    needsCredentials = false;

    _service.configure(
      primaryUrl: primaryUrl,
      secondaryUrl: secondaryUrl,
      username: username,
      password: password,
    );
    isConfigured = true;
    // notifyListeners kaldırıldı — init() refresh() ile zaten notify ediyor

    // Arka plan servisi ayrı bir FlutterEngine'de çalışıyor ve
    // shared_preferences bu iki motor arasında güvenilmez kalıyor — veri
    // cloud'dan geldiyse local'e hiç yazılmadığı için arka plan servisi
    // AdGuard'ı hep "yapılandırılmamış" görüp widget'ı hiç güncellemiyordu.
    // Aynı bilgi, tüm oturum boyunca güvenilir çalıştığı kanıtlanmış
    // home_widget deposuna da yazılıyor (bkz. NotificationProvider,
    // ProxmoxProvider, NutProvider'daki aynı düzeltme).
    await HomeWidget.saveWidgetData(
      'bg_adguard_config',
      jsonEncode({
        'primaryUrl': primaryUrl,
        'secondaryUrl': secondaryUrl,
        'username': username,
        'password': password,
      }),
    );
  }

  Future<void> saveConfig({
    required String primaryUrl,
    required String secondaryUrl,
    required String username,
    required String password,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      prefs.setString('adguard_primary_url', primaryUrl),
      prefs.setString('adguard_secondary_url', secondaryUrl),
      prefs.setString('adguard_username', username),
      prefs.setString('adguard_password', password),
    ]);
    // Kullanıcı adı/şifre cloud'a hiç yazılmaz — sadece URL'ler (yapı) ve
    // "bu cihazda kimlik bilgisi girildi mi" bayrağı senkronize olur (bkz.
    // credential_sync.dart).
    final cloud = CloudSyncService();
    await cloud.saveSettings({
      'adguard_primary_url': primaryUrl,
      'adguard_secondary_url': secondaryUrl,
      'adguard_has_credentials': username.isNotEmpty,
    });

    needsCredentials = false;
    _service.configure(
      primaryUrl: primaryUrl,
      secondaryUrl: secondaryUrl,
      username: username,
      password: password,
    );
    isConfigured = true;
    // notifyListeners kaldırıldı — refresh() zaten sonunda notify ediyor
    await HomeWidget.saveWidgetData(
      'bg_adguard_config',
      jsonEncode({
        'primaryUrl': primaryUrl,
        'secondaryUrl': secondaryUrl,
        'username': username,
        'password': password,
      }),
    );
    await refresh();
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => refresh());
  }

  Future<void> refresh() async {
    if (!isConfigured) return;
    if (isLoading) return;

    // Sadece bir notifyListeners — isLoading flag'i okuyucular zaten
    // select ile dinliyorsa gereksiz rebuild olmaz
    isLoading = true;
    error = null;
    notifyListeners();

    try {
      final results = await Future.wait<Map<String, dynamic>>([
        _service.getStats(),
        _service.getStatus(),
      ]);
      stats = results[0];
      status = results[1];
      isConnected = true;
      isStale = false;
      lastSuccessAt = DateTime.now();
    } catch (e) {
      error = e.toString();
      isConnected = false;
      // Eski veri UI'da kalmaya devam eder — sadece "bayat" işaretlenir.
      isStale = stats.isNotEmpty;
    }

    isLoading = false;
    notifyListeners();
    WidgetService.updateAdGuard(this);
  }

  Future<void> loadFilters() async {
    try {
      final data = await _service.getFilters();
      filteringStatus = data;
      filters = data['filters'] as List? ?? [];
      whitelistFilters = data['whitelist_filters'] as List? ?? [];
      userRules = _service.parseUserRules(data);
      notifyListeners();
    } catch (e) {
      error = e.toString();
      notifyListeners();
    }
  }

  Future<void> loadQueryLog({bool reset = false}) async {
    if (queryLogLoading) return;

    if (reset) {
      queryLogOffset = 0;
      queryLogHasMore = true;
      // queryLog temizliği notify'dan önce değil, veri gelince yapılıyor
      // flash önlendi
    }
    if (!queryLogHasMore) return;

    queryLogLoading = true;
    notifyListeners();

    try {
      final data = await _service.getQueryLog(
        limit: 50,
        offset: queryLogOffset,
        search: _queryLogSearch.isNotEmpty ? _queryLogSearch : null,
        responseStatus: _queryLogFilter != 'all' ? _queryLogFilter : null,
      );
      final newItems = data['data'] as List? ?? [];

      if (reset) {
        // Veri geldikten sonra temizle + ekle — tek notify, flash yok
        queryLog = List.from(newItems);
      } else {
        queryLog.addAll(newItems);
      }

      if (newItems.length < 50) queryLogHasMore = false;
      queryLogOffset += newItems.length;
    } catch (e) {
      error = e.toString();
    }

    queryLogLoading = false;
    notifyListeners();
  }

  Future<void> loadFeatures() async {
    try {
      final results = await Future.wait<dynamic>([
        _service.getSafeBrowsing(),
        _service.getParentalControl(),
        _service.getSafeSearch(),
        _service.getDnsConfig(),
        _service.getClients(),
      ]);
      safeBrowsing = results[0] as bool;
      parentalControl = results[1] as bool;
      safeSearch = results[2] as Map<String, dynamic>;
      dnsConfig = results[3] as Map<String, dynamic>;
      clients = results[4] as Map<String, dynamic>;
      notifyListeners();
    } catch (e) {
      error = e.toString();
      notifyListeners();
    }
  }

  /// İşlem sürüyor göstergesi için — hangi toggle'ın anda beklemede olduğu.
  /// Switch'ler bunu görüp kendi yerine küçük bir spinner çizer.
  final Set<String> loadingToggles = {};

  Future<void> _withToggleLoading(String key, Future<void> Function() fn) async {
    loadingToggles.add(key);
    notifyListeners();
    try {
      await fn();
    } finally {
      loadingToggles.remove(key);
      notifyListeners();
    }
  }

  Future<void> toggleProtection() => _withToggleLoading('protection', () async {
        final current = status['protection_enabled'] ?? true;
        await _service.setProtection(!current);
        await refresh();
      });

  Future<void> toggleSafeBrowsing() => _withToggleLoading('safe_browsing', () async {
        final prev = safeBrowsing;
        safeBrowsing = !prev;
        notifyListeners();
        try {
          await _service.toggleSafeBrowsing(safeBrowsing);
        } catch (e) {
          safeBrowsing = prev; // rollback
          error = e.toString();
          notifyListeners();
        }
      });

  Future<void> toggleParentalControl() =>
      _withToggleLoading('parental_control', () async {
        final prev = parentalControl;
        parentalControl = !prev;
        notifyListeners();
        try {
          await _service.toggleParentalControl(parentalControl);
        } catch (e) {
          parentalControl = prev; // rollback
          error = e.toString();
          notifyListeners();
        }
      });

  Future<void> toggleSafeSearch() => _withToggleLoading('safe_search', () async {
        final current = safeSearch['enabled'] ?? false;
        safeSearch['enabled'] = !current;
        notifyListeners();
        try {
          await _service.toggleSafeSearch(!current);
        } catch (e) {
          safeSearch['enabled'] = current; // rollback
          error = e.toString();
          notifyListeners();
        }
      });

  Future<void> toggleFilter(Map<String, dynamic> filter) =>
      _withToggleLoading('filter_${filter['id']}', () async {
        final enabled = !(filter['enabled'] ?? false);
        await _service.toggleFilter(
          filter['id'] as int,
          enabled,
          filter['url'] as String,
          filter['name'] as String,
        );
        await loadFilters();
      });

  Future<void> addFilter(String url, String name,
      {bool whitelist = false}) async {
    await _service.addFilter(url, name, whitelist: whitelist);
    await loadFilters();
  }

  Future<void> removeFilter(String url, {bool whitelist = false}) async {
    await _service.removeFilter(url, whitelist: whitelist);
    await loadFilters();
  }

  Future<void> refreshFilters() async {
    await _service.refreshFilters();
    await loadFilters();
  }

  Future<void> saveUserRules(List<String> rules) async {
    await _service.setUserRules(rules);
    userRules = rules;
    notifyListeners();
  }

  Future<void> clearQueryLog() async {
    await _service.clearQueryLog();
    await loadQueryLog(reset: true);
  }

  Future<void> resetStats() async {
    await _service.resetStats();
    await refresh();
  }

  Future<void> setDnsConfig(Map<String, dynamic> config) async {
    await _service.setDnsConfig(config);
    dnsConfig = config;
    notifyListeners();
  }

  void reset() {
    _timer?.cancel();
    isConfigured = false;
    isLoading = false;
    isConnected = false;
    error = null;
    stats = {};
    status = {};
    queryLog = [];
    filters = [];
    whitelistFilters = [];
    userRules = [];
    safeBrowsing = false;
    parentalControl = false;
    safeSearch = {};
    dnsConfig = {};
    clients = {};
    loadingToggles.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
