import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/constants/links.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/design_widgets.dart';
import '../../core/theme/mtools_mark.dart';
import '../../core/utils/app_transitions.dart';
import 'error_log_screen.dart';
import 'error_log_service.dart';
import '../feedback/feedback_screen.dart';
import '../update/release_history_screen.dart';
import '../update/update_screen.dart';

/// Dış bağlantıyı açan fonksiyon — varsayılan url_launcher'ın launchUrl'ü.
/// Testler, hangi adresin açıldığını doğrulamak için kendi fonksiyonunu verir.
typedef UrlLauncher = Future<bool> Function(Uri uri, {LaunchMode mode});

class AboutScreen extends StatefulWidget {
  final UrlLauncher? urlLauncher;

  const AboutScreen({super.key, this.urlLauncher});

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

  Future<bool> _launch(Uri uri) =>
      (widget.urlLauncher ?? launchUrl)(uri,
          mode: LaunchMode.externalApplication);

  Future<void> _sendMail() async {
    const email = MToolsLinks.contactEmail;
    final subject =
        'MTools${_version.isNotEmpty ? ' v$_version' : ''} Geri Bildirim';
    final uri = Uri(
      scheme: 'mailto',
      path: email,
      query: 'subject=${Uri.encodeComponent(subject)}',
    );
    try {
      final launched = await _launch(uri);
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

  /// Dış tarayıcıda açar; açılamazsa (tarayıcı yok, hata) uygulama çökmez,
  /// "Bağlantı açılamadı" gösterilir.
  Future<void> _openUrl(String url) async {
    var launched = false;
    try {
      launched = await _launch(Uri.parse(url));
    } catch (_) {
      // Aşağıda kullanıcıya bildiriliyor.
    }
    if (launched || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: const Text('Bağlantı açılamadı'),
      backgroundColor: context.appColors.warning,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md)),
    ));
  }

  void _push(Widget page) =>
      Navigator.push(context, AppTransitions.slideFade(page));

  void _showLicenses() => showLicensePage(
        context: context,
        applicationName: 'MTools',
        applicationVersion:
            _version.isNotEmpty ? 'v$_version ($_buildNumber)' : null,
        applicationIcon: const Padding(
          padding: EdgeInsets.all(12),
          child: MtoolsMark(size: 48),
        ),
        applicationLegalese: '© 2026 MTools',
      );

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

                      const SizedBox(height: 14),

                      OutlinedButton.icon(
                        onPressed: () => _push(const UpdateScreen()),
                        icon: const Icon(Icons.system_update_rounded, size: 16),
                        label: const Text('Güncellemeleri denetle'),
                        // primary (OLED paletinde açık gri) açık temada
                        // metin için yeterli kontrast vermiyor — nötr metin
                        // rengi ve ince kenarlık her iki temada okunur.
                        style: OutlinedButton.styleFrom(
                          foregroundColor: colors.textPrimary,
                          side: BorderSide(color: colors.hairline),
                          shape: RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(AppRadius.md)),
                        ),
                      ).animate().fadeIn(delay: 320.ms),
                    ],
                  ),
                ),

                const SizedBox(height: 28),

                // ── Uygulama ────────────────────────────────────────────────
                const _GroupLabel('Uygulama'),
                _SectionCard(
                  colors: colors,
                  delay: 380,
                  child: Column(
                    children: [
                      _LinkTile(
                        colors: colors,
                        icon: Icons.new_releases_outlined,
                        title: 'Sürüm notları',
                        subtitle: _version.isNotEmpty
                            ? 'v$_version ile gelen yenilikler'
                            : 'Bu sürümdeki yenilikler',
                        onTap: () => _push(_ReleaseNotesPage(
                            version: _version, notes: _releaseNotes)),
                      ),
                      _LinkTile(
                        colors: colors,
                        icon: Icons.language_rounded,
                        title: 'Web sitesi',
                        subtitle: MToolsLinks.websiteLabel,
                        external: true,
                        onTap: () => _openUrl(MToolsLinks.website),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // ── Destek ──────────────────────────────────────────────────
                const _GroupLabel('Destek'),
                _SectionCard(
                  colors: colors,
                  delay: 440,
                  child: Column(
                    children: [
                      _LinkTile(
                        colors: colors,
                        icon: Icons.feedback_outlined,
                        title: 'Geri bildirim gönder',
                        subtitle: 'Hata bildir, öneri ya da soru gönder',
                        onTap: () => _push(const FeedbackScreen()),
                      ),
                      _LinkTile(
                        colors: colors,
                        icon: Icons.email_outlined,
                        title: 'İletişim',
                        subtitle: MToolsLinks.contactEmail,
                        external: true,
                        onTap: _sendMail,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // ── Yasal ───────────────────────────────────────────────────
                // Kullanım koşulları sayfası mtools.tr'de henüz yok; yayınlanınca
                // MToolsLinks'e eklenip buraya bir satır olarak gelecek.
                const _GroupLabel('Yasal'),
                _SectionCard(
                  colors: colors,
                  delay: 500,
                  child: Column(
                    children: [
                      _LinkTile(
                        colors: colors,
                        icon: Icons.privacy_tip_outlined,
                        title: 'Gizlilik politikası',
                        subtitle: MToolsLinks.privacyLabel,
                        external: true,
                        onTap: () => _openUrl(MToolsLinks.privacy),
                      ),
                      _LinkTile(
                        colors: colors,
                        icon: Icons.description_outlined,
                        title: 'Açık kaynak lisansları',
                        subtitle: 'Kullanılan paketlerin lisansları',
                        onTap: _showLicenses,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 28),

                // ── Alt bilgi ───────────────────────────────────────────────
                Center(
                  child: Text(
                    '${MToolsLinks.websiteLabel} · ${MToolsLinks.contactEmail}',
                    style: TextStyle(color: colors.textMuted, fontSize: 11),
                  ),
                ).animate().fadeIn(delay: 560.ms),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static const _releaseNotes = [
    'Hakkında ekranı yenilendi, gizlilik politikası ve açık kaynak lisansları eklendi',
    'Alt menüde dokunma titreşimi ve daha hızlı geçiş',
    'Bildirim motorunda 4 güvenilirlik hatası düzeltildi: UPS-çevrimdışı '
        'bildiriminin bekleme süresi ayarı yok sayılıyordu, node-çevrimdışı '
        'bildirimleri tutarsız bekleme süresi kullanıyordu, node-tekrar-'
        'çevrimiçi bildirimi hiç bekleme süresine uymuyordu, Terminal\'in '
        'bağlantı hatası bildirimi geçmiş ekranıyla senkron bozulabiliyordu.',
    'UPS widget\'ı dar alanda 2./3. birimi hiçbir iz bırakmadan '
        'kaybediyordu — düzeltildi, artık Sistem ve Wake-on-LAN '
        'widget\'ları gibi kendi yapılandırma ekranı da var.',
    'AdGuard widget\'ı geniş-ama-kısa ya da dar-ama-uzun yerleşimlerde '
        'fazladan alana rağmen en az detaylı görünüme düşüyordu; koruma '
        'durumu metni de her zaman yeşil kalıyordu — ikisi de düzeltildi.',
    'Wake-on-LAN cihaz düzenleme ekranı, kayıtlı relay sunucusu o an '
        'listede yoksa sessizce başka bir sunucuyla değiştiriyordu — artık '
        'mevcut seçim korunup uyarılı olarak gösteriliyor.',
    'Sistem sekmesinde: özet bannerı erişilemeyen bir sunucuyu yanlışlıkla '
        '"çevrimiçi" gösterebiliyordu, Depolama/Ağ Arayüzleri bölümleri '
        'bazen boş görünüyordu, geçmiş grafiğindeki zaman etiketleri '
        'gerçek örnekleme zamanı yerine sabit bir tahmine dayanıyordu.',
    'Konteyner/VM başlat-durdur-yeniden başlat-sil işlemleri artık '
        'Proxmox\'un görev sonucunu doğrudan sorguluyor — belirsiz '
        '"gönderildi" mesajı yerine kesin başarı, gerçek hata metniyle '
        'kesin başarısızlık ya da (yalnızca bağlantı koparsa) dürüst bir '
        '"doğrulanamadı" gösteriliyor.',
    'Konteyner/VM detay sayfası, işlem gerçekten başarısız olsa bile '
        'hata mesajını okumadan otomatik kapanıyordu — düzeltildi.',
    'Bir sunucunun host/IP\'si ayarlardan değiştirildiğinde Wake-on-LAN '
        'relay eşleşmesi sessizce bozuluyordu — düzeltildi.',
    'İki farklı Proxmox sunucusu aynı node adını raporluyorsa (ör. '
        'ikisi de "pve") artık verileri karışmıyor, işlemler yanlış '
        'sunucuya gitmiyor.',
    'Yeni: Sistem Özeti bannerı artık özelleştirilebilir — şerit, '
        'dairesel ya da kart görünümü arasında seçim yapılabiliyor, '
        'CPU/sistem yükü verisi de eklendi.',
    'Yeni: Depolama detay sayfasına yedekten geri yükleme desteği '
        'eklendi — yedekleri listele, geri yükle ya da sil.',
  ];
}

// ─────────────────────────────────────────────
// Section Card
// ─────────────────────────────────────────────

/// Kart içindeki tek satır: solda ikon, sağda dış bağlantılar için
/// [Icons.open_in_new], uygulama içi sayfalar için ok.
class _LinkTile extends StatelessWidget {
  final AppThemeData colors;
  final IconData icon;
  final String title;
  final String subtitle;
  final bool external;
  final VoidCallback onTap;

  const _LinkTile({
    required this.colors,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.external = false,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      contentPadding: EdgeInsets.zero,
      dense: true,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
      leading: Icon(icon, color: colors.primary, size: 20),
      title: Text(title,
          style: TextStyle(
              color: colors.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle,
          style: TextStyle(color: colors.textMuted, fontSize: 11)),
      trailing: Icon(
          external ? Icons.open_in_new : Icons.chevron_right_rounded,
          color: colors.textMuted,
          size: external ? 16 : 20),
    );
  }
}

/// Kart grubunun üstündeki küçük başlık (UYGULAMA / DESTEK / YASAL).
class _GroupLabel extends StatelessWidget {
  final String text;
  const _GroupLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: SectionLabel(text),
    );
  }
}

/// Hakkında → Sürüm notları: bu sürümün Türkçe notları (internetsiz) ve
/// altta GitHub'daki tüm sürümler için Sürüm geçmişi ekranı.
class _ReleaseNotesPage extends StatelessWidget {
  final String version;
  final List<String> notes;

  const _ReleaseNotesPage({required this.version, required this.notes});

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
        title: Text('Sürüm Notları',
            style: TextStyle(
                color: colors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.bold)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        children: [
          _SectionCard(
            colors: colors,
            delay: 0,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SectionHeader(
                    colors: colors,
                    icon: Icons.update_rounded,
                    title: version.isNotEmpty ? 'v$version' : 'Bu sürüm'),
                const SizedBox(height: 16),
                ...notes.map((note) => Container(
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
          const SizedBox(height: 12),
          Center(
            child: TextButton.icon(
              onPressed: () => Navigator.push(context,
                  AppTransitions.slideFade(const ReleaseHistoryScreen())),
              icon: const Icon(Icons.history_rounded, size: 16),
              label: const Text('Tüm sürümler'),
              style: TextButton.styleFrom(foregroundColor: colors.primary),
            ),
          ),
        ],
      ),
    );
  }
}

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
