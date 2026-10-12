import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../features/dashboard/error_log_service.dart';

/// Yakalanmamış bir hatanın kullanıcıya gösterilecek kimliği: hangi ekranda
/// oluştuğu ve kısa, sabit bir kod (ör. `SYS-7F3A`). Aynı hata (aynı tip,
/// aynı dosya:satır) her seferinde aynı kodu üretir — kullanıcının ekran
/// görüntüsündeki kod, Hata Günlüğü'ndeki kayıtla birebir eşleşir.
class ErrorOrigin {
  final String screenName;
  final String code;
  const ErrorOrigin(this.screenName, this.code);
}

// Dosya adı → (kod öneki, ekran adı). Önce tam dosya adı, sonra özellik
// klasörü denenir; hiçbiri eşleşmezse genel 'APP / Uygulama'ya düşülür.
const _fileOrigins = <String, (String, String)>{
  'system_screen': ('SYS', 'Sistem'),
  'home_screen': ('HOM', 'Ana Ekran'),
  'settings_screen': ('SET', 'Ayarlar'),
  'about_screen': ('ABT', 'Hakkında'),
  'auth_screen': ('AUT', 'Giriş'),
  'error_log_screen': ('LOG', 'Hata Günlüğü'),
  'proxmox_connection_screen': ('CON', 'Sunucu Bağlantısı'),
  'security_settings_screen': ('SEC', 'Güvenlik'),
  'tab_settings_screen': ('TAB', 'Sekme Ayarları'),
  'container_detail_page': ('CTD', 'Konteyner Detayı'),
  'create_container_screen': ('CTN', 'Yeni Konteyner'),
  'create_vm_screen': ('VMN', 'Yeni Sanal Makine'),
};

const _featureOrigins = <String, (String, String)>{
  'proxmox': ('PVE', 'Proxmox'),
  'adguard': ('ADG', 'AdGuard'),
  'ups': ('UPS', 'UPS'),
  'terminal': ('TRM', 'Terminal'),
  'wol': ('WOL', 'Wake-on-LAN'),
  'notifications': ('BLD', 'Bildirimler'),
  'update': ('GNC', 'Güncelleme'),
  'dashboard': ('APP', 'Uygulama'),
};

final _appFrame = RegExp(r'package:mtools/([\w/]+)\.dart:(\d+)');

/// [error] ve [stack]'ten ekran adını ve kısa kodu türetir. Stack'teki ilk
/// `package:mtools/` karesi hatanın kaynağı kabul edilir.
ErrorOrigin describeError(Object error, StackTrace? stack) {
  final match = _appFrame.firstMatch(stack?.toString() ?? '');
  var prefix = 'APP';
  var screenName = 'Uygulama';
  var location = 'unknown';

  if (match != null) {
    final path = match.group(1)!;
    location = '$path:${match.group(2)}';
    final segments = path.split('/');
    final file = segments.last;
    final feature = segments.length >= 3 && segments[0] == 'features'
        ? segments[1]
        : null;
    final origin = _fileOrigins[file] ?? _featureOrigins[feature];
    if (origin != null) (prefix, screenName) = origin;
  }

  final hash = _fnv1a32('${error.runtimeType}|$location') & 0xFFFF;
  final code =
      '$prefix-${hash.toRadixString(16).toUpperCase().padLeft(4, '0')}';
  return ErrorOrigin(screenName, code);
}

// Dart'ın String.hashCode'u çalıştırmalar arası sabit olmak zorunda değil —
// kodun her sürümde/cihazda aynı kalması için kendi FNV-1a hash'imiz.
int _fnv1a32(String input) {
  var hash = 0x811C9DC5;
  for (final unit in input.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xFFFFFFFF;
  }
  return hash;
}

/// Hatayı, kullanıcıya gösterilen kodla birlikte ErrorLogService'e yazar.
/// Teknik ayrıntı (stack trace) sadece günlükte durur.
Future<void> logUncaughtError(Object error, StackTrace? stack) async {
  final origin = describeError(error, stack);
  try {
    final log = ErrorLogService();
    // Bu izolatta henüz yüklenmemişse mevcut kayıtları ezmemek için önce
    // diskten yükle (bkz. notification_dispatch.dart'taki aynı not).
    await log.load();
    await log.log(
      type: ErrorLogType.unknown,
      message: '[${origin.code}] ${origin.screenName} ekranında hata: '
          '${error.runtimeType}',
      detail: '$error\n\n$stack',
    );
  } catch (e) {
    // Bilinçli sessiz: günlüğe yazma da başarısız olursa yapılacak başka
    // bir şey yok — en azından konsola düşsün.
    debugPrint('[MTools] Hata günlüğe yazılamadı: $e');
  }
}

/// Framework (build/layout/paint) ve asenkron (zone dışı) hataları
/// ErrorLogService'e yönlendirir. `main()` içinde `runApp`'ten önce çağrılır.
void installCrashReporting() {
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    unawaited(logUncaughtError(details.exception, details.stack));
    // Konsol çıktısı (debug'da kırmızı ekran ayrıntısı) korunuyor.
    (previous ?? FlutterError.presentError)(details);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    unawaited(logUncaughtError(error, stack));
    debugPrint('[MTools] Yakalanmamış hata: $error');
    return true;
  };
}
