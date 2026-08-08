import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:showcaseview/showcaseview.dart';
import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/design_widgets.dart';
import '../../core/utils/app_transitions.dart'; // ← YENİ
import '../../core/widgets/operation_overlay.dart';
import '../notifications/notification_settings_screen.dart';
import 'proxmox_connection_screen.dart';
import 'about_screen.dart';
import 'security_settings_screen.dart';
import 'tab_settings_screen.dart';
import 'auth_screen.dart';
import '../../core/services/user_data_service.dart';
import '../../shared/models/alias_provider.dart';
import '../../shared/models/tab_config.dart';
import '../notifications/notification_provider.dart';
import '../../core/services/cloud_sync_service.dart';
import '../../core/services/security_cleanup_service.dart';
import '../proxmox/proxmox_provider.dart';
import '../adguard/adguard_provider.dart';
import '../ups/nut_provider.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../update/update_screen.dart';

class SettingsScreen extends StatefulWidget {
  final bool startTour;
  const SettingsScreen({super.key, this.startTour = false});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _showcaseTema = GlobalKey();
  final _showcaseProxmox = GlobalKey();
  final _showcaseBildirim = GlobalKey();
  final _showcaseSekme = GlobalKey();
  final _showcaseGuvenlik = GlobalKey();

  @override
  void initState() {
    super.initState();
    if (widget.startTour) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Future.delayed(const Duration(milliseconds: 300), () {
          if (!mounted) return;
          ShowCaseWidget.of(context).startShowCase([
            _showcaseTema,
            _showcaseProxmox,
            _showcaseBildirim,
            _showcaseSekme,
            _showcaseGuvenlik,
          ]);
        });
      });
    }
  }

  // ── Animasyonlu push yardımcısı ──────────────────────────────────────────
  void _push(Widget page) =>
      Navigator.push(context, AppTransitions.slideFade(page));

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Scaffold(
      backgroundColor: colors.surface0,
      appBar: AppBar(
        title: const Text('Ayarlar'),
        backgroundColor: colors.surface0,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          // ── Hesap ────────────────────────────────────────────────────────
          _AccountCard(),
          const SizedBox(height: 28),

          // ── Görünüm ──────────────────────────────────────────────────────
          const Padding(
            padding: EdgeInsets.only(bottom: 10, left: 4),
            child: SectionLabel('Görünüm'),
          ),
          Showcase(
            key: _showcaseTema,
            description: 'Görünümünü seç: sana göre bir tema.',
            tooltipBackgroundColor: colors.surface1,
            textColor: colors.textPrimary,
            descTextStyle: TextStyle(color: colors.textSecondary, fontSize: 13),
            scaleAnimationDuration: AppMotion.base,
            scaleAnimationCurve: AppMotion.curve,
            onBarrierClick: () => ShowCaseWidget.of(context).next(),
            onToolTipClick: () => ShowCaseWidget.of(context).next(),
            child: _ThemePicker(),
          ),
          const SizedBox(height: 28),

          // ── Bağlantılar ───────────────────────────────────────────────────
          const Padding(
            padding: EdgeInsets.only(bottom: 10, left: 4),
            child: SectionLabel('Bağlantılar'),
          ),
          Showcase(
            key: _showcaseProxmox,
            description: 'Sunucularını buradan ekle ya da düzenle.',
            tooltipBackgroundColor: colors.surface1,
            textColor: colors.textPrimary,
            descTextStyle: TextStyle(color: colors.textSecondary, fontSize: 13),
            scaleAnimationDuration: AppMotion.base,
            scaleAnimationCurve: AppMotion.curve,
            onBarrierClick: () => ShowCaseWidget.of(context).next(),
            onToolTipClick: () => ShowCaseWidget.of(context).next(),
            child: _SettingsCard(
              icon: Icons.dns_rounded,
              title: 'Proxmox Sunucuları',
              subtitle: 'Sunucu ekle, düzenle veya sil',
              onTap: () => _push(const ProxmoxConnectionScreen()),
            ),
          ),
          const SizedBox(height: 28),

          // ── Bildirimler ───────────────────────────────────────────────────
          const Padding(
            padding: EdgeInsets.only(bottom: 10, left: 4),
            child: SectionLabel('Bildirimler'),
          ),
          Showcase(
            key: _showcaseBildirim,
            description: 'Hangi durumda haber almak istediğini burada belirle.',
            tooltipBackgroundColor: colors.surface1,
            textColor: colors.textPrimary,
            descTextStyle: TextStyle(color: colors.textSecondary, fontSize: 13),
            scaleAnimationDuration: AppMotion.base,
            scaleAnimationCurve: AppMotion.curve,
            onBarrierClick: () => ShowCaseWidget.of(context).next(),
            onToolTipClick: () => ShowCaseWidget.of(context).next(),
            child: _SettingsCard(
              icon: Icons.notifications_outlined,
              title: 'Bildirim Kuralları',
              subtitle: 'Bildirimlerini özelleştir',
              onTap: () => _push(const NotificationSettingsScreen()),
            ),
          ),
          const SizedBox(height: 28),

          // ── Sekmeler ──────────────────────────────────────────────────────
          const Padding(
            padding: EdgeInsets.only(bottom: 10, left: 4),
            child: SectionLabel('Sekmeler'),
          ),
          Showcase(
            key: _showcaseSekme,
            description:
                'Hangi sekmelerin görüneceğini ve sırasını burada değiştir.',
            tooltipBackgroundColor: colors.surface1,
            textColor: colors.textPrimary,
            descTextStyle: TextStyle(color: colors.textSecondary, fontSize: 13),
            scaleAnimationDuration: AppMotion.base,
            scaleAnimationCurve: AppMotion.curve,
            onBarrierClick: () => ShowCaseWidget.of(context).next(),
            onToolTipClick: () => ShowCaseWidget.of(context).next(),
            child: _SettingsCard(
              icon: Icons.dashboard_customize_outlined,
              title: 'Sekme Yönetimi',
              subtitle: 'Sekmeleri göster/gizle ve sırala',
              onTap: () => _push(const TabSettingsScreen()),
            ),
          ),
          const SizedBox(height: 28),

          // ── Güvenlik ──────────────────────────────────────────────────────
          const Padding(
            padding: EdgeInsets.only(bottom: 10, left: 4),
            child: SectionLabel('Güvenlik'),
          ),
          // NOT: Bu adımın metni "Artık hazırsın!" kapanışını içeriyor çünkü
          // startShowCase([...]) listesinde (initState, birkaç satır yukarıda)
          // şu an SABİT sırayla SON adım bu — sıra değişirse (yeni bir bölüm
          // eklenirse/Güvenlik başka yere taşınırsa) bu kapanış cümlesi de
          // gerçek son adıma taşınmalı.
          Showcase(
            key: _showcaseGuvenlik,
            description:
                'Parmak izi ya da PIN ile kilitle. Artık hazırsın!',
            tooltipBackgroundColor: colors.surface1,
            textColor: colors.textPrimary,
            descTextStyle: TextStyle(color: colors.textSecondary, fontSize: 13),
            scaleAnimationDuration: AppMotion.base,
            scaleAnimationCurve: AppMotion.curve,
            onBarrierClick: () {
              ShowCaseWidget.of(context).dismiss();
              Navigator.pop(context);
            },
            onToolTipClick: () {
              ShowCaseWidget.of(context).dismiss();
              Navigator.pop(context);
            },
            child: _SettingsCard(
              icon: Icons.lock_outline_rounded,
              title: 'Uygulama Kilidi',
              subtitle: 'Parmak izi veya PIN ile giriş',
              onTap: () => _push(const SecuritySettingsScreen()),
            ),
          ),
          const SizedBox(height: 28),

          // ── Uygulama ──────────────────────────────────────────────────────
          const Padding(
            padding: EdgeInsets.only(bottom: 10, left: 4),
            child: SectionLabel('Uygulama'),
          ),
          _UpdateSettingsCard(),
          const SizedBox(height: 8),
          _SettingsCard(
            icon: Icons.info_outline_rounded,
            title: 'Hakkında',
            subtitle: 'MTools v2 — Sürüm bilgisi',
            onTap: () => _push(const AboutScreen()),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Hesap Kartı
// ─────────────────────────────────────────────

class _AccountCard extends StatefulWidget {
  @override
  State<_AccountCard> createState() => _AccountCardState();
}

class _AccountCardState extends State<_AccountCard> {
  late final StreamSubscription<User?> _authSub;

  @override
  void initState() {
    super.initState();
    _authSub = FirebaseAuth.instance.authStateChanges().listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _authSub.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final user = FirebaseAuth.instance.currentUser;
    final isLoggedIn = user != null;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: colors.hairline),
      ),
      child: isLoggedIn
          ? _LoggedInContent(user: user, colors: colors)
          : _GuestContent(colors: colors),
    );
  }
}

