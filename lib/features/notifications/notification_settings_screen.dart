import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/design_widgets.dart';
import 'notification_provider.dart';
import 'notification_rule.dart';

class NotificationSettingsScreen extends StatelessWidget {
  const NotificationSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final provider = context.watch<NotificationProvider>();
    final rules = provider.rules;

    final Map<String, List<int>> categories = {};
    for (int i = 0; i < rules.length; i++) {
      categories.putIfAbsent(rules[i].category, () => []).add(i);
    }

    final enabledCount = rules.where((r) => r.enabled).length;

    return Scaffold(
      backgroundColor: colors.surface0,
      appBar: AppBar(
        title: const Text('Bildirim Ayarları'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: colors.hairline),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
        children: [
          // ── Mimari bilgi kartı ───────────────────────────────────────────
          _ArchInfoCard(colors: colors),
          const SizedBox(height: 16),

          // ── Servis kontrolü ─────────────────────────────────────────────
          const SectionLabel('SERVİS KONTROLÜ'),
          const SizedBox(height: 8),
          _ServiceCard(provider: provider, colors: colors),
          const SizedBox(height: 8),
          _TestNotificationButton(provider: provider, colors: colors),
          const SizedBox(height: 16),

          if (provider.serviceEnabled) ...[
            // ── Kontrol sıklığı ────────────────────────────────────────────
            const SectionLabel('İZLEME'),
            const SizedBox(height: 8),
            _IntervalCard(provider: provider, colors: colors),
            const SizedBox(height: 8),

            // ── Sessiz saatler ─────────────────────────────────────────────
            _QuietHoursCard(provider: provider, colors: colors),
            const SizedBox(height: 16),

            // ── Token filtre bilgisi ───────────────────────────────────────
            _TokenFilterCard(colors: colors),
            const SizedBox(height: 16),

            // ── Kural özeti ────────────────────────────────────────────────
            const SectionLabel('BİLDİRİM KURALLARI'),
            const SizedBox(height: 8),
            _SummaryBanner(
                enabledCount: enabledCount,
                total: rules.length,
                colors: colors),
            const SizedBox(height: 16),

            // ── Kategoriler ────────────────────────────────────────────────
            ...categories.entries.map((catEntry) => _CategorySection(
                  key: ValueKey(catEntry.key),
                  categoryName: catEntry.key,
                  indices: catEntry.value,
                  rules: rules,
                  provider: provider,
                  colors: colors,
                )),
          ],
        ],
      ),
    );
  }
}

// ── Mimari bilgi kartı ────────────────────────────────────────────────────────

class _ArchInfoCard extends StatelessWidget {
  final AppThemeData colors;
  const _ArchInfoCard({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
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
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: colors.surface2,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Icon(Icons.architecture_outlined,
                    color: colors.textSecondary, size: 16),
              ),
              const SizedBox(width: 10),
              Text(
                'Bildirim Mimarisi',
                style: TextStyle(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: colors.surface2,
                  borderRadius: BorderRadius.circular(AppRadius.xs),
                ),
                child: Text(
                  'Task Log',
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const _ArchStep(
            icon: Icons.sync_outlined,
            title: 'Proxmox Task Log Tabanlı',
            description:
                'CT/VM olayları durum karşılaştırması yerine doğrudan Proxmox görev geçmişinden okunur. Uygulama kapalıyken gerçekleşen olaylar dahi yakalanır.',
          ),
          _Divider(colors: colors),
          const _ArchStep(
            icon: Icons.token_outlined,
            title: 'MTools Token Filtresi',
            description:
                'Uygulama içinden yapılan start/stop/reboot işlemleri (MToolsV2 token\'ı) otomatik olarak atlanır. Yalnızca Proxmox UI, SSH veya harici araçlardan gelen olaylar bildirim üretir.',
          ),
          _Divider(colors: colors),
          const _ArchStep(
            icon: Icons.wifi_off_outlined,
            title: 'Offline Tespiti',
            description:
                'Sunucuya erişilemeyen durumlarda son erişim saati kaydedilir ve node offline bildirimi iletilir. Bağlantı yeniden kurulduğunda online bildirimi gönderilir.',
            isLast: true,
          ),
        ],
      ),
    );
  }
}

