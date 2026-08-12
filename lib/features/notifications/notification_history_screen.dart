import 'package:flutter/material.dart';
import '../../core/utils/app_transitions.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import 'notification_provider.dart';

class NotificationHistoryScreen extends StatelessWidget {
  const NotificationHistoryScreen({super.key});

  String _formatTime(String iso) {
    final dt = DateTime.parse(iso);
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'Az önce';
    if (diff.inMinutes < 60) return '${diff.inMinutes} dakika önce';
    if (diff.inHours < 24) return '${diff.inHours} saat önce';
    return '${diff.inDays} gün önce';
  }

  // v3.1.0 öncesi bildirimler emoji ile geliyordu (ör. "🔴 Sunucu
  // Erişilemiyor") — geriye dönük kayıtlar migrate edilmiyor, sadece burada
  // görüntülenirken temizleniyor. Emoji çıkınca da bu regex Türkçe
  // anahtar kelimeyi ("Erişilemiyor" vb.) olduğu gibi bırakır, bu yüzden
  // aşağıdaki _getIcon/_getColor eski ve yeni kayıtlarda aynı şekilde çalışır.
  static final _emojiPattern = RegExp(
    r'[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}\u{2190}-\u{21FF}\u{2B00}-\u{2BFF}️]+\s*',
    unicode: true,
  );

  String _stripEmoji(String s) => s.replaceAll(_emojiPattern, '').trim();

  IconData _getIcon(String title) {
    if (title.contains('CPU')) return Icons.memory;
    if (title.contains('RAM')) return Icons.storage;
    if (title.contains('Disk') || title.contains('Sıcaklık')) {
      return Icons.thermostat;
    }
    if (title.contains('UPS')) return Icons.battery_charging_full;
    if (title.contains('AdGuard')) return Icons.shield_outlined;
    // 'İnternet' kontrolü Terminal/Bağlantı kontrolünden ÖNCE gelmeli —
    // cihaz bağlantısı bildirimleri de 'Bağlantı' kelimesini içeriyor,
    // aksi halde yanlışlıkla terminal ikonu alırlardı.
    if (title.contains('İnternet')) return Icons.signal_wifi_off_rounded;
    if (title.contains('Terminal') || title.contains('Bağlantı')) {
      return Icons.terminal;
    }
    if (title.contains('Durdu')) return Icons.stop_circle_outlined;
    if (title.contains('Başladı') || title.contains('Bağlandı')) {
      return Icons.play_circle_outlined;
    }
    if (title.contains('Sunucu') || title.contains('Node')) {
      return Icons.dns_outlined;
    }
    return Icons.notifications_outlined;
  }

  /// Emoji yerine anahtar kelimeye göre renk belirler — hem eski (emoji'li)
  /// hem yeni kayıtlarda aynı şekilde çalışır, çünkü Türkçe kelime her
  /// ikisinde de aynı.
  Color _getColor(BuildContext context, String title) {
    final colors = context.appColors;
    if (title.contains('Başarısız') || title.contains('Hata')) {
      return colors.error;
    }
    if (title.contains('Erişilemiyor') ||
        title.contains('Ulaşılamıyor') ||
        title.contains('Çevrimdışı') ||
        title.contains('Bağlantınız Yok')) {
      return colors.error;
    }
    if (title.contains('Yüksek') ||
        title.contains('Düşük') ||
        title.contains('Aşırı')) {
      return colors.warning;
    }
    if (title.contains('Çevrimiçi') ||
        title.contains('Başladı') ||
        title.contains('Bağlandı') ||
        title.contains('Şebekeye Döndü') ||
        title.contains('Yeniden Ulaşıldı') ||
        title.contains('Bağlantınız Geri Geldi')) {
      return colors.success;
    }
    return colors.primary;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final provider = context.watch<NotificationProvider>();
    final history = provider.history;

    return Scaffold(
      backgroundColor: colors.bgDark,
      appBar: AppBar(
        title: const Text('Bildirim Geçmişi'),
        actions: [
          if (history.isNotEmpty)
            TextButton(
              onPressed: () {
                appShowDialog(
                  context: context,
                  builder: (ctx) {
                    final dColors = ctx.appColors;
                    return AlertDialog(
                      backgroundColor: dColors.bgCard,
                      title: Text('Tümünü Sil',
                          style: TextStyle(color: dColors.textPrimary)),
                      content: Text('Tüm bildirimler silinecek.',
                          style: TextStyle(color: dColors.textSecondary)),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: const Text('İptal')),
                        TextButton(
                          onPressed: () {
                            provider.clearHistory();
                            Navigator.pop(ctx);
                          },
                          child: Text('Sil',
                              style: TextStyle(color: dColors.error)),
                        ),
                      ],
                    );
                  },
                );
              },
              child: Text('Temizle', style: TextStyle(color: colors.error)),
            ),
        ],
      ),
      body: history.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.notifications_none,
                      color: colors.textMuted, size: 64),
                  const SizedBox(height: 16),
                  Text('Henüz bildirim yok',
                      style:
                          TextStyle(color: colors.textSecondary, fontSize: 16)),
                  const SizedBox(height: 8),
                  Text('Sistem uyarıları burada görünecek',
                      style: TextStyle(color: colors.textMuted, fontSize: 13)),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: history.length,
              itemBuilder: (context, i) {
                final item = history[i];
                final title = _stripEmoji(item['title'] ?? '');
                final body = _stripEmoji(item['body'] ?? '');
                final color = _getColor(context, title);
                return Dismissible(
                  key: ValueKey('$i-${item['time']}'),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 20),
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: colors.error.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(Icons.delete_outline, color: colors.error),
                  ),
                  onDismissed: (_) => provider.removeHistory(i),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: colors.bgCard,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: color.withValues(alpha: 0.2)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(AppRadius.md),
                          ),
                          child: Icon(_getIcon(title), color: color, size: 18),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(title,
                                  style: TextStyle(
                                      color: colors.textPrimary,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13)),
                              const SizedBox(height: 4),
                              Text(body,
                                  style: TextStyle(
                                      color: colors.textSecondary,
                                      fontSize: 12)),
                              const SizedBox(height: 6),
                              Text(_formatTime(item['time'] ?? ''),
                                  style: TextStyle(
                                      color: colors.textMuted, fontSize: 11)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
