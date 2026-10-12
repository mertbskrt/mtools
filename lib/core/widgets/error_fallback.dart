import 'package:flutter/material.dart';
import '../services/crash_reporter.dart';

/// Release modunda bir ekran build() sırasında hata fırlattığında Flutter'ın
/// gri/boş kutusu yerine gösterilen MTools markalı mesaj (bkz. main.dart'taki
/// ErrorWidget.builder). Kullanıcı ekran görüntüsü attığında sebebin
/// bulunabilmesi için ekran adı ve kısa hata kodu gösterilir; aynı kod
/// Hata Günlüğü'ndeki kayıtta da bulunur. Stack trace burada gösterilmez.
class GlobalErrorFallback extends StatelessWidget {
  final ErrorOrigin origin;

  /// "Bu hatayı bildir" butonuna basılınca çağrılır (bkz. main.dart — geri
  /// bildirim ekranını ön doldurulmuş açar). null ise buton gösterilmez.
  final ValueChanged<ErrorOrigin>? onReport;

  const GlobalErrorFallback({super.key, required this.origin, this.onReport});

  factory GlobalErrorFallback.fromDetails(FlutterErrorDetails details,
          {ValueChanged<ErrorOrigin>? onReport}) =>
      GlobalErrorFallback(
        origin: describeError(details.exception, details.stack),
        onReport: onReport,
      );

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF0D0D0D),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline_rounded,
              color: Colors.white.withValues(alpha: 0.5), size: 40),
          const SizedBox(height: 16),
          const Text(
            'Bir şeyler ters gitti',
            style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            'Bu ekran yüklenemedi. Geri dönüp tekrar deneyin.',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 13),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 14),
          Text(
            'Ekran: ${origin.screenName} · Kod: ${origin.code}',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.75),
              fontSize: 12,
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
            textAlign: TextAlign.center,
          ),
          if (onReport != null) ...[
            const SizedBox(height: 18),
            // ErrorWidget her zaman bir Material'ın altında çizilmeyebilir;
            // buton (InkWell) için şeffaf bir Material sağlanıyor.
            Material(
              type: MaterialType.transparency,
              child: OutlinedButton.icon(
                onPressed: () => onReport!(origin),
                icon: const Icon(Icons.bug_report_outlined, size: 16),
                label: const Text('Bu hatayı bildir'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: BorderSide(color: Colors.white.withValues(alpha: 0.4)),
                ),
              ),
            ),
          ],
          const SizedBox(height: 32),
          Text(
            'MTools',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.35),
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