class _ArchStep extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final bool isLast;

  const _ArchStep({
    required this.icon,
    required this.title,
    required this.description,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: colors.surface2,
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Icon(icon, color: colors.textSecondary, size: 14),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  description,
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: 11,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  final AppThemeData colors;
  const _Divider({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 1,
      margin: const EdgeInsets.only(bottom: 12),
      color: colors.hairline,
    );
  }
}

// ── Token filtre kartı ────────────────────────────────────────────────────────

class _TokenFilterCard extends StatelessWidget {
  final AppThemeData colors;
  const _TokenFilterCard({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: colors.hairline),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: colors.surface2,
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Icon(Icons.filter_alt_outlined,
                color: colors.textSecondary, size: 16),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Akıllı Token Filtresi Aktif',
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'MTools uygulaması üzerinden gerçekleştirilen tüm CT/VM işlemleri bildirim üretmez. Proxmox web arayüzü, SSH veya diğer araçlardan yapılan değişiklikler bildirilir.',
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: 11,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 8),
                const Row(
                  children: [
                    _FilterBadge(label: 'MToolsV2 → Sessiz'),
                    SizedBox(width: 8),
                    _FilterBadge(label: 'Harici → Bildirim'),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterBadge extends StatelessWidget {
  final String label;
  const _FilterBadge({required this.label});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colors.surface2,
        borderRadius: BorderRadius.circular(AppRadius.xs),
        border: Border.all(color: colors.hairline),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: colors.textSecondary,
          fontSize: 10,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

// ── Servis toggle kartı ───────────────────────────────────────────────────────

class _ServiceCard extends StatelessWidget {
  final NotificationProvider provider;
  final AppThemeData colors;
  const _ServiceCard({required this.provider, required this.colors});

  @override
  Widget build(BuildContext context) {
    final on = provider.serviceEnabled;
    final statusColor = on ? colors.success : colors.textMuted;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: colors.hairline),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Icon(
                  on ? Icons.sensors : Icons.sensors_off_outlined,
                  color: statusColor,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Arka Plan İzleme Servisi',
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      on
                          ? 'Aktif — uygulama arka plandayken/kapalıyken izlenir'
                          : 'Servis durduruldu — bildirim üretilmiyor',
                      style: TextStyle(color: statusColor, fontSize: 11),
                    ),
                  ],
                ),
              ),
              Transform.scale(
                scale: 0.85,
                child: Switch(
                  value: on,
                  onChanged: provider.setServiceEnabled,
                  activeThumbColor: colors.success,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
          if (on) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: colors.surface2,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: colors.hairline),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: colors.textMuted, size: 13),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Uygulama kapalıyken dahi Proxmox task log\'u izlenir. Olaylar gerçek zamanlı olarak yakalanır.',
                      style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: 11,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Test bildirimi butonu ─────────────────────────────────────────────────────

class _TestNotificationButton extends StatefulWidget {
  final NotificationProvider provider;
  final AppThemeData colors;
  const _TestNotificationButton({required this.provider, required this.colors});

  @override
  State<_TestNotificationButton> createState() =>
      _TestNotificationButtonState();
}

class _TestNotificationButtonState extends State<_TestNotificationButton> {
  bool _sending = false;

  Future<void> _send() async {
    if (_sending) return;
    setState(() => _sending = true);
    try {
      await widget.provider.sendTestNotification();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('Test bildirimi gönderildi'),
          backgroundColor: widget.colors.success,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.sm)),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'Test bildirimi gönderilemedi: ${e.toString().replaceFirst('Exception: ', '')}'),
          backgroundColor: widget.colors.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.sm)),
        ));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: _sending ? null : _send,
        icon: _sending
            ? SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: colors.textSecondary),
              )
            : Icon(Icons.notifications_active_outlined,
                size: 16, color: colors.textSecondary),
        label: Text(
          'Test bildirimi gönder',
          style: TextStyle(color: colors.textSecondary, fontSize: 13),
        ),
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: colors.hairline),
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.md)),
        ),
      ),
    );
  }
}

