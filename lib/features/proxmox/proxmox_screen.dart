import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/services/connectivity_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/design_widgets.dart';
import '../../core/utils/app_transitions.dart';
import '../../core/utils/connection_target.dart';
import '../../core/widgets/connection_issue_view.dart';
import '../../core/widgets/operation_overlay.dart';
import '../proxmox/proxmox_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../dashboard/proxmox_connection_screen.dart';
import 'container_detail_page.dart';
import 'create_container_screen.dart';
import 'create_vm_screen.dart';

class ProxmoxScreen extends StatefulWidget {
  const ProxmoxScreen({super.key});

  @override
  State<ProxmoxScreen> createState() => _ProxmoxScreenState();
}

class _ProxmoxScreenState extends State<ProxmoxScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) setState(() {});
    });
    Future.microtask(() {
      if (mounted) context.read<ProxmoxProvider>().refresh();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final isLoading = context.select<ProxmoxProvider, bool>((p) => p.isLoading);
    final hasNodes =
        context.select<ProxmoxProvider, bool>((p) => p.nodes.isNotEmpty);
    final isOperationInProgress =
        context.select<ProxmoxProvider, bool>((p) => p.isOperationInProgress);

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

    if (isLoading && !hasNodes) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 40,
              height: 40,
              child: CircularProgressIndicator(
                  strokeWidth: 2.5, color: colors.primary),
            ),
            const SizedBox(height: 16),
            Text('Sunucu verileri yükleniyor...',
                style: TextStyle(color: colors.textMuted, fontSize: 13)),
          ],
        ),
      );
    }

    final isInitialLoad =
        context.select<ProxmoxProvider, bool>((p) => p.isInitialLoad);
    final isOffline = context.select<ProxmoxProvider, bool>((p) => p.isOffline);

    // Henüz ilk yükleme tamamlanmadıysa bekle
    if (isInitialLoad && !hasNodes) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 40,
              height: 40,
              child: CircularProgressIndicator(
                  strokeWidth: 2.5, color: colors.primary),
            ),
            const SizedBox(height: 16),
            Text('Sunucu verileri yükleniyor...',
                style: TextStyle(color: colors.textMuted, fontSize: 13)),
          ],
        ),
      );
    }

    // Yükleme tamamlandı, sunucu yok ve offline değil → gerçekten boş
    if (!hasNodes && !isOperationInProgress && !isInitialLoad) {
      if (!isOffline) return _EmptyState();

      final hasInternet =
          context.watch<ConnectivityProvider>().hasInternet;
      // İnternet hiç yoksa bu ayrımın bir anlamı yok — eski davranış aynen
      // korunuyor (home_screen'deki genel overlay zaten üstünü kaplar).
      if (!hasInternet) {
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.cloud_off_rounded, color: colors.textMuted, size: 56),
              const SizedBox(height: 16),
              Text('Sunucuya bağlanılamıyor',
                  style: TextStyle(color: colors.textSecondary, fontSize: 16)),
              const SizedBox(height: 6),
              Text('Ağ bağlantınızı kontrol edin',
                  style: TextStyle(color: colors.textMuted, fontSize: 13)),
            ],
          ),
        );
      }

      final host =
          context.select<ProxmoxProvider, String?>((p) => p.lastFailedHost) ??
              '';
      final kind = switch (classifyHost(host)) {
        ConnectionTarget.privateNetwork => ConnectionIssueKind.privateNetwork,
        ConnectionTarget.tailscale => ConnectionIssueKind.tailscale,
        ConnectionTarget.external => ConnectionIssueKind.generic,
      };
      return ConnectionIssueView(
        kind: kind,
        serviceName: 'Proxmox',
        host: host,
        onRetry: () => context.read<ProxmoxProvider>().manualRefresh(),
      );
    }

    return Stack(
      children: [
        Column(
          children: [
            if (!isOperationInProgress) ...[
              // ── Özet başlık ──
              _ProxmoxSummaryHeader(tabController: _tabController),
            ],
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: const [
                  _ContainerList(type: 'lxc'),
                  _ContainerList(type: 'qemu'),
                ],
              ),
            ),
          ],
        ),
        if (isOperationInProgress)
          Builder(builder: (context) {
            final p = context.watch<ProxmoxProvider>();
            return OperationOverlay(
              message: p.operationMessage,
              subMessage: p.operationSubMessage,
              progress: p.operationProgress,
              success: p.operationSuccess,
              isError: p.operationIsError,
            );
          }),
      ],
    );
  }
}

