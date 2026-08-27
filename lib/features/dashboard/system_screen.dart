import 'package:flutter/material.dart';
import '../../core/utils/app_transitions.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/design_widgets.dart';
import '../../core/utils/connection_target.dart';
import '../../core/widgets/operation_overlay.dart';
import '../../core/widgets/confirm_dialog.dart';
import '../../core/services/quick_auth_gate.dart';
import '../proxmox/proxmox_provider.dart';
import '../../shared/models/alias_provider.dart';
import '../dashboard/proxmox_connection_screen.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class SystemScreen extends StatefulWidget {
  const SystemScreen({super.key});

  @override
  State<SystemScreen> createState() => _SystemScreenState();
}

class _SystemScreenState extends State<SystemScreen> {
  final Map<String, bool> _expandedNodes = {};
  final Map<String, Map<String, bool>> _sectionVisibility = {};
  String _summaryStyle = 'strip';

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final expandedRaw = prefs.getString('node_expanded_states');
    final sectionRaw = prefs.getString('node_section_visibility');
    final summaryStyleRaw = prefs.getString('system_summary_style');
    if (!mounted) return;
    if (expandedRaw != null) {
      final Map<String, dynamic> decoded = jsonDecode(expandedRaw);
      setState(() {
        decoded.forEach((key, value) => _expandedNodes[key] = value as bool);
      });
    }
    if (sectionRaw != null) {
      final Map<String, dynamic> decoded = jsonDecode(sectionRaw);
      setState(() {
        decoded.forEach((key, value) {
          _sectionVisibility[key] = Map<String, bool>.from(value as Map);
        });
      });
    }
    if (summaryStyleRaw != null) {
      setState(() => _summaryStyle = summaryStyleRaw);
    }
  }

  Future<void> _saveExpandedState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('node_expanded_states', jsonEncode(_expandedNodes));
  }

  Future<void> _saveSectionVisibility() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        'node_section_visibility', jsonEncode(_sectionVisibility));
  }

  Future<void> _saveSummaryStyle() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('system_summary_style', _summaryStyle);
  }

  void _setSummaryStyle(String style) {
    setState(() => _summaryStyle = style);
    _saveSummaryStyle();
  }

  void _showStylePicker(BuildContext context) {
    final colors = context.appColors;
    const styles = {
      'strip': ('Şerit', 'Kompakt metin sütunları', Icons.view_headline),
      'circular': ('Dairesel', 'Yüzdesel halka göstergeler', Icons.donut_large_outlined),
      'cards': ('Kartlar', 'Renkli ikonlu kart ızgarası', Icons.grid_view_rounded),
    };

    appShowModalBottomSheet(
      context: context,
      backgroundColor: colors.surface1,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.md))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colors.textMuted.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Icon(Icons.tune_rounded, color: colors.textSecondary, size: 18),
                  const SizedBox(width: 8),
                  Text('Gösterim Stili',
                      style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 4),
              Text('Sistem Özeti bannerının nasıl gösterileceğini seçin',
                  style: TextStyle(color: colors.textMuted, fontSize: 12)),
              const SizedBox(height: 16),
              ...styles.entries.map((e) {
                final key = e.key;
                final (label, desc, icon) = e.value;
                final selected = _summaryStyle == key;
                return GestureDetector(
                  key: ValueKey(key),
                  onTap: () {
                    _setSummaryStyle(key);
                    setModal(() {});
                  },
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: selected
                          ? colors.primary.withValues(alpha: 0.08)
                          : colors.surface2,
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      border: Border.all(
                        color: selected
                            ? colors.primary.withValues(alpha: 0.25)
                            : colors.hairline,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(icon,
                            color: selected ? colors.primary : colors.textMuted,
                            size: 18),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(label,
                                  style: TextStyle(
                                      color: selected
                                          ? colors.textPrimary
                                          : colors.textMuted,
                                      fontSize: 14,
                                      fontWeight: selected
                                          ? FontWeight.w600
                                          : FontWeight.normal)),
                              Text(desc,
                                  style: TextStyle(
                                      color: colors.textMuted, fontSize: 11)),
                            ],
                          ),
                        ),
                        AnimatedContainer(
                          duration: AppMotion.fast,
                          curve: AppMotion.curve,
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: selected
                                ? colors.primary
                                : Colors.transparent,
                            border: Border.all(
                              color: selected
                                  ? colors.primary
                                  : colors.textMuted.withValues(alpha: 0.4),
                              width: 1.5,
                            ),
                          ),
                          child: selected
                              ? const Icon(Icons.check,
                                  color: Colors.white, size: 12)
                              : null,
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  Map<String, bool> _defaultSections() => {
        'resources': true,
        'disks': true,
        'storage': true,
        'network': true,
        'netstat': true,
        'system_info': true,
      };

  Map<String, bool> _getSections(String nodeName) {
    return _sectionVisibility[nodeName] ?? _defaultSections();
  }

  void _toggleSection(String nodeName, String section) {
    setState(() {
      _sectionVisibility[nodeName] ??= _defaultSections();
      _sectionVisibility[nodeName]![section] =
          !(_sectionVisibility[nodeName]![section] ?? true);
    });
    _saveSectionVisibility();
  }

  String _formatUptime(int seconds) {
    final d = seconds ~/ 86400;
    final h = (seconds % 86400) ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    if (d > 0) return '${d}g ${h}s';
    if (h > 0) return '${h}s ${m}dk';
    return '${m}dk';
  }

  String _formatBytes(int bytes) {
    if (bytes >= 1e12) return '${(bytes / 1e12).toStringAsFixed(1)} TB';
    if (bytes >= 1e9) return '${(bytes / 1e9).toStringAsFixed(1)} GB';
    if (bytes >= 1e6) return '${(bytes / 1e6).toStringAsFixed(1)} MB';
    if (bytes >= 1e3) return '${(bytes / 1e3).toStringAsFixed(1)} KB';
    return '$bytes B';
  }

  String _formatBytesShort(int bytes) {
    if (bytes >= 1e9) return '${(bytes / 1e9).toStringAsFixed(0)}G';
    if (bytes >= 1e6) return '${(bytes / 1e6).toStringAsFixed(0)}M';
    if (bytes >= 1e3) return '${(bytes / 1e3).toStringAsFixed(0)}K';
    return '$bytes B';
  }

  String _translateHealth(String health) {
    switch (health) {
      case 'PASSED':
        return 'Sağlıklı';
      case 'FAILED':
        return 'Hatalı';
      default:
        return health;
    }
  }

  String _translateNodeStatus(String status) {
    switch (status) {
      case 'online':
        return 'Çevrimiçi';
      case 'offline':
        return 'Çevrimdışı';
      default:
        return 'Bilinmiyor';
    }
  }

  String _translateDiskType(String type) {
    switch (type) {
      case 'ssd':
        return 'SSD';
      case 'hdd':
        return 'HDD';
      case 'nvme':
        return 'NVMe';
      default:
        return type.toUpperCase();
    }
  }

  String _translateSmartAttr(String name) {
    const map = {
      'Raw_Read_Error_Rate': 'Ham Okuma Hata Oranı',
      'Reallocated_Sector_Ct': 'Yeniden Tahsis Edilen Sektör',
      'Power_On_Hours': 'Çalışma Süresi',
      'Power_Cycle_Count': 'Açma/Kapama Sayısı',
      'Temperature_Celsius': 'Sıcaklık',
      'Wear_Leveling_Count': 'Yıpranan Sektör Sayısı',
      'Total_LBAs_Written': 'Toplam Yazılan Veri',
      'Total_LBAs_Read': 'Toplam Okunan Veri',
      'Reallocated_Event_Count': 'Yeniden Tahsis Olayı',
      'Current_Pending_Sector': 'Bekleyen Sektör',
      'Offline_Uncorrectable': 'Düzeltilemeyen Hata',
      'UDMA_CRC_Error_Count': 'CRC Hata Sayısı',
      'Power-Off_Retract_Count': 'Güç Kesme Sayısı',
      'Hardware_ECC_Recovered': 'ECC Düzeltme',
      'Available_Reservd_Space': 'Rezerv Alan',
      'Airflow_Temperature_Cel': 'Hava Akış Sıcaklığı',
    };
    return map[name] ?? name;
  }

  // Eskiden burada kendi 85/60 eşik mantığı vardı — artık tek, paylaşılan
  // token'a (bkz. app_theme.dart -> thresholdColor) devrediliyor. İmza
  // aynı kalıyor çünkü bu, _NodeCard üzerinden _StorageCard'a kadar bir
  // callback olarak taşınıyor.
  Color _colorByPercent(BuildContext context, double percent) =>
      context.appColors.thresholdColor(percent);

  void _showSectionCustomizer(BuildContext context, String nodeName) {
    final colors = context.appColors;
    final sections = _getSections(nodeName);
    final labels = {
      'resources': 'Kaynaklar',
      'disks': 'Diskler',
      'storage': 'Depolama',
      'network': 'Ağ Arayüzleri',
      'netstat': 'CT/VM Ağ Trafiği',
      'system_info': 'Sistem Bilgisi',
    };
    final icons = {
      'resources': Icons.monitor_heart_outlined,
      'disks': Icons.storage_rounded,
      'storage': Icons.folder_rounded,
      'network': Icons.lan_rounded,
      'netstat': Icons.swap_horiz_rounded,
      'system_info': Icons.info_outline_rounded,
    };

    appShowModalBottomSheet(
      context: context,
      backgroundColor: colors.surface1,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.md))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colors.textMuted.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Icon(Icons.tune_rounded, color: colors.textSecondary, size: 18),
                  const SizedBox(width: 8),
                  Text('Bölümleri Özelleştir',
                      style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.bold)),
                  const Spacer(),
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _sectionVisibility[nodeName] = _defaultSections();
                      });
                      _saveSectionVisibility();
                      setModal(() {});
                    },
                    child: Text('Sıfırla',
                        style: TextStyle(color: colors.primary, fontSize: 12)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ...labels.entries.map((e) {
                final visible = sections[e.key] ?? true;
                return GestureDetector(
                  key: ValueKey(e.key),
                  onTap: () {
                    _toggleSection(nodeName, e.key);
                    setModal(() {});
                  },
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: visible
                          ? colors.primary.withValues(alpha: 0.08)
                          : colors.surface2,
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      border: Border.all(
                        color: visible
                            ? colors.primary.withValues(alpha: 0.25)
                            : colors.hairline,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(icons[e.key]!,
                            color: visible ? colors.primary : colors.textMuted,
                            size: 18),
                        const SizedBox(width: 12),
                        Text(e.value,
                            style: TextStyle(
                                color: visible
                                    ? colors.textPrimary
                                    : colors.textMuted,
                                fontSize: 14,
                                fontWeight: visible
                                    ? FontWeight.w600
                                    : FontWeight.normal)),
                        const Spacer(),
                        AnimatedContainer(
                          duration: AppMotion.fast,
                          curve: AppMotion.curve,
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color:
                                visible ? colors.primary : Colors.transparent,
                            border: Border.all(
                              color: visible
                                  ? colors.primary
                                  : colors.textMuted.withValues(alpha: 0.4),
                              width: 1.5,
                            ),
                          ),
                          child: visible
                              ? const Icon(Icons.check,
                                  color: Colors.white, size: 12)
                              : null,
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  void _showDiskDetail(BuildContext context, Map<String, dynamic> disk,
      ProxmoxProvider provider, String nodeName) {
    final colors = context.appColors;
    final devpath = disk['devpath'] ?? '';
    final smart = provider.nodeDiskSmarts[devpath] ?? {};
    final aliasProvider = context.read<AliasProvider>();
    final aliasController =
        TextEditingController(text: aliasProvider.getAlias(devpath));

    appShowModalBottomSheet<void>(
      context: context,
      backgroundColor: colors.surface1,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.md))),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.65,
        minChildSize: 0.5,
        maxChildSize: 0.92,
        builder: (ctx, scrollCtrl) => StatefulBuilder(
          builder: (ctx, setModalState) {
            final temp = smart['temperature'];
            final health = disk['health'] ?? 'UNKNOWN';
            final isHealthy = health == 'PASSED';
            final diskType = _translateDiskType(disk['type'] ?? '-');
            final sizeGb = ((disk['size'] ?? 0) / 1e9).toStringAsFixed(0);
            final healthColor = isHealthy ? colors.success : colors.error;
            final tempColor = temp == null
                ? colors.textMuted
                : (temp as num) > 50
                    ? colors.error
                    : temp > 40
                        ? colors.warning
                        : colors.success;

            return SingleChildScrollView(
              controller: scrollCtrl,
              padding: EdgeInsets.fromLTRB(
                  20, 16, 20, MediaQuery.of(ctx).viewInsets.bottom + 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: colors.textMuted.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(AppSpace.md),
                        decoration: BoxDecoration(
                          color: colors.surface2,
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                        ),
                        child: Icon(
                          disk['type'] == 'nvme'
                              ? Icons.memory_rounded
                              : disk['type'] == 'ssd'
                                  ? Icons.storage_rounded
                                  : Icons.album_rounded,
                          color: colors.textSecondary,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(disk['model'] ?? devpath,
                                style: TextStyle(
                                    color: colors.textPrimary,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold)),
                            const SizedBox(height: 4),
                            MetaLine([devpath, diskType, '$sizeGb GB']),
                            const SizedBox(height: 6),
                            StatusIndicator(
                              color: healthColor,
                              label: _translateHealth(health),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                          child: _StatColumn(
                        label: 'Kapasite',
                        value: '$sizeGb GB',
                        colors: colors,
                      )),
                      Container(width: 1, height: 32, color: colors.hairline),
                      Expanded(
                          child: _StatColumn(
                        label: 'Sıcaklık',
                        value: temp != null ? '$temp°C' : '-',
                        colors: colors,
                        valueColor: tempColor,
                      )),
                      Container(width: 1, height: 32, color: colors.hairline),
                      Expanded(
                          child: _StatColumn(
                        label: 'Sağlık',
                        value: _translateHealth(health),
                        colors: colors,
                        valueColor: healthColor,
                      )),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (smart['attributes'] != null) ...[
                    _InfoCard(
                      colors: colors,
                      title: 'SMART Verileri',
                      icon: Icons.analytics_outlined,
                      child: Column(
                        children: (smart['attributes'] as List)
                            .where(
                                (attr) => attr['name'] != 'Unknown_Attribute')
                            .take(10)
                            .map((attr) {
                          final attrName =
                              _translateSmartAttr(attr['name'] ?? '');
                          final attrValue = attr['name'] == 'Power_On_Hours'
                              ? _formatUptime((int.tryParse(attr['raw']
                                          .toString()
                                          .split(' ')
                                          .first) ??
                                      0) *
                                  3600)
                              : attr['raw']?.toString().split(' ').first ??
                                  '${attr['value'] ?? '-'}';
                          return Padding(
                            key: ValueKey(attr['name']),
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              children: [
                                Expanded(
                                    child: Text(attrName,
                                        style: TextStyle(
                                            color: colors.textMuted,
                                            fontSize: 11))),
                                Text(attrValue,
                                    style: TextStyle(
                                        color: colors.textPrimary,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600)),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  _InfoCard(
                    colors: colors,
                    title: 'Özel Disk Adı',
                    icon: Icons.label_outline_rounded,
                    child: Column(
                      children: [
                        TextField(
                          controller: aliasController,
                          style: TextStyle(
                              color: colors.textPrimary, fontSize: 13),
                          decoration: InputDecoration(
                            hintText: 'Örn: Ana Disk, NVMe Boot...',
                            hintStyle: TextStyle(color: colors.textMuted),
                            filled: true,
                            fillColor: colors.surface2,
                            border: OutlineInputBorder(
                                borderRadius:
                                    BorderRadius.circular(AppRadius.sm),
                                borderSide: BorderSide.none),
                            focusedBorder: OutlineInputBorder(
                                borderRadius:
                                    BorderRadius.circular(AppRadius.sm),
                                borderSide: BorderSide(
                                    color: colors.primary, width: 1.5)),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 12),
                          ),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: () {
                              aliasProvider.setAlias(
                                  devpath, aliasController.text.trim());
                              Navigator.pop(ctx);
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: colors.primary,
                              padding: const EdgeInsets.symmetric(vertical: 13),
                              shape: RoundedRectangleBorder(
                                  borderRadius:
                                      BorderRadius.circular(AppRadius.sm)),
                            ),
                            child: const Text('Kaydet',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    ).whenComplete(aliasController.dispose);
  }

  void _showMetricHistory(
      BuildContext context, String nodeName, String metricType) {
    final provider = context.read<ProxmoxProvider>();
    final rrd = provider.nodeRRDData[nodeName] ?? [];
    final colors = context.appColors;

    appShowModalBottomSheet(
      context: context,
      backgroundColor: colors.surface1,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.md))),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.65,
        minChildSize: 0.5,
        maxChildSize: 0.92,
        builder: (ctx, scrollCtrl) => _MetricHistorySheet(
          scrollCtrl: scrollCtrl,
          nodeName: nodeName,
          metricType: metricType,
          rrd: rrd,
        ),
      ),
    );
  }

  void _showStorageContent(
      BuildContext context, String nodeName, String storageName) {
    final colors = context.appColors;
    final provider = context.read<ProxmoxProvider>();
    final storages = provider.nodeStorages[nodeName] ?? [];
    final storage = storages.firstWhere(
      (s) => s['storage'] == storageName,
      orElse: () => <String, dynamic>{},
    );

    appShowModalBottomSheet(
      context: context,
      backgroundColor: colors.surface1,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.md))),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.92,
        builder: (ctx, scrollCtrl) => _StorageDetailSheet(
          nodeName: nodeName,
          storage: storage,
          scrollCtrl: scrollCtrl,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    // Değer kullanılmıyor ama select() kaydı bilinçli korunuyor — bu widget
    // isLoading değiştiğinde de rebuild olmaya devam etsin diye (silinmesi
    // rebuild zamanlamasını değiştirebilir).
    context.select<ProxmoxProvider, bool>((p) => p.isLoading);
    final isInitialLoad =
        context.select<ProxmoxProvider, bool>((p) => p.isInitialLoad);
    final nodes =
        context.select<ProxmoxProvider, List<dynamic>>((p) => p.nodes);
    final hasError =
        context.select<ProxmoxProvider, bool>((p) => p.error != null);
    final provider = context.read<ProxmoxProvider>();

    final isReady = context.select<ProxmoxProvider, bool>((p) => p.isReady);

    if (!isReady) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 36,
              height: 36,
              child: CircularProgressIndicator(
                  strokeWidth: 2.5, color: colors.primary),
            ),
            const SizedBox(height: 14),
            Text('Yükleniyor...',
                style: TextStyle(color: colors.textMuted, fontSize: 13)),
          ],
        ),
      );
    }

    if (!provider.isConfigured) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.dns_outlined, color: colors.textMuted, size: 64),
            const SizedBox(height: 16),
            Text('Henüz bir sunucu bağlanmadı',
                style: TextStyle(color: colors.textSecondary, fontSize: 16)),
            const SizedBox(height: 8),
            Text('Ayarlardan Proxmox sunucusu ekleyin',
                style: TextStyle(color: colors.textMuted, fontSize: 13)),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => Navigator.push(
                  context, AppTransitions.slideFade(const ProxmoxConnectionScreen())),
              icon: const Icon(Icons.add, color: Colors.white, size: 18),
              label: const Text('Sunucu Ekle',
                  style: TextStyle(color: Colors.white)),
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.primary,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.sm)),
              ),
            ),
          ],
        ),
      );
    }

    if (isInitialLoad) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 36,
              height: 36,
              child: CircularProgressIndicator(
                  strokeWidth: 2.5, color: colors.primary),
            ),
            const SizedBox(height: 14),
            Text('Yükleniyor...',
                style: TextStyle(color: colors.textMuted, fontSize: 13)),
          ],
        ),
      );
    }

    if (nodes.isEmpty && hasError) {
      final unreachable = provider.unreachableNodeNames;
      final allDeliberate = unreachable.isNotEmpty &&
          unreachable.every(provider.isDeliberateOff);
      final lastSuccessAt = provider.lastSuccessAt;
      final lastSuccessStr = lastSuccessAt == null
          ? null
          : '${lastSuccessAt.hour.toString().padLeft(2, '0')}:${lastSuccessAt.minute.toString().padLeft(2, '0')}';

      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
                allDeliberate
                    ? Icons.power_settings_new_rounded
                    : Icons.dns_rounded,
                color: allDeliberate ? colors.primary : colors.error,
                size: 64),
            const SizedBox(height: 16),
            Text(
                allDeliberate
                    ? 'Sunucu Bilinçli Olarak Kapatıldı'
                    : 'Sunucu(lar)a Şu An Ulaşılamıyor',
                textAlign: TextAlign.center,
                style: TextStyle(color: colors.textSecondary, fontSize: 16)),
            const SizedBox(height: 8),
            Text(
                allDeliberate
                    ? 'WOL ile ya da fiziksel olarak açabilirsiniz.'
                    : (provider.retryStatus ?? 'Bağlantı kontrol ediliyor...'),
                textAlign: TextAlign.center,
                style: TextStyle(color: colors.textMuted, fontSize: 13)),
            if (lastSuccessStr != null) ...[
              const SizedBox(height: 4),
              Text('Son erişim: $lastSuccessStr',
                  style: TextStyle(color: colors.textMuted, fontSize: 12)),
            ],
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => provider.manualRefresh(),
              icon: const Icon(Icons.refresh, color: Colors.white, size: 18),
              label: const Text('Tekrar Dene',
                  style: TextStyle(color: Colors.white)),
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.primary,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.sm)),
              ),
            ),
          ],
        ),
      );
    }

    if (nodes.isEmpty) {
      return Center(
          child: Text('Makine bulunamadı',
              style: TextStyle(color: colors.textSecondary)));
    }

    final isOperationInProgress =
        context.select<ProxmoxProvider, bool>((p) => p.isOperationInProgress);

    // Özet banner verileri
    int totalCT = 0, runningCT = 0, totalVM = 0, runningVM = 0;
    for (final node in nodes) {
      final name = node['node'] as String;
      final lxcs = provider.nodeLXCs[name] ?? [];
      final vms = provider.nodeVMs[name] ?? [];
      totalCT += lxcs.length;
      runningCT += lxcs.where((c) => c['status'] == 'running').length;
      totalVM += vms.length;
      runningVM += vms.where((v) => v['status'] == 'running').length;
    }

    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: () => provider.refresh(),
          child: CustomScrollView(
            slivers: [
              // ── Özet Banner ──
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: _SummaryBanner(
                    nodes: nodes,
                    provider: provider,
                    totalCT: totalCT,
                    runningCT: runningCT,
                    totalVM: totalVM,
                    runningVM: runningVM,
                    style: _summaryStyle,
                    onCustomize: () => _showStylePicker(context),
                  ),
                ),
              ),

              // ── Node Listesi ──
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
                sliver: SliverReorderableList(
                  onReorder: (oldIndex, newIndex) =>
                      provider.reorderNodes(oldIndex, newIndex),
                  itemCount: nodes.length,
                  proxyDecorator: (child, index, animation) =>
                      Material(color: Colors.transparent, child: child),
                  itemBuilder: (context, i) {
                    final node = nodes[i];
                    final name = node['node'] as String;

                    if (provider.unreachableNodeNames.contains(name)) {
                      return _UnreachableNodeCard(
                        key: ValueKey(name),
                        name: name,
                        host: provider.hostForNode(name) ?? '',
                      );
                    }

                    final isExpanded = _expandedNodes[name] ?? true;
                    final status = provider.nodeStatuses[name] ?? {};
                    final sections = _getSections(name);

                    final cpuUsage = ((status['cpu'] ?? 0) * 100).toDouble();
                    final memTotal = (status['memory']?['total'] ?? 1) as int;
                    final memUsed = (status['memory']?['used'] ?? 0) as int;
                    final memAvailable =
                        (status['memory']?['available'] ?? 0) as int;
                    final memFree = (status['memory']?['free'] ?? 0) as int;
                    final memPercent =
                        memTotal > 0 ? memUsed / memTotal * 100 : 0.0;
                    final swapTotal = (status['swap']?['total'] ?? 0) as int;
                    final swapUsed = (status['swap']?['used'] ?? 0) as int;
                    final uptime = status['uptime'] ?? 0;
                    final loadAvg = status['loadavg'] ?? [];
                    final cpuInfo = status['cpuinfo'] ?? {};
                    final rootfs = status['rootfs'] ?? {};
                    final disks = provider.nodeDisks[name] ?? [];
                    final networks = provider.nodeNetworks[name] ?? [];
                    final storages = provider.nodeStorages[name] ?? [];
                    final netstat = provider.nodeNetstat[name] ?? [];
                    final nodeStatus =
                        _translateNodeStatus(node['status'] ?? 'unknown');
                    final isOnline = node['status'] == 'online';
                    final pveVersion = (status['pveversion'] as String? ?? '')
                            .split('/')
                            .elementAtOrNull(1) ??
                        '';
                    final kernelRelease =
                        status['current-kernel']?['release'] as String? ?? '';
                    final bootMode =
                        status['boot-info']?['mode'] as String? ?? '';
                    final cpuMhz =
                        double.tryParse(cpuInfo['mhz']?.toString() ?? '0') ?? 0;

                    return _NodeCard(
                      key: ValueKey(name),
                      name: name,
                      isExpanded: isExpanded,
                      isOnline: isOnline,
                      nodeStatus: nodeStatus,
                      cpuUsage: cpuUsage,
                      memPercent: memPercent,
                      memUsed: memUsed,
                      memTotal: memTotal,
                      memFree: memFree,
                      memAvailable: memAvailable,
                      swapTotal: swapTotal,
                      swapUsed: swapUsed,
                      uptime: uptime,
                      loadAvg: loadAvg,
                      cpuInfo: cpuInfo,
                      cpuMhz: cpuMhz,
                      rootfs: rootfs,
                      disks: disks,
                      networks: networks,
                      storages: storages,
                      netstat: netstat,
                      status: status,
                      pveVersion: pveVersion,
                      kernelRelease: kernelRelease,
                      bootMode: bootMode,
                      provider: provider,
                      index: i,
                      sections: sections,
                      colorByPercent: _colorByPercent,
                      formatUptime: _formatUptime,
                      formatBytes: _formatBytes,
                      formatBytesShort: _formatBytesShort,
                      translateHealth: _translateHealth,
                      translateDiskType: _translateDiskType,
                      onToggleExpand: () {
                        setState(() => _expandedNodes[name] = !isExpanded);
                        _saveExpandedState();
                      },
                      onShowDiskDetail: (disk) =>
                          _showDiskDetail(context, disk, provider, name),
                      onShowMetricHistory: (type) =>
                          _showMetricHistory(context, name, type),
                      onShowStorageContent: (storage) =>
                          _showStorageContent(context, name, storage),
                      onCustomize: () => _showSectionCustomizer(context, name),
                    );
                  },
                ),
              ),

              // ── Hiç node bilgisi bilinmeyen (bir kez bile başarılı
              // olmamış), bu turda erişilemeyen sunucular ──
              Builder(builder: (context) {
                final knownHosts = nodes
                    .map((n) => provider.hostForNode(n['node'] as String))
                    .toSet();
                final orphanServers = provider.unreachableServers
                    .where((s) => !knownHosts.contains(s.host))
                    .toList();
                if (orphanServers.isEmpty) return const SliverToBoxAdapter();
                return SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  sliver: SliverList.list(
                    children: [
                      for (final s in orphanServers)
                        _UnreachableNodeCard(
                          key: ValueKey('orphan_${s.host}'),
                          name: s.name.isNotEmpty ? s.name : s.host,
                          host: s.host,
                        ),
                    ],
                  ),
                );
              }),

              // ── Yapı bilgisiyle (cloud) gelmiş ama token'ı bu cihazda
              // hiç girilmemiş sunucular — hiç sorgu atılmadı ──
              if (provider.credentialMissingServers.isNotEmpty)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  sliver: SliverList.list(
                    children: [
                      for (final s in provider.credentialMissingServers)
                        _CredentialMissingCard(
                          key: ValueKey('needs_creds_${s.name}'),
                          name: s.name.isNotEmpty ? s.name : s.host,
                          host: s.host,
                          onTap: () => Navigator.push(
                            context,
                            AppTransitions.slideFade(ProxmoxConnectionScreen(
                              openEditForServerName: s.name,
                            )),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        if (isOperationInProgress)
          Positioned.fill(
            child: Builder(builder: (context) {
              final p = context.watch<ProxmoxProvider>();
              return OperationOverlay(
                message: p.operationMessage,
                subMessage: p.operationSubMessage,
                progress: p.operationProgress,
                success: p.operationSuccess,
                isError: p.operationIsError,
              );
            }),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────
// Özet Banner
// ─────────────────────────────────────────────

class _SummaryBanner extends StatelessWidget {
  final List<dynamic> nodes;
  final ProxmoxProvider provider;
  final int totalCT, runningCT, totalVM, runningVM;
  final String style;
  final VoidCallback onCustomize;

  const _SummaryBanner({
    required this.nodes,
    required this.provider,
    required this.totalCT,
    required this.runningCT,
    required this.totalVM,
    required this.runningVM,
    required this.style,
    required this.onCustomize,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final onlineCount = nodes.where((n) => n['status'] == 'online').length;

    int totalMem = 0, usedMem = 0;
    double cpuSum = 0;
    int cpuCount = 0;
    for (final node in nodes) {
      final name = node['node'] as String;
      final status = provider.nodeStatuses[name];
      totalMem += (status?['memory']?['total'] ?? 0) as int;
      usedMem += (status?['memory']?['used'] ?? 0) as int;
      // Ortalama sadece verisi olan (online) node'lar üzerinden alınıyor —
      // offline node'ların boş status map'i ortalamayı yanlışlıkla aşağı
      // çekmesin diye (bellek toplamında bu sorun yok, çünkü hem pay hem
      // payda 0 alıyor, ama CPU bir ORTALAMA olduğu için sayaç şart).
      if (status != null && status['cpu'] != null) {
        cpuSum += (status['cpu'] as num) * 100;
        cpuCount++;
      }
    }
    final memPercent = totalMem > 0 ? usedMem / totalMem * 100 : 0.0;
    final cpuPercent = cpuCount > 0 ? cpuSum / cpuCount : 0.0;

    final allOnline = onlineCount == nodes.length;
    final memColor = colors.thresholdColor(memPercent);
    final cpuColor = colors.thresholdColor(cpuPercent);

    return Container(
      padding: const EdgeInsets.all(AppSpace.lg),
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: colors.hairline),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.dashboard_outlined, color: colors.textSecondary, size: 16),
              const SizedBox(width: AppSpace.sm),
              Text('Sistem Özeti', style: colors.body.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(width: 6),
              GestureDetector(
                onTap: onCustomize,
                child: Icon(Icons.tune_rounded, color: colors.textMuted, size: 15),
              ),
              const Spacer(),
              StatusIndicator(
                color: allOnline ? colors.success : colors.warning,
                label: '$onlineCount/${nodes.length} Makine',
                style: colors.meta,
              ),
            ],
          ),
          const SizedBox(height: AppSpace.md),
          AnimatedSize(
            duration: AppMotion.base,
            curve: AppMotion.curve,
            alignment: Alignment.topCenter,
            child: AnimatedSwitcher(
              duration: AppMotion.base,
              switchInCurve: AppMotion.curve,
              switchOutCurve: AppMotion.curve,
              child: KeyedSubtree(
                key: ValueKey(style),
                child: switch (style) {
                  'circular' => _SummaryCircularRow(
                      totalCT: totalCT,
                      runningCT: runningCT,
                      totalVM: totalVM,
                      runningVM: runningVM,
                      memPercent: memPercent,
                      memColor: memColor,
                      cpuPercent: cpuPercent,
                      cpuColor: cpuColor,
                      colors: colors,
                    ),
                  'cards' => _SummaryCardGrid(
                      totalCT: totalCT,
                      runningCT: runningCT,
                      totalVM: totalVM,
                      runningVM: runningVM,
                      memPercent: memPercent,
                      memColor: memColor,
                      cpuPercent: cpuPercent,
                      cpuColor: cpuColor,
                      colors: colors,
                    ),
                  _ => Row(
                      children: [
                        Expanded(
                            child: _StatColumn(
                          label: 'Konteyner',
                          value: '$runningCT/$totalCT',
                          colors: colors,
                        )),
                        Container(width: 1, height: 32, color: colors.hairline),
                        Expanded(
                            child: _StatColumn(
                          label: 'Sanal Makine',
                          value: '$runningVM/$totalVM',
                          colors: colors,
                        )),
                        Container(width: 1, height: 32, color: colors.hairline),
                        Expanded(
                            child: _StatColumn(
                          label: 'Bellek',
                          value: '%${memPercent.toStringAsFixed(0)}',
                          colors: colors,
                          valueColor: memColor,
                        )),
                        Container(width: 1, height: 32, color: colors.hairline),
                        Expanded(
                            child: _StatColumn(
                          label: 'CPU',
                          value: '%${cpuPercent.toStringAsFixed(0)}',
                          colors: colors,
                          valueColor: cpuColor,
                        )),
                      ],
                    ),
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Dairesel gösterim stili: her metrik için native `CircularProgressIndicator`
/// tabanlı küçük bir halka (yeni bağımlılık yok, proje genelinde zaten
/// kullanılan widget) + ortasında değer, altında etiket.
class _SummaryCircularRow extends StatelessWidget {
  final int totalCT, runningCT, totalVM, runningVM;
  final double memPercent, cpuPercent;
  final Color memColor, cpuColor;
  final AppThemeData colors;

  const _SummaryCircularRow({
    required this.totalCT,
    required this.runningCT,
    required this.totalVM,
    required this.runningVM,
    required this.memPercent,
    required this.memColor,
    required this.cpuPercent,
    required this.cpuColor,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    final ctRatio = totalCT > 0 ? runningCT / totalCT : 0.0;
    final vmRatio = totalVM > 0 ? runningVM / totalVM : 0.0;

    return Row(
      children: [
        Expanded(
          child: _CircularStat(
            value: ctRatio,
            centerText: '$runningCT/$totalCT',
            color: colors.primary,
            label: 'Konteyner',
            colors: colors,
          ),
        ),
        Expanded(
          child: _CircularStat(
            value: vmRatio,
            centerText: '$runningVM/$totalVM',
            color: colors.primary,
            label: 'Sanal Makine',
            colors: colors,
          ),
        ),
        Expanded(
          child: _CircularStat(
            value: (memPercent / 100).clamp(0.0, 1.0),
            centerText: '%${memPercent.toStringAsFixed(0)}',
            color: memColor,
            label: 'Bellek',
            colors: colors,
          ),
        ),
        Expanded(
          child: _CircularStat(
            value: (cpuPercent / 100).clamp(0.0, 1.0),
            centerText: '%${cpuPercent.toStringAsFixed(0)}',
            color: cpuColor,
            label: 'CPU',
            colors: colors,
          ),
        ),
      ],
    );
  }
}

class _CircularStat extends StatelessWidget {
  final double value;
  final String centerText;
  final Color color;
  final String label;
  final AppThemeData colors;

  const _CircularStat({
    required this.value,
    required this.centerText,
    required this.color,
    required this.label,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          width: 52,
          height: 52,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CircularProgressIndicator(
                value: value,
                strokeWidth: 5,
                backgroundColor: colors.surface2,
                valueColor: AlwaysStoppedAnimation(color),
              ),
              Text(centerText,
                  style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 11,
                      fontWeight: FontWeight.bold)),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Text(label, style: colors.meta),
      ],
    );
  }
}

/// Kartlar gösterim stili: aynı dosyada zaten var olan `_StatCard`
/// (ikon + renkli kutu + büyük değer + etiket) 2×2 ızgarada.
class _SummaryCardGrid extends StatelessWidget {
  final int totalCT, runningCT, totalVM, runningVM;
  final double memPercent, cpuPercent;
  final Color memColor, cpuColor;
  final AppThemeData colors;

  const _SummaryCardGrid({
    required this.totalCT,
    required this.runningCT,
    required this.totalVM,
    required this.runningVM,
    required this.memPercent,
    required this.memColor,
    required this.cpuPercent,
    required this.cpuColor,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _StatCard(
                label: 'Konteyner',
                value: '$runningCT/$totalCT',
                color: colors.primary,
                colors: colors,
                icon: Icons.widgets_outlined,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _StatCard(
                label: 'Sanal Makine',
                value: '$runningVM/$totalVM',
                color: colors.primary,
                colors: colors,
                icon: Icons.dns_outlined,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _StatCard(
                label: 'Bellek',
                value: '%${memPercent.toStringAsFixed(0)}',
                color: memColor,
                colors: colors,
                icon: Icons.memory,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _StatCard(
                label: 'CPU',
                value: '%${cpuPercent.toStringAsFixed(0)}',
                color: cpuColor,
                colors: colors,
                icon: Icons.speed_outlined,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Sistem Özeti'ndeki tek bir sütun: büyük tabular değer + altında küçük gri
/// etiket. Üç ayrı renkli/kutulu "_SummaryTile" yerine tek yüzeyde kompakt
/// bir şerit (bkz. plan Adım 2a).
class _StatColumn extends StatelessWidget {
  final String label, value;
  final AppThemeData colors;
  final Color? valueColor;

  const _StatColumn({
    required this.label,
    required this.value,
    required this.colors,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value, style: colors.metric.copyWith(color: valueColor ?? colors.textPrimary)),
        const SizedBox(height: 2),
        Text(label, style: colors.meta),
      ],
    );
  }
}

// ─────────────────────────────────────────────
// Node Card
// ─────────────────────────────────────────────

// ─────────────────────────────────────────────
// Erişilemeyen sunucu kartı — CPU/RAM/disk bölümleri yok, sahte/eski veri
// göstermez. "Son görülme" varsa background_service.dart'ın yazdığı
// node_last_seen_$name anahtarından salt-okunur tüketilir.
// ─────────────────────────────────────────────

String _unreachableShortDescription(String host) {
  if (host.isEmpty) return 'Sunucuya ulaşılamıyor';
  return switch (classifyHost(host)) {
    ConnectionTarget.privateNetwork => 'İç ağda değilsiniz olabilir',
    ConnectionTarget.tailscale => 'Tailscale bağlantısını kontrol edin',
    ConnectionTarget.external => 'Sunucuya ulaşılamıyor',
  };
}

class _UnreachableNodeCard extends StatelessWidget {
  final String name;
  final String host;

  const _UnreachableNodeCard({super.key, required this.name, required this.host});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: colors.hairline),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: colors.surface2,
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Icon(Icons.dns_rounded, color: colors.textMuted, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(name,
                          style: TextStyle(
                              color: colors.textPrimary,
                              fontSize: 16,
                              fontWeight: FontWeight.bold)),
                    ),
                    StatusIndicator(
                      color: colors.warning,
                      label: 'Erişilemiyor',
                      style: colors.meta,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(_unreachableShortDescription(host),
                    style: colors.meta.copyWith(color: colors.textMuted)),
                FutureBuilder<SharedPreferences>(
                  future: SharedPreferences.getInstance(),
                  builder: (context, snapshot) {
                    final lastSeen =
                        snapshot.data?.getString('node_last_seen_$name');
                    if (lastSeen == null || lastSeen.isEmpty) {
                      return const SizedBox.shrink();
                    }
                    return Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text('son görülme: $lastSeen',
                          style:
                              colors.meta.copyWith(color: colors.textMuted)),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Cloud'dan yapı bilgisiyle (host/port) gelmiş ama token'ı bu cihazda hiç
/// girilmemiş sunucu — "Erişilemiyor"dan kasıtlı olarak ayrı: bağlantı hiç
/// denenmedi (bkz. ProxmoxProvider.credentialMissingServers). Dokununca
/// doğrudan bu sunucunun düzenleme sheet'i açılır.
class _CredentialMissingCard extends StatelessWidget {
  final String name;
  final String host;
  final VoidCallback onTap;

  const _CredentialMissingCard({
    super.key,
    required this.name,
    required this.host,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colors.surface1,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: colors.hairline),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: colors.surface2,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Icon(Icons.key_off_rounded,
                  color: colors.textMuted, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(name,
                            style: TextStyle(
                                color: colors.textPrimary,
                                fontSize: 16,
                                fontWeight: FontWeight.bold)),
                      ),
                      StatusIndicator(
                        color: colors.warning,
                        label: 'Kimlik bilgisi gerekli',
                        style: colors.meta,
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                      'Bu sunucu başka bir cihazda eklendi — token girmek için dokunun',
                      style: colors.meta.copyWith(color: colors.textMuted)),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: colors.textMuted, size: 18),
          ],
        ),
      ),
    );
  }
}

class _NodeCard extends StatelessWidget {
  final String name;
  final bool isExpanded, isOnline;
  final String nodeStatus;
  final double cpuUsage, memPercent, cpuMhz;
  final int memUsed, memTotal, memFree, memAvailable;
  final int swapTotal, swapUsed, uptime;
  final List<dynamic> loadAvg, disks, networks, storages, netstat;
  final Map<String, dynamic> cpuInfo, rootfs, status;
  final String pveVersion, kernelRelease, bootMode;
  final ProxmoxProvider provider;
  final int index;
  final Map<String, bool> sections;
  final Color Function(BuildContext, double) colorByPercent;
  final String Function(int) formatUptime;
  final String Function(int) formatBytes;
  final String Function(int) formatBytesShort;
  final String Function(String) translateHealth;
  final String Function(String) translateDiskType;
  final VoidCallback onToggleExpand;
  final void Function(Map<String, dynamic>) onShowDiskDetail;
  final void Function(String) onShowMetricHistory;
  final void Function(String) onShowStorageContent;
  final VoidCallback onCustomize;

  const _NodeCard({
    super.key,
    required this.name,
    required this.isExpanded,
    required this.isOnline,
    required this.nodeStatus,
    required this.cpuUsage,
    required this.memPercent,
    required this.cpuMhz,
    required this.memUsed,
    required this.memTotal,
    required this.memFree,
    required this.memAvailable,
    required this.swapTotal,
    required this.swapUsed,
    required this.uptime,
    required this.loadAvg,
    required this.cpuInfo,
    required this.rootfs,
    required this.disks,
    required this.networks,
    required this.storages,
    required this.netstat,
    required this.status,
    required this.pveVersion,
    required this.kernelRelease,
    required this.bootMode,
    required this.provider,
    required this.index,
    required this.sections,
    required this.colorByPercent,
    required this.formatUptime,
    required this.formatBytes,
    required this.formatBytesShort,
    required this.translateHealth,
    required this.translateDiskType,
    required this.onToggleExpand,
    required this.onShowDiskDetail,
    required this.onShowMetricHistory,
    required this.onShowStorageContent,
    required this.onCustomize,
  });

  Future<void> _confirmPowerAction(
    BuildContext context,
    AppThemeData colors, {
    required String title,
    required String message,
    required String confirmLabel,
    required Future<void> Function() onConfirm,
  }) async {
    final gated =
        await QuickAuthGate.isScopeGated(scopeKey: 'lock_scope_power_ops');
    if (!context.mounted) return;
    final ok = await showAppConfirmDialog(
      context: context,
      title: title,
      message: message,
      confirmLabel: confirmLabel,
      requireAuth: gated,
      authReason: 'İşlemi onaylamak için doğrulayın',
    );
    if (ok) await onConfirm();
  }

  PopupMenuItem<String> _powerMenuItem({
    required AppThemeData colors,
    required String value,
    required IconData icon,
    required String label,
    required Color accent,
    bool bold = false,
  }) {
    return PopupMenuItem<String>(
      value: value,
      height: 42,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadius.xs),
            ),
            child: Icon(icon, color: accent, size: 15),
          ),
          const SizedBox(width: 10),
          Text(
            label,
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 13,
              fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Node Header ──
        GestureDetector(
          onTap: onToggleExpand,
          child: Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: colors.surface1,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: colors.hairline),
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          ReorderableDragStartListener(
                            index: index,
                            child: Padding(
                              padding: const EdgeInsets.only(right: 10),
                              child: Icon(Icons.drag_handle,
                                  color:
                                      colors.textMuted.withValues(alpha: 0.4),
                                  size: 18),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: colors.surface2,
                              borderRadius: BorderRadius.circular(AppRadius.sm),
                            ),
                            child: Icon(Icons.dns_rounded,
                                color: isOnline
                                    ? colors.primary
                                    : colors.textMuted,
                                size: 20),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(name,
                                    style: TextStyle(
                                        color: colors.textPrimary,
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold)),
                                const SizedBox(height: 2),
                                Text(
                                  isExpanded
                                      ? 'Uptime: ${formatUptime(uptime)}'
                                      : '%${cpuUsage.toStringAsFixed(0)} · %${memPercent.toStringAsFixed(0)}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  softWrap: false,
                                  style: TextStyle(
                                      color: colors.textMuted, fontSize: 11),
                                ),
                              ],
                            ),
                          ),
                          StatusIndicator(
                            color: isOnline ? colors.success : colors.error,
                            label: nodeStatus,
                            style: colors.meta,
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            isExpanded
                                ? Icons.keyboard_arrow_up
                                : Icons.keyboard_arrow_down,
                            color: colors.textMuted.withValues(alpha: 0.6),
                            size: 18,
                          ),
                          PopupMenuButton<String>(
                            icon: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: colors.surface2,
                                borderRadius:
                                    BorderRadius.circular(AppRadius.xs),
                              ),
                              child: Icon(Icons.more_vert,
                                  color: colors.textMuted,
                                  size: 16),
                            ),
                            color: colors.surface1,
                            elevation: 6,
                            offset: const Offset(0, 8),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(AppRadius.md),
                              side: BorderSide(color: colors.hairline),
                            ),
                            itemBuilder: (ctx) => [
                              _powerMenuItem(
                                colors: colors,
                                value: 'customize',
                                icon: Icons.tune_rounded,
                                label: 'Bölümleri Özelleştir',
                                accent: colors.primary,
                              ),
                              PopupMenuItem<String>(
                                enabled: false,
                                height: 9,
                                padding: EdgeInsets.zero,
                                child: Divider(
                                  height: 1,
                                  color: colors.hairline,
                                ),
                              ),
                              _powerMenuItem(
                                colors: colors,
                                value: 'reboot',
                                icon: Icons.restart_alt_rounded,
                                label: 'Yeniden Başlat',
                                accent: colors.warning,
                              ),
                              _powerMenuItem(
                                colors: colors,
                                value: 'shutdown',
                                icon: Icons.power_settings_new_rounded,
                                label: 'Kapat',
                                accent: colors.error,
                                bold: true,
                              ),
                            ],
                            onSelected: (value) async {
                              if (value == 'reboot') {
                                await _confirmPowerAction(
                                  context,
                                  colors,
                                  title: 'Emin misiniz?',
                                  message:
                                      '$name yeniden başlatılacak. Sunucudaki tüm VM/CT\'ler bu sırada kesintiye uğrar.',
                                  confirmLabel: 'Yeniden Başlat',
                                  onConfirm: () => provider.rebootNode(name),
                                );
                              } else if (value == 'shutdown') {
                                await _confirmPowerAction(
                                  context,
                                  colors,
                                  title: 'Emin misiniz?',
                                  message:
                                      '$name kapatılacak. Fiziksel erişiminiz yoksa tekrar açmak için Wake-on-LAN gerekir.',
                                  confirmLabel: 'Kapat',
                                  onConfirm: () => provider.shutdownNode(name),
                                );
                              } else if (value == 'customize') {
                                onCustomize();
                              }
                            },
                          ),
                        ],
                      ),

                      const SizedBox(height: 12),

                      // ── CPU model + PVE version bilgi şeridi ──
                      Row(
                        children: [
                          Icon(Icons.memory_rounded,
                              color: colors.textMuted, size: 12),
                          const SizedBox(width: AppSpace.xs),
                          Expanded(
                            child: Text(
                              [
                                cpuInfo['model'] ?? '-',
                                '${cpuInfo['cpus'] ?? '-'} çekirdek',
                                if (pveVersion.isNotEmpty) 'PVE $pveVersion',
                              ].join(' · '),
                              style: colors.meta,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // ── Collapsed metrikler ──
                if (!isExpanded)
                  Container(
                    decoration: BoxDecoration(
                      border: Border(top: BorderSide(color: colors.hairline)),
                    ),
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
                    child: Column(
                      children: [
                        MetricRow(
                          label: 'CPU',
                          value: cpuUsage,
                          valueLabel: '%${cpuUsage.toStringAsFixed(0)}',
                          color: colorByPercent(context, cpuUsage),
                        ),
                        const SizedBox(height: AppSpace.xs),
                        MetricRow(
                          label: 'RAM',
                          value: memPercent,
                          valueLabel: '%${memPercent.toStringAsFixed(0)}',
                          color: colorByPercent(context, memPercent),
                        ),
                        if (swapTotal > 0) ...[
                          const SizedBox(height: AppSpace.xs),
                          MetricRow(
                            label: 'Swap',
                            value: swapUsed / swapTotal * 100,
                            valueLabel:
                                '%${(swapUsed / swapTotal * 100).toStringAsFixed(0)}',
                            color: colorByPercent(
                                context, swapUsed / swapTotal * 100),
                          ),
                        ],
                        const SizedBox(height: AppSpace.sm),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: MetaLine([
                            formatUptime(uptime),
                            '${(cpuMhz / 1000).toStringAsFixed(1)} GHz',
                            if (bootMode.isNotEmpty) bootMode.toUpperCase(),
                          ]),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),

        // ── Expanded içerik ──
        AnimatedCrossFade(
          duration: AppMotion.base,
          firstCurve: AppMotion.curve,
          secondCurve: AppMotion.curve,
          sizeCurve: AppMotion.curve,
          crossFadeState:
              isExpanded ? CrossFadeState.showFirst : CrossFadeState.showSecond,
          secondChild: const SizedBox(width: double.infinity),
          firstChild: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Kaynaklar ──
              if (sections['resources'] ?? true) ...[
                _SectionHeader(
                  title: 'Kaynaklar',
                  icon: Icons.monitor_heart_outlined,
                  colors: context.appColors,
                ),
                _CardContainer(
                  child: Column(
                    children: [
                      GestureDetector(
                        onTap: () => onShowMetricHistory('cpu'),
                        child: _ResourceRow(
                          icon: Icons.memory_rounded,
                          label: 'İşlemci',
                          value: cpuUsage,
                          subtitle:
                              'Load: ${loadAvg.isNotEmpty ? loadAvg[0] : '-'} / ${loadAvg.length > 1 ? loadAvg[1] : '-'} / ${loadAvg.length > 2 ? loadAvg[2] : '-'}',
                          extra: '${(cpuMhz / 1000).toStringAsFixed(2)} GHz',
                          tappable: true,
                        ),
                      ),
                      const _Divider(),
                      GestureDetector(
                        onTap: () => onShowMetricHistory('iowait'),
                        child: _ResourceRow(
                          icon: Icons.swap_vert_rounded,
                          label: 'I/O Wait',
                          value:
                              ((status['wait'] ?? status['iowait'] ?? 0) * 100)
                                  .toDouble(),
                          subtitle:
                              '↓ ${formatBytes(((status['netin'] ?? 0)).toInt())}/s  ↑ ${formatBytes(((status['netout'] ?? 0)).toInt())}/s',
                          tappable: true,
                        ),
                      ),
                      const _Divider(),
                      GestureDetector(
                        onTap: () => onShowMetricHistory('mem'),
                        child: _ResourceRow(
                          icon: Icons.developer_board_rounded,
                          label: 'Bellek',
                          value: memPercent,
                          subtitle:
                              '${formatBytes(memUsed)} / ${formatBytes(memTotal)}',
                          extra: 'Boş: ${formatBytes(memAvailable)}',
                          tappable: true,
                        ),
                      ),
                      if (swapTotal > 0) ...[
                        const _Divider(),
                        _ResourceRow(
                          icon: Icons.swap_horiz_rounded,
                          label: 'Takas (Swap)',
                          value: swapUsed / swapTotal * 100,
                          subtitle:
                              '${formatBytes(swapUsed)} / ${formatBytes(swapTotal)}',
                        ),
                      ],
                      if (rootfs.isNotEmpty) ...[
                        const _Divider(),
                        _ResourceRow(
                          icon: Icons.folder_rounded,
                          label: 'Root FS',
                          value: (rootfs['used'] ?? 0) /
                              (rootfs['total'] ?? 1) *
                              100,
                          subtitle:
                              '${formatBytes(rootfs['used'] ?? 0)} / ${formatBytes(rootfs['total'] ?? 1)}',
                          extra: 'Boş: ${formatBytes(rootfs['avail'] ?? 0)}',
                        ),
                      ],
                    ],
                  ),
                ),
              ],

              // ── Sistem Bilgisi ──
              if (sections['system_info'] ?? true) ...[
                _SectionHeader(
                  title: 'Sistem Bilgisi',
                  icon: Icons.info_outline_rounded,
                  colors: context.appColors,
                ),
                _CardContainer(
                  child: Column(
                    children: [
                      _InfoRowWidget(
                        label: 'Proxmox Versiyonu',
                        value: pveVersion,
                        icon: Icons.dns_rounded,
                        colors: context.appColors,
                      ),
                      const _Divider(),
                      _InfoRowWidget(
                        label: 'Kernel',
                        value: kernelRelease,
                        icon: Icons.code_rounded,
                        colors: context.appColors,
                      ),
                      const _Divider(),
                      _InfoRowWidget(
                        label: 'Mimari',
                        value: status['current-kernel']?['machine'] ?? '-',
                        icon: Icons.computer_rounded,
                        colors: context.appColors,
                      ),
                      const _Divider(),
                      _InfoRowWidget(
                        label: 'Boot Modu',
                        value: bootMode.toUpperCase(),
                        icon: Icons.security_rounded,
                        colors: context.appColors,
                      ),
                      const _Divider(),
                      _InfoRowWidget(
                        label: 'CPU Frekansı',
                        value: '${(cpuMhz / 1000).toStringAsFixed(2)} GHz',
                        icon: Icons.speed_rounded,
                        colors: context.appColors,
                      ),
                      const _Divider(),
                      _InfoRowWidget(
                        label: 'Çalışma Süresi',
                        value: formatUptime(uptime),
                        icon: Icons.timer_outlined,
                        colors: context.appColors,
                      ),
                    ],
                  ),
                ),
              ],

              // ── Diskler ──
              if ((sections['disks'] ?? true) && disks.isNotEmpty) ...[
                _SectionHeader(
                  title: 'Diskler',
                  icon: Icons.storage_rounded,
                  colors: context.appColors,
                ),
                ...disks.map((disk) {
                  final devpath = disk['devpath'] ?? '';
                  final smart = provider.nodeDiskSmarts[devpath] ?? {};
                  final temp = smart['temperature'];
                  final health = disk['health'] ?? 'UNKNOWN';
                  final isHealthy = health == 'PASSED';
                  final tempColor = temp == null
                      ? context.appColors.textMuted
                      : (temp as num) > 50
                          ? context.appColors.error
                          : temp > 40
                              ? context.appColors.warning
                              : context.appColors.success;

                  return GestureDetector(
                    key: ValueKey('disk_${name}_$devpath'),
                    onTap: () => onShowDiskDetail(disk),
                    child: _CardContainer(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: context.appColors.surface2,
                              borderRadius:
                                  BorderRadius.circular(AppRadius.xs),
                            ),
                            child: Icon(
                              disk['type'] == 'nvme'
                                  ? Icons.memory_rounded
                                  : disk['type'] == 'ssd'
                                      ? Icons.storage_rounded
                                      : Icons.album_rounded,
                              color: context.appColors.textSecondary,
                              size: 18,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Consumer<AliasProvider>(
                                  builder: (ctx, aliasProvider, _) {
                                    final alias =
                                        aliasProvider.getAlias(devpath);
                                    return Text(
                                      alias.isNotEmpty
                                          ? alias
                                          : (disk['model'] ?? devpath),
                                      style: TextStyle(
                                          color: context.appColors.textPrimary,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13),
                                    );
                                  },
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '$devpath  •  ${translateDiskType(disk['type'] ?? '-')}  •  ${((disk['size'] ?? 0) / 1e9).toStringAsFixed(0)} GB',
                                  style: TextStyle(
                                      color: context.appColors.textMuted,
                                      fontSize: 11),
                                ),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              StatusIndicator(
                                color: isHealthy
                                    ? context.appColors.success
                                    : context.appColors.error,
                                label: isHealthy ? 'Sağlıklı' : 'Hatalı',
                                style: context.appColors.meta,
                              ),
                              if (temp != null) ...[
                                const SizedBox(height: 4),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.thermostat_rounded,
                                        color: tempColor, size: 12),
                                    const SizedBox(width: 3),
                                    Text('$temp°C',
                                        style: TextStyle(
                                            color: tempColor,
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold)),
                                  ],
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(width: 4),
                          Icon(Icons.chevron_right_rounded,
                              color: context.appColors.textMuted, size: 16),
                        ],
                      ),
                    ),
                  );
                }),
              ],

              // ── Depolama ──
              if ((sections['storage'] ?? true) && storages.isNotEmpty) ...[
                _SectionHeader(
                  title: 'Depolama',
                  icon: Icons.folder_rounded,
                  colors: context.appColors,
                ),
                ...storages.where((s) => s['active'] == 1).map((s) {
                  final used = (s['used'] ?? 0) as int;
                  final total = (s['total'] ?? 1) as int;
                  final percent = total > 0 ? used / total * 100 : 0.0;
                  return _StorageCard(
                    key: ValueKey('storage_${name}_${s['storage']}'),
                    storage: s,
                    percent: percent,
                    used: used,
                    total: total,
                    colorByPercent: colorByPercent,
                    formatBytes: formatBytes,
                    onTap: () => onShowStorageContent(s['storage'] ?? ''),
                  );
                }),
              ],

              // ── CT/VM Ağ Trafiği ──
              if ((sections['netstat'] ?? true) && netstat.isNotEmpty) ...[
                _SectionHeader(
                  title: 'CT/VM Ağ Trafiği',
                  icon: Icons.swap_horiz_rounded,
                  colors: context.appColors,
                ),
                _CardContainer(
                  child: Column(
                    children: netstat.asMap().entries.map((entry) {
                      final i = entry.key;
                      final net = entry.value;
                      final vmid = net['vmid'] ?? '-';
                      final inBytes =
                          int.tryParse(net['in']?.toString() ?? '0') ?? 0;
                      final outBytes =
                          int.tryParse(net['out']?.toString() ?? '0') ?? 0;

                      // CT veya VM adını bul
                      final lxcs = provider.nodeLXCs[name] ?? [];
                      final vms = provider.nodeVMs[name] ?? [];
                      final allContainers = [...lxcs, ...vms];
                      final container = allContainers.firstWhere(
                        (c) => c['vmid']?.toString() == vmid.toString(),
                        orElse: () => <String, dynamic>{},
                      );
                      final containerName = container['name'] ?? 'CT/VM $vmid';
                      final isLxc = lxcs
                          .any((c) => c['vmid']?.toString() == vmid.toString());

                      return Column(
                        key: ValueKey('netstat_${name}_${i}_$vmid'),
                        children: [
                          if (i > 0) const _Divider(),
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: context.appColors.surface2,
                                    borderRadius:
                                        BorderRadius.circular(AppRadius.xs),
                                  ),
                                  child: Icon(
                                    isLxc
                                        ? Icons.view_in_ar_rounded
                                        : Icons.computer_rounded,
                                    color: context.appColors.textSecondary,
                                    size: 14,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(containerName,
                                          style: TextStyle(
                                              color:
                                                  context.appColors.textPrimary,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600)),
                                      Text(
                                          'ID: $vmid  •  ${net['dev'] ?? 'net0'}',
                                          style: TextStyle(
                                              color:
                                                  context.appColors.textMuted,
                                              fontSize: 10)),
                                    ],
                                  ),
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.arrow_downward_rounded,
                                            color:
                                                context.appColors.textSecondary,
                                            size: 11),
                                        const SizedBox(width: 3),
                                        Text(formatBytes(inBytes),
                                            style: TextStyle(
                                                color: context
                                                    .appColors.textSecondary,
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600)),
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.arrow_upward_rounded,
                                            color:
                                                context.appColors.textSecondary,
                                            size: 11),
                                        const SizedBox(width: 3),
                                        Text(formatBytes(outBytes),
                                            style: TextStyle(
                                                color: context
                                                    .appColors.textSecondary,
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600)),
                                      ],
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      );
                    }).toList(),
                  ),
                ),
              ],

              // ── Ağ Arayüzleri ──
              if ((sections['network'] ?? true) && networks.isNotEmpty) ...[
                _SectionHeader(
                  title: 'Ağ Arayüzleri',
                  icon: Icons.lan_rounded,
                  colors: context.appColors,
                ),
                _CardContainer(
                  child: Column(
                    children: networks
                        .where((n) =>
                            n['type'] != 'OVSBridge' &&
                            (n['address'] != null || n['address6'] != null))
                        .toList()
                        .asMap()
                        .entries
                        .map((entry) {
                      final i = entry.key;
                      final net = entry.value;
                      return Column(
                        key: ValueKey('iface_${name}_${net['iface']}_$i'),
                        children: [
                          if (i > 0) const _Divider(),
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: context.appColors.surface2,
                                    borderRadius:
                                        BorderRadius.circular(AppRadius.xs),
                                  ),
                                  child: Icon(Icons.lan_rounded,
                                      color: context.appColors.textSecondary,
                                      size: 14),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(net['iface'] ?? '',
                                          style: TextStyle(
                                              color:
                                                  context.appColors.textPrimary,
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600)),
                                      MetaLine([
                                        if (net['address'] != null)
                                          net['address'] as String,
                                        net['type'] ?? '-',
                                      ]),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      );
                    }).toList(),
                  ),
                ),
              ],
            ],
          ),
        ),

        const SizedBox(height: 16),
      ],
    );
  }
}