class _LoggedInContent extends StatelessWidget {
  final User user;
  final AppThemeData colors;
  const _LoggedInContent({required this.user, required this.colors});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: colors.surface2,
          ),
          child: user.photoURL != null
              ? ClipOval(
                  child: Image.network(
                    user.photoURL!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Icon(
                      Icons.person_rounded,
                      color: colors.textSecondary,
                      size: 26,
                    ),
                  ),
                )
              : Icon(Icons.person_rounded, color: colors.textSecondary, size: 26),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                user.displayName ?? 'Kullanıcı',
                style: TextStyle(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                user.email ?? '',
                style: TextStyle(color: colors.textSecondary, fontSize: 12),
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
              StatusIndicator(
                color: colors.success,
                label: 'Google ile bağlı',
                style: TextStyle(color: colors.textSecondary, fontSize: 10),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        _SignOutButton(),
      ],
    );
  }
}

class _GuestContent extends StatefulWidget {
  final AppThemeData colors;
  const _GuestContent({required this.colors});

  @override
  State<_GuestContent> createState() => _GuestContentState();
}

class _GuestContentState extends State<_GuestContent> {
  bool _loading = false;
  String? _error;

  Future<void> _signIn() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) {
        if (mounted) {
          setState(() {
            _loading = false;
            _error = 'Giriş iptal edildi';
          });
        }
        return;
      }
      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      await FirebaseAuth.instance.signInWithCredential(credential);
      // NOT: burada eskiden local sunucu listelerini (ssh_servers/
      // proxmox_servers dahil) ELLE ve HAM haliyle cloud'a yazan bir döngü
      // vardı — hem kimlik bilgilerini (şifre/token) sanitize etmeden
      // cloud'a yazıyordu (bkz. credential_sync.dart — bu güvenlik turunda
      // düzeltilen tam da bu sorundu) hem de cloud'daki gerçek veriyi bu
      // cihazın (çoğu zaman boş misafir) local kopyasıyla köründen eziyordu.
      // Aşağıdaki provider.init() çağrıları zaten cloud+local'i doğru
      // birleştiriyor (yapı cloud'dan, kimlik bilgisi local'den) ve cloud
      // boşsa local'i SANİTİZE EDİLMİŞ olarak kendi kendine cloud'a basıyor
      // — o yüzden burada ayrıca elle senkron gerekmiyor.
      CloudSyncService().invalidateCache();
      // Açılıştaki akışın eşdeğeri: eski (v3.1.0 öncesi) düz metin kalıntısı
      // varsa temizler — provider'ların cloud'a yazmaya başlamasından ÖNCE
      // çalışmalı (bkz. security_cleanup_service.dart).
      await SecurityCleanupService.runOnce();
      if (mounted) {
        setState(() => _loading = false);
        await Future.wait([
          context.read<ProxmoxProvider>().init(),
          context.read<AdGuardProvider>().init(),
          context.read<NutProvider>().init(),
          context.read<NotificationProvider>().reload(),
        ]);
        // Terminal ve WOL ekranları kendi authStateChanges() dinleyicileriyle
        // (bkz. terminal_screen.dart, wol_screen.dart) otomatik yeniden
        // yükleniyor — burada ayrıca tetiklemeye gerek yok.
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Giriş başarısız, tekrar deneyin';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    return Row(
      children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: colors.surface2,
            border: Border.all(color: colors.hairline),
          ),
          child: Icon(Icons.person_outline_rounded,
              color: colors.textMuted, size: 26),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Giriş Yapılmadı',
                style: TextStyle(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                'Veriler yalnızca bu cihazda saklanıyor',
                style: TextStyle(color: colors.textSecondary, fontSize: 12),
              ),
              if (_error != null) ...[
                const SizedBox(height: 4),
                Text(
                  _error!,
                  style: TextStyle(color: colors.error, fontSize: 11),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 12),
        _loading
            ? SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: colors.primary,
                ),
              )
            : GestureDetector(
                onTap: _signIn,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: colors.primary,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: const Text(
                    'Bağla',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
      ],
    );
  }
}

