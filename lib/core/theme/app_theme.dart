import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/cloud_sync_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Tasarım token'ları — radius ve spacing artık stilden bağımsız, tek ve
// disiplinli bir ölçek. Eskiden her AppStyle kendi radius/padding değerlerini
// taşıyordu (8/12/16 vb.) — bu, ekranlar arası tutarsız köşe/boşluk kullanımına
// yol açıyordu. AppStyle'ın eski alanları geçiş süresince duruyor (aşağıya
// bakınız) ama yeni kod HER ZAMAN buradaki sabitleri kullanmalı.
// ─────────────────────────────────────────────────────────────────────────────

class AppRadius {
  AppRadius._();
  static const double xs = 4; // rozet, chip
  static const double sm = 6; // buton, input
  static const double md = 10; // kart
  static const double full = 999; // sadece durum noktası gibi dairesel öğeler
}

class AppSpace {
  AppSpace._();
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
}

// Hareket/animasyon token'ları — süre ve eğri de artık dosyadan dosyaya
// rastgele seçilmiyor. Eskiden aynı proje içinde 100/120/150/180/200/250/
// 300/400/500/600/700/800ms gibi 12'den fazla farklı süre ve easeOut/
// easeOutCubic/easeOutBack/easeInOut/elasticIn gibi 5+ farklı eğri bir arada
// kullanılıyordu — hiçbiri kasıtlı bir sebeple seçilmemişti, bu da
// geçişlerin ekrandan ekrana tutarsız/"çat pat" hissettirmesine yol
// açıyordu. Not: bu token'lar sadece GERÇEK görsel geçişler (genişleme/
// daralma, sheet açılışı, sekme geçişi, buton press-scale) için — splash/
// giriş ekranlarındaki dekoratif "nefes alma" animasyonları ve
// Future.delayed tabanlı zamanlayıcılar (yeniden bağlanma gecikmesi,
// snackbar süresi vb.) bu tasarım sisteminin kapsamı dışında, kasıtlı
// olarak dokunulmadı.
class AppMotion {
  AppMotion._();
  static const Duration fast = Duration(milliseconds: 150); // mikro: press-scale, chip/toggle seçimi
  static const Duration base = Duration(milliseconds: 250); // standart: genişleme, sheet, sekme geçişi
  static const Duration slow = Duration(milliseconds: 400); // istisnai: grafik/veri reveal gibi büyük geçişler
  static const Curve curve = Curves.easeOutCubic; // tek standart eğri, abartısız
}

class AppStyle {
  final String id;
  final String name;
  final String description;
  final double cardElevation;

  const AppStyle({
    required this.id,
    required this.name,
    required this.description,
    required this.cardElevation,
  });

  // ── OLED ───────────────────────────────────────────────────────────────────
  // Köşeli, sıkı grid, yüksek kontrast — tam siyah / tam beyaz estetiği
  static const AppStyle classic = AppStyle(
    id: 'classic',
    name: 'OLED',
    description: 'Simsiyah, yüksek kontrast',
    cardElevation: 0,
  );

  // ── Kahve ──────────────────────────────────────────────────────────────────
  // Border yok, sıcak ve toprak tonlarında sessiz bir görünüm
  static const AppStyle minimal = AppStyle(
    id: 'minimal',
    name: 'Kahve',
    description: 'Sıcak ve toprak tonları',
    cardElevation: 0,
  );

  // ── Antrasit ───────────────────────────────────────────────────────────────
  // Yumuşak gölgeler, nötr gri — kurumsal şıklık
  static const AppStyle slate = AppStyle(
    id: 'slate',
    name: 'Antrasit',
    description: 'Kurumsal ve profesyonel',
    cardElevation: 0,
  );

  static const List<AppStyle> all = [classic, minimal, slate];

  static AppStyle fromId(String id) =>
      all.firstWhere((s) => s.id == id, orElse: () => slate);
}

// ─────────────────────────────────────────────────────────────────────────────
// Renk paleti — profesyonel, sakin tonlar
// ─────────────────────────────────────────────────────────────────────────────

class _Palette {
  final Color primary;
  final Color primaryDark;
  final Color success;
  final Color warning;
  final Color error;
  final Color info;

  const _Palette({
    required this.primary,
    required this.primaryDark,
    required this.success,
    required this.warning,
    required this.error,
    required this.info,
  });
}

