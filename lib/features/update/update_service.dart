import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'update_manifest.dart';
import 'signature_verifier.dart';

class UpdateCheckResult {
  final bool updateAvailable;
  final bool mandatory;
  final UpdateManifest? manifest;
  UpdateCheckResult(this.updateAvailable, this.mandatory, this.manifest);
}

/// GitHub Releases'teki en son yayından manifest + imzayı çeker, Ed25519
/// imzasını doğrular ve telefondaki sürümle karşılaştırır. İmza
/// doğrulaması başarısız olursa güncelleme kesinlikle reddedilir
/// (fail-closed) — sunucu/hesap ele geçirilse bile sahte veya downgrade
/// edici bir güncelleme kabul edilmez.
class UpdateService {
  static const _manifestUrl =
      'https://github.com/mertbskrt/mtools-releases/releases/latest/download/manifest.json';
  static const _sigUrl =
      'https://github.com/mertbskrt/mtools-releases/releases/latest/download/manifest.json.sig';

  final Dio _dio = Dio();

  Future<UpdateCheckResult> check() async {
    final manifestRes = await _dio.get<List<int>>(
      _manifestUrl,
      options: Options(responseType: ResponseType.bytes),
    );
    final sigRes = await _dio.get<String>(
      _sigUrl,
      options: Options(responseType: ResponseType.plain),
    );

    final manifestBytes = Uint8List.fromList(manifestRes.data ?? const []);
    final signatureB64 = sigRes.data ?? '';

    // İMZA DOĞRULAMASI — geçmezse hiçbir alana güvenilmez, akış burada durur.
    final valid = await SignatureVerifier.verify(manifestBytes, signatureB64);
    if (!valid) {
      throw Exception(
          'Manifest imza doğrulaması başarısız — güncelleme reddedildi');
    }

    final manifest =
        UpdateManifest.fromJson(jsonDecode(utf8.decode(manifestBytes)));
    final info = await PackageInfo.fromPlatform();
    final currentCode = int.tryParse(info.buildNumber) ?? 0;

    final hasUpdate = manifest.versionCode > currentCode;
    final forced =
        manifest.mandatory || _isBelowMin(info.version, manifest.minVersion);

    return UpdateCheckResult(hasUpdate, hasUpdate && forced, manifest);
  }

  /// APK dosya boyutunu manifest şemasına dokunmadan öğrenmek için HEAD
  /// isteğiyle Content-Length okunur. Manifest'te böyle bir alan yok ve
  /// eklemek ayrı bir repo (mtools-releases) değişikliği gerektirir — bu
  /// yüzden client-only bu yol tercih edildi. Sunucu Content-Length
  /// döndürmezse (nadir) null döner, çağıran taraf boyutu göstermez.
  Future<int?> fetchApkSize(String apkUrl) async {
    try {
      final res = await _dio.head(apkUrl);
      final len = res.headers.value('content-length');
      return len != null ? int.tryParse(len) : null;
    } catch (_) {
      return null;
    }
  }

  bool _isBelowMin(String current, String min) {
    List<int> parse(String v) =>
        v.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final c = parse(current), m = parse(min);
    for (var i = 0; i < 3 && i < c.length && i < m.length; i++) {
      if (c[i] != m[i]) return c[i] < m[i];
    }
    return false;
  }
}