class _SignOutButton extends StatefulWidget {
  @override
  State<_SignOutButton> createState() => _SignOutButtonState();
}

class _SignOutButtonState extends State<_SignOutButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) async {
        setState(() => _pressed = false);
        await _confirmSignOut(context, colors);
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: PressableScale(
        pressed: _pressed,
        child: AnimatedContainer(
          duration: AppMotion.fast,
          curve: AppMotion.curve,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: _pressed
                ? colors.error.withValues(alpha: 0.2)
                : colors.error.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(
              color: _pressed
                  ? colors.error.withValues(alpha: 0.5)
                  : colors.error.withValues(alpha: 0.2),
            ),
          ),
          child: Icon(Icons.logout_rounded, color: colors.error, size: 20),
        ),
      ),
    );
  }

  Future<void> _confirmSignOut(
      BuildContext context, AppThemeData colors) async {
    final confirmed = await appShowDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.surface1,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md)),
        title: Text('Çıkış Yap', style: TextStyle(color: colors.textPrimary)),
        content: Text(
          'Google hesabından çıkış yapılacak.\nYerel verileriniz güvenlik için silinecek.',
          style:
              TextStyle(color: colors.textSecondary, fontSize: 13, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('İptal', style: TextStyle(color: colors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Çıkış Yap',
              style:
                  TextStyle(color: colors.error, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      if (!context.mounted) return;
      final overlay = Overlay.of(context);
      late OverlayEntry entry;
      entry = OverlayEntry(
        builder: (_) => const OperationOverlay(message: 'Çıkış yapılıyor...'),
      );
      overlay.insert(entry);
      try {
        await UserDataService.instance.clearAll();
        await GoogleSignIn().signOut();
        await FirebaseAuth.instance.signOut();
        // Sonraki oturumun (misafir ya da başka bir hesap) eski hesabın
        // önbelleklenmiş bulut verisini görmemesi için elle ve garantili
        // sırayla geçersiz kılıyoruz (bkz. cloud_sync_service.dart).
        CloudSyncService().invalidateCache();
        if (context.mounted) {
          context.read<TabConfigProvider>().reset();
          context.read<AliasProvider>().reset();
          context.read<NotificationProvider>().reset();
          context.read<ProxmoxProvider>().reset();
          context.read<AdGuardProvider>().reset();
          context.read<NutProvider>().reset();
        }
      } finally {
        entry.remove();
      }
      if (context.mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          AppTransitions.fadeThrough(const AuthScreen()),
          (route) => false,
        );
      }
    }
  }
}

// ─────────────────────────────────────────────
// Settings Card
// ─────────────────────────────────────────────

class _SettingsCard extends StatefulWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _SettingsCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  State<_SettingsCard> createState() => _SettingsCardState();
}

