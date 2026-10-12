import 'dart:io';
import 'dart:ui';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:dio/dio.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../dashboard/error_log_service.dart';
import '../../core/constants/links.dart';

/// Geri bildirim API anahtarı derleme sırasında verilir:
/// `flutter build apk --dart-define=MTOOLS_APP_KEY=...`
/// Değer koda ve repoya girmez; verilmezse boş kalır ve ekran form yerine
/// e-posta seçeneğini gösterir (bkz. [FeedbackService.isConfigured]).
const kMtoolsAppKey = String.fromEnvironment('MTOOLS_APP_KEY');


/// Geri bildirim türleri — sunucunun beklediği değerler ve ekrandaki adları.
enum FeedbackType {
  hata('Hata bildirimi'),
  oneri('Öneri'),
  soru('Soru'),
  diger('Diğer');

  final String label;
  const FeedbackType(this.label);
}

sealed class FeedbackResult {
  const FeedbackResult();
}

class FeedbackSent extends FeedbackResult {
  const FeedbackSent();
}

/// Sunucu isteği reddetti (`{ok: false, hata}`) ya da anlaşılamayan bir
/// yanıt döndü — [message] kullanıcıya olduğu gibi gösterilir.
class FeedbackRejected extends FeedbackResult {
  final String message;
  const FeedbackRejected(this.message);
}

class FeedbackRateLimited extends FeedbackResult {
  const FeedbackRateLimited();
}

class FeedbackNetworkError extends FeedbackResult {
  const FeedbackNetworkError();
}

class FeedbackService {
  static const maxLogEntries = 50;
  static const maxLogChars = 15000;

  final Dio _dio;
  final String _appKey;

  FeedbackService({Dio? dio, String appKey = kMtoolsAppKey})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 15),
            )),
        _appKey = appKey;

  /// Anahtar derlemede verilmediyse form gösterilmez.
  bool get isConfigured => _appKey.isNotEmpty;

  /// ErrorLogService'teki en yeni [maxLogEntries] kaydı, Hata Günlüğü
  /// ekranındaki "kopyala" biçimiyle metne çevirir; [maxLogChars]'ı
  /// aşarsa sondan kırpar (en yeni kayıtlar başta kalır).
  static String formatLog(List<ErrorLogEntry> logs) {
    final text = logs
        .take(maxLogEntries)
        .map((e) => '[${e.time.toIso8601String()}] ${e.typeLabel}: ${e.message}'
            '${e.detail != null ? '\n${e.detail}' : ''}')
        .join('\n\n');
    if (text.length <= maxLogChars) return text;
    const marker = '\n…(kırpıldı)';
    return text.substring(0, maxLogChars - marker.length) + marker;
  }

  /// Gövdedeki `dil`: cihaz dili Türkçe ise "tr", değilse "en".
  static String deviceLanguage([Locale? locale]) =>
      (locale ?? PlatformDispatcher.instance.locale).languageCode == 'tr'
          ? 'tr'
          : 'en';

  Future<FeedbackResult> send({
    required FeedbackType type,
    required String name,
    required String email,
    required String message,
    required bool includeLog,
    Map<String, String>? deviceFields,
  }) async {
    String log = '';
    if (includeLog) {
      await ErrorLogService().load();
      log = formatLog(ErrorLogService().logs);
    }

    final body = {
      'tur': type.name,
      'ad': name.trim(),
      'eposta': email.trim(),
      'mesaj': message.trim(),
      ...(deviceFields ?? await collectDeviceFields()),
      'dil': deviceLanguage(),
      'gunluk': log,
    };

    try {
      final res = await _dio.post<dynamic>(
        MToolsLinks.feedbackEndpoint,
        data: body,
        options: Options(
          contentType: Headers.jsonContentType,
          headers: {'X-MTools-App': _appKey},
          // Hata kodlarını exception yerine yanıt olarak alıp aşağıda
          // ayrıştırıyoruz (429 ve {ok:false, hata} ayrı mesajlar).
          validateStatus: (_) => true,
        ),
      );
      return parseResponse(res.statusCode, res.data);
    } on DioException catch (e) {
      // Sadece gönderim hatasını günlüğe yaz — mesaj içeriğini değil.
      await ErrorLogService().log(
        type: ErrorLogType.connection,
        message: 'Geri bildirim gönderilemedi',
        detail: e.type.name,
      );
      return const FeedbackNetworkError();
    }
  }

  static FeedbackResult parseResponse(int? status, dynamic data) {
    if (status == 429) return const FeedbackRateLimited();
    if (data is Map) {
      if (data['ok'] == true) return const FeedbackSent();
      final hata = data['hata'];
      if (hata is String && hata.trim().isNotEmpty) {
        return FeedbackRejected(hata.trim());
      }
    }
    return FeedbackRejected(
        'Sunucu beklenmeyen bir yanıt verdi (${status ?? '-'}). '
        'Lütfen daha sonra tekrar deneyin ya da ${MToolsLinks.contactEmail} adresine yazın.');
  }

  /// `surum`, `cihaz`, `android` alanları — ör. "3.4.0 (24)",
  /// "Samsung SM-S918B", "14".
  static Future<Map<String, String>> collectDeviceFields() async {
    final info = await PackageInfo.fromPlatform();
    var device = '-';
    var android = '-';
    if (Platform.isAndroid) {
      final a = await DeviceInfoPlugin().androidInfo;
      final maker = a.manufacturer.isEmpty
          ? ''
          : a.manufacturer[0].toUpperCase() + a.manufacturer.substring(1);
      device = '$maker ${a.model}'.trim();
      android = a.version.release;
    }
    return {
      'surum': '${info.version} (${info.buildNumber})',
      'cihaz': device,
      'android': android,
    };
  }
}
