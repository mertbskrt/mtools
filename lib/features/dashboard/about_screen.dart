import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/mtools_mark.dart';
import '../../core/utils/app_transitions.dart';
import 'error_log_screen.dart';
import 'error_log_service.dart';

class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  int _secretTapCount = 0;
  String _version = '';
  String _buildNumber = '';

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (mounted) {
      setState(() {
        _version = info.version;
        _buildNumber = info.buildNumber;
      });
    }
  }

  Future<void> _sendMail() async {
    const email = 'mertbaskurt14@gmail.com';
    final subject =
        'MTools${_version.isNotEmpty ? ' v$_version' : ''} Geri Bildirim';
    final uri = Uri(
      scheme: 'mailto',
      path: email,
      query: 'subject=${Uri.encodeComponent(subject)}',
    );
    try {
      final launched =
          await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched && mounted) {
        await Clipboard.setData(const ClipboardData(text: email));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: const Text(
                'Mail uygulaması bulunamadı. E-posta adresi kopyalandı.'),
            backgroundColor: context.appColors.warning,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
          ));
        }
      }
    } catch (e) {
      await Clipboard.setData(const ClipboardData(text: email));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('E-posta adresi panoya kopyalandı.'),
          backgroundColor: context.appColors.info,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
        ));
      }
    }
  }

  Future<void> _openRepo() async {
    const url = 'https://github.com/mertbskrt/mtools-releases';
    try {
      final launched =
          await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      if (!launched && mounted) {
        await Clipboard.setData(const ClipboardData(text: url));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: const Text('Tarayıcı bulunamadı. Bağlantı kopyalandı.'),
            backgroundColor: context.appColors.warning,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.md)),
          ));
        }
      }
    } catch (e) {
      await Clipboard.setData(const ClipboardData(text: url));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('Bağlantı panoya kopyalandı.'),
          backgroundColor: context.appColors.info,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.md)),
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Scaffold(
      backgroundColor: colors.bgDark,
      appBar: AppBar(
        backgroundColor: colors.bgDark,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new,
              color: colors.textPrimary, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Hakkında',
            style: TextStyle(
                color: colors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.bold)),
      ),
      body: Stack(
        children: [
          // ── Arka plan ────────────────────────────────────────────────────
          // Statik, profesyonel bir görünüm için sabit üst parıltı + ince
          // nokta ızgarası — önceki sürümdeki "uçuşan baloncuklar" animasyonu
          // kaldırıldı.
          RepaintBoundary(
            child: CustomPaint(
              painter: _BgPainter(colors.primary),
              size: Size.infinite,
            ),
          ),

          SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 48),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 12),

                // ── Hero bölümü ─────────────────────────────────────────────
                Center(
                  child: Column(
                    children: [
                      const MtoolsMark(size: 88)
                          .animate()
                          .fadeIn(duration: 500.ms)
                          .scale(
                              begin: const Offset(0.5, 0.5),
                              curve: Curves.easeOutBack),

                      const SizedBox(height: 16),

                      Text(
                        'MTools',
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2,
                        ),
                      ).animate().fadeIn(delay: 150.ms).slideY(begin: 0.2),

                      const SizedBox(height: 6),

                      // Gizli 5-dokunuş — hata günlüğü ekranını açar. Konum
                      // ve davranış bilinçli olarak değiştirilmedi (bkz.
                      // redesign talebi).
                      GestureDetector(
                        onTap: () async {
                          _secretTapCount++;
                          if (_secretTapCount >= 5) {
                            _secretTapCount = 0;
                            await ErrorLogService().load();
                            if (context.mounted) {
                              Navigator.push(
                                context,
                                AppTransitions.slideFade(
                                    const ErrorLogScreen()),
                              );
                            }
                          }
                        },
                        child: Text(
                          _version.isNotEmpty
                              ? 'v$_version ($_buildNumber)'
                              : ' ',
                          style: TextStyle(
                            color: colors.textMuted,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ).animate().fadeIn(delay: 250.ms),

                      const SizedBox(height: 10),

                      Text(
                        'Sunucu Yönetim ve İzleme Platformu',
                        style: TextStyle(
                            color: colors.textMuted, fontSize: 12),
                      ).animate().fadeIn(delay: 320.ms),
                    ],
                  ),
                ),

                const SizedBox(height: 32),

                // ── Platform bilgisi ────────────────────────────────────────
                _SectionCard(
                  colors: colors,
                  delay: 380,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _SectionHeader(
                          colors: colors,
                          icon: Icons.info_outline_rounded,
                          title: 'Platform'),
                      const SizedBox(height: 14),
                      Text(
                        'MTools, kendi Proxmox, AdGuard Home, UPS ve ağ '
                        'cihazlarını yöneten kişiler için tasarlanmış, açık '
                        'kaynaklı bir Android izleme ve yönetim uygulamasıdır. '
                        'Flutter ile geliştirilmiştir; sunucu bilgileriniz ve '
                        'kimlik bilgileriniz cihazınızda kalır.',
                        style: TextStyle(
                          color: colors.textSecondary,
                          fontSize: 13,
                          height: 1.7,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                // ── Geliştirici ─────────────────────────────────────────────
                _SectionCard(
                  colors: colors,
                  delay: 460,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _SectionHeader(
                          colors: colors,
                          icon: Icons.person_outline_rounded,
                          title: 'Geliştirici'),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: colors.surface2,
                            ),
                            child: const Center(child: MtoolsMark(size: 26)),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text('Mert Başkurt',
                                style: TextStyle(
                                    color: colors.textPrimary,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      GestureDetector(
                        onTap: _sendMail,
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: colors.primary.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(AppRadius.md),
                            border: Border.all(
                                color: colors.primary.withValues(alpha: 0.15)),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: colors.primary.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(AppRadius.sm),
                                ),
                                child: Icon(Icons.email_outlined,
                                    color: colors.primary, size: 16),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text('mertbaskurt14@gmail.com',
                                        style: TextStyle(
                                            color: colors.textPrimary,
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600)),
                                    const SizedBox(height: 2),
                                    Text('Hata bildir veya öneri gönder',
                                        style: TextStyle(
                                            color: colors.textMuted,
                                            fontSize: 11)),
                                  ],
                                ),
                              ),
                              Icon(Icons.arrow_forward_ios,
                                  color: colors.textMuted, size: 12),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                // ── Sürüm Notları ───────────────────────────────────────────
                _SectionCard(
                  colors: colors,
                  delay: 540,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _SectionHeader(
                          colors: colors,
                          icon: Icons.update_rounded,
                          title: 'Sürüm Notları'),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: colors.primary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(AppRadius.sm),
                              border: Border.all(
                                  color: colors.primary.withValues(alpha: 0.25)),
                            ),
                            child: Text(
                                _version.isNotEmpty
                                    ? 'v$_version'
                                    : '',
                                style: TextStyle(
                                    color: colors.primary,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold)),
                          ),
                          const SizedBox(width: 10),
                          Text('Ağustos 2026',
                              style: TextStyle(
                                  color: colors.textMuted, fontSize: 11)),
                        ],
                      ),
                      const SizedBox(height: 16),
                      ..._releaseNotes.map((note) => Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.only(left: 12),
                            decoration: BoxDecoration(
                              border: Border(
                                left: BorderSide(
                                  color: colors.primary.withValues(alpha: 0.35),
                                  width: 2,
                                ),
                              ),
                            ),
                            child: Text(note,
                                style: TextStyle(
                                    color: colors.textSecondary,
                                    fontSize: 12,
                                    height: 1.5)),
                          )),
                    ],
                  ),
                ),

                const SizedBox(height: 28),

                // ── Footer ──────────────────────────────────────────────────
                Center(
                  child: Column(
                    children: [
                      Container(
                        width: 40,
                        height: 1,
                        color: colors.textMuted.withValues(alpha: 0.2),
                      ),
                      const SizedBox(height: 12),
                      GestureDetector(
                        onTap: _openRepo,
                        child: Text(
                          'github.com/mertbskrt/mtools-releases',
                          style: TextStyle(
                            color: colors.textMuted,
                            fontSize: 11,
                            decoration: TextDecoration.underline,
                            decorationColor:
                                colors.textMuted.withValues(alpha: 0.4),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        '© 2025 Mert Başkurt',
                        style: TextStyle(
                            color: colors.textMuted, fontSize: 11),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Tüm hakları saklıdır.',
                        style: TextStyle(
                            color: colors.textMuted.withValues(alpha: 0.6),
                            fontSize: 10),
                      ),
                    ],
                  ).animate().fadeIn(delay: 620.ms),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static const _releaseNotes = [
    'Wake-on-LAN widget\'ındaki bir sorun düzeltildi — "Uyandır" butonu '
        'bazı durumlarda paket gerçekte gönderilmediği halde başarılı '
        'gösteriyordu, artık gönderim gerçekten doğrulanıyor.',
    'İnternet bağlantınız koptuğunda, uygulama açıkken de artık doğru '
        'bildirimi alıyorsunuz — önceden bu sadece uygulama arka '
        'plandayken çalışıyordu.',
    'Arka plan izleme servisinin nadir durumlarda çökme ihtimali '
        'giderildi, izleme artık daha kararlı çalışıyor.',
    'Güncelleme kontrolü sırasında oluşabilecek sessiz hatalar artık '
        'kayıt altına alınıyor.',
  ];
}

// ─────────────────────────────────────────────
// Section Card
// ─────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  final AppThemeData colors;
  final int delay;
  final Widget child;

  const _SectionCard({
    required this.colors,
    required this.delay,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.bgCard,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: colors.hairline),
      ),
      child: child,
    )
        .animate()
        .fadeIn(delay: Duration(milliseconds: delay))
        .slideY(begin: 0.08, curve: Curves.easeOut);
  }
}