class _SettingsCardState extends State<_SettingsCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: PressableScale(
        pressed: _pressed,
        child: AnimatedContainer(
          duration: AppMotion.fast,
          curve: AppMotion.curve,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _pressed ? colors.surface2 : colors.surface1,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: colors.hairline),
          ),
          child: Row(
            children: [
              AnimatedContainer(
                duration: AppMotion.fast,
                curve: AppMotion.curve,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _pressed ? colors.surface3 : colors.surface2,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Icon(widget.icon, color: colors.textSecondary, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.subtitle,
                      style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: _pressed ? colors.textPrimary : colors.textMuted,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Güncellemeler
// ─────────────────────────────────────────────

class _UpdateSettingsCard extends StatefulWidget {
  @override
  State<_UpdateSettingsCard> createState() => _UpdateSettingsCardState();
}

class _UpdateSettingsCardState extends State<_UpdateSettingsCard> {
  bool _pressed = false;
  String _version = '';

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (mounted) setState(() => _version = info.version);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final subtitle = _version.isEmpty
        ? 'Sürüm bilgisi yükleniyor...'
        : 'v$_version — kontrol etmek için dokun';

    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        Navigator.push(context, AppTransitions.slideFade(const UpdateScreen()));
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: PressableScale(
        pressed: _pressed,
        child: AnimatedContainer(
          duration: AppMotion.fast,
          curve: AppMotion.curve,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _pressed ? colors.surface2 : colors.surface1,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: colors.hairline),
          ),
          child: Row(
            children: [
              AnimatedContainer(
                duration: AppMotion.fast,
                curve: AppMotion.curve,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _pressed ? colors.surface3 : colors.surface2,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Icon(Icons.system_update_rounded,
                    color: colors.textSecondary, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Güncellemeler',
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: _pressed ? colors.textPrimary : colors.textMuted,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Tema Seçici
// ─────────────────────────────────────────────

class _ThemePicker extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final provider = context.watch<ThemeProvider>();
    final current = provider.current;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: colors.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: colors.surface2,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Icon(Icons.palette_outlined,
                    color: colors.primary, size: 18),
              ),
              const SizedBox(width: 10),
              Text(
                'Tema',
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: colors.surface2,
                  borderRadius: BorderRadius.circular(AppRadius.xs),
                ),
                child: Text(
                  current.style.name,
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: AppStyle.all
                .map((style) => Expanded(
                      key: ValueKey(style.id),
                      child: Padding(
                        padding: EdgeInsets.only(
                            right: style == AppStyle.all.last ? 0 : 8),
                        child: _ThemeCard(
                          style: style,
                          isSelected: current.style.id == style.id,
                          isDark: current.isDark,
                          onTap: () => provider.setStyle(style),
                        ),
                      ),
                    ))
                .toList(),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: colors.surface0,
              borderRadius: BorderRadius.circular(AppRadius.sm),
              border: Border.all(color: colors.hairline),
            ),
            child: Row(
              children: [
                _ModeButton(
                  label: 'Karanlık',
                  icon: Icons.dark_mode_rounded,
                  selected: current.isDark,
                  colors: colors,
                  onTap: () => provider.toggleDark(true),
                ),
                _ModeButton(
                  label: 'Aydınlık',
                  icon: Icons.light_mode_rounded,
                  selected: !current.isDark,
                  colors: colors,
                  onTap: () => provider.toggleDark(false),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final AppThemeData colors;
  final VoidCallback onTap;

  const _ModeButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.colors,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: AppMotion.fast,
          curve: AppMotion.curve,
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? colors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.xs),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  size: 15,
                  color: selected ? Colors.white : colors.textSecondary),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: selected ? Colors.white : colors.textSecondary,
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ThemeCard extends StatelessWidget {
  final AppStyle style;
  final bool isSelected;
  final bool isDark;
  final VoidCallback onTap;

  const _ThemeCard({
    required this.style,
    required this.isSelected,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final preview = AppThemeData.build(style: style, isDark: isDark);

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppMotion.fast,
        curve: AppMotion.curve,
        decoration: BoxDecoration(
          color: preview.surface1,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
            color: isSelected ? preview.primary : preview.hairline,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(AppRadius.md - 1)),
              child: Container(
                height: 64,
                color: preview.surface0,
                padding: const EdgeInsets.all(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 32,
                          height: 5,
                          decoration: BoxDecoration(
                            color: preview.textPrimary.withValues(alpha: 0.7),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                        const Spacer(),
                        Container(
                          width: 14,
                          height: 14,
                          decoration: BoxDecoration(
                            color: preview.primary.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(AppRadius.xs),
                            border: Border.all(
                                color: preview.primary.withValues(alpha: 0.5)),
                          ),
                          child: Center(
                            child: Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: preview.primary,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Container(
                      height: 28,
                      decoration: BoxDecoration(
                        color: preview.surface1,
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                        border: Border.all(
                            color: preview.primary.withValues(alpha: 0.2)),
                      ),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 4),
                      child: Row(
                        children: [
                          Container(
                            width: 14,
                            height: 14,
                            decoration: BoxDecoration(
                              color: preview.primary.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(AppRadius.xs),
                            ),
                            child: Center(
                              child: Container(
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  color: preview.primary,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 5),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                  width: 24,
                                  height: 4,
                                  decoration: BoxDecoration(
                                      color: preview.textPrimary
                                          .withValues(alpha: 0.6),
                                      borderRadius: BorderRadius.circular(2))),
                              const SizedBox(height: 3),
                              Container(
                                  width: 18,
                                  height: 3,
                                  decoration: BoxDecoration(
                                      color: preview.textMuted
                                          .withValues(alpha: 0.5),
                                      borderRadius: BorderRadius.circular(2))),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _Swatch(preview.primary, borderColor: preview.hairline),
                      const SizedBox(width: 4),
                      _Swatch(preview.surface1, borderColor: preview.hairline),
                      const SizedBox(width: 4),
                      _Swatch(preview.success, borderColor: preview.hairline),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (isSelected) ...[
                        Icon(Icons.check_circle_rounded,
                            color: preview.primary, size: 12),
                        const SizedBox(width: 4),
                      ],
                      Text(
                        style.name,
                        style: TextStyle(
                          color: isSelected
                              ? preview.primary
                              : preview.textSecondary,
                          fontSize: 11,
                          fontWeight:
                              isSelected ? FontWeight.bold : FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  final Color color;
  final Color borderColor;
  const _Swatch(this.color, {required this.borderColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: borderColor, width: 1),
      ),
    );
  }
}
