import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Sayfa/sekme geçişleri için tek, paylaşılan koreografi — tüm navigasyon
/// bu dosyadan akar. Yeni süre/eğri icat edilmez, sadece [AppMotion] token'ları
/// farklı desenlere uygulanır.
class AppTransitions {
  AppTransitions._();

  /// Liste → detay ve hiyerarşik iniş (sharedAxis-horizontal benzeri).
  /// Sağdan sola kayarak + fade ile açılır, geri dönüşte sola solarak kayar.
  ///
  /// Kullanım:
  ///   Navigator.push(context, AppTransitions.slideFade(SettingsScreen()));
  static PageRouteBuilder<T> slideFade<T>(
    Widget page, {
    Duration duration = AppMotion.base,
    Duration reverseDuration = AppMotion.base,
  }) {
    return PageRouteBuilder<T>(
      pageBuilder: (_, __, ___) => page,
      transitionDuration: duration,
      reverseTransitionDuration: reverseDuration,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        // Gelen sayfa: sağdan sola + fade in
        final slideIn = Tween<Offset>(
          begin: const Offset(0.06, 0),
          end: Offset.zero,
        ).animate(CurvedAnimation(
          parent: animation,
          curve: AppMotion.curve,
        ));

        // Giden sayfa: sola doğru hafifçe kayar + fade out
        final slideOut = Tween<Offset>(
          begin: Offset.zero,
          end: const Offset(-0.04, 0),
        ).animate(CurvedAnimation(
          parent: secondaryAnimation,
          curve: AppMotion.curve,
        ));

        final fadeIn = CurvedAnimation(
          parent: animation,
          curve: const Interval(0.0, 0.6, curve: AppMotion.curve),
        );

        return SlideTransition(
          position: slideOut,
          child: SlideTransition(
            position: slideIn,
            child: FadeTransition(
              opacity: fadeIn,
              child: child,
            ),
          ),
        );
      },
    );
  }

  /// Mod değişimi hissi veren geçiş (auth ↔ ana uygulama gibi) — düz fade +
  /// hafif ölçek, yatay kayma YOK. [slideFade]'den bilinçli olarak görsel
  /// olarak ayrışır: hiyerarşik "ileri gitme" değil, bağlamın tamamen
  /// değiştiği anlar için.
  ///
  /// Kullanım:
  ///   Navigator.pushReplacement(context, AppTransitions.fadeThrough(HomeScreen()));
  static PageRouteBuilder<T> fadeThrough<T>(
    Widget page, {
    Duration duration = AppMotion.base,
  }) {
    return PageRouteBuilder<T>(
      pageBuilder: (_, __, ___) => page,
      transitionDuration: duration,
      reverseTransitionDuration: duration,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(parent: animation, curve: AppMotion.curve);
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.96, end: 1.0).animate(curved),
            child: child,
          ),
        );
      },
    );
  }
}

/// [showModalBottomSheet] sarmalayıcısı — açılış/kapanış süresi+eğrisini
/// [AppMotion.base]/[AppMotion.curve] ile senkron eder. Parametreler mevcut
/// çağrı yerlerinde kullanılanlarla birebir aynı; yeni ihtiyaç çıkarsa
/// buraya eklenir.
Future<T?> appShowModalBottomSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  Color? backgroundColor,
  ShapeBorder? shape,
  bool isScrollControlled = false,
}) {
  return showModalBottomSheet<T>(
    context: context,
    builder: builder,
    backgroundColor: backgroundColor,
    shape: shape,
    isScrollControlled: isScrollControlled,
    sheetAnimationStyle: const AnimationStyle(
      duration: AppMotion.base,
      reverseDuration: AppMotion.base,
      curve: AppMotion.curve,
      reverseCurve: AppMotion.curve,
    ),
  );
}

/// [showDialog] sarmalayıcısı — aynı senkron mantığı dialoglara uygular.
Future<T?> appShowDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) {
  return showDialog<T>(
    context: context,
    builder: builder,
    barrierDismissible: barrierDismissible,
    animationStyle: const AnimationStyle(
      duration: AppMotion.base,
      reverseDuration: AppMotion.base,
      curve: AppMotion.curve,
      reverseCurve: AppMotion.curve,
    ),
  );
}
