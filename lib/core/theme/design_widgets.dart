import 'package:flutter/material.dart';
import 'app_theme.dart';

/// Küçük, büyük harfli, aralıklı bölüm başlığı (ör. "KAYNAKLAR"). Metni
/// otomatik büyük harfe çevirir — çağıran taraf .toUpperCase() hatırlamak
/// zorunda kalmasın diye.
class SectionLabel extends StatelessWidget {
  final String text;

  const SectionLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Text(text.toUpperCase(), style: context.appColors.sectionLabel);
  }
}

/// Büyük renkli pill rozetlerin yerini alır: küçük renkli bir nokta + nötr
/// tonda metin (ör. "● Çalışıyor" — nokta yeşil, yazı normal renkte). Renk
/// sadece nokta üzerinden anlam taşır, metin her zaman nötr kalır.
class StatusIndicator extends StatelessWidget {
  final Color color;
  final String label;
  final double dotSize;
  final TextStyle? style;

  const StatusIndicator({
    super.key,
    required this.color,
    required this.label,
    this.dotSize = 6,
    this.style,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: dotSize,
          height: dotSize,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: AppSpace.sm),
        Text(label, style: style ?? colors.body),
      ],
    );
  }
}

/// Grafana tarzı kompakt metrik satırı: etiket, ince bar, tabular değer aynı
/// hizada — isteğe bağlı ikon ve alt satır (ör. "512 MB / 2 GB") ile. Node
/// kartlarındaki CPU/RAM, "Kaynaklar" bölümü, konteyner/VM detayı ve proxmox
/// liste satırlarındaki mini CPU/RAM için ortak — aynı deseni her ekranda
/// yeniden yazmamak için tek bir widget'ta toplandı. Bar değeri değiştiğinde
/// AppMotion token'larıyla yumuşak geçiş yapar (her tüketici için otomatik).
class MetricRow extends StatelessWidget {
  final String label;
  final double value; // 0-100, bar dolgusunu belirler
  final String valueLabel; // gösterilecek tam metin, ör. '%42'
  final Color color;
  final double labelWidth;
  final double valueWidth;
  final IconData? icon;
  final String? subtitle;

  const MetricRow({
    super.key,
    required this.label,
    required this.value,
    required this.valueLabel,
    required this.color,
    this.labelWidth = 40,
    this.valueWidth = 40,
    this.icon,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final row = Row(
      children: [
        if (icon != null) ...[
          Icon(icon, size: 14, color: color),
          const SizedBox(width: AppSpace.sm),
        ],
        SizedBox(width: labelWidth, child: Text(label, style: colors.meta)),
        const SizedBox(width: AppSpace.sm),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.xs),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: (value / 100).clamp(0.0, 1.0)),
              duration: AppMotion.base,
              curve: AppMotion.curve,
              builder: (_, v, __) => LinearProgressIndicator(
                value: v,
                minHeight: 4,
                backgroundColor: colors.surface2,
                valueColor: AlwaysStoppedAnimation(color),
              ),
            ),
          ),
        ),
        const SizedBox(width: AppSpace.sm),
        SizedBox(
          width: valueWidth,
          child: Text(
            valueLabel,
            textAlign: TextAlign.right,
            style: colors.metricSmall.copyWith(color: color),
          ),
        ),
      ],
    );
    if (subtitle == null || subtitle!.isEmpty) return row;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        row,
        const SizedBox(height: 2),
        Text(subtitle!, style: colors.meta.copyWith(fontSize: 10)),
      ],
    );
  }
}

/// Ayrı ayrı hap rozetler yerine tek satır, gri, " · " ile ayrılmış meta
/// metin (ör. "4g 15s · 3.1 GHz · EFI"). Boş parçalar otomatik elenir.
class MetaLine extends StatelessWidget {
  final List<String> parts;
  final TextStyle? style;

  const MetaLine(this.parts, {super.key, this.style});

  @override
  Widget build(BuildContext context) {
    final text = parts.where((p) => p.trim().isNotEmpty).join(' · ');
    if (text.isEmpty) return const SizedBox.shrink();
    return Text(text, style: style ?? context.appColors.meta);
  }
}

/// Basılı tutulan butonlarda tutarlı basma geri bildirimi — [pressed] true
/// olduğunda hafifçe küçülür (0.97). Renk/kenar geçişini YÖNETMEZ; her
/// çağıran kendi `_pressed` durumunu/dekorasyonunu tutmaya devam eder, bu
/// widget sadece o durumun üstüne tutarlı bir ölçek ekler — böylece
/// uygulama genelinde "kiminde var kiminde yok" tutarsızlığı bitiyor.
class PressableScale extends StatelessWidget {
  final bool pressed;
  final Widget child;

  const PressableScale({super.key, required this.pressed, required this.child});

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: pressed ? 0.97 : 1.0,
      duration: AppMotion.fast,
      curve: AppMotion.curve,
      child: child,
    );
  }
}
