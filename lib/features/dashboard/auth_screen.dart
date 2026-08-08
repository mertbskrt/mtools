import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/design_widgets.dart';
import '../../core/theme/mtools_mark.dart';
import '../../core/utils/app_transitions.dart';
import 'home_screen.dart';
import 'permission_screen.dart';
import 'package:provider/provider.dart';
import '../proxmox/proxmox_provider.dart';
import '../adguard/adguard_provider.dart';
import '../ups/nut_provider.dart';
import '../../core/services/cloud_sync_service.dart';
import '../../core/services/security_cleanup_service.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> with TickerProviderStateMixin {
  final LocalAuthentication _auth = LocalAuthentication();
  final GoogleSignIn _googleSignIn = GoogleSignIn();

  // 'landing' | 'welcome' | 'pin' | 'biometric'
  String? _stage;

  String _lockType = 'none';
  bool _lockEnabled = false;

  bool _bioAuthenticating = false;
  bool _bioError = false;
  String _bioStatus = 'Doğrulama bekleniyor';

  String _pin = '';
  bool _pinError = false;

  bool _googleLoading = false;
  String? _googleError;

  late AnimationController _pulseCtrl;
  late AnimationController _rippleCtrl;
  late AnimationController _shakeCtrl;
  late Animation<double> _shakeAnim;

  @override
  void initState() {
    super.initState();

    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1800))
      ..repeat(reverse: true);
    _rippleCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1600))
      ..repeat();
    _shakeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    _shakeAnim = Tween<double>(begin: 0, end: 1)
        .animate(CurvedAnimation(parent: _shakeCtrl, curve: Curves.elasticIn));

    _init();
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _rippleCtrl.dispose();
    _shakeCtrl.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    // authStateChanges().first zaten doğru desen (senkron currentUser değil,
    // restore edilmiş oturumu bekliyor). Ama stream'in kendisi bir istisna
    // fırlatırsa (geçici platform-kanalı hatası, Firebase henüz hazır
    // değilken vb.) bunu yakalayıp SDK'nın o an bellekte tuttuğu son bilinen
    // kullanıcıya (senkron currentUser) düşüyoruz — geçici bir hata asla
    // geçerli bir oturumu "çıkış yapılmış" gibi göstermesin diye.
    User? user;
    try {
      user = await FirebaseAuth.instance.authStateChanges().first;
    } catch (_) {
      user = FirebaseAuth.instance.currentUser;
    }

    if (user == null) {
      if (mounted) setState(() => _stage = 'landing');
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    _lockEnabled = prefs.getBool('lock_enabled') ?? false;
    _lockType = prefs.getString('lock_type') ?? 'none';

    if (!mounted) return;
    setState(() => _stage = 'welcome');

    // Firestore'da eski (v3.1.0 öncesi) düz metin kimlik bilgisi kalıntısı
    // varsa temizler — provider'ların cloud'a yazmaya başlamasından ÖNCE
    // çalışmalı (bkz. security_cleanup_service.dart).
    await SecurityCleanupService.runOnce();
    await _initProviders();
    if (!mounted) return;
    await _proceedToLock();
  }

  /// Provider init + minimum splash süresi — tek yerde tanımlı
  Future<void> _initProviders({bool withDelay = true}) async {
    await Future.wait([
      context.read<ProxmoxProvider>().init(),
      context.read<AdGuardProvider>().init(),
      context.read<NutProvider>().init(),
      if (withDelay) Future.delayed(const Duration(milliseconds: 900)),
    ]);
  }

  Future<void> _proceedToLock() async {
    if (!_lockEnabled || _lockType == 'none') {
      await _goHomeOrPermission();
      return;
    }
    if (_lockType == 'app_pin') {
      setState(() => _stage = 'pin');
      return;
    }
    setState(() => _stage = 'biometric');
    _doBiometric();
  }

  /// Google ile giriş akışı daha önce izin ekranını hiç göstermiyordu —
  /// sadece "hesapsız devam et" yolu 'onboarding_seen' bayrağına
  /// bakıyordu. Bu yüzden Google ile giren kullanıcılar bildirim izni hiç
  /// istenmeden doğrudan ana ekrana geçiyordu (POST_NOTIFICATIONS hiç
  /// verilmediği için arka planda hiçbir bildirim görünmüyordu).
  ///
  /// 'onboarding_seen' cihaz-yerel ve giriş yönteminden bağımsızdır —
  /// UserDataService.clearAll() tarafından SİLİNMEZ, bu yüzden çıkış yapıp
  /// tekrar girmek ya da hesap değiştirmek tanıtımı geri getirmez.
  Future<void> _goHomeOrPermission() async {
    final prefs = await SharedPreferences.getInstance();
    final onboardingSeen = prefs.getBool('onboarding_seen') ?? false;
    if (!mounted) return;
    if (!onboardingSeen) {
      _goPermission();
    } else {
      _goHome();
    }
  }

  Future<void> _doGoogleSignIn() async {
    setState(() {
      _googleLoading = true;
      _googleError = null;
    });

    try {
      final googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        if (mounted) {
          setState(() {
            _googleLoading = false;
            _googleError = 'Giriş iptal edildi';
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
      if (!mounted) return;

      // CloudSyncService kendi başına da hesap değişimini dinleyip önbelleği
      // temizliyor, ama bu Firebase'in kendi olay akışına (stream) bağlı ve
      // bazen bir sonraki satırdan (_initProviders → providerlar cloud'u
      // okuyor) DAHA GEÇ tetiklenebiliyor — bu durumda providerlar hâlâ eski/
      // boş önbelleği görüp veri gelmiyormuş gibi davranıyordu. Burada
      // sırayı garanti altına almak için önbelleği elle, hemen temizliyoruz.
      CloudSyncService().invalidateCache();

      final prefs = await SharedPreferences.getInstance();
      _lockEnabled = prefs.getBool('lock_enabled') ?? false;
      _lockType = prefs.getString('lock_type') ?? 'none';

      if (!mounted) return;
      setState(() {
        _googleLoading = false;
        _stage = 'welcome';
      });

      // Firestore'da eski (v3.1.0 öncesi) düz metin kimlik bilgisi kalıntısı
      // varsa temizler — provider'ların cloud'a yazmaya başlamasından ÖNCE
      // çalışmalı (bkz. security_cleanup_service.dart).
      await SecurityCleanupService.runOnce();
      await _initProviders();
      if (!mounted) return;
      await _proceedToLock();
    } catch (e) {
      if (mounted) {
        setState(() {
          _googleLoading = false;
          _googleError = 'Giriş başarısız, tekrar deneyin';
        });
      }
    }
  }

  Future<void> _continueWithoutLogin() async {
    if (!mounted) return;
    setState(() => _stage = 'welcome');

    if (context.mounted) {
      await _initProviders();
    }
    if (!mounted) return;
    await _goHomeOrPermission();
  }

  void _goHome() {
    Navigator.of(context).pushReplacement(
      AppTransitions.fadeThrough<void>(const HomeScreen()),
    );
  }

  void _goPermission() {
    Navigator.of(context).pushReplacement(
      AppTransitions.fadeThrough<void>(const PermissionScreen()),
    );
  }

  Future<void> _doBiometric() async {
    setState(() {
      _bioAuthenticating = true;
      _bioError = false;
      _bioStatus = 'Doğrulanıyor...';
    });

    try {
      final authenticated = await _auth.authenticate(
        localizedReason: 'MTools\'a erişmek için doğrulama yapın',
        options: AuthenticationOptions(
          biometricOnly: _lockType == 'biometric',
          stickyAuth: true,
        ),
      );

      if (authenticated && mounted) {
        _goHome();
      } else {
        if (mounted) {
          setState(() {
            _bioStatus = 'Doğrulama başarısız';
            _bioAuthenticating = false;
            _bioError = true;
          });
        }
      }
    } catch (e) {
      if (mounted) _goHome();
    }
  }

  void _onKey(String key) {
    if (key == '⌫') {
      if (_pin.isNotEmpty) {
        setState(() {
          _pin = _pin.substring(0, _pin.length - 1);
          _pinError = false;
        });
      }
      return;
    }
    if (_pin.length >= 4) return;
    setState(() {
      _pin += key;
      _pinError = false;
    });
    HapticFeedback.lightImpact();
    if (_pin.length == 4) _verifyPIN();
  }

  Future<void> _verifyPIN() async {
    final prefs = await SharedPreferences.getInstance();
    final savedPin = prefs.getString('app_pin') ?? '';

    if (_pin == savedPin) {
      HapticFeedback.heavyImpact();
      // PIN'i ekranda gösterme — dolu nokta animasyonu yeterli
      await Future.delayed(const Duration(milliseconds: 200));
      if (mounted) _goHome();
    } else {
      HapticFeedback.vibrate();
      _shakeCtrl.forward(from: 0);
      setState(() {
        _pinError = true;
        _pin = '';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Scaffold(
      backgroundColor: colors.bgDark,
      body: Stack(
        children: [
          Center(
            child: Container(
              width: 400,
              height: 400,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    colors.primary.withValues(alpha: 0.06),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            child: _stage == null
                ? const SizedBox.shrink()
                : AnimatedSwitcher(
                    duration: AppMotion.slow,
                    transitionBuilder: (child, anim) => FadeTransition(
                      opacity: anim,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0, 0.04),
                          end: Offset.zero,
                        ).animate(CurvedAnimation(
                            parent: anim, curve: AppMotion.curve)),
                        child: child,
                      ),
                    ),
                    child: _stage == 'landing'
                        ? _LandingContent(
                            key: const ValueKey('landing'),
                            loading: _googleLoading,
                            error: _googleError,
                            onSignIn: _doGoogleSignIn,
                            onContinue: _continueWithoutLogin,
                          )
                        : _stage == 'welcome'
                            ? const _WelcomeContent(
                                key: ValueKey('welcome'),
                              )
                            : _stage == 'biometric'
                                ? _BiometricContent(
                                    key: const ValueKey('bio'),
                                    authenticating: _bioAuthenticating,
                                    error: _bioError,
                                    status: _bioStatus,
                                    pulseCtrl: _pulseCtrl,
                                    rippleCtrl: _rippleCtrl,
                                    onRetry: _doBiometric,
                                    onUsePIN: _lockType != 'biometric'
                                        ? () => setState(() => _stage = 'pin')
                                        : null,
                                  )
                                : _PINContent(
                                    key: const ValueKey('pin'),
                                    pin: _pin,
                                    error: _pinError,
                                    shakeAnim: _shakeAnim,
                                    onKey: _onKey,
                                    onUseBiometric: _lockType != 'app_pin'
                                        ? () {
                                            setState(
                                                () => _stage = 'biometric');
                                            _doBiometric();
                                          }
                                        : null,
                                  ),
                  ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Landing — Giriş Seçim Ekranı
// ─────────────────────────────────────────────

class _LandingContent extends StatefulWidget {
  final bool loading;
  final String? error;
  final VoidCallback onSignIn;
  final VoidCallback onContinue;

  const _LandingContent({
    super.key,
    required this.loading,
    required this.error,
    required this.onSignIn,
    required this.onContinue,
  });

  @override
  State<_LandingContent> createState() => _LandingContentState();
}

class _LandingContentState extends State<_LandingContent>
    with SingleTickerProviderStateMixin {
  late AnimationController _bgCtrl;

  @override
  void initState() {
    super.initState();
    _bgCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 8000), // 3s → 8s, daha az CPU
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _bgCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final size = MediaQuery.of(context).size;

    return SizedBox.expand(
      child: Stack(
        children: [
          // ── Animasyonlu arka plan ──
          AnimatedBuilder(
            animation: _bgCtrl,
            builder: (_, __) => Stack(
              children: [
                Positioned(
                  top: -60 + _bgCtrl.value * 30,
                  left: -40 + _bgCtrl.value * 20,
                  child: Container(
                    width: 280,
                    height: 280,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          colors.primary.withValues(alpha: 0.10),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  bottom: -80 + _bgCtrl.value * 40,
                  right: -60 + _bgCtrl.value * 20,
                  child: Container(
                    width: 320,
                    height: 320,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          colors.info.withValues(alpha: 0.07),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── İçerik ──
          SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              children: [
                SizedBox(height: size.height * 0.09),

                // Logo
                const MtoolsMark(size: 88).animate().fadeIn(duration: 500.ms).scale(
                    begin: const Offset(0.7, 0.7), curve: Curves.easeOutBack),

                const SizedBox(height: 20),

                Text(
                  'MTools',
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 34,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.5,
                  ),
                ).animate().fadeIn(delay: 150.ms),

                const SizedBox(height: 4),

                Text(
                  'Sunucu Yönetim Sistemi',
                  style: TextStyle(
                    color: colors.textMuted,
                    fontSize: 13,
                    letterSpacing: 0.5,
                  ),
                ).animate().fadeIn(delay: 200.ms),

                SizedBox(height: size.height * 0.055),

                // ── Giriş kartı ──
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: colors.bgCard,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.25),
                        blurRadius: 24,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Hoş Geldiniz',
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Sunucu bağlantı bilgileriniz Google hesabınıza güvenle kaydedilir.',
                        style: TextStyle(
                          color: colors.textSecondary,
                          fontSize: 13,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 20),
                      _FeatureRow(
                        icon: Icons.sync_rounded,
                        color: colors.primary,
                        text: 'Tüm cihazlarda senkronizasyon',
                      ),
                      const SizedBox(height: 10),
                      _FeatureRow(
                        icon: Icons.lock_outline_rounded,
                        color: colors.success,
                        text: 'Veriler yalnızca sizinle paylaşılır',
                      ),
                      const SizedBox(height: 10),
                      _FeatureRow(
                        icon: Icons.block_rounded,
                        color: colors.info,
                        text: 'Reklam yok, takip yok, analitik yok',
                      ),
                      const SizedBox(height: 24),

                      // Google butonu
                      widget.loading
                          ? Center(
                              child: SizedBox(
                                width: 26,
                                height: 26,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2.5, color: colors.primary),
                              ),
                            )
                          : GestureDetector(
                              onTap: widget.onSignIn,
                              child: Container(
                                width: double.infinity,
                                height: 54,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      colors.primary.withValues(alpha: 0.15),
                                      colors.info.withValues(alpha: 0.08),
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: colors.primary.withValues(alpha: 0.3),
                                  ),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Container(
                                      width: 26,
                                      height: 26,
                                      decoration: const BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: Colors.white,
                                      ),
                                      child: const Center(
                                        child: Text(
                                          'G',
                                          style: TextStyle(
                                            color: Color(0xFF4285F4),
                                            fontSize: 15,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Text(
                                      'Google ile Giriş Yap',
                                      style: TextStyle(
                                        color: colors.textPrimary,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ).animate().fadeIn(delay: 300.ms),

                      if (widget.error != null) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: colors.error.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(AppRadius.md),
                            border: Border.all(
                                color: colors.error.withValues(alpha: 0.2)),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.error_outline,
                                  color: colors.error, size: 16),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  widget.error!,
                                  style: TextStyle(
                                      color: colors.error, fontSize: 12),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      const SizedBox(height: 16),

                      // Ayırıcı
                      Row(
                        children: [
                          Expanded(
                            child: Divider(
                              color: Colors.white.withValues(alpha: 0.08),
                              thickness: 1,
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Text(
                              'veya',
                              style: TextStyle(
                                color: colors.textMuted,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Divider(
                              color: Colors.white.withValues(alpha: 0.08),
                              thickness: 1,
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 16),

                      // Devam Et butonu
                      GestureDetector(
                        onTap: widget.loading ? null : widget.onContinue,
                        child: Container(
                          width: double.infinity,
                          height: 50,
                          decoration: BoxDecoration(
                            color: Colors.transparent,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.12),
                            ),
                          ),
                          child: Center(
                            child: Text(
                              'Giriş Yapmadan Devam Et',
                              style: TextStyle(
                                color: colors.textSecondary,
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                      ).animate().fadeIn(delay: 400.ms),

                      const SizedBox(height: 12),

                      Center(
                        child: Text(
                          'Giriş yapmadan veriler yalnızca bu cihazda kalır.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: colors.textMuted,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ],
                  ),
                ).animate().fadeIn(delay: 250.ms),

                SizedBox(height: size.height * 0.04),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Welcome — Tekrar Hoş Geldiniz
// ─────────────────────────────────────────────

class _WelcomeContent extends StatefulWidget {
  const _WelcomeContent({super.key});

  @override
  State<_WelcomeContent> createState() => _WelcomeContentState();
}

class _WelcomeContentState extends State<_WelcomeContent>
    with SingleTickerProviderStateMixin {
  late AnimationController _shimmerCtrl;

  @override
  void initState() {
    super.initState();
    _shimmerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();
  }

  @override
  void dispose() {
    _shimmerCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final user = FirebaseAuth.instance.currentUser;
    final displayName = user?.displayName?.trim() ?? '';
    final name = user == null
        ? 'Misafir Kullanıcı'
        : (displayName.isNotEmpty
            ? displayName
            : (user.email?.split('@').first ?? 'Kullanıcı'));
    final email = user?.email ?? '';
    final photoUrl = user?.photoURL;

    return SizedBox.expand(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Avatar
          Stack(
            alignment: Alignment.bottomRight,
            children: [
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [colors.primary, colors.info],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: colors.primary.withValues(alpha: 0.4),
                      blurRadius: 28,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: photoUrl != null
                    ? ClipOval(
                        child: Image.network(
                          photoUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const Icon(
                            Icons.person_rounded,
                            color: Colors.white,
                            size: 44,
                          ),
                        ),
                      )
                    : const Icon(Icons.person_rounded,
                        color: Colors.white, size: 44),
              ),
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: colors.success,
                  shape: BoxShape.circle,
                  border: Border.all(color: colors.bgDark, width: 2),
                ),
                child: const Icon(Icons.check, color: Colors.white, size: 10),
              ),
            ],
          )
              .animate()
              .fadeIn(duration: 500.ms)
              .scale(begin: const Offset(0.7, 0.7), curve: Curves.easeOutBack),

          const SizedBox(height: 32),

          // Hoş geldiniz yazısı
          Text(
            'Merhaba,',
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: 16,
              fontWeight: FontWeight.w400,
              letterSpacing: 0.5,
            ),
          ).animate().fadeIn(delay: 200.ms),

          const SizedBox(height: 6),

          // İsim — shimmer efektli
          RepaintBoundary(
            child: AnimatedBuilder(
              animation: _shimmerCtrl,
              builder: (_, child) {
                return ShaderMask(
                shaderCallback: (bounds) => LinearGradient(
                  colors: [
                    colors.primary,
                    colors.info,
                    colors.primary,
                  ],
                  stops: [
                    (_shimmerCtrl.value - 0.3).clamp(0.0, 1.0),
                    _shimmerCtrl.value.clamp(0.0, 1.0),
                    (_shimmerCtrl.value + 0.3).clamp(0.0, 1.0),
                  ],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ).createShader(bounds),
                child: child!,
              );
            },
            child: Text(
              name,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 36,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
              ),
            ),
          ),
          ).animate().fadeIn(delay: 300.ms).slideY(begin: 0.1, end: 0),

          const SizedBox(height: 12),

          // Email chip — misafir modunda e-posta olmadığı için gösterilmiyor
          if (email.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: colors.bgCard,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: colors.success,
                      boxShadow: [
                        BoxShadow(
                            color: colors.success.withValues(alpha: 0.5),
                            blurRadius: 6)
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    email,
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ).animate().fadeIn(delay: 450.ms),

          const SizedBox(height: 48),

          // Divider + yükleniyor
          SizedBox(
            width: 160,
            child: Column(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    backgroundColor: colors.primary.withValues(alpha: 0.08),
                    valueColor:
                        AlwaysStoppedAnimation(colors.primary.withValues(alpha: 0.6)),
                    minHeight: 2,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Veriler yükleniyor...',
                  style: TextStyle(
                    color: colors.textMuted,
                    fontSize: 11,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ).animate().fadeIn(delay: 600.ms),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Feature Row (landing ekranı için)
// ─────────────────────────────────────────────

class _FeatureRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;

  const _FeatureRow({
    required this.icon,
    required this.color,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 14),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: 13,
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────
// Biyometrik İçerik
// ─────────────────────────────────────────────

class _BiometricContent extends StatelessWidget {
  final bool authenticating;
  final bool error;
  final String status;
  final AnimationController pulseCtrl;
  final AnimationController rippleCtrl;
  final VoidCallback onRetry;
  final VoidCallback? onUsePIN;

  const _BiometricContent({
    super.key,
    required this.authenticating,
    required this.error,
    required this.status,
    required this.pulseCtrl,
    required this.rippleCtrl,
    required this.onRetry,
    this.onUsePIN,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return SizedBox.expand(
      child: SingleChildScrollView(
        physics: const ClampingScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: MediaQuery.of(context).size.height -
                MediaQuery.of(context).padding.top -
                MediaQuery.of(context).padding.bottom,
          ),
          child: IntrinsicHeight(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Spacer(),
                AnimatedBuilder(
                  animation: rippleCtrl,
                  builder: (_, child) => Stack(
                    alignment: Alignment.center,
                    children: [
                      Opacity(
                        opacity: (1 - rippleCtrl.value).clamp(0.0, 1.0) * 0.15,
                        child: Container(
                          width: 90 + rippleCtrl.value * 60,
                          height: 90 + rippleCtrl.value * 60,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: error ? colors.error : colors.primary,
                                width: 1),
                          ),
                        ),
                      ),
                      Opacity(
                        opacity: ((1 - (rippleCtrl.value + 0.4) % 1))
                                .clamp(0.0, 1.0) *
                            0.1,
                        child: Container(
                          width: 90 + ((rippleCtrl.value + 0.4) % 1) * 60,
                          height: 90 + ((rippleCtrl.value + 0.4) % 1) * 60,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: error ? colors.error : colors.primary,
                                width: 1),
                          ),
                        ),
                      ),
                      child!,
                    ],
                  ),
                  child: AnimatedBuilder(
                    animation: pulseCtrl,
                    builder: (_, child) => Container(
                      width: 88,
                      height: 88,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: error
                              ? [colors.error, colors.error]
                              : [colors.primary, colors.info],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: (error ? colors.error : colors.primary)
                                .withValues(alpha: 0.3),
                            blurRadius: 20 + pulseCtrl.value * 16,
                            spreadRadius: 2,
                          )
                        ],
                      ),
                      child: child,
                    ),
                    child: const Icon(Icons.fingerprint,
                        color: Colors.white, size: 44),
                  ),
                ).animate().fadeIn(duration: 500.ms).scale(
                    begin: const Offset(0.6, 0.6), curve: Curves.easeOutBack),
                const SizedBox(height: 40),
                const MtoolsMark(size: 48).animate().fadeIn(delay: 150.ms),
                const SizedBox(height: 14),
                Text(
                  'MTools',
                  style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2),
                ).animate().fadeIn(delay: 200.ms),
                const SizedBox(height: 6),
                Text(
                  'Sunucu Yönetim Sistemi',
                  style: TextStyle(
                      color: colors.textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                      letterSpacing: 0.5),
                ).animate().fadeIn(delay: 300.ms),
                const SizedBox(height: 36),
                AnimatedSwitcher(
                  duration: AppMotion.base,
                  switchInCurve: AppMotion.curve,
                  switchOutCurve: AppMotion.curve,
                  child: Text(
                    status,
                    key: ValueKey(status),
                    style: TextStyle(
                        color: error ? colors.error : colors.textSecondary,
                        fontSize: 12,
                        letterSpacing: 1),
                  ),
                ),
                const SizedBox(height: 28),
                if (authenticating)
                  SizedBox(
                    width: 160,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        backgroundColor: colors.primary.withValues(alpha: 0.1),
                        valueColor: AlwaysStoppedAnimation(colors.primary),
                        minHeight: 2,
                      ),
                    ),
                  )
                else
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      OutlinedButton.icon(
                        onPressed: onRetry,
                        icon: Icon(Icons.fingerprint,
                            size: 16, color: colors.primary),
                        label: Text(
                          'Tekrar Dene',
                          style: TextStyle(
                              color: colors.primary,
                              fontSize: 13,
                              letterSpacing: 0.5),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(
                              color: colors.primary.withValues(alpha: 0.4)),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 28, vertical: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(24)),
                        ),
                      ),
                      if (onUsePIN != null) ...[
                        const SizedBox(height: 12),
                        TextButton(
                          onPressed: onUsePIN,
                          child: Text(
                            'PIN ile giriş',
                            style: TextStyle(
                                color: colors.textMuted, fontSize: 12),
                          ),
                        ),
                      ],
                    ],
                  ).animate().fadeIn(delay: 200.ms),
                const Spacer(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// PIN İçerik
// ─────────────────────────────────────────────

class _PINContent extends StatelessWidget {
  final String pin;
  final bool error;
  final Animation<double> shakeAnim;
  final Function(String) onKey;
  final VoidCallback? onUseBiometric;

  const _PINContent({
    super.key,
    required this.pin,
    required this.error,
    required this.shakeAnim,
    required this.onKey,
    this.onUseBiometric,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final size = MediaQuery.of(context).size;

    return SizedBox.expand(
      child: Column(
        children: [
          const Spacer(flex: 2),
          const MtoolsMark(size: 48)
              .animate()
              .fadeIn(duration: 400.ms)
              .scale(begin: const Offset(0.8, 0.8), curve: Curves.easeOutBack),
          const SizedBox(height: 14),
          Text(
            'MTools',
            style: TextStyle(
                color: colors.textPrimary,
                fontSize: 26,
                fontWeight: FontWeight.w700,
                letterSpacing: 2),
          ).animate().fadeIn(delay: 100.ms),
          const SizedBox(height: 6),
          AnimatedSwitcher(
            duration: AppMotion.base,
            switchInCurve: AppMotion.curve,
            switchOutCurve: AppMotion.curve,
            child: Text(
              error ? 'Yanlış PIN — Tekrar deneyin' : 'PIN kodunuzu girin',
              key: ValueKey(error),
              style: TextStyle(
                color: error ? colors.error : colors.textMuted,
                fontSize: 12,
                letterSpacing: 0.5,
              ),
            ),
          ),
          const SizedBox(height: 32),
          AnimatedBuilder(
            animation: shakeAnim,
            builder: (_, child) {
              final offset =
                  error ? 10 * (0.5 - (shakeAnim.value - 0.5).abs()) * 2 : 0.0;
              return Transform.translate(
                offset: Offset(offset * (shakeAnim.value < 0.5 ? 1 : -1), 0),
                child: child,
              );
            },
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(4, (i) {
                final filled = pin.length > i;
                return AnimatedContainer(
                  duration: AppMotion.fast,
                  curve: AppMotion.curve,
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  width: filled ? 18 : 14,
                  height: filled ? 18 : 14,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: error
                        ? colors.error
                        : filled
                            ? colors.primary
                            : Colors.transparent,
                    border: Border.all(
                      color: error
                          ? colors.error
                          : filled
                              ? colors.primary
                              : colors.textMuted.withValues(alpha: 0.4),
                      width: 1.5,
                    ),
                    boxShadow: filled && !error
                        ? [
                            BoxShadow(
                                color: colors.primary.withValues(alpha: 0.6),
                                blurRadius: 10,
                                spreadRadius: 1)
                          ]
                        : null,
                  ),
                );
              }),
            ),
          ),
          const Spacer(),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: size.width * 0.1),
            child: Column(children: [
              _row(['1', '2', '3'], onKey),
              const SizedBox(height: 10),
              _row(['4', '5', '6'], onKey),
              const SizedBox(height: 10),
              _row(['7', '8', '9'], onKey),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: onUseBiometric != null
                      ? GestureDetector(
                          onTap: onUseBiometric,
                          child: Container(
                            height: 60,
                            decoration: BoxDecoration(
                              color: colors.bgCard.withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.06)),
                            ),
                            child: Icon(Icons.fingerprint,
                                color: colors.textMuted, size: 22),
                          ),
                        )
                      : const SizedBox(),
                ),
                const SizedBox(width: 10),
                Expanded(child: _KeyBtn(label: '0', onTap: () => onKey('0'))),
                const SizedBox(width: 10),
                Expanded(
                  child: _KeyBtn(
                      label: '⌫', onTap: () => onKey('⌫'), isDelete: true),
                ),
              ]),
            ]),
          ),
          const Spacer(),
        ],
      ),
    );
  }

  Widget _row(List<String> keys, Function(String) onKey) {
    return Row(
      children: keys
          .asMap()
          .entries
          .map((e) => Expanded(
                child: Padding(
                  padding: EdgeInsets.only(left: e.key == 0 ? 0 : 10),
                  child: _KeyBtn(label: e.value, onTap: () => onKey(e.value)),
                ),
              ))
          .toList(),
    );
  }
}

// ─────────────────────────────────────────────
// Numpad Tuş Widget'ı
// ─────────────────────────────────────────────

class _KeyBtn extends StatefulWidget {
  final String label;
  final VoidCallback onTap;
  final bool isDelete;

  const _KeyBtn(
      {required this.label, required this.onTap, this.isDelete = false});

  @override
  State<_KeyBtn> createState() => _KeyBtnState();
}

class _KeyBtnState extends State<_KeyBtn> {
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
        height: 60,
        decoration: BoxDecoration(
          color: _pressed
              ? colors.primary.withValues(alpha: 0.15)
              : colors.bgCard.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _pressed
                ? colors.primary.withValues(alpha: 0.4)
                : Colors.white.withValues(alpha: 0.06),
          ),
          boxShadow: _pressed
              ? [
                  BoxShadow(
                      color: colors.primary.withValues(alpha: 0.15),
                      blurRadius: 12,
                      spreadRadius: 0)
                ]
              : null,
        ),
        child: Center(
          child: widget.isDelete
              ? Icon(Icons.backspace_outlined,
                  color: _pressed ? colors.primary : colors.textSecondary,
                  size: 20)
              : Text(widget.label,
                  style: TextStyle(
                      color: _pressed ? colors.primary : colors.textPrimary,
                      fontSize: 22,
                      fontWeight: FontWeight.w300)),
        ),
        ),
      ),
    );
  }
}
