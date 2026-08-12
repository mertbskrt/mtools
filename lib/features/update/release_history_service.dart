import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

class GithubReleaseInfo {
  final String tagName;
  final DateTime publishedAt;
  final String body;

  GithubReleaseInfo({
    required this.tagName,
    required this.publishedAt,
    required this.body,
  });

  factory GithubReleaseInfo.fromJson(Map<String, dynamic> j) => GithubReleaseInfo(
        tagName: j['tag_name'] as String? ?? '',
        publishedAt: DateTime.tryParse(j['published_at'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        body: j['body'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        'tag_name': tagName,
        'published_at': publishedAt.toIso8601String(),
        'body': body,
      };
}

/// mtools-releases'teki TÜM geçmiş release'leri GitHub'ın public REST
/// API'sinden çeker (kimlik doğrulama gerekmiyor, public repo) — sadece
/// "Sürüm Geçmişi" ekranı açıldığında, o da 1 saatlik bir SharedPreferences
/// önbelleği tazeyse hiç çağrılmadan. Ekran nadiren açılacağı ve önbellek
/// bulunduğu için kimliksiz isteklerin saatlik limitine (60/saat) pratikte
/// hiç yaklaşılmıyor.
///
/// GitHub REST API, User-Agent header'ı olmayan isteklerde 403 döndürüyor —
/// Dio bunu kendiliğinden eklemiyor, burada elle ekleniyor.
class ReleaseHistoryService {
  static const _apiUrl =
      'https://api.github.com/repos/mertbskrt/mtools-releases/releases?per_page=100';
  static const _cacheKey = 'release_history_cache_json';
  static const _cacheAtKey = 'release_history_cached_at';
  static const _cacheTtl = Duration(hours: 1);

  final Dio _dio = Dio();

  Future<List<GithubReleaseInfo>> fetch() async {
    final prefs = await SharedPreferences.getInstance();
    final cachedAtMs = prefs.getInt(_cacheAtKey);
    final cachedJson = prefs.getString(_cacheKey);
    if (cachedAtMs != null && cachedJson != null) {
      final age = DateTime.now()
          .difference(DateTime.fromMillisecondsSinceEpoch(cachedAtMs));
      if (age < _cacheTtl) {
        return _decode(cachedJson);
      }
    }

    final res = await _dio.get<List<dynamic>>(
      _apiUrl,
      options: Options(headers: {'User-Agent': 'MTools-App'}),
    );
    final releases = (res.data ?? const [])
        .map((e) => GithubReleaseInfo.fromJson(e as Map<String, dynamic>))
        .toList();

    await prefs.setString(
        _cacheKey, jsonEncode(releases.map((r) => r.toJson()).toList()));
    await prefs.setInt(_cacheAtKey, DateTime.now().millisecondsSinceEpoch);

    return releases;
  }

  List<GithubReleaseInfo> _decode(String json) {
    final list = jsonDecode(json) as List<dynamic>;
    return list
        .map((e) => GithubReleaseInfo.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