// ─────────────────────────────────────────────
// Section Header
// ─────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final AppThemeData colors;
  final IconData icon;
  final String title;

  const _SectionHeader({
    required this.colors,
    required this.icon,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: colors.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          child: Icon(icon, color: colors.primary, size: 14),
        ),
        const SizedBox(width: 10),
        Text(
          title,
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 13,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.3,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────
// Arka Plan Painter
// ─────────────────────────────────────────────

class _BgPainter extends CustomPainter {
  final Color color;

  _BgPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    // Üstte sabit, yumuşak bir parıltı — hero bölümünün arkasında derinlik
    // hissi verir, oynamaz/animasyonsuzdur.
    final glowCenter = Offset(size.width * 0.5, 0);
    final glowPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          color.withValues(alpha: 0.10),
          color.withValues(alpha: 0.0),
        ],
      ).createShader(
        Rect.fromCircle(center: glowCenter, radius: size.width * 0.9),
      );
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), glowPaint);

    // İnce, sabit nokta ızgarası — mühendislik/blueprint hissi veren
    // profesyonel bir doku, çok düşük opaklıkta.
    final dotPaint = Paint()
      ..color = color.withValues(alpha: 0.05)
      ..style = PaintingStyle.fill;
    const spacing = 28.0;
    const dotRadius = 0.9;
    for (double y = 0; y < size.height; y += spacing) {
      for (double x = 0; x < size.width; x += spacing) {
        canvas.drawCircle(Offset(x, y), dotRadius, dotPaint);
      }
    }
  }

  @override
  bool shouldRepaint(_BgPainter old) => old.color != color;
}
