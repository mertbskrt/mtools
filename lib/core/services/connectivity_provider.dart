import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';

/// Cihazın gerçek internet erişimini izler — Wi-Fi/mobil veri arayüzünün
/// bağlı olması internetin çalıştığı anlamına gelmez (router'ın interneti
/// gitmiş olabilir), bu yüzden gerçek bir DNS sorgusuyla doğrulanır.
///
/// Bağlantı koptuğunda ekranlar anında (ve birbirinden farklı, kafa
/// karıştırıcı mesajlarla — "Makine bulunamadı", "Sunucu bağlı değil" gibi)
/// tepki vermek yerine, 7 saniye kesintisiz kopukluk doğrulandıktan sonra
/// [hasInternet] false olur; tüm ekranlar bunu izleyip tek/tutarlı bir
/// "Bağlantı Yok" durumu gösterir. Bağlantı geri gelir gelmez (bir sonraki
/// kontrolde) hemen normale döner — uygulamadan çıkıp girmeye gerek yoktur.
class ConnectivityProvider extends ChangeNotifier {
  static const _checkInterval = Duration(seconds: 2);
  static const _offlineThreshold = Duration(seconds: 7);
  static const _lookupHost = 'one.one.one.one';

  Timer? _timer;
  DateTime? _unreachableSince;
  bool _checking = false;
  bool hasInternet = true;

  void start() {
    _timer?.cancel();
    _timer = Timer.periodic(_checkInterval, (_) => _check());
    _check();
  }

  /// Kullanıcı "Tekrar Dene" dediğinde döngüyü beklemeden hemen kontrol eder.
  Future<void> recheckNow() => _check();

  Future<void> _check() async {
    if (_checking) return;
    _checking = true;
    try {
      bool reachable;
      try {
        final result = await InternetAddress.lookup(_lookupHost)
            .timeout(const Duration(seconds: 4));
        reachable = result.isNotEmpty && result.first.rawAddress.isNotEmpty;
      } catch (_) {
        reachable = false;
      }

      if (reachable) {
        _unreachableSince = null;
        if (!hasInternet) {
          hasInternet = true;
          notifyListeners();
        }
        return;
      }

      _unreachableSince ??= DateTime.now();
      final downFor = DateTime.now().difference(_unreachableSince!);
      if (downFor >= _offlineThreshold && hasInternet) {
        hasInternet = false;
        notifyListeners();
      }
    } finally {
      _checking = false;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
