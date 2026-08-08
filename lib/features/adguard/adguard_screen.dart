import 'package:flutter/material.dart';
import '../../core/utils/app_transitions.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/services/connectivity_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/design_widgets.dart';
import '../../core/utils/connection_target.dart';
import '../../core/widgets/connection_issue_view.dart';
import '../../shared/widgets/connection_error_view.dart';
import 'adguard_provider.dart';

/// Toggle işlemi sürerken Switch'in yerine geçen küçük, sakin gösterge —
/// tam ekran overlay yerine, tek bir toggle için hafif inline geri bildirim.
Widget _switchSlot(AppThemeData colors,
    {required bool loading, required Widget child}) {
  if (!loading) return child;
  return SizedBox(
    width: 34,
    height: 20,
    child: Center(
      child: SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(strokeWidth: 2, color: colors.primary),
      ),
    ),
  );
}

class AdGuardScreen extends StatefulWidget {
  const AdGuardScreen({super.key});

  @override
  State<AdGuardScreen> createState() => _AdGuardScreenState();
}

class _AdGuardScreenState extends State<AdGuardScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    // Sadece index değişince rebuild et, animasyon sırasında değil
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) setState(() {});
    });
    final provider = context.read<AdGuardProvider>();
    Future.microtask(() => provider.init());
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AdGuardProvider>();

    if (!provider.isConfigured) {
      if (provider.needsCredentials) {
        return _AdGuardCredentialMissingCard(
          onTap: () => appShowModalBottomSheet(
            context: context,
            backgroundColor: context.appColors.surface1,
            isScrollControlled: true,
            shape: const RoundedRectangleBorder(
              borderRadius:
                  BorderRadius.vertical(top: Radius.circular(AppRadius.md)),
            ),
            builder: (_) => const _AdGuardFormScreen(isEdit: true),
          ),
        );
      }
      return const _AdGuardFormScreen(isEdit: false);
    }

    // Sunucu tanımlı ama hiç veri gelmemiş (ilk yükleme başarısız oldu) —
    // önceden bu durumda içerik sıfır değerlerle "her şey yolunda" gibi
    // görünüyordu. Artık açıkça bağlantı hatası gösteriliyor.
    if (!provider.isConnected && !provider.isLoading && !provider.isStale) {
      final hasInternet =
          context.watch<ConnectivityProvider>().hasInternet;
      // İnternet hiç yoksa bu ayrımın bir anlamı yok — eski/genel davranış
      // aynen korunuyor (home_screen'deki tam-ekran overlay zaten üstünü
      // kaplayacağı için bu görünmez, ama davranış değişmiyor).
      if (!hasInternet) {
        return ConnectionErrorView(onRetry: () => provider.refresh());
      }

      final host = provider.lastFailedHost ?? '';
      final kind = switch (classifyHost(host)) {
        ConnectionTarget.privateNetwork => ConnectionIssueKind.privateNetwork,
        ConnectionTarget.tailscale => ConnectionIssueKind.tailscale,
        ConnectionTarget.external => ConnectionIssueKind.generic,
      };
      return ConnectionIssueView(
        kind: kind,
        serviceName: 'AdGuard',
        host: host,
        onRetry: () => provider.refresh(),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _TabChip(
                  label: 'Dashboard',
                  icon: Icons.dashboard_outlined,
                  selected: _tabController.index == 0,
                  onTap: () => setState(() => _tabController.animateTo(0)),
                ),
                const SizedBox(width: 8),
                _TabChip(
                  label: 'Sorgular',
                  icon: Icons.search,
                  selected: _tabController.index == 1,
                  onTap: () {
                    setState(() => _tabController.animateTo(1));
                    provider.loadQueryLog(reset: true);
                  },
                ),
                const SizedBox(width: 8),
                _TabChip(
                  label: 'Filtreler',
                  icon: Icons.filter_list,
                  selected: _tabController.index == 2,
                  onTap: () {
                    setState(() => _tabController.animateTo(2));
                    provider.loadFilters();
                  },
                ),
                const SizedBox(width: 8),
                _TabChip(
                  label: 'Ayarlar',
                  icon: Icons.tune,
                  selected: _tabController.index == 3,
                  onTap: () {
                    setState(() => _tabController.animateTo(3));
                    provider.loadFeatures();
                  },
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: const [
              _DashboardTab(),
              _QueryLogTab(),
              _FiltersTab(),
              _SettingsTab(),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── Unified form: hem setup ekranı hem de düzenleme sheet'i ──────────────────

/// AdGuard bağlantısı başka bir cihazda kuruldu (URL cloud'dan geldi) ama
/// kullanıcı adı/şifre bu cihazda hiç girilmemiş — "hiç yapılandırılmamış"
/// boş ekranından kasıtlı olarak ayrı: hiç sorgu atılmadı, sadece kimlik
/// bilgisi eksik (bkz. credential_sync.dart).
class _AdGuardCredentialMissingCard extends StatelessWidget {
  final VoidCallback onTap;

  const _AdGuardCredentialMissingCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: colors.surface1,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: colors.hairline),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.key_off_rounded, color: colors.warning, size: 32),
                const SizedBox(height: 12),
                Text('Kimlik Bilgisi Gerekli',
                    style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Text(
                  'Bu AdGuard bağlantısı başka bir cihazda kuruldu — kullanıcı adı/şifre girmek için dokunun',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: colors.textMuted, fontSize: 12.5),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AdGuardFormScreen extends StatefulWidget {
  final bool isEdit;

  const _AdGuardFormScreen({required this.isEdit});

  @override
  State<_AdGuardFormScreen> createState() => _AdGuardFormScreenState();
}

class _AdGuardFormScreenState extends State<_AdGuardFormScreen> {
  final _primaryCtrl = TextEditingController();
  final _secondaryCtrl = TextEditingController();
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _loading = false;
  bool? _success;
  String _errorMsg = '';

  @override
  void initState() {
    super.initState();
    if (widget.isEdit) _loadExisting();
  }

  Future<void> _loadExisting() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _primaryCtrl.text = prefs.getString('adguard_primary_url') ?? '';
      _secondaryCtrl.text = prefs.getString('adguard_secondary_url') ?? '';
      _userCtrl.text = prefs.getString('adguard_username') ?? '';
      _passCtrl.text = prefs.getString('adguard_password') ?? '';
    });
  }

  @override
  void dispose() {
    _primaryCtrl.dispose();
    _secondaryCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_primaryCtrl.text.trim().isEmpty || _userCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Lütfen zorunlu alanları doldurun'),
        backgroundColor: context.appColors.error,
      ));
      return;
    }

    setState(() {
      _loading = true;
      _success = null;
      _errorMsg = '';
    });

    try {
      await context.read<AdGuardProvider>().saveConfig(
            primaryUrl: _primaryCtrl.text.trim(),
            secondaryUrl: _secondaryCtrl.text.trim(),
            username: _userCtrl.text.trim(),
            password: _passCtrl.text.trim(),
          );
      if (!mounted) return;
      setState(() {
        _loading = false;
        _success = true;
      });
      if (widget.isEdit) Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _success = false;
        _errorMsg = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    final content = SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        20,
        widget.isEdit ? 8 : 20,
        20,
        widget.isEdit ? MediaQuery.of(context).viewInsets.bottom + 20 : 20,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.isEdit) ...[
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: colors.textMuted,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Bağlantı Ayarları',
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ] else ...[
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colors.surface2,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Icon(Icons.shield_outlined,
                      color: colors.textSecondary, size: 24),
                ),
                const SizedBox(width: 14),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'AdGuard Home',
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Bağlantı kurulmamış',
                      style: TextStyle(color: colors.textMuted, fontSize: 12),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(14),
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
                      Icon(Icons.info_outline,
                          color: colors.textSecondary, size: 16),
                      const SizedBox(width: 8),
                      Text(
                        'Bağlantı Bilgisi',
                        style: TextStyle(
                          color: colors.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '• İç ağ ve dış ağ için iki farklı URL girebilirsin\n'
                    '• Erişilemeyen URL otomatik atlanır\n'
                    '• URL formatı: http://IP:PORT\n'
                    '• Varsayılan port 3000\'dir, farklıysa belirt\n'
                    '• Örnek: http://192.168.1.10:80',
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: 12,
                      height: 1.6,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 20),
          _FormField(
            label: 'Birincil URL *',
            controller: _primaryCtrl,
            hint: 'http://192.168.1.x:3000',
            fillColor: colors.surface2,
          ),
          _FormField(
            label: 'İkincil URL (opsiyonel)',
            controller: _secondaryCtrl,
            hint: 'https://adguard.domain.com',
            fillColor: colors.surface2,
          ),
          _FormField(
            label: 'Kullanıcı Adı *',
            controller: _userCtrl,
            hint: 'admin',
            fillColor: colors.surface2,
          ),
          _FormField(
            label: 'Şifre *',
            controller: _passCtrl,
            hint: '••••••••',
            obscure: true,
            fillColor: colors.surface2,
          ),
          const SizedBox(height: 20),
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else ...[
            if (_success == false)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colors.errorMuted,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(color: colors.error.withValues(alpha: 0.2)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, color: colors.error, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorMsg,
                        style: TextStyle(color: colors.error, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _submit,
                icon: Icon(
                  widget.isEdit ? Icons.save : Icons.link,
                  color: Colors.white,
                  size: 16,
                ),
                label: Text(
                  widget.isEdit ? 'Kaydet' : 'Bağlan',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: colors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );

    return content;
  }
}

// ─── Reusable form field ───────────────────────────────────────────────────────

class _FormField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String hint;
  final bool obscure;
  final Color? fillColor;

  const _FormField({
    required this.label,
    required this.controller,
    required this.hint,
    this.obscure = false,
    this.fillColor,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        obscureText: obscure,
        style: TextStyle(color: colors.textPrimary, fontSize: 14),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          labelStyle: TextStyle(color: colors.textSecondary, fontSize: 13),
          hintStyle: TextStyle(color: colors.textMuted, fontSize: 13),
          filled: true,
          fillColor: fillColor ?? colors.surface2,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            borderSide: BorderSide(color: colors.primary, width: 1.5),
          ),
        ),
      ),
    );
  }
}