// ─────────────────────────────────────────────
// Yardımcı Widget'lar
// ─────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;
  final AppThemeData colors;

  const _SectionHeader({
    required this.title,
    required this.icon,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 16, 0, 8),
      child: Row(
        children: [
          Icon(icon, color: colors.textMuted, size: 14),
          const SizedBox(width: 6),
          SectionLabel(title),
        ],
      ),
    );
  }
}

class _CardContainer extends StatelessWidget {
  final Widget child;
  final EdgeInsets? margin;

  const _CardContainer({required this.child, this.margin});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      width: double.infinity,
      margin: margin ?? const EdgeInsets.only(bottom: AppSpace.sm),
      padding: const EdgeInsets.all(AppSpace.lg),
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: colors.hairline),
      ),
      child: child,
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return Divider(height: 20, color: context.appColors.hairline);
  }
}

class _InfoRowWidget extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final AppThemeData colors;

  const _InfoRowWidget({
    required this.label,
    required this.value,
    required this.icon,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: colors.textMuted, size: 14),
        const SizedBox(width: 10),
        Text(label,
            style: TextStyle(color: colors.textSecondary, fontSize: 12)),
        const Spacer(),
        Text(value,
            style: TextStyle(
                color: colors.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w500)),
      ],
    );
  }
}

