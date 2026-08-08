import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/mtools_mark.dart';
import '../../core/utils/app_transitions.dart';
import 'home_screen.dart';
import 'package:provider/provider.dart';
import '../proxmox/proxmox_provider.dart';
import '../adguard/adguard_provider.dart';
import '../ups/nut_provider.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Onboarding verisi
// ─────────────────────────────────────────────────────────────────────────────

class _OnboardPage {
  final IconData icon;
  final String title;
  final String description;

  const _OnboardPage({
    required this.icon,
    required this.title,
    required this.description,
  });
}

const _pages = [
  _OnboardPage(
    icon: Icons.waving_hand_rounded,
    title: 'Hoş Geldin',
    description: 'Sunucularının tamamı artık cebinde.',
  ),
  _OnboardPage(
    icon: Icons.dashboard_rounded,
    title: 'Tek Bakışta',
    description: 'Sunucularının nabzını buradan tut.',
  ),
  _OnboardPage(
    icon: Icons.storage_rounded,
    title: 'Uzaktan Kumanda',
    description:
        'Konteynerlerini ve sanal makinelerini parmaklarının ucuyla yönet.',
  ),
  _OnboardPage(
    icon: Icons.shield_rounded,
    title: 'Sessiz Bekçi',
    description: 'Reklamları ve takibi engelleyen korumanı izle.',
  ),
  _OnboardPage(
    icon: Icons.battery_charging_full_rounded,
    title: 'Erken Uyarı',
    description: 'Güç kaynağın seni önceden uyarır.',
  ),
  _OnboardPage(
    icon: Icons.terminal_rounded,
    title: 'Doğrudan Bağlan',
    description: 'Komut satırın bir dokunuş uzağında.',
  ),
  _OnboardPage(
    icon: Icons.power_settings_new_rounded,
    title: 'Uzaktan Uyandır',
    description: 'Kapalı bir cihazı bile evden uzaktayken çalıştır.',
  ),
  _OnboardPage(
    icon: Icons.notifications_rounded,
    title: 'Haberin Olsun',
    description: 'Bir şeyler ters giderse ilk sen öğrenirsin.',
  ),
  _OnboardPage(
    icon: Icons.forum_rounded,
    title: 'Sesini Duyalım',
    description: 'Bir fikrin mi var? Bize ulaşman yeter.',
  ),
];