const Map<String, _Palette> _palettes = {
  // OLED: monokrom gri-gümüş vurgu, mor/mavi yok
  'classic': _Palette(
    primary: Color(0xFFB4B4BA),
    primaryDark: Color(0xFF87878E),
    success: Color(0xFF4CAF80),
    warning: Color(0xFFC98A3D),
    error: Color(0xFFD16565),
    info: Color(0xFF9AA0A6),
  ),
  // Kahve: sıcak bronz/tunç vurgu
  'minimal': _Palette(
    primary: Color(0xFFB08D5A),
    primaryDark: Color(0xFF8A6D42),
    success: Color(0xFF6B9C6B),
    warning: Color(0xFFC98A3D),
    error: Color(0xFFC4645A),
    info: Color(0xFF8C8377),
  ),
  // Antrasit: nötr koyu gri + çamurlu yeşil-turkuaz vurgu
  'slate': _Palette(
    primary: Color(0xFF4E9C8C),
    primaryDark: Color(0xFF357367),
    success: Color(0xFF3DAA7C),
    warning: Color(0xFFC98A3D),
    error: Color(0xFFD16565),
    info: Color(0xFF6B9C99),
  ),
};

// ─────────────────────────────────────────────────────────────────────────────
// AppThemeData
// ─────────────────────────────────────────────────────────────────────────────

class AppThemeData {
  final AppStyle style;
  final bool isDark;

  final Color primary;
  final Color primaryDark;
  final Color bgDark;
  final Color bgCard;
  final Color bgCardLight;
  final Color surface3;
  final Color success;
  final Color warning;
  final Color error;
  final Color info;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;

  const AppThemeData._({
    required this.style,
    required this.isDark,
    required this.primary,
    required this.primaryDark,
    required this.bgDark,
    required this.bgCard,
    required this.bgCardLight,
    required this.surface3,
    required this.success,
    required this.warning,
    required this.error,
    required this.info,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
  });

  // ── Yüzey katmanları — elevation gölgeyle değil ton farkıyla ifade edilir ──
  // surface0 = sayfa zemini, surface1 = kart, surface2 = kart içi grup/input,
  // surface3 = hover/pressed. Eski bgDark/bgCard/bgCardLight adları da (çok
  // sayıda mevcut çağrı noktası için) geçerliliğini koruyor.
  Color get surface0 => bgDark;
  Color get surface1 => bgCard;
  Color get surface2 => bgCardLight;

  // ── Semantic renklerin zemin/tint tonu — rozet arka planı gibi kullanımlar
  // için. Karanlıkta aynı alpha çok daha soluk okunduğundan alpha ayrışıyor.
  Color get successMuted => success.withValues(alpha: isDark ? 0.18 : 0.12);
  Color get warningMuted => warning.withValues(alpha: isDark ? 0.18 : 0.12);
  Color get errorMuted => error.withValues(alpha: isDark ? 0.18 : 0.12);
  Color get infoMuted => info.withValues(alpha: isDark ? 0.18 : 0.12);

