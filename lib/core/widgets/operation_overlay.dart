import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../theme/design_widgets.dart';

/// Bir aksiyonun (CT/VM başlat-durdur, sunucudan çıkış, ...) sürdüğünü/sonuçlandığını
/// gösteren tek, paylaşılan, sakin görsel dil — hiçbir yerde hardcoded renk yok,
/// tamamen [context.appColors] token'larından besleniyor.
///
/// Saf/sunumsal widget: hiçbir provider'a bağlı değil — durumunu constructor
/// parametreleriyle alır, böylece hem [ProxmoxProvider] alanlarını izleyen
/// ekranlar hem kendi yerel state'ini yöneten ekranlar (ör. sign-out) aynı
/// bileşeni kullanabilir.
class OperationOverlay extends StatelessWidget {
  final String message;
  final String? subMessage;
  final double? progress;
  final bool success;
  final bool isError;

  const OperationOverlay({
    super.key,
    required this.message,
    this.subMessage,
    this.progress,
    this.success = false,
    this.isError = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final accent =
        isError ? colors.error : (success ? colors.success : colors.primary);

    return Container(
      color: Colors.black.withValues(alpha: 0.6),
      child: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 40),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          decoration: BoxDecoration(
            color: colors.surface1,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: colors.hairline),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedSwitcher(
                duration: AppMotion.fast,
                switchInCurve: AppMotion.curve,
                switchOutCurve: AppMotion.curve,
                child: (success || isError)
                    ? StatusIndicator(
                        key: ValueKey(isError ? 'error' : 'success'),
                        color: accent,
                        label: isError ? 'Başarısız' : 'Tamamlandı',
                        dotSize: 8,
                        style: colors.body.copyWith(
                            color: accent, fontWeight: FontWeight.w600),
                      )
                    : SizedBox(
                        key: const ValueKey('loading'),
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.5, color: colors.primary),
                      ),
              ),
              const SizedBox(height: AppSpace.md),
              Text(message, style: colors.body, textAlign: TextAlign.center),
              if (subMessage != null && subMessage!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(subMessage!, style: colors.meta, textAlign: TextAlign.center),
              ],
              if (!isError && progress != null) ...[
                const SizedBox(height: AppSpace.md),
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.xs),
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0.0, end: progress),
                    duration: AppMotion.slow,
                    curve: AppMotion.curve,
                    builder: (_, value, __) => LinearProgressIndicator(
                      value: value,
                      backgroundColor: colors.surface2,
                      valueColor: AlwaysStoppedAnimation(accent),
                      minHeight: 3,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