// ─────────────────────────────────────────────────────────────────────────────
// Widget
// ─────────────────────────────────────────────────────────────────────────────

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with TickerProviderStateMixin {
  final _pageController = PageController();
  int _currentPage = 0;
  // Sayfa başına ayrı controller — komşu sayfalar PageView tarafından fiziksel
  // kaydırma için önceden inşa edilse bile, animasyonun sadece o an "aktif"
  // olan sayfaya uygulanmasını garantiler (paylaşılan tek controller komşu
  // sayfayı da etkiler).
  late List<AnimationController> _pageAnimControllers;

  @override
  void initState() {
    super.initState();
    _pageAnimControllers = List.generate(
      _pages.length,
      (_) => AnimationController(vsync: this, duration: AppMotion.base),
    );
    _pageAnimControllers[0].forward();
  }

  @override
  void dispose() {
    _pageController.dispose();
    for (final c in _pageAnimControllers) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _markSeenAndGo() => _finishOnboarding(startTour: true);
  Future<void> _skipAndGo() => _finishOnboarding(startTour: false);

  Future<void> _finishOnboarding({required bool startTour}) async {
    final prefs = await SharedPreferences.getInstance();
    final packageInfo = await PackageInfo.fromPlatform();
    await prefs.setString('onboarding_version', packageInfo.version);
    if (!mounted) return;
    await Future.wait([
      context.read<ProxmoxProvider>().init(),
      context.read<AdGuardProvider>().init(),
      context.read<NutProvider>().init(),
    ]);
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      AppTransitions.fadeThrough<void>(HomeScreen(startTour: startTour)),
    );
  }

  void _next() {
    if (_currentPage < _pages.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOutCubic,
      );
    } else {
      _markSeenAndGo();
    }
  }

  void _onPageChanged(int index) {
    setState(() => _currentPage = index);
    _pageAnimControllers[index]
      ..reset()
      ..forward();
  }

  Future<void> _sendEmail() async {
    final uri = Uri(
      scheme: 'mailto',
      path: 'mertbaskurt14@gmail.com',
      queryParameters: {
        'subject': 'MTools Geri Bildirim',
        'body': 'Merhaba,\n\nMTools uygulaması hakkında geri bildirimim:\n\n',
      },
    );
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      // Bilinçli sessiz: cihazda mail istemcisi yoksa launchUrl başarısız
      // olur; onboarding'de bunu bildirecek bir SnackBar/hata yüzeyi yok.
    }
  }

  bool get _isLastPage => _currentPage == _pages.length - 1;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Scaffold(
      backgroundColor: colors.surface0,
      body: SafeArea(
        child: Column(
          children: [
            // ── Atla butonu ────────────────────────────────────────────────
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(0, 12, 20, 0),
                child: AnimatedOpacity(
                  opacity: _isLastPage ? 0 : 1,
                  duration: AppMotion.fast,
                  curve: AppMotion.curve,
                  child: TextButton(
                    onPressed: _isLastPage ? null : _skipAndGo,
                    child: Text(
                      'Atla',
                      style: TextStyle(
                        color: colors.textMuted,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // ── PageView ───────────────────────────────────────────────────
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                onPageChanged: _onPageChanged,
                itemCount: _pages.length,
                itemBuilder: (context, index) {
                  final p = _pages[index];
                  return _PageContent(
                    page: p,
                    isFirstPage: index == 0,
                    isLastPage: index == _pages.length - 1,
                    animController: _pageAnimControllers[index],
                    onEmailTap: _sendEmail,
                  );
                },
              ),
            ),

            // ── Dots + İleri butonu ────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
              child: Column(
                children: [
                  // Dots
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(_pages.length, (i) {
                      final isActive = i == _currentPage;
                      return AnimatedContainer(
                        duration: AppMotion.fast,
                        curve: AppMotion.curve,
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        width: isActive ? 20 : 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: isActive ? colors.primary : colors.hairline,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 28),

                  // İleri / Başla butonu
                  SizedBox(
                    width: double.infinity,
                    child: Material(
                      color: colors.primary,
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      child: InkWell(
                        onTap: _next,
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                _isLastPage ? 'Başlayalım' : 'Devam',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Icon(
                                _isLastPage
                                    ? Icons.rocket_launch_rounded
                                    : Icons.arrow_forward_rounded,
                                color: Colors.white,
                                size: 18,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
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

// ─────────────────────────────────────────────────────────────────────────────
// Sayfa içeriği — tipografi öncelikli: bol boşluk, küçük nötr ikon, büyük
// başlık, tek satır açıklama. İçerik tek blok halinde fade + 8px yukarı
// kayma ile beliriyor (AppMotion.base) — parça parça belirme yok.
// ─────────────────────────────────────────────────────────────────────────────

class _PageContent extends StatelessWidget {
  final _OnboardPage page;
  final bool isFirstPage;
  final bool isLastPage;
  final AnimationController animController;
  final VoidCallback onEmailTap;

  const _PageContent({
    required this.page,
    required this.isFirstPage,
    required this.isLastPage,
    required this.animController,
    required this.onEmailTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final curved = CurvedAnimation(parent: animController, curve: AppMotion.curve);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedBuilder(
            animation: curved,
            builder: (context, child) => Opacity(
              opacity: curved.value,
              child: Transform.translate(
                offset: Offset(0, (1 - curved.value) * 8),
                child: child,
              ),
            ),
            child: Column(
              children: [
                // ── İkon / marka anı ──────────────────────────────────────
                isFirstPage
                    ? const MtoolsMark(size: 48)
                    : Icon(page.icon, size: 26, color: colors.textSecondary),
                const SizedBox(height: 32),

                // ── Başlık ─────────────────────────────────────────────────
                Text(
                  page.title,
                  textAlign: TextAlign.center,
                  style: colors.pageTitle.copyWith(fontSize: 32),
                ),
                const SizedBox(height: 12),

                // ── Açıklama ───────────────────────────────────────────────
                Text(
                  page.description,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: colors.textSecondary, fontSize: 15),
                ),

                // ── Son sayfaya özel ek içerik ──────────────────────────────
                if (isLastPage) ...[
                  const SizedBox(height: 32),
                  _ContactCard(onEmailTap: onEmailTap),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// İletişim kartı
// ─────────────────────────────────────────────────────────────────────────────

class _ContactCard extends StatelessWidget {
  final VoidCallback onEmailTap;

  const _ContactCard({required this.onEmailTap});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
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
                  color: colors.success.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Icon(
                  Icons.mark_email_unread_rounded,
                  color: colors.success,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Bize Ulaşın',
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Bir şey mi aksadı? Bize yaz.',
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: 13,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onEmailTap,
              icon: Icon(
                Icons.send_rounded,
                size: 15,
                color: colors.success,
              ),
              label: Text(
                'mertbaskurt14@gmail.com',
                style: TextStyle(
                  color: colors.success,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              style: OutlinedButton.styleFrom(
                side: BorderSide(
                  color: colors.success,
                  width: 1,
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