  // ── İnce ayraç/kenarlık — kart dışı çizgisi ve liste satırı ayracı için tek,
  // her zaman açık, global ton. Eski stile-özel useBorder/useShadow/
  // useGradientCard alanları kaldırıldı — elevation sadece yüzey tonundan gelir.
  Color get hairline =>
      isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.08);

  // ── Tipografi ölçeği ─────────────────────────────────────────────────────
  TextStyle get pageTitle => TextStyle(
        color: textPrimary,
        fontSize: 20,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
      );

  // sectionLabel metni büyük harfe çevirmez — çağıran taraf zaten büyük harfli
  // metin geçmeli (bkz. design_widgets.dart -> SectionLabel).
  TextStyle get sectionLabel => TextStyle(
        color: textMuted,
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.8,
      );

  TextStyle get body => TextStyle(color: textPrimary, fontSize: 14);

  TextStyle get meta => TextStyle(color: textSecondary, fontSize: 12);

  TextStyle get metric => TextStyle(
        color: textPrimary,
        fontSize: 20,
        fontWeight: FontWeight.w600,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  TextStyle get metricSmall => TextStyle(
        color: textPrimary,
        fontSize: 13,
        fontWeight: FontWeight.w600,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  /// Bir yüzde değerini eşiğe göre semantic renge çevirir — renk sadece
  /// anlam taşır: normal aralıkta nötr (textSecondary), sonra warning, sonra
  /// error. Öntanımlı eşikler (80/90) sistem genelinde uyumlu hale getirildi;
  /// önceden system_screen.dart'ta 85/60, proxmox_screen.dart'ta 80/50 gibi
  /// üç farklı eşik çifti ayrı ayrı kullanılıyordu.
  Color thresholdColor(double value, {double warn = 80, double error = 90}) {
    if (value >= error) return this.error;
    if (value >= warn) return warning;
    return textSecondary;
  }

  factory AppThemeData.build({
    required AppStyle style,
    required bool isDark,
  }) {
    final p = _palettes[style.id] ?? _palettes['slate']!;

    Color bg, card, cardLight, surface3, txtPrimary, txtSecondary, txtMuted;

    if (isDark) {
      switch (style.id) {
        case 'classic':
          // OLED — tam siyah, piksel kapatan gerçek OLED koyu tema
          bg = const Color(0xFF000000);
          card = const Color(0xFF0D0D0D);
          cardLight = const Color(0xFF1A1A1A);
          surface3 = const Color(0xFF242424);
          break;
        case 'minimal':
          // Kahve — sıcak, kahverengi ağırlıklı koyu ton
          bg = const Color(0xFF1B1815);
          card = const Color(0xFF241F1A);
          cardLight = const Color(0xFF2E2822);
          surface3 = const Color(0xFF383029);
          break;
        case 'slate':
          // Antrasit — nötr, soğuk olmayan koyu gri
          bg = const Color(0xFF15171A);
          card = const Color(0xFF1E2124);
          cardLight = const Color(0xFF282B2F);
          surface3 = const Color(0xFF323539);
          break;
        default:
          bg = const Color(0xFF15171A);
          card = const Color(0xFF1E2124);
          cardLight = const Color(0xFF282B2F);
          surface3 = const Color(0xFF323539);
      }
      txtPrimary = const Color(0xFFEDEDED);
      txtSecondary = const Color(0xFFA3A3A3);
      txtMuted = const Color(0xFF5A5A5A);
    } else {
      switch (style.id) {
        case 'classic':
          // Beyaz — OLED'in yüksek kontrastlı aydınlık karşılığı. bg, saf
          // beyaz karttan (surface1) hafifçe ayrışsın diye çok hafif bir gri
          // alıyor — aksi halde sayfa zemini ile kart aynı renk oluyordu
          // (surface0 == surface1), bu da "her katman ayrışacak" kuralını
          // ihlal ediyordu.
          bg = const Color(0xFFF7F7F8);
          card = const Color(0xFFFFFFFF);
          cardLight = const Color(0xFFEFEFEF);
          surface3 = const Color(0xFFE4E4E4);
          break;
        case 'minimal':
          // Krem — Kahve temasının sıcak aydınlık karşılığı
          bg = const Color(0xFFF7F1E8);
          card = const Color(0xFFFFFFFF);
          cardLight = const Color(0xFFEFE6D8);
          surface3 = const Color(0xFFE5D8C3);
          break;
        case 'slate':
          // Açık Gri — Antrasit temasının nötr aydınlık karşılığı
          bg = const Color(0xFFF2F3F4);
          card = const Color(0xFFFFFFFF);
          cardLight = const Color(0xFFE6E8EA);
          surface3 = const Color(0xFFDADDE0);
          break;
        default:
          bg = const Color(0xFFF2F3F4);
          card = const Color(0xFFFFFFFF);
          cardLight = const Color(0xFFE6E8EA);
          surface3 = const Color(0xFFDADDE0);
      }
      txtPrimary = const Color(0xFF1A1A1A);
      txtSecondary = const Color(0xFF666666);
      txtMuted = const Color(0xFFA0A0A0);
    }

    return AppThemeData._(
      style: style,
      isDark: isDark,
      primary: p.primary,
      primaryDark: p.primaryDark,
      bgDark: bg,
      bgCard: card,
      bgCardLight: cardLight,
      surface3: surface3,
      success: p.success,
      // Açık temalarda kart zemini beyaza yakın (bkz. yukarıdaki bg/card
      // atamaları) — p.warning'in tüm stillerde ortak olan tonu (0xFFC98A3D)
      // orada ~2.9:1 kontrast veriyor, WCAG AA'nın metin için istediği 4.5:1
      // eşiğinin altında kalıyor. Koyu temalarda p.warning aynen korunuyor,
      // sadece açık tema için ayrı ve daha koyu/doygun bir ton kullanılıyor
      // (~5.4:1 kontrast).
      warning: isDark ? p.warning : const Color(0xFF9C5A1A),
      error: p.error,
      info: p.info,
      textPrimary: txtPrimary,
      textSecondary: txtSecondary,
      textMuted: txtMuted,
    );
  }

  ThemeData toThemeData() {
    return ThemeData(
      useMaterial3: true,
      brightness: isDark ? Brightness.dark : Brightness.light,
      scaffoldBackgroundColor: bgDark,
      colorScheme: ColorScheme(
        brightness: isDark ? Brightness.dark : Brightness.light,
        primary: primary,
        onPrimary: Colors.white,
        secondary: info,
        onSecondary: Colors.white,
        error: error,
        onError: Colors.white,
        surface: bgCard,
        onSurface: textPrimary,
      ),
      cardTheme: CardThemeData(
        color: bgCard,
        elevation: style.cardElevation,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md)),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: bgDark,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          color: textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
        ),
        iconTheme: IconThemeData(color: textPrimary),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: bgCard,
        selectedItemColor: primary,
        unselectedItemColor: textMuted,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? primary : textMuted,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? primary.withValues(alpha: 0.3)
              : textMuted.withValues(alpha: 0.2),
        ),
      ),
      textTheme: TextTheme(
        headlineLarge:
            TextStyle(color: textPrimary, fontWeight: FontWeight.bold),
        headlineMedium:
            TextStyle(color: textPrimary, fontWeight: FontWeight.w600),
        bodyLarge: TextStyle(color: textPrimary),
        bodyMedium: TextStyle(color: textSecondary),
        labelSmall: TextStyle(color: textMuted),
      ),
    );
  }

  static List<AppThemeData> get all => AppStyle.all
      .map((s) => AppThemeData.build(style: s, isDark: true))
      .toList();

  String get id => '${style.id}_${isDark ? 'dark' : 'light'}';
  String get name => '${style.name} ${isDark ? '· Koyu' : '· Açık'}';
}

