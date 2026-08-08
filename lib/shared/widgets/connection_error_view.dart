import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

/// Bir sunucuya hiç bağlanılamadığında (veri gelmediğinde) tutarlı şekilde
/// gösterilen durum ekranı. Önceden bazı sayfalarda bağlantı yoksa içerik
/// boş kalıyordu (beyaz/boş ekran); bunun yerine kullanıcıya açık bir mesaj
/// ve isteğe bağlı "Tekrar Dene" seçeneği gösterilir.
class ConnectionErrorView extends StatelessWidget {
  final String title;
  final String message;
  final VoidCallback? onRetry;

  const ConnectionErrorView({
    super.key,
    this.title = 'Bağlantı Yok',
    this.message = 'Bağlantınızı kontrol edin',
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colors.error.withValues(alpha: 0.1),
                border:
                    Border.all(color: colors.error.withValues(alpha: 0.3)),
              ),
              child: Icon(Icons.wifi_off_rounded,
                  color: colors.error, size: 32),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              message,
              style: TextStyle(color: colors.textMuted, fontSize: 13),
              textAlign: TextAlign.center,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 20),
              TextButton.icon(
                onPressed: onRetry,
                icon: Icon(Icons.refresh_rounded,
                    color: colors.primary, size: 16),
                label: Text(
                  'Tekrar Dene',
                  style: TextStyle(
                      color: colors.primary, fontWeight: FontWeight.w600),
                ),
              ),
            ],
            const SizedBox(height: 40),
            Text(
              'MTools',
              style: TextStyle(
                color: colors.textMuted.withValues(alpha: 0.4),
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