// ── Kontrol sıklığı kartı ─────────────────────────────────────────────────────

class _IntervalCard extends StatelessWidget {
  final NotificationProvider provider;
  final AppThemeData colors;
  const _IntervalCard({required this.provider, required this.colors});

  static const _options = [
    (label: '30 sn', seconds: 30),
    (label: '1 dk', seconds: 60),
    (label: '5 dk', seconds: 300),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: colors.surface2,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Icon(Icons.timer_outlined,
                    color: colors.textSecondary, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Kontrol Sıklığı',
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Proxmox API ve task log sorgu aralığı',
                      style:
                          TextStyle(color: colors.textSecondary, fontSize: 11),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: colors.surface0,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  border: Border.all(color: colors.hairline),
                ),
                child: Row(
                  children: _options.map((opt) {
                    final selected =
                        provider.checkIntervalSeconds == opt.seconds;
                    return GestureDetector(
                      key: ValueKey(opt.seconds),
                      onTap: () => provider.setCheckInterval(opt.seconds),
                      child: AnimatedContainer(
                        duration: AppMotion.fast,
                        curve: AppMotion.curve,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: selected ? colors.primary : Colors.transparent,
                          borderRadius: BorderRadius.circular(AppRadius.xs),
                        ),
                        child: Text(
                          opt.label,
                          style: TextStyle(
                            color:
                                selected ? Colors.white : colors.textSecondary,
                            fontSize: 12,
                            fontWeight:
                                selected ? FontWeight.w600 : FontWeight.normal,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Sessiz saatler kartı ──────────────────────────────────────────────────────

class _QuietHoursCard extends StatelessWidget {
  final NotificationProvider provider;
  final AppThemeData colors;
  const _QuietHoursCard({required this.provider, required this.colors});

  String _fmt(int h) => '${h.toString().padLeft(2, '0')}:00';

  Future<void> _pickHour(BuildContext context, bool isStart) async {
    final initial = TimeOfDay(
        hour: isStart ? provider.quietStart : provider.quietEnd, minute: 0);
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked == null) return;
    if (isStart) {
      provider.setQuietStart(picked.hour);
    } else {
      provider.setQuietEnd(picked.hour);
    }
  }

  @override
  Widget build(BuildContext context) {
    final on = provider.quietHoursEnabled;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: colors.hairline),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: colors.surface2,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Icon(Icons.bedtime_outlined,
                    color: colors.textSecondary, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Sessiz Saatler',
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      on
                          ? '${_fmt(provider.quietStart)} – ${_fmt(provider.quietEnd)} arası bildirim yok'
                          : 'Tüm saatlerde bildirim aktif',
                      style:
                          TextStyle(color: colors.textSecondary, fontSize: 11),
                    ),
                  ],
                ),
              ),
              Transform.scale(
                scale: 0.85,
                child: Switch(
                  value: on,
                  onChanged: provider.setQuietHoursEnabled,
                  activeThumbColor: colors.primary,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
          if (on) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _HourTile(
                    label: 'Başlangıç',
                    hour: provider.quietStart,
                    colors: colors,
                    onTap: () => _pickHour(context, true),
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.arrow_forward, color: colors.textMuted, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: _HourTile(
                    label: 'Bitiş',
                    hour: provider.quietEnd,
                    colors: colors,
                    onTap: () => _pickHour(context, false),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _HourTile extends StatelessWidget {
  final String label;
  final int hour;
  final AppThemeData colors;
  final VoidCallback onTap;
  const _HourTile(
      {required this.label,
      required this.hour,
      required this.colors,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: colors.surface2,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: colors.hairline),
        ),
        child: Column(
          children: [
            Text(label,
                style: TextStyle(color: colors.textMuted, fontSize: 10)),
            const SizedBox(height: 4),
            Text(
              '${hour.toString().padLeft(2, '0')}:00',
              style: TextStyle(
                color: colors.primary,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Özet banner ───────────────────────────────────────────────────────────────

class _SummaryBanner extends StatelessWidget {
  final int enabledCount;
  final int total;
  final AppThemeData colors;
  const _SummaryBanner(
      {required this.enabledCount, required this.total, required this.colors});

  @override
  Widget build(BuildContext context) {
    final pct = total == 0 ? 0 : (enabledCount / total * 100).toInt();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: colors.hairline),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$enabledCount / $total kural aktif',
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Her kural için eşik ve tekrar aralığı aşağıdan ayarlanabilir',
                  style: TextStyle(color: colors.textSecondary, fontSize: 11),
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.xs),
                  child: LinearProgressIndicator(
                    value: total == 0 ? 0 : enabledCount / total,
                    backgroundColor: colors.surface2,
                    valueColor: AlwaysStoppedAnimation(colors.primary),
                    minHeight: 4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Text(
            '%$pct',
            style: TextStyle(
              color: colors.primary,
              fontSize: 28,
              fontWeight: FontWeight.w800,
              letterSpacing: -1,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Kategori section ──────────────────────────────────────────────────────────

class _CategorySection extends StatelessWidget {
  final String categoryName;
  final List<int> indices;
  final List<NotificationRule> rules;
  final NotificationProvider provider;
  final AppThemeData colors;

  const _CategorySection({
    super.key,
    required this.categoryName,
    required this.indices,
    required this.rules,
    required this.provider,
    required this.colors,
  });

  IconData get _categoryIcon {
    switch (categoryName) {
      case 'Sistem Kaynakları':
        return Icons.monitor_heart_outlined;
      case 'Konteyner':
        return Icons.view_in_ar_outlined;
      case 'Sanal Makine':
        return Icons.computer_outlined;
      case 'Makine Durumu':
        return Icons.dns_outlined;
      case 'UPS':
        return Icons.electrical_services_outlined;
      case 'AdGuard':
        return Icons.shield_outlined;
      default:
        return Icons.tune_outlined;
    }
  }

  String get _categoryDescription {
    switch (categoryName) {
      case 'Sistem Kaynakları':
        return 'CPU, RAM, Swap ve disk kullanım eşikleri';
      case 'Konteyner':
        return 'Task log tabanlı — MTools dışı işlemler bildirilir';
      case 'Sanal Makine':
        return 'Task log tabanlı — MTools dışı işlemler bildirilir';
      case 'Makine Durumu':
        return 'Node erişilebilirlik ve son görülme zamanı';
      case 'UPS':
        return 'Batarya, yük ve sıcaklık izleme';
      case 'AdGuard':
        return 'Sunucu erişilebilirlik izleme';
      default:
        return '';
    }
  }

  bool get _isTaskLogBased =>
      categoryName == 'Konteyner' || categoryName == 'Sanal Makine';

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Kategori başlığı
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: colors.surface1,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(AppRadius.md),
              topRight: Radius.circular(AppRadius.md),
            ),
            border: Border(
              top: BorderSide(color: colors.hairline),
              left: BorderSide(color: colors.hairline),
              right: BorderSide(color: colors.hairline),
            ),
          ),
          child: Row(
            children: [
              Icon(_categoryIcon, color: colors.textSecondary, size: 15),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      categoryName.toUpperCase(),
                      style: TextStyle(
                        color: colors.textSecondary,
                        fontWeight: FontWeight.w800,
                        fontSize: 11,
                        letterSpacing: 0.8,
                      ),
                    ),
                    if (_categoryDescription.isNotEmpty) ...[
                      const SizedBox(height: 1),
                      Text(
                        _categoryDescription,
                        style: TextStyle(color: colors.textMuted, fontSize: 10),
                      ),
                    ],
                  ],
                ),
              ),
              if (_isTaskLogBased)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: colors.surface2,
                    borderRadius: BorderRadius.circular(AppRadius.xs),
                  ),
                  child: Text(
                    'Task Log',
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
            ],
          ),
        ),

        // Kurallar
        Container(
          decoration: BoxDecoration(
            color: colors.surface1,
            borderRadius: const BorderRadius.only(
              bottomLeft: Radius.circular(AppRadius.md),
              bottomRight: Radius.circular(AppRadius.md),
            ),
            border: Border(
              bottom: BorderSide(color: colors.hairline),
              left: BorderSide(color: colors.hairline),
              right: BorderSide(color: colors.hairline),
            ),
          ),
          child: Column(
            children: indices.asMap().entries.map((e) {
              final isLast = e.key == indices.length - 1;
              final rule = rules[e.value];
              return Column(
                key: ValueKey(rule.trigger),
                children: [
                  _RuleItem(
                      rule: rule,
                      index: e.value,
                      provider: provider,
                      colors: colors),
                  if (!isLast)
                    Divider(
                      height: 1,
                      indent: 16,
                      endIndent: 16,
                      color: colors.hairline,
                    ),
                ],
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 14),
      ],
    );
  }
}

// ── Kural satırı ──────────────────────────────────────────────────────────────

class _RuleItem extends StatelessWidget {
  final NotificationRule rule;
  final int index;
  final NotificationProvider provider;
  final AppThemeData colors;

  const _RuleItem({
    required this.rule,
    required this.index,
    required this.provider,
    required this.colors,
  });

  bool get _hasThreshold =>
      rule.trigger == NotificationTrigger.cpuHigh ||
      rule.trigger == NotificationTrigger.ramHigh ||
      rule.trigger == NotificationTrigger.swapHigh ||
      rule.trigger == NotificationTrigger.diskTemp ||
      rule.trigger == NotificationTrigger.diskUsage ||
      rule.trigger == NotificationTrigger.upsBatteryLow ||
      rule.trigger == NotificationTrigger.upsLoadHigh ||
      rule.trigger == NotificationTrigger.upsTempHigh;

  bool get _hasCooldown =>
      rule.trigger == NotificationTrigger.cpuHigh ||
      rule.trigger == NotificationTrigger.ramHigh ||
      rule.trigger == NotificationTrigger.swapHigh ||
      rule.trigger == NotificationTrigger.diskTemp ||
      rule.trigger == NotificationTrigger.diskUsage ||
      rule.trigger == NotificationTrigger.upsBatteryLow ||
      rule.trigger == NotificationTrigger.upsLoadHigh ||
      rule.trigger == NotificationTrigger.upsTempHigh ||
      rule.trigger == NotificationTrigger.upsOnBattery ||
      rule.trigger == NotificationTrigger.upsOnline ||
      rule.trigger == NotificationTrigger.upsOffline;

  bool get _isTaskLogBased =>
      rule.trigger == NotificationTrigger.containerStopped ||
      rule.trigger == NotificationTrigger.containerStarted ||
      rule.trigger == NotificationTrigger.vmStopped ||
      rule.trigger == NotificationTrigger.vmStarted;

  bool get _isDiskTemp => rule.trigger == NotificationTrigger.diskTemp;
  bool get _isUpsTemp => rule.trigger == NotificationTrigger.upsTempHigh;
  bool get _isUpsBattery => rule.trigger == NotificationTrigger.upsBatteryLow;
  bool get _isTempBased => _isDiskTemp || _isUpsTemp;

  String get _thresholdLabel {
    if (_isTempBased) return '${rule.threshold.toInt()}°C';
    return '%${rule.threshold.toInt()}';
  }

  String get _maxLabel {
    if (_isDiskTemp) return '90°C';
    if (_isUpsTemp) return '60°C';
    return '%100';
  }

  double get _min {
    if (_isDiskTemp) return 30;
    if (_isUpsTemp) return 20;
    if (_isUpsBattery) return 10;
    return 50;
  }

  double get _max {
    if (_isDiskTemp) return 90;
    if (_isUpsTemp) return 60;
    if (_isUpsBattery) return 80;
    return 100;
  }

  int get _divisions {
    if (_isDiskTemp) return 60;
    if (_isUpsTemp) return 40;
    if (_isUpsBattery) return 70;
    return 50;
  }

  @override
  Widget build(BuildContext context) {
    final activeColor = rule.enabled ? colors.primary : colors.textMuted;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AnimatedContainer(
                duration: AppMotion.fast,
                curve: AppMotion.curve,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: rule.enabled
                      ? colors.primary.withValues(alpha: 0.12)
                      : colors.surface2,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Icon(rule.icon, color: activeColor, size: 17),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            rule.label,
                            style: TextStyle(
                              color: rule.enabled
                                  ? colors.textPrimary
                                  : colors.textMuted,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        if (_isTaskLogBased && rule.enabled) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 2),
                            decoration: BoxDecoration(
                              color: colors.surface2,
                              borderRadius: BorderRadius.circular(AppRadius.xs),
                            ),
                            child: Text(
                              'LOG',
                              style: TextStyle(
                                color: colors.textSecondary,
                                fontSize: 8,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      rule.description,
                      style:
                          TextStyle(color: colors.textSecondary, fontSize: 11),
                    ),
                  ],
                ),
              ),
              Transform.scale(
                scale: 0.85,
                child: Switch(
                  value: rule.enabled,
                  onChanged: (v) => provider.updateRule(index, enabled: v),
                  activeThumbColor: colors.primary,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
          if (_hasThreshold && rule.enabled) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: colors.surface2,
                    borderRadius: BorderRadius.circular(AppRadius.xs),
                    border: Border.all(color: colors.hairline),
                  ),
                  child: Text(
                    'Eşik: $_thresholdLabel',
                    style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.w600),
                  ),
                ),
                const Spacer(),
                Text(_maxLabel,
                    style: TextStyle(color: colors.textMuted, fontSize: 11)),
              ],
            ),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: colors.primary,
                inactiveTrackColor: colors.surface2,
                thumbColor: colors.primary,
                overlayColor: colors.primary.withValues(alpha: 0.08),
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              ),
              child: Slider(
                value: rule.threshold,
                min: _min,
                max: _max,
                divisions: _divisions,
                onChanged: (v) => provider.updateRule(index, threshold: v),
              ),
            ),
          ],
          if (_hasCooldown && rule.enabled) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: colors.surface2,
                    borderRadius: BorderRadius.circular(AppRadius.xs),
                    border: Border.all(color: colors.hairline),
                  ),
                  child: Text(
                    rule.cooldownMinutes == 0
                        ? 'Tekrar: Her seferinde'
                        : 'Tekrar: ${rule.cooldownMinutes} dk',
                    style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.w600),
                  ),
                ),
                const Spacer(),
                Text('120 dk',
                    style: TextStyle(color: colors.textMuted, fontSize: 11)),
              ],
            ),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: colors.info,
                inactiveTrackColor: colors.surface2,
                thumbColor: colors.info,
                overlayColor: colors.info.withValues(alpha: 0.08),
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              ),
              child: Slider(
                value: rule.cooldownMinutes.toDouble(),
                min: 0,
                max: 120,
                divisions: 24,
                onChanged: (v) =>
                    provider.updateRule(index, cooldownMinutes: v.toInt()),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