// ─────────────────────────────────────────────────────────────────────────────
// ThemeProvider
// ─────────────────────────────────────────────────────────────────────────────

class ThemeProvider extends ChangeNotifier {
  // Yeni kurulumda varsayılan: Beyaz (OLED stilinin aydınlık karşılığı) —
  // sadece ilk-değer, kayıtlı bir tercihi olan kullanıcıları etkilemez
  // (bkz. _load()).
  AppThemeData _current = AppThemeData.build(
    style: AppStyle.classic,
    isDark: false,
  );

  // Prefs tek seferinde alınır, tekrar tekrar getInstance() çağrılmaz
  SharedPreferences? _prefs;

  AppThemeData get current => _current;
  ThemeData get themeData => _current.toThemeData();
  AppStyle get currentStyle => _current.style;
  bool get isDark => _current.isDark;

  ThemeProvider() {
    _load();
  }

  Future<SharedPreferences> get _p async =>
      _prefs ??= await SharedPreferences.getInstance();

  Future<void> _load() async {
    final prefs = await _p;
    final styleId = prefs.getString('app_style') ?? 'classic';
    final dark = prefs.getBool('app_dark') ?? false;
    _current = AppThemeData.build(
      style: AppStyle.fromId(styleId),
      isDark: dark,
    );
    notifyListeners();

    final cloud = await CloudSyncService().getThemeSettings();
    if (cloud != null) {
      final cloudStyle = cloud['style'] as String;
      final cloudDark = cloud['dark'] as bool;
      _current = AppThemeData.build(
        style: AppStyle.fromId(cloudStyle),
        isDark: cloudDark,
      );
      await Future.wait([
        prefs.setString('app_style', cloudStyle),
        prefs.setBool('app_dark', cloudDark),
      ]);
      notifyListeners();
    }
  }

  Future<void> setStyle(AppStyle style) async {
    _current = AppThemeData.build(style: style, isDark: _current.isDark);
    notifyListeners();
    final prefs = await _p;
    await Future.wait([
      prefs.setString('app_style', style.id),
      CloudSyncService().saveThemeSettings(style.id, _current.isDark),
    ]);
  }

  Future<void> toggleDark(bool dark) async {
    _current = AppThemeData.build(style: _current.style, isDark: dark);
    notifyListeners();
    final prefs = await _p;
    await Future.wait([
      prefs.setBool('app_dark', dark),
      CloudSyncService().saveThemeSettings(_current.style.id, dark),
    ]);
  }

  Future<void> setTheme(AppThemeData theme) async {
    _current = theme;
    notifyListeners();
    final prefs = await _p;
    // Cloud'a da kaydet (setStyle/toggleDark ile tutarlı)
    await Future.wait([
      prefs.setString('app_style', theme.style.id),
      prefs.setBool('app_dark', theme.isDark),
      CloudSyncService().saveThemeSettings(theme.style.id, theme.isDark),
    ]);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// InheritedWidget & extension
// ─────────────────────────────────────────────────────────────────────────────

class AppThemeScope extends InheritedWidget {
  final AppThemeData themeData;

  const AppThemeScope({
    super.key,
    required this.themeData,
    required super.child,
  });

  static AppThemeData of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppThemeScope>();
    return scope?.themeData ??
        AppThemeData.build(style: AppStyle.slate, isDark: true);
  }

  @override
  bool updateShouldNotify(AppThemeScope old) =>
      themeData.id != old.themeData.id;
}

extension AppThemeExtension on BuildContext {
  AppThemeData get appColors => AppThemeScope.of(this);
}