// ─────────────────────────────────────────────
// Özet Header + Tab
// ─────────────────────────────────────────────

class _ProxmoxSummaryHeader extends StatelessWidget {
  final TabController tabController;

  const _ProxmoxSummaryHeader({required this.tabController});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final provider = context.watch<ProxmoxProvider>();

    int totalCT = 0, runningCT = 0, totalVM = 0, runningVM = 0;
    for (final node in provider.nodes) {
      final name = node['node'] as String;
      final lxcs = provider.nodeLXCs[name] ?? [];
      final vms = provider.nodeVMs[name] ?? [];
      totalCT += lxcs.length;
      runningCT += lxcs.where((c) => c['status'] == 'running').length;
      totalVM += vms.length;
      runningVM += vms.where((v) => v['status'] == 'running').length;
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        children: [
          // ── Tab bar ──
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: colors.surface1,
              borderRadius: BorderRadius.circular(AppRadius.sm),
              border: Border.all(color: colors.hairline),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _TabChip(
                    label: 'Konteynerler',
                    icon: Icons.view_in_ar_rounded,
                    count: totalCT,
                    runningCount: runningCT,
                    selected: tabController.index == 0,
                    onTap: () => tabController.animateTo(0),
                  ),
                ),
                Expanded(
                  child: _TabChip(
                    label: 'Sanal Makineler',
                    icon: Icons.computer_rounded,
                    count: totalVM,
                    runningCount: runningVM,
                    selected: tabController.index == 1,
                    onTap: () => tabController.animateTo(1),
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

class _TabChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final int count, runningCount;
  final bool selected;
  final VoidCallback onTap;

  const _TabChip({
    required this.label,
    required this.icon,
    required this.count,
    required this.runningCount,
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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? colors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.xs),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
                size: 14, color: selected ? Colors.white : colors.textMuted),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : colors.textMuted,
                fontSize: 12,
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
            if (count > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: selected
                      ? Colors.white.withValues(alpha: 0.2)
                      : colors.surface2,
                  borderRadius: BorderRadius.circular(AppRadius.xs),
                ),
                child: Text(
                  '$runningCount/$count',
                  style: TextStyle(
                    color: selected ? Colors.white : colors.textSecondary,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Container List
// ─────────────────────────────────────────────

class _ContainerList extends StatefulWidget {
  final String type;
  const _ContainerList({required this.type});

  @override
  State<_ContainerList> createState() => _ContainerListState();
}

class _ContainerListState extends State<_ContainerList> {
  String _sortBy = 'name';
  bool _sortAsc = true;
  String _filterStatus = 'all'; // all, running, stopped
  bool _prefsLoaded = false;
  SharedPreferences? _prefs;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    if (_prefsLoaded) return;
    _prefs ??= await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _sortBy = _prefs!.getString('container_sort_by') ?? 'name';
      _sortAsc = _prefs!.getBool('container_sort_asc') ?? true;
      _prefsLoaded = true;
    });
  }

  Future<void> _savePrefs() async {
    _prefs ??= await SharedPreferences.getInstance();
    await Future.wait([
      _prefs!.setString('container_sort_by', _sortBy),
      _prefs!.setBool('container_sort_asc', _sortAsc),
    ]);
  }

  List<Map<String, dynamic>> _getSortedItems(ProxmoxProvider provider) {
    final isLxc = widget.type == 'lxc';
    final List<Map<String, dynamic>> items = [];

    for (final node in provider.nodes) {
      final name = node['node'] as String;
      final list = isLxc
          ? (provider.nodeLXCs[name] ?? [])
          : (provider.nodeVMs[name] ?? []);
      for (final item in list) {
        items.add({...Map<String, dynamic>.from(item), '_node': name});
      }
    }

    // Filtre
    final filtered = _filterStatus == 'all'
        ? items
        : items
            .where((i) => _filterStatus == 'running'
                ? i['status'] == 'running'
                : i['status'] != 'running')
            .toList();

    filtered.sort((a, b) {
      int result;
      switch (_sortBy) {
        case 'id':
          result = (a['vmid'] as int).compareTo(b['vmid'] as int);
          break;
        case 'status':
          result = (a['status'] ?? '').compareTo(b['status'] ?? '');
          break;
        case 'cpu':
          result = ((b['cpu'] ?? 0) as num).compareTo((a['cpu'] ?? 0) as num);
          break;
        default:
          result = (a['name'] ?? '').compareTo(b['name'] ?? '');
      }
      return _sortAsc ? result : -result;
    });

    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final isLxc = widget.type == 'lxc';
    final provider = context.watch<ProxmoxProvider>();
    final items = _getSortedItems(provider);

    if (provider.isOperationInProgress) {
      return const SizedBox.expand();
    }

    final unreachableServers = provider.unreachableServers;

    if (items.isEmpty) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        floatingActionButton: FloatingActionButton(
          onPressed: () => Navigator.push(
            context,
            AppTransitions.slideFade(
              isLxc ? const CreateContainerScreen() : const CreateVMScreen(),
            ),
          ),
          backgroundColor: colors.primary,
          elevation: 0,
          child: const Icon(Icons.add, color: Colors.white),
        ),
        body: Column(
          children: [
            if (unreachableServers.isNotEmpty)
              _UnreachableServersBanner(servers: unreachableServers),
            Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      isLxc ? Icons.view_in_ar_rounded : Icons.computer_rounded,
                      color: colors.textMuted,
                      size: 56,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _filterStatus != 'all'
                          ? 'Bu filtreye uyan sonuç yok'
                          : isLxc
                              ? 'Konteyner bulunamadı'
                              : 'Sanal makine bulunamadı',
                      style:
                          TextStyle(color: colors.textSecondary, fontSize: 15),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _filterStatus != 'all'
                          ? 'Filtreyi değiştirmeyi deneyin'
                          : 'Sunucu bağlı değil veya liste boş',
                      style: TextStyle(color: colors.textMuted, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton:
          context.select<ProxmoxProvider, bool>((p) => p.isOperationInProgress)
              ? null
              : FloatingActionButton(
                  onPressed: () => Navigator.push(
                    context,
                    AppTransitions.slideFade(
                      isLxc
                          ? const CreateContainerScreen()
                          : const CreateVMScreen(),
                    ),
                  ),
                  backgroundColor: colors.primary,
                  elevation: 0,
                  child: const Icon(Icons.add, color: Colors.white),
                ),
      body: Column(
        children: [
          // ── Toolbar ──
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Row(
              children: [
                // Filtre
                _FilterChip(
                  label: 'Tümü',
                  selected: _filterStatus == 'all',
                  color: colors.primary,
                  onTap: () => setState(() => _filterStatus = 'all'),
                ),
                const SizedBox(width: 6),
                _FilterChip(
                  label: 'Çalışan',
                  selected: _filterStatus == 'running',
                  color: colors.success,
                  onTap: () => setState(() => _filterStatus = 'running'),
                ),
                const SizedBox(width: 6),
                _FilterChip(
                  label: 'Durmuş',
                  selected: _filterStatus == 'stopped',
                  color: colors.error,
                  onTap: () => setState(() => _filterStatus = 'stopped'),
                ),
                const Spacer(),
                // Sıralama
                PopupMenuButton<String>(
                  color: colors.surface1,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      side: BorderSide(color: colors.hairline)),
                  icon: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: colors.surface2,
                      borderRadius: BorderRadius.circular(AppRadius.xs),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.sort_rounded,
                            color: colors.textSecondary, size: 14),
                        const SizedBox(width: 4),
                        Icon(
                          _sortAsc
                              ? Icons.arrow_upward_rounded
                              : Icons.arrow_downward_rounded,
                          color: colors.textSecondary,
                          size: 11,
                        ),
                      ],
                    ),
                  ),
                  onSelected: (value) {
                    setState(() {
                      if (_sortBy == value) {
                        _sortAsc = !_sortAsc;
                      } else {
                        _sortBy = value;
                        _sortAsc = true;
                      }
                    });
                    _savePrefs();
                  },
                  itemBuilder: (ctx) => [
                    _menuItem(ctx, 'name', 'İsme Göre',
                        Icons.sort_by_alpha_rounded, colors),
                    _menuItem(
                        ctx, 'id', "ID'ye Göre", Icons.tag_rounded, colors),
                    _menuItem(ctx, 'status', 'Duruma Göre',
                        Icons.circle_rounded, colors),
                    _menuItem(ctx, 'cpu', 'CPU Kullanımına Göre',
                        Icons.memory_rounded, colors),
                  ],
                ),
              ],
            ),
          ),

          if (unreachableServers.isNotEmpty)
            _UnreachableServersBanner(servers: unreachableServers),

          // ── Liste ──
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => provider.refresh(),
              color: colors.primary,
              child: ListView.separated(
                key: ValueKey('${_filterStatus}_$_sortBy'),
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 80),
                itemCount: items.length,
                separatorBuilder: (_, __) =>
                    Divider(height: 1, color: colors.hairline),
                itemBuilder: (context, i) {
                  final item = items[i];
                  return _ContainerRow(
                    key: ValueKey(item['vmid']),
                    item: item,
                    isLxc: isLxc,
                    provider: provider,
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  PopupMenuItem<String> _menuItem(BuildContext context, String value,
      String label, IconData icon, AppThemeData colors) {
    return PopupMenuItem(
      value: value,
      child: Row(
        children: [
          Icon(icon,
              color: _sortBy == value ? colors.primary : colors.textMuted,
              size: 16),
          const SizedBox(width: 10),
          Text(label,
              style: TextStyle(
                  color: _sortBy == value ? colors.primary : colors.textPrimary,
                  fontSize: 13)),
          if (_sortBy == value) ...[
            const Spacer(),
            Icon(
              _sortAsc
                  ? Icons.arrow_upward_rounded
                  : Icons.arrow_downward_rounded,
              color: colors.primary,
              size: 13,
            ),
          ],
        ],
      ),
    );
  }
}

/// Erişilemeyen sunucular için kompakt, sunucu-düzeyi banner — tek tek
/// konteyner satırı DEĞİL (sahte veri olmasın diye), sadece "X sunucusuna
/// erişilemiyor" bilgisi.
class _UnreachableServersBanner extends StatelessWidget {
  final List<UnreachableProxmoxServer> servers;

  const _UnreachableServersBanner({required this.servers});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Column(
        children: [
          for (final s in servers)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  Icon(Icons.dns_outlined, color: colors.warning, size: 14),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '${s.name.isNotEmpty ? s.name : s.host} sunucusuna erişilemiyor',
                      style: colors.meta.copyWith(color: colors.textMuted),
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

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppMotion.fast,
        curve: AppMotion.curve,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.xs),
          border: Border.all(
            color: selected
                ? color.withValues(alpha: 0.4)
                : context.appColors.hairline,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? color : context.appColors.textMuted,
            fontSize: 11,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// List Item
// ─────────────────────────────────────────────

/// Tailscale tarzı kompakt liste satırı — eskiden ayrı bir "kart görünümü"
/// (_CardItem, gömülü progress bar'lar + satır içi aksiyon butonlarıyla) ve
/// bir de "liste görünümü" (_ListItem) vardı; artık TEK bir satır tasarımı
/// var, görünüm anahtarı kaldırıldı. Aksiyonlar (başlat/durdur/yeniden
/// başlat) satırdan kalktı — dokunma detay sayfasını açar, uzun basma hızlı
/// aksiyon sheet'ini açar.
class _ContainerRow extends StatelessWidget {
  final Map<String, dynamic> item;
  final bool isLxc;
  final ProxmoxProvider provider;

  const _ContainerRow({
    super.key,
    required this.item,
    required this.isLxc,
    required this.provider,
  });

  String _formatUptime(int s) {
    if (s <= 0) return '-';
    final d = s ~/ 86400;
    final h = (s % 86400) ~/ 3600;
    if (d > 0) return '${d}g ${h}s';
    final m = (s % 3600) ~/ 60;
    return h > 0 ? '${h}s ${m}dk' : '${m}dk';
  }

  void _showActions(BuildContext context, AppThemeData colors,
      String nodeName, int vmid, bool isRunning) {
    appShowModalBottomSheet(
      context: context,
      backgroundColor: colors.surface1,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.md)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: colors.textMuted.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 8),
            if (isRunning) ...[
              ListTile(
                leading: Icon(Icons.restart_alt_rounded, color: colors.warning),
                title: Text('Yeniden Başlat',
                    style: TextStyle(color: colors.textPrimary)),
                onTap: () {
                  Navigator.pop(ctx);
                  provider.rebootContainer(nodeName, vmid, isLxc: isLxc);
                },
              ),
              ListTile(
                leading: Icon(Icons.stop_rounded, color: colors.error),
                title: Text('Durdur', style: TextStyle(color: colors.textPrimary)),
                onTap: () {
                  Navigator.pop(ctx);
                  provider.stopContainer(nodeName, vmid, isLxc: isLxc);
                },
              ),
            ] else
              ListTile(
                leading: Icon(Icons.play_arrow_rounded, color: colors.success),
                title: Text('Başlat', style: TextStyle(color: colors.textPrimary)),
                onTap: () {
                  Navigator.pop(ctx);
                  provider.startContainer(nodeName, vmid, isLxc: isLxc);
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final nodeName = item['_node'] as String;
    final vmid = item['vmid'] as int;
    final name = item['name'] ?? (isLxc ? 'CT $vmid' : 'VM $vmid');
    final status = item['status'] ?? 'unknown';
    final isRunning = status == 'running';
    final cpu = ((item['cpu'] ?? 0) * 100).toDouble();
    final maxmem = (item['maxmem'] ?? 1) as int;
    final mem = (item['mem'] ?? 0) as int;
    final memPercent = maxmem > 0 ? mem / maxmem * 100 : 0.0;
    final uptime = item['uptime'] as int? ?? 0;

    return InkWell(
      onTap: () => Navigator.push(
        context,
        AppTransitions.slideFade(
          ContainerDetailPage(
            item: item,
            nodeName: nodeName,
            isLxc: isLxc,
            provider: provider,
          ),
        ),
      ),
      onLongPress: () => _showActions(context, colors, nodeName, vmid, isRunning),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isRunning ? colors.success : colors.textMuted,
              ),
            ),
            const SizedBox(width: 12),
            Icon(
              isLxc ? Icons.view_in_ar_rounded : Icons.computer_rounded,
              color: colors.textSecondary,
              size: 16,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  MetaLine([
                    '${isLxc ? 'CT' : 'VM'} $vmid',
                    nodeName,
                    if (isRunning && uptime > 0) _formatUptime(uptime),
                  ]),
                ],
              ),
            ),
            if (isRunning) ...[
              const SizedBox(width: 12),
              _MiniPct(label: 'CPU', value: cpu, colors: colors),
              const SizedBox(width: 14),
              _MiniPct(label: 'RAM', value: memPercent, colors: colors),
            ],
          ],
        ),
      ),
    );
  }
}

/// Satır sağındaki kompakt CPU/RAM yüzdesi — etiket üstte küçük gri,
/// değer altta tabular ve eşiğe göre renkli.
class _MiniPct extends StatelessWidget {
  final String label;
  final double value;
  final AppThemeData colors;

  const _MiniPct({required this.label, required this.value, required this.colors});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(label, style: TextStyle(color: colors.textMuted, fontSize: 9)),
        Text('${value.toStringAsFixed(0)}%',
            style: colors.metricSmall.copyWith(color: colors.thresholdColor(value))),
      ],
    );
  }
}

// ─────────────────────────────────────────────
// Empty State
// ─────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: colors.surface2,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.dns_outlined,
                  color: colors.textSecondary, size: 48),
            ),
            const SizedBox(height: 20),
            Text('Sunucu Bağlı Değil',
                style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(
              'Proxmox sunucunuzu ekleyerek\nkonteyner ve VM\'lerinizi yönetin.',
              textAlign: TextAlign.center,
              style:
                  TextStyle(color: colors.textMuted, fontSize: 13, height: 1.6),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => Navigator.push(
                context,
                AppTransitions.slideFade(const ProxmoxConnectionScreen()),
              ),
              icon: const Icon(Icons.add, color: Colors.white, size: 18),
              label: const Text('Sunucu Ekle',
                  style: TextStyle(color: Colors.white)),
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.primary,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 13),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.sm)),
                elevation: 0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

