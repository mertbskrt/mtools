import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'core/theme/app_theme.dart';
import 'features/dashboard/splash_screen.dart';
import 'features/dashboard/auth_screen.dart';
import 'features/dashboard/home_screen.dart';
import 'package:provider/provider.dart';
import 'features/proxmox/proxmox_provider.dart';
import 'shared/models/alias_provider.dart';
import 'features/notifications/notification_provider.dart';
import 'features/notifications/background_service.dart';
import 'shared/models/tab_config.dart';
import 'features/adguard/adguard_provider.dart';
import 'features/ups/nut_provider.dart';
import 'core/services/connectivity_provider.dart';
import 'package:showcaseview/showcaseview.dart';
import 'core/services/crash_reporter.dart';
import 'core/widgets/error_fallback.dart';
import 'features/dashboard/error_log_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Günlük açılışta bir kez diskten yüklenir — aksi halde bu oturumdaki ilk
  // ErrorLogService().log() çağrısı boş bellek listesini kaydedip önceki
  // oturumların kayıtlarını eziyordu.
  await ErrorLogService().load();
  // Yakalanmamış framework/asenkron hatalar ErrorLogService'e, hata
  // ekranında gösterilen kısa kodla birlikte yazılır (bkz. crash_reporter.dart).
  installCrashReporting();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  // Servis burada, uygulama açılışında bir kez başlatılır (bkz.
  // background_service.dart üstündeki not — Android, uygulama arka
  // plandayken yeni bir foreground service başlatılmasını kısıtladığı için
  // servis bir daha asla start/stop edilmez, yalnızca ön plan/arka plan
  // MODU değiştirilir).
  await initBackgroundService();

  // Kalıcı "izleniyor" bildirimi SADECE uygulama gerçekten arka
  // plandayken görünür; uygulama açıkken canlı ekranlar zaten aynı
  // verileri çektiği için bildirim gizli kalır. AppLifecycleListener
  // kendini WidgetsBinding'e kaydeder, ayrıca bir değişkende tutulmasına
  // gerek yok.
  AppLifecycleListener(
    onPause: notifyAppBackgrounded,
    onResume: notifyAppForegrounded,
  );

  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFF0D0D0D),
    ),
  );

  // Bir ekran build() sırasında beklenmeyen bir hata fırlatırsa Flutter'ın
  // varsayılan davranışı: debug'da kırmızı hata ekranı, release'te ise
  // düz gri/boş bir kutu ("beyaz ekran"). Debug'da orijinal detaylı hata
  // ekranı korunuyor (geliştirmeyi kolaylaştırmak için); release'te
  // kullanıcı hiçbir zaman boş bir ekranla karşılaşmasın diye MTools
  // markalı, anlaşılır bir mesaj gösteriliyor — ekran adı ve kısa hata kodu
  // ile (aynı kod Hata Günlüğü'ndeki kayıtta da var).
  if (kReleaseMode) {
    ErrorWidget.builder = GlobalErrorFallback.fromDetails;
  }

  runApp(const MToolsApp());
}

class MToolsApp extends StatelessWidget {
  const MToolsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ConnectivityProvider()..start()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => NotificationProvider()..init()),
        ChangeNotifierProvider(create: (_) => AliasProvider()..load()),
        ChangeNotifierProvider(create: (_) => AdGuardProvider()),
        ChangeNotifierProvider(create: (_) => NutProvider()),
        ChangeNotifierProxyProvider2<NotificationProvider, NutProvider, ProxmoxProvider>(
          create: (_) => ProxmoxProvider(),
          update: (_, notif, nut, proxmox) {
            proxmox!.notificationProvider = notif;
            proxmox.nutProvider = nut;
            return proxmox;
          },
        ),
        ChangeNotifierProvider(create: (_) => TabConfigProvider()..load()),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, _) {
          return AppThemeScope(
            themeData: themeProvider.current,
            child: ShowCaseWidget(
              // Ayarlar ekranındaki hedefler scrollable bir ListView içinde
              // — bu olmadan hedef görünür alanda değilse tooltip yanlış
              // yerde/taşmış kalıyordu. Paketin kendi Scrollable.ensureVisible
              // mekanizması, her adımı otomatik doğru konuma kaydırıyor.
              enableAutoScroll: true,
              scrollDuration: AppMotion.base,
              builder: (context) => MaterialApp(
                title: 'MTools',
                debugShowCheckedModeBanner: false,
                theme: themeProvider.themeData,
                initialRoute: '/',
                routes: {
                  '/': (context) => const SplashScreen(),
                  '/login': (context) => const AuthScreen(),
                  '/pin_entry': (context) => const AuthScreen(),
                  '/home': (context) => const HomeScreen(),
                },
              ),
            ),
          );
        },
      ),
    );
  }
}