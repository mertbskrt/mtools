import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';

class AdGuardService {
  Dio? _primaryDio;
  Dio? _secondaryDio;

  String _primaryUrl = '';
  String _secondaryUrl = '';
  String _username = '';
  String _password = '';
  bool _configured = false;

  bool get isConfigured => _configured;

  String? _lastFailedHost;

  /// En son hangi host'un (primary ya da secondary) hata verdiği — bağlantı
  /// hatası sınıflandırması (bkz. connection_target.dart) için kullanılır.
  /// Başarılı bir istek olduğunda null'a döner.
  String? get lastFailedHost => _lastFailedHost;

  void configure({
    required String primaryUrl,
    String secondaryUrl = '',
    required String username,
    required String password,
  }) {
    _primaryUrl = _stripTrailingSlash(primaryUrl);
    _secondaryUrl = _stripTrailingSlash(secondaryUrl);
    _username = username;
    _password = password;
    _configured = true;

    _primaryDio = _buildDio(_primaryUrl);
    _secondaryDio =
        _secondaryUrl.isNotEmpty ? _buildDio(_secondaryUrl) : null;
  }

  String _stripTrailingSlash(String url) =>
      url.endsWith('/') ? url.substring(0, url.length - 1) : url;

  Dio _buildDio(String baseUrl) {
    final dio = Dio(BaseOptions(
      baseUrl: '$baseUrl/control',
      headers: {
        // dart:convert ile güvenli Base64 encoding
        'Authorization':
            'Basic ${base64Encode(utf8.encode('$_username:$_password'))}',
        'Content-Type': 'application/json',
      },
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 10),
      validateStatus: (s) => true,
    ));

    // Self-signed sertifika desteği — sadece local ağ için kullanılmalı
    (dio.httpClientAdapter as IOHttpClientAdapter).createHttpClient = () {
      final client = HttpClient();
      client.badCertificateCallback = (cert, host, port) => true;
      return client;
    };

    return dio;
  }

  Future<Response> _get(String path, {Map<String, dynamic>? params}) async {
    final primary = _primaryDio!;
    try {
      final res = await primary.get(path, queryParameters: params);
      if (res.statusCode != null && res.statusCode! < 500) {
        _lastFailedHost = null;
        return res;
      }
      throw Exception('Server error: ${res.statusCode}');
    } catch (e) {
      final secondary = _secondaryDio;
      if (secondary != null) {
        try {
          // Secondary başarısız olursa exception üste fırlar, Dio durumu bozulmaz
          final res = await secondary.get(path, queryParameters: params);
          _lastFailedHost = null;
          return res;
        } catch (_) {
          _lastFailedHost = _secondaryUrl;
          rethrow;
        }
      }
      _lastFailedHost = _primaryUrl;
      rethrow;
    }
  }

  Future<Response> _post(String path, {dynamic data}) async {
    final primary = _primaryDio!;
    try {
      final res = await primary.post(path, data: data);
      if (res.statusCode != null && res.statusCode! < 500) {
        _lastFailedHost = null;
        return res;
      }
      throw Exception('Server error: ${res.statusCode}');
    } catch (e) {
      final secondary = _secondaryDio;
      if (secondary != null) {
        try {
          final res = await secondary.post(path, data: data);
          _lastFailedHost = null;
          return res;
        } catch (_) {
          _lastFailedHost = _secondaryUrl;
          rethrow;
        }
      }
      _lastFailedHost = _primaryUrl;
      rethrow;
    }
  }

  // ── Stats ──────────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> getStats() async {
    final res = await _get('/stats');
    return res.data ?? {};
  }

  Future<Map<String, dynamic>> getStatus() async {
    final res = await _get('/status');
    return res.data ?? {};
  }

  Future<void> resetStats() async {
    await _post('/stats_reset');
  }

  // ── Query Log ──────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> getQueryLog({
    int limit = 100,
    int offset = 0,
    String? search,
    String? responseStatus,
  }) async {
    final params = <String, dynamic>{'limit': limit, 'offset': offset};
    if (search != null && search.isNotEmpty) params['search'] = search;
    if (responseStatus != null && responseStatus != 'all') {
      params['response_status'] = responseStatus;
    }
    final res = await _get('/querylog', params: params);
    return res.data ?? {};
  }

  Future<void> clearQueryLog() async {
    await _post('/querylog_clear');
  }

  // ── Filtering ──────────────────────────────────────────────────────────────

  /// Hem filtre listelerini hem user rules'u tek istekte döndürür.
  /// Provider'da getFilters + getUserRules ayrı çağrılmamalı.
  Future<Map<String, dynamic>> getFilters() async {
    final res = await _get('/filtering/status');
    return res.data ?? {};
  }

  /// [getFilters] içinden parse et, ayrı istek atma.
  List<String> parseUserRules(Map<String, dynamic> filteringStatus) {
    final rules = filteringStatus['user_rules'] as List? ?? [];
    return rules.cast<String>();
  }

  Future<void> toggleFilter(
      int filterId, bool enabled, String url, String name) async {
    await _post('/filtering/set_url', data: {
      'data': {'enabled': enabled, 'id': filterId, 'name': name, 'url': url},
      'url': url,
    });
  }

  Future<void> addFilter(String url, String name,
      {bool whitelist = false}) async {
    await _post('/filtering/add_url',
        data: {'name': name, 'url': url, 'whitelist': whitelist});
  }

  Future<void> removeFilter(String url, {bool whitelist = false}) async {
    await _post('/filtering/remove_url',
        data: {'url': url, 'whitelist': whitelist});
  }

  Future<void> refreshFilters() async {
    // Paralel yenileme — ikisi de aynı anda gönderilir
    await Future.wait([
      _post('/filtering/refresh', data: {'whitelist': false}),
      _post('/filtering/refresh', data: {'whitelist': true}),
    ]);
  }

  Future<void> setUserRules(List<String> rules) async {
    await _post('/filtering/set_rules', data: {'rules': rules});
  }

  // ── Protection & Safety ────────────────────────────────────────────────────

  Future<void> setProtection(bool enabled) async {
    await _post('/dns_config', data: {'protection_enabled': enabled});
  }

  Future<bool> getSafeBrowsing() async {
    final res = await _get('/safebrowsing/status');
    return (res.data?['enabled'] ?? false) as bool;
  }

  Future<void> toggleSafeBrowsing(bool enabled) async {
    await _post(enabled ? '/safebrowsing/enable' : '/safebrowsing/disable');
  }

  Future<bool> getParentalControl() async {
    final res = await _get('/parental/status');
    return (res.data?['enabled'] ?? false) as bool;
  }

  Future<void> toggleParentalControl(bool enabled) async {
    await _post(enabled ? '/parental/enable' : '/parental/disable');
  }

  Future<Map<String, dynamic>> getSafeSearch() async {
    final res = await _get('/safesearch/status');
    return res.data ?? {};
  }

  Future<void> toggleSafeSearch(bool enabled) async {
    await _post('/safesearch/settings', data: {'enabled': enabled});
  }

  // ── DNS & Clients ──────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> getDnsConfig() async {
    final res = await _get('/dns_config');
    return res.data ?? {};
  }

  Future<void> setDnsConfig(Map<String, dynamic> config) async {
    await _post('/dns_config', data: config);
  }

  Future<Map<String, dynamic>> getClients() async {
    final res = await _get('/clients');
    return res.data ?? {};
  }

  // ── Test ───────────────────────────────────────────────────────────────────

  Future<bool> testConnection() async {
    try {
      final res = await _get('/status');
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}