import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'update_manifest.dart';

/// APK'yı indirir, SHA-256'sını manifest'teki değerle bit bit doğrular
/// (uyuşmazsa dosyayı siler ve reddeder), kurulum iznini ister ve Android
/// paket yükleyicisini tetikler. Android'in kurulum-anı imza kontrolü
/// (yeni APK aynı release keystore ile imzalı olmalı) bu akışın dışında,
/// işletim sistemi tarafından ayrıca uygulanır.
class UpdateInstaller {
  final Dio _dio = Dio();

  Future<void> downloadAndInstall(
    UpdateManifest m, {
    required void Function(double progress) onProgress,
  }) async {
    final dir = await getTemporaryDirectory();
    final apkPath = '${dir.path}/mtools-${m.latestVersion}.apk';
    final file = File(apkPath);

    // 1) indir (ilerleme bildirimiyle)
    await _dio.download(
      m.apkUrl,
      apkPath,
      onReceiveProgress: (received, total) {
        if (total > 0) onProgress(received / total);
      },
    );

    // 2) SHA-256 doğrula — uyuşmazsa sil ve dur
    final digest = await sha256.bind(file.openRead()).first;
    if (digest.toString().toLowerCase() != m.sha256.toLowerCase()) {
      await file.delete();
      throw Exception('SHA-256 uyuşmuyor — dosya reddedildi');
    }

    // 3) kurulum izni (Android 8+)
    if (!await Permission.requestInstallPackages.isGranted) {
      final status = await Permission.requestInstallPackages.request();
      if (!status.isGranted) {
        throw Exception('Kurulum izni verilmedi');
      }
    }

    // 4) Android paket yükleyicisini tetikle
    final res = await OpenFilex.open(
      apkPath,
      type: 'application/vnd.android.package-archive',
    );
    if (res.type != ResultType.done) {
      throw Exception('Kurulum başlatılamadı: ${res.message}');
    }
  }
}
