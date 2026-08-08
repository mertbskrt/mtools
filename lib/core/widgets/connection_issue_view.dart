import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../theme/mtools_mark.dart';

/// Bir servise (Proxmox/AdGuard/UPS) internet varken erişilemediğinde
/// gösterilecek durumu belirtir — [ConnectionTarget]'tan (bkz.
/// core/utils/connection_target.dart) türetilir.
enum ConnectionIssueKind {
  /// Hedef özel/iç ağ IP'si — kullanıcı muhtemelen dış ağda/VPN'siz,
  /// servis çökmemiş olabilir.
  privateNetwork,

  /// Hedef Tailscale adresi — Tailscale bu cihazda bağlı olmayabilir.
  tailscale,

  /// Hedef dış adres/alan adı — servisin kendisiyle ilgili gerçek bir
  /// sorun olma ihtimali daha yüksek. Bilinçli olarak alarm/kırmızı tonu
  /// korur (bkz. [ConnectionIssueView] renk mantığı).
  generic,
}

/// [kind]/[serviceName]/[host]'a göre başlık ve açıklama metnini üretir.
/// [ConnectionIssueView] bunu kendi içinde kullanır; UPS ekranının satır-içi
/// kompakt banner'ı da (tam widget yerine) aynı metni buradan okur — Türkçe
/// kopya tek yerde tutulur, iki yerde tekrarlanmaz.
(String title, String message) connectionIssueCopy(
  ConnectionIssueKind kind,
  String serviceName,
  String host,
) {
  switch (kind) {
    case ConnectionIssueKind.privateNetwork:
      return (
        'İç ağa erişilemiyor',
        'İnternet bağlantınız var ancak $serviceName iç IP adresi ($host) '
            'üzerinden yanıt vermiyor. İç ağınızda olduğunuza emin misiniz? '
            'Dışarıdaysanız VPN (Tailscale) bağlantınızı kontrol edin.',
      );
    case ConnectionIssueKind.tailscale:
      return (
        'Tailscale ağına erişilemiyor',
        'İnternet bağlantınız var ancak $serviceName Tailscale adresi '
            '($host) üzerinden yanıt vermiyor. Tailscale\'in bu cihazda '
            'bağlı olduğundan emin olun.',
      );
    case ConnectionIssueKind.generic:
      return (
        '$serviceName sunucusuna bağlanılamıyor',
        'Ağ bağlantınızı kontrol edin',
      );
  }
}

/// Bir servise internet varken erişilemediğinde gösterilen tek paylaşılan
/// hata görünümü. Üç [kind] da aynı yerleşimi (ikon, başlık, açıklama,
/// isteğe bağlı Tekrar Dene, altta sakin MtoolsMark) paylaşır — sadece
/// renk/ikon/metin kind'e göre değişir. [ConnectionIssueKind.generic]
/// bilinçli olarak bugünkü alarm tonunu (colors.error) korur; diğer ikisi
/// nötr/bilgi tonundadır — bunlar "servis çökmüş" değil "yanlış ağdasın"
/// durumları olduğu için kullanıcıyı alarma geçirmemesi gerekir.
class ConnectionIssueView extends StatelessWidget {
  final ConnectionIssueKind kind;
  final String serviceName;
  final String host;
  final VoidCallback? onRetry;

  const ConnectionIssueView({
    super.key,
    required this.kind,
    required this.serviceName,
    required this.host,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final (title, message) = connectionIssueCopy(kind, serviceName, host);
    final isGeneric = kind == ConnectionIssueKind.generic;

    final iconColor = isGeneric ? colors.error : colors.textMuted;
    final circleColor =
        isGeneric ? colors.error.withValues(alpha: 0.1) : colors.surface2;
    final borderColor =
        isGeneric ? colors.error.withValues(alpha: 0.3) : colors.hairline;
    final icon = switch (kind) {
      ConnectionIssueKind.privateNetwork => Icons.lan_outlined,
      ConnectionIssueKind.tailscale => Icons.vpn_lock_outlined,
      ConnectionIssueKind.generic => Icons.wifi_off_rounded,
    };

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpace.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: circleColor,
                border: Border.all(color: borderColor),
              ),
              child: Icon(icon, color: iconColor, size: 32),
            ),
            const SizedBox(height: AppSpace.xl),
            Text(
              title,
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpace.sm),
            Text(
              message,
              style: colors.meta,
              textAlign: TextAlign.center,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: AppSpace.xl),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: Icon(Icons.refresh_rounded,
                    color: colors.primary, size: 16),
                label: Text(
                  'Tekrar Dene',
                  style: TextStyle(
                      color: colors.primary, fontWeight: FontWeight.w600),
                ),
                style: OutlinedButton.styleFrom(
                  backgroundColor: colors.primary.withValues(alpha: 0.08),
                  side: BorderSide(color: colors.primary.withValues(alpha: 0.3)),
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpace.lg, vertical: AppSpace.sm),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.sm)),
                ),
              ),
            ],
            const SizedBox(height: AppSpace.xxl),
            MtoolsMark(
              size: 22,
              lineColor: colors.textMuted,
              dotColor: colors.textMuted,
            ),
          ],
        ),
      ),
    );
  }
}
