import 'dart:async';
import 'package:flutter/widgets.dart';

/// Canlı ekran verisini 30 sn'de bir yenileyen provider'lar için ortak
/// yoklama döngüsü — uygulama arka plandayken (paused) durur, ön plana
/// dönünce hemen bir [refresh] yapıp devam eder.
///
/// Neden: arka plan servisi (background_service.dart) kalıcı foreground
/// olduğundan süreç artık arka planda dondurulmuyor; bu timer'lar görünmeyen
/// ekranlar için yoklamaya devam ederdi. Bildirim için gereken tüm
/// kontroller (Proxmox/UPS/AdGuard) zaten arka plan servisinde, provider'dan
/// bağımsız yapılıyor.
mixin ForegroundPolling on ChangeNotifier {
  Timer? _pollTimer;
  // Döngü isteniyor mu (startPolling sonrası true, stopPolling sonrası
  // false) — reset() ile bilinçli durdurulmuş bir döngü ön plana dönüşte
  // yeniden başlamamalı.
  bool _pollingWanted = false;
  bool _inBackground = false;
  AppLifecycleListener? _lifecycleListener;

  Future<void> refresh();

  /// Periyodik yenilemeyi başlatır (ya da yeniden kurar). Uygulama o an
  /// arka plandaysa timer ön plana dönüşte kurulur.
  void startPolling() {
    _pollingWanted = true;
    _lifecycleListener ??= AppLifecycleListener(
      onPause: _pausePolling,
      onResume: _resumePolling,
    );
    _pollTimer?.cancel();
    _pollTimer = _inBackground
        ? null
        : Timer.periodic(const Duration(seconds: 30), (_) => refresh());
  }

  /// Döngüyü bilinçli olarak durdurur (oturum kapatma, sıfırlama).
  void stopPolling() {
    _pollingWanted = false;
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  /// `dispose()` içinden çağrılır.
  void disposePolling() {
    stopPolling();
    _lifecycleListener?.dispose();
    _lifecycleListener = null;
  }

  void _pausePolling() {
    _inBackground = true;
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  void _resumePolling() {
    _inBackground = false;
    if (!_pollingWanted) return;
    refresh();
    startPolling();
  }
}