// ─── Dashboard Tab ────────────────────────────────────────────────────────────

class _DashboardTab extends StatelessWidget {
  const _DashboardTab();
  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final provider = context.watch<AdGuardProvider>();
    final stats = provider.stats;
    final status = provider.status;
    final total = stats['num_dns_queries'] ?? 0;
    final blocked = stats['num_blocked_filtering'] ?? 0;
    final pct = total > 0 ? (blocked / total * 100).toStringAsFixed(1) : '0.0';
    final avg = stats['avg_processing_time'] ?? 0.0;
    final isProtected = status['protection_enabled'] ?? true;

    return RefreshIndicator(
      onRefresh: () => provider.refresh(),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
        children: [
          if (provider.isStale)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: colors.warningMuted,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: colors.warning.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded, size: 14, color: colors.warning),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      provider.lastSuccessAt != null
                          ? 'Sunucuya ulaşılamıyor — son güncelleme: '
                              '${provider.lastSuccessAt!.hour.toString().padLeft(2, '0')}:'
                              '${provider.lastSuccessAt!.minute.toString().padLeft(2, '0')}'
                          : 'Sunucuya ulaşılamıyor — eski veriler gösteriliyor',
                      style: TextStyle(
                          color: colors.warning,
                          fontSize: 11,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colors.surface1,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: colors.hairline),
            ),
            child: Row(
              children: [
                Icon(
                  isProtected ? Icons.shield : Icons.shield_outlined,
                  color: isProtected ? colors.success : colors.error,
                  size: 22,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      StatusIndicator(
                        color: isProtected ? colors.success : colors.error,
                        label: isProtected ? 'Koruma Aktif' : 'Koruma Devre Dışı',
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        isProtected
                            ? 'AdGuard Home reklamları engelliyor'
                            : 'Tüm sorgular filtresiz geçiyor',
                        style: TextStyle(color: colors.textMuted, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                _switchSlot(
                  colors,
                  loading: provider.loadingToggles.contains('protection'),
                  child: Switch(
                    value: isProtected,
                    onChanged: (_) => provider.toggleProtection(),
                    activeThumbColor: colors.success,
                    inactiveThumbColor: colors.error,
                  ),
                ),
              ],
            ),
          ),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 1.4,
            children: [
              _StatCard(
                icon: Icons.dns_outlined,
                label: 'Toplam Sorgu',
                value: _fmtNum(total),
                rawValue: total.toDouble(),
              ),
              _StatCard(
                icon: Icons.block,
                label: 'Engellenen',
                value: _fmtNum(blocked),
                rawValue: blocked.toDouble(),
                subtitle: '%$pct',
              ),
              _StatCard(
                icon: Icons.check_circle_outline,
                label: 'Güvenli Arama',
                value: _fmtNum(stats['num_replaced_safesearch'] ?? 0),
                rawValue: (stats['num_replaced_safesearch'] ?? 0).toDouble(),
              ),
              _StatCard(
                icon: Icons.timer_outlined,
                label: 'Ort. Süre',
                value: '${((avg as num) * 1000).toStringAsFixed(1)}ms',
                rawValue: ((avg) * 1000).toDouble(),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if ((stats['top_queried_domains'] as List?)?.isNotEmpty ?? false) ...[
            const _SectionHeader('En Çok Sorgulanan'),
            _TopList(
              items: (stats['top_queried_domains'] as List).take(5).toList(),
            ),
            const SizedBox(height: 16),
          ],
          if ((stats['top_blocked_domains'] as List?)?.isNotEmpty ?? false) ...[
            const _SectionHeader('En Çok Engellenen'),
            _TopList(
              items: (stats['top_blocked_domains'] as List).take(5).toList(),
            ),
            const SizedBox(height: 16),
          ],
          if ((stats['top_clients'] as List?)?.isNotEmpty ?? false) ...[
            const _SectionHeader('En Aktif İstemciler'),
            _TopList(
              items: (stats['top_clients'] as List).take(5).toList(),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Shared formatter ────────────────────────────────────────────────────────

String _fmtNum(num val) {
  if (val >= 1000000) return '${(val / 1000000).toStringAsFixed(1)}M';
  if (val >= 1000) return '${(val / 1000).toStringAsFixed(1)}K';
  return val.toInt().toString();
}

// ─── Stat Card ────────────────────────────────────────────────────────────────

/// Sistem Özeti'ndeki (system_screen.dart) düz istatistik şeridiyle aynı
/// mantık: tek tek renkli/kutulu "kart" yerine nötr ikon+değer+etiket —
/// bu sayılar bir durum değil, sade birer sayaç.
class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final double rawValue;
  final String? subtitle;

  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.rawValue,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      padding: const EdgeInsets.all(14),
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
              Icon(icon, color: colors.textMuted, size: 16),
              const Spacer(),
              if (subtitle != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: colors.surface2,
                    borderRadius: BorderRadius.circular(AppRadius.xs),
                  ),
                  child: Text(
                    subtitle!,
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
          const Spacer(),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: rawValue),
            duration: AppMotion.slow,
            curve: AppMotion.curve,
            builder: (_, val, __) => Text(
              _fmtNum(val),
              style: colors.metric,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(color: colors.textMuted, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

// ─── Section Header ───────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: TextStyle(
          color: context.appColors.textSecondary,
          fontSize: 13,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

// ─── Top List ─────────────────────────────────────────────────────────────────

class _TopList extends StatelessWidget {
  final List items;

  const _TopList({required this.items});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: colors.hairline),
      ),
      child: Column(
        children: items.asMap().entries.map((e) {
          final item = e.value as Map;
          final key = item.keys.first as String;
          final count = item.values.first as int;
          final isLast = e.key == items.length - 1;

          return Container(
            key: ValueKey(key),
            decoration: BoxDecoration(
              border: isLast
                  ? null
                  : Border(bottom: BorderSide(color: colors.hairline)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                SizedBox(
                  width: 20,
                  child: Text(
                    '${e.key + 1}',
                    style: TextStyle(
                      color: colors.textMuted,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    key,
                    style: TextStyle(color: colors.textPrimary, fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  '$count',
                  style: colors.metricSmall,
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ─── Query Log Tab ────────────────────────────────────────────────────────────

class _QueryLogTab extends StatefulWidget {
  const _QueryLogTab();

  @override
  State<_QueryLogTab> createState() => _QueryLogTabState();
}

class _QueryLogTabState extends State<_QueryLogTab> {
  final _searchCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
  }

  void _onScroll() {
    if (_scrollCtrl.position.pixels >=
        _scrollCtrl.position.maxScrollExtent - 200) {
      context.read<AdGuardProvider>().loadQueryLog();
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _scrollCtrl
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  Color _statusColor(String reason) {
    final colors = context.appColors;
    switch (reason) {
      case 'FilteredBlackList':
      case 'FilteredBlockedService':
        return colors.error;
      case 'FilteredSafeBrowsing':
      case 'FilteredParental':
      case 'FilteredSafeSearch':
        return colors.warning;
      case 'ReasonRewrite':
      case 'Rewrite':
        return colors.info;
      case 'NotFilteredWhiteList':
        return colors.success;
      default:
        return colors.textMuted;
    }
  }

  String _statusLabel(Map<String, dynamic> entry) {
    switch (entry['reason'] ?? '') {
      case 'FilteredBlackList':
        return 'ENGELLENDİ';
      case 'FilteredBlockedService':
        return 'SERVİS ENGELLİ';
      case 'FilteredSafeBrowsing':
        return 'SAFE BROWSE';
      case 'FilteredParental':
        return 'EBEVEYN';
      case 'FilteredSafeSearch':
        return 'SAFE SEARCH';
      case 'ReasonRewrite':
      case 'Rewrite':
        return 'YÖNLENDİRİLDİ';
      case 'NotFilteredWhiteList':
        return 'İZİN VERİLDİ';
      default:
        return 'İŞLENDİ';
    }
  }

  String _formatTime(String? timeStr) {
    if (timeStr == null) return '-';
    try {
      final dt = DateTime.parse(timeStr).toLocal();
      return '${dt.hour.toString().padLeft(2, '0')}:'
          '${dt.minute.toString().padLeft(2, '0')}:'
          '${dt.second.toString().padLeft(2, '0')}';
    } catch (_) {
      return '-';
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final provider = context.watch<AdGuardProvider>();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  style: TextStyle(color: colors.textPrimary, fontSize: 13),
                  onSubmitted: (v) {
                    provider.setQueryLogSearch(v);
                  },
                  decoration: InputDecoration(
                    hintText: 'Domain ara...',
                    hintStyle: TextStyle(color: colors.textMuted, fontSize: 13),
                    prefixIcon:
                        Icon(Icons.search, color: colors.textMuted, size: 18),
                    suffixIcon: _searchCtrl.text.isNotEmpty
                        ? IconButton(
                            icon: Icon(Icons.clear,
                                color: colors.textMuted, size: 16),
                            onPressed: () {
                              _searchCtrl.clear();
                              provider.setQueryLogSearch('');
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: colors.surface2,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              PopupMenuButton<String>(
                color: colors.surface1,
                icon: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: colors.surface2,
                    borderRadius: BorderRadius.circular(AppRadius.xs),
                  ),
                  child: Icon(Icons.filter_list,
                      color: colors.textSecondary, size: 20),
                ),
                onSelected: (v) {
                  provider.setQueryLogFilter(v);
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'all',
                    child: Text('Tümü',
                        style: TextStyle(color: colors.textPrimary)),
                  ),
                  PopupMenuItem(
                    value: 'filtered',
                    child: Text('Engellenenler',
                        style: TextStyle(color: colors.textPrimary)),
                  ),
                  PopupMenuItem(
                    value: 'processed',
                    child: Text('İşlenenler',
                        style: TextStyle(color: colors.textPrimary)),
                  ),
                  PopupMenuItem(
                    value: 'whitelisted',
                    child: Text('İzin Verilenler',
                        style: TextStyle(color: colors.textPrimary)),
                  ),
                ],
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Row(
            children: [
              Text(
                '${provider.queryLog.length} kayıt',
                style: TextStyle(color: colors.textMuted, fontSize: 11),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: () => provider.clearQueryLog(),
                icon: Icon(Icons.delete_outline, color: colors.error, size: 14),
                label: Text('Temizle',
                    style: TextStyle(color: colors.error, fontSize: 12)),
                style: TextButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: provider.queryLog.isEmpty && !provider.queryLogLoading
              ? Center(
                  child: Text(
                    'Sorgu bulunamadı',
                    style: TextStyle(color: colors.textMuted),
                  ),
                )
              : ListView.builder(
                  controller: _scrollCtrl,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
                  itemCount: provider.queryLog.length +
                      (provider.queryLogLoading ? 1 : 0),
                  itemBuilder: (ctx, i) {
                    if (i == provider.queryLog.length) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(16),
                          child: CircularProgressIndicator(),
                        ),
                      );
                    }

                    final entry = provider.queryLog[i] as Map<String, dynamic>;
                    final question = entry['question'] as Map? ?? {};
                    final domain = question['name'] ?? '-';
                    final qtype = question['type'] ?? 'A';
                    final client = entry['client'] ?? '-';
                    final time = _formatTime(entry['time'] as String?);
                    final elapsedMs =
                        ((entry['elapsed_ms'] ?? 0) as num).toDouble();
                    final color = _statusColor(entry['reason'] ?? '');
                    final label = _statusLabel(entry);

                    return Container(
                      key: ValueKey('${entry['time']}_${domain}_$i'),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        border:
                            Border(bottom: BorderSide(color: colors.hairline)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration:
                                BoxDecoration(color: color, shape: BoxShape.circle),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  domain,
                                  style: TextStyle(
                                    color: colors.textPrimary,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                MetaLine([client, time],
                                    style: TextStyle(
                                        color: colors.textMuted, fontSize: 10)),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: color.withValues(alpha: 0.12),
                                  borderRadius:
                                      BorderRadius.circular(AppRadius.xs),
                                ),
                                child: Text(
                                  label,
                                  style: TextStyle(
                                    color: color,
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${elapsedMs.toStringAsFixed(1)}ms  $qtype',
                                style: TextStyle(
                                  color: colors.textMuted,
                                  fontSize: 9,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

// ─── Filters Tab ──────────────────────────────────────────────────────────────

class _FiltersTab extends StatelessWidget {
  const _FiltersTab();

  void _showAddFilterDialog(
    BuildContext context,
    AdGuardProvider provider,
    bool whitelist,
  ) {
    final colors = context.appColors;
    final nameCtrl = TextEditingController();
    final urlCtrl = TextEditingController();

    appShowModalBottomSheet<void>(
      context: context,
      backgroundColor: colors.surface1,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.md)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          MediaQuery.of(ctx).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: colors.textMuted,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              whitelist ? 'İzin Listesi Ekle' : 'Engelleme Listesi Ekle',
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Filtre listesi adı ve URL\'sini girin',
              style: TextStyle(color: colors.textMuted, fontSize: 12),
            ),
            const SizedBox(height: 16),
            Text(
              'Popüler Listeler',
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _QuickFilterChip(
                    name: 'AdGuard Base',
                    url: 'https://adguardteam.github.io/AdGuardSDNSFilter/Filters/filter.txt',
                    nameCtrl: nameCtrl,
                    urlCtrl: urlCtrl,
                  ),
                  _QuickFilterChip(
                    name: 'EasyList',
                    url: 'https://easylist.to/easylist/easylist.txt',
                    nameCtrl: nameCtrl,
                    urlCtrl: urlCtrl,
                  ),
                  _QuickFilterChip(
                    name: 'uBlock Origin',
                    url: 'https://ublockorigin.github.io/uAssets/filters/filters.txt',
                    nameCtrl: nameCtrl,
                    urlCtrl: urlCtrl,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _FormField(
              label: 'Liste Adı *',
              controller: nameCtrl,
              hint: 'Örn: AdGuard Base Filter',
              fillColor: colors.surface2,
            ),
            _FormField(
              label: 'Liste URL *',
              controller: urlCtrl,
              hint: 'https://example.com/filter.txt',
              fillColor: colors.surface2,
            ),
            const SizedBox(height: 4),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () async {
                  if (nameCtrl.text.trim().isEmpty ||
                      urlCtrl.text.trim().isEmpty) {
                    return;
                  }
                  Navigator.pop(ctx);
                  await provider.addFilter(
                    urlCtrl.text.trim(),
                    nameCtrl.text.trim(),
                    whitelist: whitelist,
                  );
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: const Text('Filtre eklendi'),
                        backgroundColor: colors.success,
                      ),
                    );
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: colors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                ),
                child: const Text(
                  'Ekle',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ).whenComplete(() {
      nameCtrl.dispose();
      urlCtrl.dispose();
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final provider = context.watch<AdGuardProvider>();

    return RefreshIndicator(
      onRefresh: () => provider.loadFilters(),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
        children: [
          Row(
            children: [
              const SectionLabel('Engelleme Listeleri'),
              const Spacer(),
              TextButton.icon(
                onPressed: () => provider.refreshFilters(),
                icon: Icon(Icons.refresh, color: colors.primary, size: 14),
                label: Text('Güncelle',
                    style: TextStyle(color: colors.primary, fontSize: 12)),
              ),
              TextButton.icon(
                onPressed: () => _showAddFilterDialog(context, provider, false),
                icon: Icon(Icons.add, color: colors.success, size: 14),
                label: Text('Ekle',
                    style: TextStyle(color: colors.success, fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (provider.filters.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  'Filtre listesi boş',
                  style: TextStyle(color: colors.textMuted),
                ),
              ),
            )
          else
            ...provider.filters.map(
              (f) => _FilterCard(filter: f, whitelist: false),
            ),
          if (provider.whitelistFilters.isNotEmpty) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                const SectionLabel('İzin Listeleri'),
                const Spacer(),
                TextButton.icon(
                  onPressed: () =>
                      _showAddFilterDialog(context, provider, true),
                  icon: Icon(Icons.add, color: colors.success, size: 14),
                  label: Text('Ekle',
                      style: TextStyle(color: colors.success, fontSize: 12)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ...provider.whitelistFilters.map(
              (f) => _FilterCard(filter: f, whitelist: true),
            ),
          ],
          if (provider.userRules.isNotEmpty) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                const SectionLabel('Özel Kurallar'),
                const Spacer(),
                Text(
                  '${provider.userRules.length} kural',
                  style: TextStyle(color: colors.textMuted, fontSize: 11),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: colors.surface1,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: colors.hairline),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: provider.userRules
                    .take(10)
                    .map(
                      (rule) => Padding(
                        key: ValueKey(rule),
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          rule,
                          style: TextStyle(
                            color: colors.textSecondary,
                            fontSize: 12,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Quick Filter Chip ────────────────────────────────────────────────────────

class _QuickFilterChip extends StatelessWidget {
  final String name;
  final String url;
  final TextEditingController nameCtrl;
  final TextEditingController urlCtrl;

  const _QuickFilterChip({
    required this.name,
    required this.url,
    required this.nameCtrl,
    required this.urlCtrl,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return GestureDetector(
      onTap: () {
        nameCtrl.text = name;
        urlCtrl.text = url;
      },
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: colors.surface2,
          borderRadius: BorderRadius.circular(AppRadius.xs),
          border: Border.all(color: colors.hairline),
        ),
        child: Text(
          name,
          style: TextStyle(
            color: colors.textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

// ─── Filter Card ──────────────────────────────────────────────────────────────

class _FilterCard extends StatelessWidget {
  final Map<String, dynamic> filter;
  final bool whitelist;

  const _FilterCard({
    required this.filter,
    required this.whitelist,
  });

  String _formatDate(String? s) {
    if (s == null || s.isEmpty) return '-';
    try {
      final dt = DateTime.parse(s).toLocal();
      return '${dt.day}.${dt.month}.${dt.year}';
    } catch (_) {
      return '-';
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final provider = context.watch<AdGuardProvider>();
    final enabled = filter['enabled'] ?? false;
    final name = filter['name'] ?? 'İsimsiz';
    final url = filter['url'] ?? '';
    final rulesCount = filter['rules_count'] ?? 0;
    final lastUpdated = filter['last_updated'] ?? '';

    return Container(
      key: ValueKey(url),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
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
                  name,
                  style: TextStyle(
                    color: enabled ? colors.textPrimary : colors.textMuted,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  url,
                  style: TextStyle(color: colors.textMuted, fontSize: 10),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                MetaLine(
                  ['$rulesCount kural', _formatDate(lastUpdated)],
                  style: TextStyle(color: colors.textMuted, fontSize: 10),
                ),
              ],
            ),
          ),
          _switchSlot(
            colors,
            loading: provider.loadingToggles.contains('filter_${filter['id']}'),
            child: Switch(
              value: enabled,
              onChanged: (_) =>
                  provider.toggleFilter(Map<String, dynamic>.from(filter)),
              activeThumbColor: whitelist ? colors.success : colors.primary,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Settings Tab ─────────────────────────────────────────────────────────────

class _SettingsTab extends StatelessWidget {
  const _SettingsTab();

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final provider = context.watch<AdGuardProvider>();

    return RefreshIndicator(
      onRefresh: () => provider.loadFeatures(),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
        children: [
          _section(context, 'Bağlantı', [
            _tile(
              context: context,
              icon: Icons.settings_ethernet,
              title: 'Bağlantı Ayarları',
              subtitle: 'URL, kullanıcı adı ve şifre',
              onTap: () => _showConnectionSettings(context),
            ),
            _tile(
              context: context,
              icon: Icons.refresh,
              title: 'İstatistikleri Sıfırla',
              subtitle: 'Tüm DNS sorgu istatistiklerini temizle',
              color: colors.warning,
              onTap: () => _confirmReset(context, provider),
            ),
          ]),
          const SizedBox(height: 16),
          _section(context, 'Güvenlik', [
            _toggleTile(
              context: context,
              icon: Icons.security,
              title: 'Güvenli Tarama',
              subtitle: 'Zararlı siteleri engelle',
              value: provider.safeBrowsing,
              onChanged: (_) => provider.toggleSafeBrowsing(),
              loading: provider.loadingToggles.contains('safe_browsing'),
            ),
            _toggleTile(
              context: context,
              icon: Icons.child_care,
              title: 'Ebeveyn Kontrolü',
              subtitle: 'Yetişkin içeriklerini engelle',
              value: provider.parentalControl,
              onChanged: (_) => provider.toggleParentalControl(),
              loading: provider.loadingToggles.contains('parental_control'),
            ),
            _toggleTile(
              context: context,
              icon: Icons.search,
              title: 'Güvenli Arama',
              subtitle: 'Arama motorlarında güvenli arama',
              value: (provider.safeSearch['enabled'] ?? false) as bool,
              onChanged: (_) => provider.toggleSafeSearch(),
              loading: provider.loadingToggles.contains('safe_search'),
            ),
          ]),
          if (provider.dnsConfig.isNotEmpty) ...[
            const SizedBox(height: 16),
            _section(context, 'DNS Yapılandırması', [
              _infoTile(
                context,
                'Upstream DNS',
                (provider.dnsConfig['upstream_dns'] as List?)?.join(', ') ??
                    '-',
              ),
              _infoTile(
                context,
                'Bootstrap DNS',
                (provider.dnsConfig['bootstrap_dns'] as List?)?.join(', ') ??
                    '-',
              ),
              _infoTile(
                context,
                'DNS Cache',
                '${provider.dnsConfig['cache_size'] ?? 0} kayıt',
              ),
            ]),
          ],
          if ((provider.clients['clients'] as List?)?.isNotEmpty ?? false) ...[
            const SizedBox(height: 16),
            _section(context, 'Kayıtlı İstemciler', [
              ...(provider.clients['clients'] as List).take(10).map((c) {
                final client = c as Map;
                final ids = client['ids'] as List? ?? [];
                return _infoTile(
                  context,
                  client['name'] ?? '-',
                  ids.join(', '),
                );
              }),
            ]),
          ],
        ],
      ),
    );
  }

  void _showConnectionSettings(BuildContext context) {
    appShowModalBottomSheet(
      context: context,
      backgroundColor: context.appColors.surface1,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.md)),
      ),
      builder: (_) => const _AdGuardFormScreen(isEdit: true),
    );
  }

  void _confirmReset(BuildContext context, AdGuardProvider provider) {
    final colors = context.appColors;
    appShowDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.surface1,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md)),
        title: Text(
          'İstatistikleri Sıfırla',
          style: TextStyle(color: colors.textPrimary),
        ),
        content: Text(
          'Tüm DNS sorgu istatistikleri silinecek.',
          style: TextStyle(color: colors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('İptal', style: TextStyle(color: colors.textMuted)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              provider.resetStats();
            },
            child: Text(
              'Sıfırla',
              style: TextStyle(
                color: colors.warning,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _section(BuildContext context, String title, List<Widget> children) {
    final colors = context.appColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionLabel(title),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: colors.surface1,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: colors.hairline),
          ),
          child: Column(children: children),
        ),
      ],
    );
  }

  Widget _tile({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    Color? color,
    required VoidCallback onTap,
  }) {
    final colors = context.appColors;
    return ListTile(
      leading: Icon(icon, color: color ?? colors.textMuted, size: 20),
      title: Text(title,
          style: TextStyle(color: colors.textPrimary, fontSize: 13)),
      subtitle: Text(subtitle,
          style: TextStyle(color: colors.textMuted, fontSize: 11)),
      trailing: Icon(Icons.chevron_right, color: colors.textMuted, size: 18),
      onTap: onTap,
    );
  }

  Widget _toggleTile({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required Function(bool) onChanged,
    bool loading = false,
  }) {
    final colors = context.appColors;
    return ListTile(
      leading: Icon(icon,
          color: value ? colors.primary : colors.textMuted, size: 20),
      title: Text(title,
          style: TextStyle(color: colors.textPrimary, fontSize: 13)),
      subtitle: Text(subtitle,
          style: TextStyle(color: colors.textMuted, fontSize: 11)),
      trailing: _switchSlot(
        colors,
        loading: loading,
        child: Switch(
          value: value,
          onChanged: onChanged,
          activeThumbColor: colors.primary,
        ),
      ),
    );
  }

  Widget _infoTile(BuildContext context, String label, String value) {
    final colors = context.appColors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Text(label,
              style: TextStyle(color: colors.textSecondary, fontSize: 13)),
          const Spacer(),
          Flexible(
            child: Text(
              value,
              style: TextStyle(color: colors.textMuted, fontSize: 12),
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Tab Chip ─────────────────────────────────────────────────────────────────

class _TabChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _TabChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppMotion.fast,
        curve: AppMotion.curve,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? colors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.xs),
          border: Border.all(
            color: selected ? colors.primary : colors.hairline,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: selected ? Colors.white : colors.textMuted,
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : colors.textMuted,
                fontSize: 12,
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
