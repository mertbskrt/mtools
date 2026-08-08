import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import '../dashboard/error_log_service.dart';

/// Manifest'in ham byte'larını, sunucunun offline private key ile imzaladığı
/// Ed25519 imzasına karşı doğrular. Bu, sunucu/hesap ele geçirilse bile
/// sahte veya downgrade edici bir güncelleme yayınlanamamasını sağlayan
/// katmandır — private key hiçbir zaman uygulamaya girmez.
///
/// Doğrulama JSON parse edilmeden ÖNCE, ham byte'lar üzerinden yapılır;
/// böylece JSON canonicalization (alan sırası, boşluk vb.) imza sonucunu
/// etkilemez.
class SignatureVerifier {
  static const _publicKeyB64 = '+k98A4Q8ZH6APguuahVq7mdCHd8f1cj6oYoGiNpU2yc=';
  static final _algo = Ed25519();

  /// Herhangi bir hata veya uyuşmazlıkta false döner (fail-closed) —
  /// çağıran taraf false durumunda güncellemeyi kesinlikle reddetmelidir.
  static Future<bool> verify(
      Uint8List manifestBytes, String signatureB64) async {
    try {
      final pubKey = SimplePublicKey(
        base64.decode(_publicKeyB64),
        type: KeyPairType.ed25519,
      );
      final signature = Signature(
        base64.decode(signatureB64.trim()),
        publicKey: pubKey,
      );
      return await _algo.verify(manifestBytes, signature: signature);
    } catch (e) {
      // Güvenli başarısızlık davranışı (false dönmesi) burada değişmiyor —
      // sadece ileride masum bir sebepten (ör. algoritma/kütüphane
      // değişikliği) bozulursa iz sürülebilsin diye kaydediliyor.
      await ErrorLogService().log(
        type: ErrorLogType.unknown,
        message: 'Güncelleme imzası doğrulanamadı',
        detail: e.toString(),
      );
      return false;
    }
  }
}