class _InfoCard extends StatelessWidget {
  final AppThemeData colors;
  final String title;
  final IconData icon;
  final Widget child;

  const _InfoCard({
    required this.colors,
    required this.title,
    required this.icon,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpace.lg),
      decoration: BoxDecoration(
        color: colors.surface2,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: colors.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: colors.textMuted, size: 14),
              const SizedBox(width: 8),
              Text(title,
                  style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Resource Row
// ─────────────────────────────────────────────

class _ResourceRow extends StatefulWidget {
  final IconData icon;
  final String label;
  final double value;
  final String subtitle;
  final String? extra;
  final bool tappable;

  const _ResourceRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.subtitle,
    this.extra,
    this.tappable = false,
  });

  @override
  State<_ResourceRow> createState() => _ResourceRowState();
}

class _ResourceRowState extends State<_ResourceRow>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _anim;
  double _previousValue = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: AppMotion.base);
    _anim = Tween<double>(begin: 0, end: widget.value).animate(
        CurvedAnimation(parent: _controller, curve: AppMotion.curve));
    _previousValue = widget.value;
    _controller.forward();
  }

  @override
  void didUpdateWidget(_ResourceRow old) {
    super.didUpdateWidget(old);
    if ((old.value - widget.value).abs() > 0.5) {
      _anim = Tween<double>(begin: _previousValue, end: widget.value).animate(
          CurvedAnimation(parent: _controller, curve: AppMotion.curve));
      _previousValue = widget.value;
      _controller
        ..reset()
        ..forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) {
        final val = _anim.value;
        final animColor = colors.thresholdColor(val);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: animColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(AppRadius.xs),
                  ),
                  child: Icon(widget.icon, color: animColor, size: 14),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(widget.label,
                              style: TextStyle(
                                  color: colors.textPrimary,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13)),
                          const Spacer(),
                          Text('${val.toStringAsFixed(1)}%',
                              style: TextStyle(
                                  color: animColor,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13)),
                          if (widget.tappable) ...[
                            const SizedBox(width: 6),
                            Icon(Icons.show_chart_rounded,
                                color: animColor.withValues(alpha: 0.5),
                                size: 13),
                          ],
                        ],
                      ),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(AppRadius.xs),
                        child: LinearProgressIndicator(
                          value: (val / 100).clamp(0.0, 1.0),
                          backgroundColor: colors.surface2,
                          valueColor: AlwaysStoppedAnimation(animColor),
                          minHeight: 5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text(widget.subtitle,
                              style: TextStyle(
                                  color: colors.textMuted, fontSize: 10)),
                          if (widget.extra != null) ...[
                            const Spacer(),
                            Text(widget.extra!,
                                style: TextStyle(
                                    color: colors.textMuted, fontSize: 10)),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

// ─────────────────────────────────────────────
// Storage Card
// ─────────────────────────────────────────────

class _StorageCard extends StatefulWidget {
  final Map<String, dynamic> storage;
  final double percent;
  final int used, total;
  final Color Function(BuildContext, double) colorByPercent;
  final String Function(int) formatBytes;
  final VoidCallback onTap;

  const _StorageCard({
    super.key,
    required this.storage,
    required this.percent,
    required this.used,
    required this.total,
    required this.colorByPercent,
    required this.formatBytes,
    required this.onTap,
  });

  @override
  State<_StorageCard> createState() => _StorageCardState();
}

class _StorageCardState extends State<_StorageCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _anim;
  double _previousPercent = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: AppMotion.base);
    _anim = Tween<double>(begin: 0, end: widget.percent).animate(
        CurvedAnimation(parent: _controller, curve: AppMotion.curve));
    _previousPercent = widget.percent;
    _controller.forward();
  }

  @override
  void didUpdateWidget(_StorageCard old) {
    super.didUpdateWidget(old);
    if ((old.percent - widget.percent).abs() > 0.5) {
      _anim = Tween<double>(begin: _previousPercent, end: widget.percent)
          .animate(CurvedAnimation(parent: _controller, curve: AppMotion.curve));
      _previousPercent = widget.percent;
      _controller
        ..reset()
        ..forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return GestureDetector(
      onTap: widget.onTap,
      child: _CardContainer(
        child: AnimatedBuilder(
          animation: _anim,
          builder: (_, __) {
            final color = widget.colorByPercent(context, _anim.value);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.folder_rounded, color: color, size: 16),
                    const SizedBox(width: 8),
                    Text(widget.storage['storage'] ?? '',
                        style: TextStyle(
                            color: colors.textPrimary,
                            fontWeight: FontWeight.w600,
                            fontSize: 13)),
                    const Spacer(),
                    Text('${_anim.value.toStringAsFixed(0)}%',
                        style: TextStyle(
                            color: color, fontWeight: FontWeight.bold)),
                    const SizedBox(width: 8),
                    Icon(Icons.chevron_right_rounded,
                        color: colors.textMuted, size: 16),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.xs),
                  child: LinearProgressIndicator(
                    value: (_anim.value / 100).clamp(0.0, 1.0),
                    backgroundColor: colors.surface2,
                    valueColor: AlwaysStoppedAnimation(color),
                    minHeight: 5,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Text(
                        '${widget.formatBytes(widget.used)} / ${widget.formatBytes(widget.total)}',
                        style:
                            TextStyle(color: colors.textMuted, fontSize: 11)),
                    const Spacer(),
                    Text(widget.storage['type'] ?? '',
                        style:
                            TextStyle(color: colors.textMuted, fontSize: 11)),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Metrik Geçmiş Sheet
// ─────────────────────────────────────────────

class _MetricHistorySheet extends StatefulWidget {
  final ScrollController scrollCtrl;
  final String nodeName, metricType;
  final List<dynamic> rrd;

  const _MetricHistorySheet({
    required this.scrollCtrl,
    required this.nodeName,
    required this.metricType,
    required this.rrd,
  });

  @override
  State<_MetricHistorySheet> createState() => _MetricHistorySheetState();
}

class _MetricHistorySheetState extends State<_MetricHistorySheet>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(vsync: this, duration: AppMotion.slow);
    _anim = CurvedAnimation(parent: _animController, curve: AppMotion.curve);
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  double _getValue(Map<String, dynamic> point) {
    switch (widget.metricType) {
      case 'cpu':
        return ((point['cpu'] ?? 0) * 100).toDouble().clamp(0, 100);
      case 'mem':
        final total = (point['memtotal'] ?? point['maxmem'] ?? 1) as num;
        final used = (point['memused'] ?? point['mem'] ?? 0) as num;
        return total > 0 ? (used / total * 100).clamp(0, 100) : 0;
      case 'iowait':
        return ((point['iowait'] ?? 0) * 100).toDouble().clamp(0, 100);
      default:
        return 0;
    }
  }

  String get _title {
    switch (widget.metricType) {
      case 'cpu':
        return 'İşlemci Kullanımı';
      case 'mem':
        return 'Bellek Kullanımı';
      case 'iowait':
        return 'I/O Wait';
      default:
        return '';
    }
  }

  IconData get _icon {
    switch (widget.metricType) {
      case 'cpu':
        return Icons.memory_rounded;
      case 'mem':
        return Icons.developer_board_rounded;
      case 'iowait':
        return Icons.swap_vert_rounded;
      default:
        return Icons.bar_chart_rounded;
    }
  }

  Color _metricColor(BuildContext context) {
    final colors = context.appColors;
    switch (widget.metricType) {
      case 'cpu':
        return colors.primary;
      case 'mem':
        return colors.info;
      case 'iowait':
        // Not: bu metriğin kategori/kimlik rengidir — o anki iowait
        // değerinin gerçekten bir uyarı durumunda olduğu anlamına gelmez.
        // Önceden colors.warning kullanılıyordu, bu da %0 iowait'te bile
        // tüm sheet'i turuncuya boyuyordu — gerçek bir eşik uyarısı değil.
        return colors.primary;
      default:
        return colors.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final color = _metricColor(context);

    final validPoints = widget.rrd
        .where((p) => p != null && p['time'] != null)
        .map((p) => _getValue(p as Map<String, dynamic>))
        .toList();

    final avg = validPoints.isEmpty
        ? 0.0
        : validPoints.reduce((a, b) => a + b) / validPoints.length;
    final max =
        validPoints.isEmpty ? 0.0 : validPoints.reduce((a, b) => a > b ? a : b);
    final min =
        validPoints.isEmpty ? 0.0 : validPoints.reduce((a, b) => a < b ? a : b);
    final current = validPoints.isEmpty ? 0.0 : validPoints.last;

    return SingleChildScrollView(
      controller: widget.scrollCtrl,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: colors.textMuted.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Icon(_icon, color: color, size: 18),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_title,
                        style: TextStyle(
                            color: colors.textPrimary,
                            fontSize: 17,
                            fontWeight: FontWeight.bold)),
                    Text('Son 1 saat  •  ${widget.nodeName}',
                        style:
                            TextStyle(color: colors.textMuted, fontSize: 11)),
                  ],
                ),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: Text('${current.toStringAsFixed(1)}%',
                      style: TextStyle(
                          color: color,
                          fontSize: 16,
                          fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                    child: _StatCard(
                  label: 'Ortalama',
                  value: '${avg.toStringAsFixed(1)}%',
                  color: color,
                  colors: colors,
                  icon: Icons.show_chart_rounded,
                )),
                const SizedBox(width: 8),
                Expanded(
                    child: _StatCard(
                  label: 'Maksimum',
                  value: '${max.toStringAsFixed(1)}%',
                  color: colors.textSecondary,
                  colors: colors,
                  icon: Icons.arrow_upward_rounded,
                )),
                const SizedBox(width: 8),
                Expanded(
                    child: _StatCard(
                  label: 'Minimum',
                  value: '${min.toStringAsFixed(1)}%',
                  color: colors.textSecondary,
                  colors: colors,
                  icon: Icons.arrow_downward_rounded,
                )),
              ],
            ),
            const SizedBox(height: 24),
            if (validPoints.isEmpty)
              Container(
                height: 160,
                decoration: BoxDecoration(
                  color: colors.surface2,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.bar_chart_rounded,
                          color: colors.textMuted, size: 36),
                      const SizedBox(height: 8),
                      Text('Grafik verisi yok',
                          style:
                              TextStyle(color: colors.textMuted, fontSize: 13)),
                    ],
                  ),
                ),
              )
            else
              Container(
                padding: const EdgeInsets.all(AppSpace.lg),
                decoration: BoxDecoration(
                  color: colors.surface2,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(color: colors.hairline),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text('Zaman Serisi',
                            style: TextStyle(
                                color: colors.textMuted,
                                fontSize: 11,
                                letterSpacing: 0.5)),
                        const Spacer(),
                        Text('${validPoints.length} veri noktası',
                            style: TextStyle(
                                color: colors.textMuted, fontSize: 11)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    AnimatedBuilder(
                      animation: _anim,
                      builder: (_, __) => SizedBox(
                        height: 160,
                        child: CustomPaint(
                          painter: _AnimatedChartPainter(
                            values: validPoints,
                            color: color,
                            progress: _anim.value,
                            bgColor: colors.surface2,
                          ),
                          size: Size.infinite,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('1 saat önce',
                            style: TextStyle(
                                color: colors.textMuted, fontSize: 9)),
                        Text('30 dk önce',
                            style: TextStyle(
                                color: colors.textMuted, fontSize: 9)),
                        Text('Şimdi',
                            style: TextStyle(
                                color: colors.textMuted, fontSize: 9)),
                      ],
                    ),
                  ],
                ),
              ),
            if (validPoints.length >= 3) ...[
              const SizedBox(height: 20),
              Text('Son Değerler',
                  style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),
              Container(
                decoration: BoxDecoration(
                  color: colors.surface2,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(color: colors.hairline),
                ),
                child: Column(
                  children: validPoints.reversed
                      .take(8)
                      .toList()
                      .asMap()
                      .entries
                      .map((e) {
                    final idx = e.key;
                    final val = e.value;
                    final isLast = idx == validPoints.take(8).length - 1;
                    final barColor = colors.thresholdColor(val);
                    return Column(
                      key: ValueKey(idx),
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          child: Row(
                            children: [
                              Text(
                                idx == 0 ? 'Şimdi' : '${idx * 2} dk önce',
                                style: TextStyle(
                                    color: idx == 0
                                        ? colors.textPrimary
                                        : colors.textMuted,
                                    fontSize: 11,
                                    fontWeight: idx == 0
                                        ? FontWeight.w600
                                        : FontWeight.normal),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(AppRadius.xs),
                                  child: TweenAnimationBuilder<double>(
                                    tween: Tween(begin: 0, end: val / 100),
                                    duration: AppMotion.base +
                                        Duration(milliseconds: idx * 80),
                                    curve: AppMotion.curve,
                                    builder: (_, v, __) =>
                                        LinearProgressIndicator(
                                      value: v.clamp(0.0, 1.0),
                                      backgroundColor: colors.surface0,
                                      valueColor:
                                          AlwaysStoppedAnimation(barColor),
                                      minHeight: 5,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              SizedBox(
                                width: 44,
                                child: Text(
                                  '${val.toStringAsFixed(1)}%',
                                  textAlign: TextAlign.right,
                                  style: TextStyle(
                                      color: barColor,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (!isLast)
                          Divider(height: 1, color: colors.hairline),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label, value;
  final Color color;
  final AppThemeData colors;
  final IconData icon;

  const _StatCard({
    required this.label,
    required this.value,
    required this.color,
    required this.colors,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(height: 6),
          Text(value,
              style: TextStyle(
                  color: color, fontSize: 15, fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(color: colors.textMuted, fontSize: 10)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Animated Chart Painter
// ─────────────────────────────────────────────

class _AnimatedChartPainter extends CustomPainter {
  final List<double> values;
  final Color color;
  final double progress;
  final Color bgColor;

  const _AnimatedChartPainter({
    required this.values,
    required this.color,
    required this.progress,
    required this.bgColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;

    final maxVal = values.reduce((a, b) => a > b ? a : b);
    final chartMax = maxVal > 80
        ? 100.0
        : maxVal > 50
            ? 80.0
            : maxVal > 20
                ? 50.0
                : 30.0;

    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.05)
      ..strokeWidth = 1;

    for (int i = 0; i <= 4; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
      final label = '${(chartMax * (4 - i) / 4).toStringAsFixed(0)}%';
      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
              color: Colors.white.withValues(alpha: 0.25), fontSize: 8),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(2, y + 2));
    }

    final visibleCount = (values.length * progress).ceil();
    if (visibleCount < 2) return;

    final visibleValues = values.take(visibleCount).toList();
    final stepX = visibleValues.length > 1
        ? size.width / (values.length - 1).toDouble()
        : size.width;

    final fillPath = Path()..moveTo(0, size.height);
    for (int i = 0; i < visibleValues.length; i++) {
      final x = i * stepX;
      final y = size.height -
          (visibleValues[i] / chartMax * size.height).clamp(0.0, size.height);
      if (i == 0) {
        fillPath.lineTo(x, y);
      } else {
        final prevX = (i - 1) * stepX;
        final prevY = size.height -
            (visibleValues[i - 1] / chartMax * size.height)
                .clamp(0.0, size.height);
        final cpX = (prevX + x) / 2;
        fillPath.cubicTo(cpX, prevY, cpX, y, x, y);
      }
    }
    final lastX = (visibleValues.length - 1) * stepX;
    fillPath.lineTo(lastX, size.height);
    fillPath.close();

    canvas.drawPath(
      fillPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0.35), color.withValues(alpha: 0.0)],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
    );

    final linePaint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final linePath = Path();
    for (int i = 0; i < visibleValues.length; i++) {
      final x = i * stepX;
      final y = size.height -
          (visibleValues[i] / chartMax * size.height).clamp(0.0, size.height);
      if (i == 0) {
        linePath.moveTo(x, y);
      } else {
        final prevX = (i - 1) * stepX;
        final prevY = size.height -
            (visibleValues[i - 1] / chartMax * size.height)
                .clamp(0.0, size.height);
        final cpX = (prevX + x) / 2;
        linePath.cubicTo(cpX, prevY, cpX, y, x, y);
      }
    }
    canvas.drawPath(linePath, linePaint);

    if (visibleValues.isNotEmpty) {
      final lastY = size.height -
          (visibleValues.last / chartMax * size.height).clamp(0.0, size.height);
      canvas.drawCircle(Offset(lastX, lastY), 4, Paint()..color = color);
      canvas.drawCircle(Offset(lastX, lastY), 2, Paint()..color = Colors.white);
    }
  }

  @override
  bool shouldRepaint(_AnimatedChartPainter old) =>
      old.progress != progress ||
      old.values.length != values.length ||
      old.color != color;
}

// ─────────────────────────────────────────────
// Storage Detail Sheet
// ─────────────────────────────────────────────

class _StorageDetailSheet extends StatelessWidget {
  final String nodeName;
  final Map<String, dynamic> storage;
  final ScrollController scrollCtrl;

  const _StorageDetailSheet({
    required this.nodeName,
    required this.storage,
    required this.scrollCtrl,
  });

  String _formatBytes(int bytes) {
    if (bytes >= 1e12) return '${(bytes / 1e12).toStringAsFixed(1)} TB';
    if (bytes >= 1e9) return '${(bytes / 1e9).toStringAsFixed(1)} GB';
    if (bytes >= 1e6) return '${(bytes / 1e6).toStringAsFixed(1)} MB';
    return '$bytes B';
  }

  String _translateType(String type) {
    switch (type) {
      case 'dir':
        return 'Dizin';
      case 'zfspool':
        return 'ZFS Pool';
      case 'lvm':
        return 'LVM';
      case 'lvmthin':
        return 'LVM-Thin';
      case 'nfs':
        return 'NFS';
      case 'cifs':
        return 'CIFS/SMB';
      case 'btrfs':
        return 'Btrfs';
      default:
        return type.toUpperCase();
    }
  }

  List<String> _parseContentTypes(dynamic content) {
    if (content == null) return [];
    return content.toString().split(',').map((s) => s.trim()).toList();
  }

  String _contentTypeLabel(String type) {
    switch (type) {
      case 'backup':
        return 'Yedek';
      case 'iso':
        return 'ISO';
      case 'images':
        return 'Disk İmajı';
      case 'rootdir':
        return 'Root FS';
      case 'vztmpl':
        return 'CT Şablonu';
      case 'snippets':
        return 'Snippet';
      default:
        return type;
    }
  }

  IconData _contentTypeIcon(String type) {
    switch (type) {
      case 'backup':
        return Icons.backup_rounded;
      case 'iso':
        return Icons.album_rounded;
      case 'images':
        return Icons.save_rounded;
      case 'rootdir':
        return Icons.folder_rounded;
      case 'vztmpl':
        return Icons.view_in_ar_rounded;
      case 'snippets':
        return Icons.code_rounded;
      default:
        return Icons.storage_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final name = storage['storage'] as String? ?? '';
    final type = storage['type'] as String? ?? '-';
    final used = (storage['used'] ?? 0) as int;
    final total = (storage['total'] ?? 1) as int;
    final avail = (storage['avail'] ?? 0) as int;
    final percent = total > 0 ? used / total * 100 : 0.0;
    final active = storage['active'] == 1;
    final shared = storage['shared'] == 1;
    final contentTypes = _parseContentTypes(storage['content']);

    final barColor = colors.thresholdColor(percent);

    return SingleChildScrollView(
      controller: scrollCtrl,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: colors.textMuted.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: colors.surface2,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Icon(Icons.storage_rounded,
                      color: colors.textSecondary, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name,
                          style: TextStyle(
                              color: colors.textPrimary,
                              fontSize: 18,
                              fontWeight: FontWeight.bold)),
                      MetaLine([nodeName, _translateType(type)]),
                    ],
                  ),
                ),
                StatusIndicator(
                  color: active ? colors.success : colors.error,
                  label: active ? 'Aktif' : 'Pasif',
                  style: colors.meta,
                ),
              ],
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colors.surface2,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: colors.hairline),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('Disk Kullanımı',
                          style: TextStyle(
                              color: colors.textSecondary,
                              fontSize: 12,
                              fontWeight: FontWeight.w600)),
                      const Spacer(),
                      TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0, end: percent),
                        duration: AppMotion.base,
                        curve: AppMotion.curve,
                        builder: (_, val, __) => Text(
                          '%${val.toStringAsFixed(1)}',
                          style: TextStyle(
                              color: barColor,
                              fontSize: 16,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: percent / 100),
                    duration: AppMotion.base,
                    curve: AppMotion.curve,
                    builder: (_, val, __) => ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadius.xs),
                      child: LinearProgressIndicator(
                        value: val.clamp(0.0, 1.0),
                        backgroundColor: colors.surface0,
                        valueColor: AlwaysStoppedAnimation(barColor),
                        minHeight: 10,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                          child: _DiskStatTile(
                        label: 'Toplam',
                        value: _formatBytes(total),
                        icon: Icons.circle_outlined,
                        color: colors.textSecondary,
                        colors: colors,
                      )),
                      Expanded(
                          child: _DiskStatTile(
                        label: 'Kullanılan',
                        value: _formatBytes(used),
                        icon: Icons.circle,
                        color: barColor,
                        colors: colors,
                      )),
                      Expanded(
                          child: _DiskStatTile(
                        label: 'Boş',
                        value: _formatBytes(avail),
                        icon: Icons.circle,
                        color: colors.textSecondary,
                        colors: colors,
                      )),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colors.surface2,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: colors.hairline),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Depolama Bilgisi',
                      style: TextStyle(
                          color: colors.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 12),
                  _InfoRowWidget(
                      label: 'Tür',
                      value: _translateType(type),
                      icon: Icons.folder_rounded,
                      colors: colors),
                  Divider(height: 16, color: colors.hairline),
                  _InfoRowWidget(
                      label: 'Paylaşımlı',
                      value: shared ? 'Evet' : 'Hayır',
                      icon: Icons.share_rounded,
                      colors: colors),
                  Divider(height: 16, color: colors.hairline),
                  _InfoRowWidget(
                      label: 'Durum',
                      value: active ? 'Aktif' : 'Pasif',
                      icon: Icons.circle,
                      colors: colors),
                  if (storage['path'] != null) ...[
                    Divider(height: 16, color: colors.hairline),
                    _InfoRowWidget(
                        label: 'Yol',
                        value: storage['path'].toString(),
                        icon: Icons.folder_open_rounded,
                        colors: colors),
                  ],
                ],
              ),
            ),
            if (contentTypes.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(AppSpace.lg),
                decoration: BoxDecoration(
                  color: colors.surface2,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(color: colors.hairline),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Desteklenen İçerikler',
                        style: TextStyle(
                            color: colors.textSecondary,
                            fontSize: 12,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: contentTypes
                          .map((ct) => Container(
                                key: ValueKey(ct),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: colors.surface2,
                                  borderRadius:
                                      BorderRadius.circular(AppRadius.xs),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(_contentTypeIcon(ct),
                                        color: colors.textSecondary, size: 13),
                                    const SizedBox(width: 6),
                                    Text(_contentTypeLabel(ct),
                                        style: TextStyle(
                                            color: colors.textSecondary,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600)),
                                  ],
                                ),
                              ))
                          .toList(),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DiskStatTile extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color color;
  final AppThemeData colors;

  const _DiskStatTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: color, size: 10),
        const SizedBox(height: 4),
        Text(value,
            style: TextStyle(
                color: color, fontSize: 12, fontWeight: FontWeight.bold)),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(color: colors.textMuted, fontSize: 10)),
      ],
    );
  }
}

// ─────────────────────────────────────────────
// Operation Overlay
// ─────────────────────────────────────────────

