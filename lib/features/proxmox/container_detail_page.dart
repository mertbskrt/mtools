import 'package:flutter/material.dart';
import '../../core/utils/app_transitions.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/design_widgets.dart';
import '../../core/widgets/operation_overlay.dart';
import 'proxmox_provider.dart';

class ContainerDetailPage extends StatefulWidget {
  final Map<String, dynamic> item;
  final String nodeName;
  final bool isLxc;
  final ProxmoxProvider provider;

  const ContainerDetailPage({
    super.key,
    required this.item,
    required this.nodeName,
    required this.isLxc,
    required this.provider,
  });

  @override
  State<ContainerDetailPage> createState() => _ContainerDetailPageState();
}

class _ContainerDetailPageState extends State<ContainerDetailPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;

  String _ipAddress = 'Yükleniyor...';
  String _gateway = '-';
  int _cpuCores = 0;
  bool _unprivileged = false;
  String _storage = '-';

  List<dynamic> _rrdData = [];
  bool _rrdLoading = true;

  // _rrdData sadece _loadRRD() tamamlandığında değişiyor ama build() her
  // çağrıldığında (ör. sekme geçişi, herhangi bir setState) 5 ayrı O(n)
  // spot listesi yeniden hesaplanıyordu — hiçbiri gerçekte değişmediği
  // halde. Artık sadece _rrdData değiştiğinde bir kez hesaplanıp burada
  // önbelleğe alınıyor.
  List<_RrdPoint> _cpuPoints = const [];
  List<_RrdPoint> _memPoints = const [];
  List<_RrdPoint> _netinPoints = const [];
  List<_RrdPoint> _netoutPoints = const [];
  List<_RrdPoint> _diskPoints = const [];

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    // Push geçişiyle (AppTransitions.slideFade, ~AppMotion.base) yarışmasınlar
    // diye ağ istekleri geçiş oturduktan sonra başlıyor — aksi halde veri
    // dönüşü tam geçiş sürerken gelip _PerformanceTab'ı grafik setiyle
    // yeniden inşa ediyor, bu da geçiş sırasında kare düşmesine yol açıyordu.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(AppMotion.base, () {
        if (!mounted) return;
        _loadConfig();
        _loadRRD();
      });
    });
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadConfig() async {
    final vmid = widget.item['vmid'] as int;
    final config = await widget.provider
        .getContainerConfig(widget.nodeName, vmid, isLxc: widget.isLxc);
    if (!mounted) return;
    final net0 = config['net0'] ?? '';
    final ipMatch = RegExp(r'ip=([\d.]+)').firstMatch(net0.toString());
    final gwMatch = RegExp(r'gw=([\d.]+)').firstMatch(net0.toString());
    final rootfs = config['rootfs'] ?? '';
    setState(() {
      _ipAddress = ipMatch?.group(1) ??
          (net0.toString().contains('dhcp') ? 'DHCP' : 'Tanımsız');
      _gateway = gwMatch?.group(1) ?? '-';
      _cpuCores = config['cores'] ?? config['cpus'] ?? 0;
      _unprivileged = (config['unprivileged'] ?? 0) == 1;
      _storage = rootfs.toString().split(':').first.isNotEmpty
          ? rootfs.toString().split(':').first
          : '-';
    });
  }

  Future<void> _loadRRD() async {
    final vmid = widget.item['vmid'] as int;
    try {
      final data = await widget.provider
          .getContainerRRD(widget.nodeName, vmid, isLxc: widget.isLxc);
      if (mounted) {
        setState(() {
          _rrdData = data;
          _rrdLoading = false;
          _recomputeSpots();
        });
      }
    } catch (_) {
      if (mounted) setState(() => _rrdLoading = false);
    }
  }

  void _recomputeSpots() {
    _cpuPoints = _buildPctSpots('cpu', scale: 100);
    _memPoints = _buildPctSpots('mem', divKey: 'maxmem');
    _netinPoints = _buildNetSpots('netin');
    _netoutPoints = _buildNetSpots('netout');
    _diskPoints = _buildPctSpots('disk', divKey: 'maxdisk');
  }

  String _fmt(int bytes) {
    if (bytes >= 1e9) return '${(bytes / 1e9).toStringAsFixed(1)} GB';
    if (bytes >= 1e6) return '${(bytes / 1e6).toStringAsFixed(1)} MB';
    return '$bytes B';
  }

  String _fmtBps(double bps) {
    if (bps >= 1e6) return '${(bps / 1e6).toStringAsFixed(1)} MB/s';
    if (bps >= 1e3) return '${(bps / 1e3).toStringAsFixed(1)} KB/s';
    return '${bps.toStringAsFixed(0)} B/s';
  }

  String _fmtUptime(int s) {
    final d = s ~/ 86400;
    final h = (s % 86400) ~/ 3600;
    final m = (s % 3600) ~/ 60;
    return d > 0 ? '${d}g ${h}s ${m}dk' : '${h}s ${m}dk';
  }

  // Yüzde spotları (cpu, mem%)
  List<_RrdPoint> _buildPctSpots(String key,
      {double scale = 1, String? divKey}) {
    final result = <_RrdPoint>[];
    for (int i = 0; i < _rrdData.length; i++) {
      final d = _rrdData[i] as Map<String, dynamic>?;
      if (d == null) continue;
      double val;
      if (divKey != null) {
        final numerator = ((d[key] ?? 0) as num).toDouble();
        final den = ((d[divKey] ?? 0) as num).toDouble();
        val = den > 0 ? (numerator / den * 100) : 0.0;
      } else {
        val = ((d[key] ?? 0) as num).toDouble() * scale;
      }
      final safe = val.isFinite ? val.clamp(0.0, 100.0) : 0.0;
      final time = ((d['time'] ?? 0) as num).toInt();
      result.add(_RrdPoint(i.toDouble(), safe, time));
    }
    return result;
  }

  // Ağ spotları — bytes/s cinsinden
  List<_RrdPoint> _buildNetSpots(String key) {
    final result = <_RrdPoint>[];
    for (int i = 0; i < _rrdData.length; i++) {
      final d = _rrdData[i] as Map<String, dynamic>?;
      if (d == null) continue;
      final val = ((d[key] ?? 0) as num).toDouble();
      final safe = val.isFinite && val >= 0 ? val : 0.0;
      final time = ((d['time'] ?? 0) as num).toInt();
      result.add(_RrdPoint(i.toDouble(), safe, time));
    }
    return result;
  }

  Future<void> _doAction(Future<void> Function() fn) async {
    try {
      await fn();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('İşlem başarısız: $e'),
        backgroundColor: context.appColors.error,
      ));
    }
  }

  void _confirmDelete(AppThemeData colors) {
    final name = widget.item['name'] ?? '';
    appShowDialog(
      context: context,
      builder: (dctx) => AlertDialog(
        backgroundColor: colors.surface1,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
        title:
            Text('Emin misiniz?', style: TextStyle(color: colors.textPrimary)),
        content: Text('$name silinecek. Bu işlem geri alınamaz.',
            style: TextStyle(color: colors.textSecondary, fontSize: 13)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dctx),
              child:
                  Text('İptal', style: TextStyle(color: colors.textSecondary))),
          TextButton(
            onPressed: () {
              Navigator.pop(dctx);
              _doAction(() => widget.provider.deleteContainer(
                  widget.nodeName, widget.item['vmid'] as int,
                  isLxc: widget.isLxc));
            },
            child: Text('Sil',
                style: TextStyle(
                    color: colors.error, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final item = widget.item;

    final vmid = item['vmid'] as int;
    final name = item['name'] ?? 'CT $vmid';
    final status = item['status'] ?? 'unknown';
    final isRunning = status == 'running';
    final cpu = ((item['cpu'] ?? 0) * 100).toDouble();
    final maxmem = (item['maxmem'] ?? 1) as int;
    final mem = (item['mem'] ?? 0) as int;
    final maxdisk = (item['maxdisk'] ?? 0) as int;
    final disk = (item['disk'] ?? 0) as int;
    final maxswap = (item['maxswap'] ?? 0) as int;
    final swap = (item['swap'] ?? 0) as int;
    final netin = (item['netin'] ?? 0) as int;
    final netout = (item['netout'] ?? 0) as int;
    final uptime = (item['uptime'] ?? 0) as int;
    final tags = item['tags']?.toString() ?? '';

    final memPct = maxmem > 0 ? mem / maxmem * 100 : 0.0;
    final diskPct = maxdisk > 0 ? disk / maxdisk * 100 : 0.0;
    final swapPct = maxswap > 0 ? swap / maxswap * 100 : 0.0;

    final cpuPoints = _cpuPoints;
    final memPoints = _memPoints;
    final netinPoints = _netinPoints;
    final netoutPoints = _netoutPoints;
    final diskPoints = _diskPoints;

    final scaffold = Scaffold(
      backgroundColor: colors.bgDark,
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          SliverAppBar(
            expandedHeight: 160,
            pinned: true,
            backgroundColor: colors.bgDark,
            surfaceTintColor: Colors.transparent,
            leading: IconButton(
              icon: Icon(Icons.arrow_back_ios_new,
                  color: colors.textPrimary, size: 18),
              onPressed: () => Navigator.pop(context),
            ),
            flexibleSpace: FlexibleSpaceBar(
              collapseMode: CollapseMode.pin,
              background: Container(
                color: colors.surface0,
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 52, 20, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: colors.surface2,
                                borderRadius:
                                    BorderRadius.circular(AppRadius.sm),
                              ),
                              child: Icon(
                                widget.isLxc
                                    ? Icons.view_in_ar_rounded
                                    : Icons.computer_rounded,
                                color: isRunning
                                    ? colors.success
                                    : colors.textMuted,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(name,
                                      style: TextStyle(
                                          color: colors.textPrimary,
                                          fontSize: 22,
                                          fontWeight: FontWeight.bold)),
                                  const SizedBox(height: 3),
                                  MetaLine([
                                    '${widget.isLxc ? 'CT' : 'VM'} $vmid',
                                    widget.nodeName,
                                  ]),
                                ],
                              ),
                            ),
                            StatusIndicator(
                              color: isRunning ? colors.success : colors.error,
                              label: isRunning ? 'Çalışıyor' : 'Durduruldu',
                              style: colors.meta,
                            ),
                          ],
                        ),
                        if (tags.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 6,
                            children: tags
                                .split(';')
                                .where((t) => t.isNotEmpty)
                                .map((t) => Container(
                                      key: ValueKey(t),
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: colors.surface2,
                                        borderRadius: BorderRadius.circular(
                                            AppRadius.xs),
                                      ),
                                      child: Text(t,
                                          style: TextStyle(
                                              color: colors.textSecondary,
                                              fontSize: 10,
                                              fontWeight: FontWeight.w500)),
                                    ))
                                .toList(),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(48),
              child: Container(
                color: colors.bgDark,
                child: TabBar(
                  controller: _tabCtrl,
                  labelColor: colors.primary,
                  unselectedLabelColor: colors.textMuted,
                  indicatorColor: colors.primary,
                  indicatorWeight: 2,
                  labelStyle: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600),
                  tabs: const [
                    Tab(text: 'Genel Bakış'),
                    Tab(text: 'Performans'),
                  ],
                ),
              ),
            ),
          ),
        ],
        body: TabBarView(
          controller: _tabCtrl,
          children: [
            _OverviewTab(
              colors: colors,
              isRunning: isRunning,
              cpu: cpu,
              memPct: memPct,
              diskPct: diskPct,
              swapPct: swapPct,
              mem: mem,
              maxmem: maxmem,
              disk: disk,
              maxdisk: maxdisk,
              swap: swap,
              maxswap: maxswap,
              netin: netin,
              netout: netout,
              uptime: uptime,
              cpuCores: _cpuCores,
              ipAddress: _ipAddress,
              gateway: _gateway,
              isLxc: widget.isLxc,
              nodeName: widget.nodeName,
              unprivileged: _unprivileged,
              storage: _storage,
              fmt: _fmt,
              fmtUptime: _fmtUptime,
            ),
            _PerformanceTab(
              colors: colors,
              isRunning: isRunning,
              rrdLoading: _rrdLoading,
              cpuPoints: cpuPoints,
              memPoints: memPoints,
              netinPoints: netinPoints,
              netoutPoints: netoutPoints,
              diskPoints: diskPoints,
              fmtBps: _fmtBps,
              fmt: _fmt,
            ),
          ],
        ),
      ),
      bottomNavigationBar: _buildActionBar(context, colors, isRunning, vmid),
    );

    return Stack(
      children: [
        scaffold,
        AnimatedBuilder(
          animation: widget.provider,
          builder: (context, _) {
            if (!widget.provider.isOperationInProgress) {
              return const SizedBox.shrink();
            }
            return Positioned.fill(
              child: OperationOverlay(
                message: widget.provider.operationMessage,
                subMessage: widget.provider.operationSubMessage,
                progress: widget.provider.operationProgress,
                success: widget.provider.operationSuccess,
                isError: widget.provider.operationIsError,
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildActionBar(
      BuildContext context, AppThemeData colors, bool isRunning, int vmid) {
    return Container(
      padding: EdgeInsets.fromLTRB(
          16, 12, 16, MediaQuery.of(context).padding.bottom + 12),
      decoration: BoxDecoration(
        color: colors.surface1,
        border: Border(top: BorderSide(color: colors.hairline)),
      ),
      child: isRunning
          ? Row(children: [
              Expanded(
                child: _ActionButton(
                  colors: colors,
                  icon: Icons.restart_alt,
                  label: 'Yeniden Başlat',
                  color: colors.warning,
                  onTap: () => _doAction(() => widget.provider.rebootContainer(
                      widget.nodeName, vmid,
                      isLxc: widget.isLxc)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ActionButton(
                  colors: colors,
                  icon: Icons.stop_rounded,
                  label: 'Durdur',
                  color: colors.error,
                  onTap: () => _doAction(() => widget.provider
                      .stopContainer(widget.nodeName, vmid, isLxc: widget.isLxc)),
                ),
              ),
            ])
          : Row(children: [
              Expanded(
                child: _ActionButton(
                  colors: colors,
                  icon: Icons.play_arrow_rounded,
                  label: 'Başlat',
                  color: colors.success,
                  onTap: () => _doAction(() => widget.provider.startContainer(
                      widget.nodeName, vmid,
                      isLxc: widget.isLxc)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ActionButton(
                  colors: colors,
                  icon: Icons.delete_outline,
                  label: 'Sil',
                  color: colors.error,
                  onTap: () => _confirmDelete(colors),
                ),
              ),
            ]),
    );
  }
}

// ─────────────────────────────────────────────
// RRD nokta modeli
// ─────────────────────────────────────────────

class _RrdPoint {
  final double x;
  final double y;
  final int time; // unix timestamp

  const _RrdPoint(this.x, this.y, this.time);

  FlSpot get spot => FlSpot(x, y);
}

// ─────────────────────────────────────────────
// Genel Bakış Tab
// ─────────────────────────────────────────────

class _OverviewTab extends StatelessWidget {
  final AppThemeData colors;
  final bool isRunning;
  final double cpu, memPct, diskPct, swapPct;
  final int mem, maxmem, disk, maxdisk, swap, maxswap;
  final int netin, netout, uptime, cpuCores;
  final String ipAddress, gateway, nodeName, storage;
  final bool isLxc, unprivileged;
  final String Function(int) fmt;
  final String Function(int) fmtUptime;

  const _OverviewTab({
    required this.colors,
    required this.isRunning,
    required this.cpu,
    required this.memPct,
    required this.diskPct,
    required this.swapPct,
    required this.mem,
    required this.maxmem,
    required this.disk,
    required this.maxdisk,
    required this.swap,
    required this.maxswap,
    required this.netin,
    required this.netout,
    required this.uptime,
    required this.cpuCores,
    required this.ipAddress,
    required this.gateway,
    required this.nodeName,
    required this.storage,
    required this.isLxc,
    required this.unprivileged,
    required this.fmt,
    required this.fmtUptime,
  });

  Widget _metricRow({
    required IconData icon,
    required String label,
    required double value,
    required String subtitle,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: MetricRow(
        icon: icon,
        label: label,
        value: value,
        valueLabel: '${value.toStringAsFixed(0)}%',
        color: colors.thresholdColor(value),
        subtitle: subtitle,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      children: [
        if (isRunning) ...[
          // 2x2 büyük metrik kartları yerine tek yüzeyde kompakt liste —
          // Kaynaklar bölümüyle (system_screen.dart) aynı desen: _SectionCard
          // + aralarında ince ayraç, tutarlılık için.
          _SectionCard(
            colors: colors,
            title: 'Kaynaklar',
            icon: Icons.monitor_heart_outlined,
            children: [
              _metricRow(
                icon: Icons.memory,
                label: 'CPU',
                value: cpu,
                subtitle: cpuCores > 0 ? '$cpuCores çekirdek' : '',
              ),
              _metricRow(
                icon: Icons.developer_board,
                label: 'RAM',
                value: memPct,
                subtitle: '${fmt(mem)} / ${fmt(maxmem)}',
              ),
              _metricRow(
                icon: Icons.storage,
                label: 'Disk',
                value: diskPct,
                subtitle: '${fmt(disk)} / ${fmt(maxdisk)}',
              ),
              if (maxswap > 0)
                _metricRow(
                  icon: Icons.swap_horiz,
                  label: 'Swap',
                  value: swapPct,
                  subtitle: '${fmt(swap)} / ${fmt(maxswap)}',
                ),
            ],
          ),
          const SizedBox(height: 10),
        ],
        _SectionCard(
          colors: colors,
          title: 'Sistem Bilgisi',
          icon: Icons.info_outline,
          children: [
            _InfoRow(
                colors: colors,
                label: 'Durum',
                value: isRunning ? 'Çalışıyor' : 'Durduruldu',
                valueColor: isRunning ? colors.success : colors.error),
            _InfoRow(
                colors: colors,
                label: 'Tip',
                value: isLxc ? 'LXC Container' : 'QEMU VM'),
            _InfoRow(colors: colors, label: 'Node', value: nodeName),
            _InfoRow(
                colors: colors,
                label: 'Unprivileged',
                value: unprivileged ? 'Evet' : 'Hayır'),
            _InfoRow(colors: colors, label: 'Storage', value: storage),
            if (uptime > 0)
              _InfoRow(
                  colors: colors,
                  label: 'Açık Kalma',
                  value: fmtUptime(uptime)),
          ],
        ),
        const SizedBox(height: 10),
        _SectionCard(
          colors: colors,
          title: 'Ağ',
          icon: Icons.wifi,
          children: [
            _InfoRow(colors: colors, label: 'IP Adresi', value: ipAddress),
            _InfoRow(colors: colors, label: 'Gateway', value: gateway),
            _InfoRow(colors: colors, label: 'Gelen Trafik', value: fmt(netin)),
            _InfoRow(colors: colors, label: 'Giden Trafik', value: fmt(netout)),
          ],
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────
// Performans Tab
// ─────────────────────────────────────────────

class _PerformanceTab extends StatelessWidget {
  final AppThemeData colors;
  final bool isRunning, rrdLoading;
  final List<_RrdPoint> cpuPoints,
      memPoints,
      netinPoints,
      netoutPoints,
      diskPoints;
  final String Function(double) fmtBps;
  final String Function(int) fmt;

  const _PerformanceTab({
    required this.colors,
    required this.isRunning,
    required this.rrdLoading,
    required this.cpuPoints,
    required this.memPoints,
    required this.netinPoints,
    required this.netoutPoints,
    required this.diskPoints,
    required this.fmtBps,
    required this.fmt,
  });

  @override
  Widget build(BuildContext context) {
    final String stateKey;
    final Widget child;

    if (!isRunning) {
      stateKey = 'not_running';
      child = Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.bar_chart, color: colors.textMuted, size: 48),
            const SizedBox(height: 12),
            Text('Konteyner çalışmıyor',
                style: TextStyle(color: colors.textMuted, fontSize: 14)),
            const SizedBox(height: 6),
            Text('Performans verisi için konteyneri başlatın',
                style: TextStyle(color: colors.textMuted, fontSize: 12)),
          ],
        ),
      );
    } else if (rrdLoading) {
      stateKey = 'loading';
      child =
          Center(child: CircularProgressIndicator(color: colors.primary));
    } else if (cpuPoints.length < 2) {
      stateKey = 'no_data';
      child = Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.bar_chart, color: colors.textMuted, size: 48),
            const SizedBox(height: 12),
            Text('Veri henüz yok',
                style: TextStyle(color: colors.textMuted, fontSize: 14)),
          ],
        ),
      );
    } else {
      stateKey = 'loaded';
      // Ağ max değeri — normalize için
      final netMax = [
        ...netinPoints.map((p) => p.y),
        ...netoutPoints.map((p) => p.y),
      ].fold(0.0, (a, b) => a > b ? a : b);

      child = ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        children: [
          _PctChartCard(
            colors: colors,
            label: 'CPU Kullanımı',
            icon: Icons.memory,
            points: cpuPoints,
            color: colors.info,
          ),
          const SizedBox(height: 12),
          _PctChartCard(
            colors: colors,
            label: 'RAM Kullanımı',
            icon: Icons.developer_board,
            points: memPoints,
            color: colors.primary,
          ),
          const SizedBox(height: 12),
          _NetChartCard(
            colors: colors,
            netinPoints: netinPoints,
            netoutPoints: netoutPoints,
            netMax: netMax,
            fmtBps: fmtBps,
          ),
          if (diskPoints.length >= 2) ...[
            const SizedBox(height: 12),
            _PctChartCard(
              colors: colors,
              label: 'Disk Kullanımı',
              icon: Icons.storage,
              points: diskPoints,
              color: colors.warning,
            ),
          ],
        ],
      );
    }

    // Grafikler veri gelince anında pat diye belirmesin diye fade-in —
    // geçiş sırasında rebuild olsa bile görsel olarak yumuşak dolduruyor.
    return AnimatedSwitcher(
      duration: AppMotion.base,
      switchInCurve: AppMotion.curve,
      switchOutCurve: AppMotion.curve,
      child: KeyedSubtree(key: ValueKey(stateKey), child: child),
    );
  }
}

// ─────────────────────────────────────────────
// Yüzde Grafik Kartı (CPU / RAM / Disk)
// ─────────────────────────────────────────────

class _PctChartCard extends StatelessWidget {
  final AppThemeData colors;
  final String label;
  final IconData icon;
  final List<_RrdPoint> points;
  final Color color;

  const _PctChartCard({
    required this.colors,
    required this.label,
    required this.icon,
    required this.points,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    if (points.length < 2) return const SizedBox.shrink();

    final values = points.map((p) => p.y).toList();
    final last = values.last;
    final avg = values.reduce((a, b) => a + b) / values.length;
    final min = values.reduce((a, b) => a < b ? a : b);
    final max = values.reduce((a, b) => a > b ? a : b);
    final chartMax = (max * 1.15).clamp(10.0, 100.0);

    // Zaman etiketleri — başlangıç, orta, son
    String timeLabel(int ts) {
      if (ts == 0) return '';
      final dt = DateTime.fromMillisecondsSinceEpoch(ts * 1000);
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }

    final startTime = timeLabel(points.first.time);
    final midTime = timeLabel(points[points.length ~/ 2].time);
    final endTime = timeLabel(points.last.time);

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
          // Başlık satırı
          Row(children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppRadius.xs),
              ),
              child: Icon(icon, color: color, size: 14),
            ),
            const SizedBox(width: 8),
            Text(label,
                style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppRadius.xs),
              ),
              child: Text(
                '${last.toStringAsFixed(1)}%',
                style: TextStyle(
                    color: color, fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ),
          ]),

          const SizedBox(height: 14),

          // Grafik
          SizedBox(
            height: 180,
            child: LineChart(
              LineChartData(
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: chartMax / 4,
                  getDrawingHorizontalLine: (_) => FlLine(
                    color: colors.hairline,
                    strokeWidth: 1,
                  ),
                ),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 36,
                      interval: chartMax / 4,
                      getTitlesWidget: (val, _) => Text(
                        '${val.toInt()}%',
                        style: TextStyle(color: colors.textMuted, fontSize: 9),
                      ),
                    ),
                  ),
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 22,
                      getTitlesWidget: (val, _) {
                        final idx = val.toInt();
                        final mid = points.length ~/ 2;
                        if (idx == 0) {
                          return Text(startTime,
                              style:
                                  TextStyle(color: colors.textMuted, fontSize: 9));
                        }
                        if (idx == mid) {
                          return Text(midTime,
                              style:
                                  TextStyle(color: colors.textMuted, fontSize: 9));
                        }
                        if (idx == points.length - 1) {
                          return Text(endTime,
                              style:
                                  TextStyle(color: colors.textMuted, fontSize: 9));
                        }
                        return const SizedBox.shrink();
                      },
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
                clipData: const FlClipData.all(),
                lineBarsData: [
                  LineChartBarData(
                    spots: points.map((p) => p.spot).toList(),
                    isCurved: true,
                    curveSmoothness: 0.3,
                    color: color,
                    barWidth: 2,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          color.withValues(alpha: 0.18),
                          color.withValues(alpha: 0.0),
                        ],
                      ),
                    ),
                  ),
                ],
                minY: 0,
                maxY: chartMax,
                minX: points.first.x,
                maxX: points.last.x,
              ),
            ),
          ),

          const SizedBox(height: 12),

          // İstatistik satırı
          Row(children: [
            _StatChip(
                label: 'Min',
                value: '${min.toStringAsFixed(1)}%',
                color: color,
                colors: colors,
                muted: true),
            const SizedBox(width: 8),
            _StatChip(
                label: 'Ort',
                value: '${avg.toStringAsFixed(1)}%',
                color: color,
                colors: colors),
            const SizedBox(width: 8),
            _StatChip(
                label: 'Maks',
                value: '${max.toStringAsFixed(1)}%',
                color: color,
                colors: colors,
                muted: true),
          ]),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Ağ Grafik Kartı
// ─────────────────────────────────────────────

class _NetChartCard extends StatelessWidget {
  final AppThemeData colors;
  final List<_RrdPoint> netinPoints, netoutPoints;
  final double netMax;
  final String Function(double) fmtBps;

  const _NetChartCard({
    required this.colors,
    required this.netinPoints,
    required this.netoutPoints,
    required this.netMax,
    required this.fmtBps,
  });

  @override
  Widget build(BuildContext context) {
    if (netinPoints.length < 2) return const SizedBox.shrink();

    final chartMax = (netMax * 1.2).clamp(1000.0, double.infinity);
    final interval = chartMax / 4;

    final lastIn = netinPoints.last.y;
    final lastOut = netoutPoints.isNotEmpty ? netoutPoints.last.y : 0.0;

    String timeLabel(int ts) {
      if (ts == 0) return '';
      final dt = DateTime.fromMillisecondsSinceEpoch(ts * 1000);
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }

    final startTime = timeLabel(netinPoints.first.time);
    final midTime = timeLabel(netinPoints[netinPoints.length ~/ 2].time);
    final endTime = timeLabel(netinPoints.last.time);

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
          Row(children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: colors.textSecondary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppRadius.xs),
              ),
              child: Icon(Icons.swap_vert, color: colors.textSecondary, size: 14),
            ),
            const SizedBox(width: 8),
            Text('Ağ Trafiği',
                style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600)),
            const Spacer(),
            // Gelen — rengi grafikteki "Gelen" çizgisiyle aynı (success),
            // gerçek bir durum değil ama alt kısımdaki lejantla eşleşmesi
            // için kasıtlı olarak korunuyor.
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: colors.success.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(AppRadius.xs),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.arrow_downward, size: 10, color: colors.success),
                const SizedBox(width: 3),
                Text(fmtBps(lastIn),
                    style: TextStyle(
                        color: colors.success,
                        fontSize: 10,
                        fontWeight: FontWeight.bold)),
              ]),
            ),
            const SizedBox(width: 6),
            // Giden — aynı şekilde grafikteki "Giden" çizgisiyle (info) eşleşir.
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: colors.info.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(AppRadius.xs),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.arrow_upward, size: 10, color: colors.info),
                const SizedBox(width: 3),
                Text(fmtBps(lastOut),
                    style: TextStyle(
                        color: colors.info,
                        fontSize: 10,
                        fontWeight: FontWeight.bold)),
              ]),
            ),
          ]),

          const SizedBox(height: 14),

          SizedBox(
            height: 180,
            child: LineChart(
              LineChartData(
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: interval,
                  getDrawingHorizontalLine: (_) => FlLine(
                    color: colors.hairline,
                    strokeWidth: 1,
                  ),
                ),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 52,
                      interval: interval,
                      getTitlesWidget: (val, _) => Text(
                        fmtBps(val),
                        style: TextStyle(color: colors.textMuted, fontSize: 8),
                      ),
                    ),
                  ),
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 22,
                      getTitlesWidget: (val, _) {
                        final idx = val.toInt();
                        final mid = netinPoints.length ~/ 2;
                        if (idx == 0) {
                          return Text(startTime,
                              style:
                                  TextStyle(color: colors.textMuted, fontSize: 9));
                        }
                        if (idx == mid) {
                          return Text(midTime,
                              style:
                                  TextStyle(color: colors.textMuted, fontSize: 9));
                        }
                        if (idx == netinPoints.length - 1) {
                          return Text(endTime,
                              style:
                                  TextStyle(color: colors.textMuted, fontSize: 9));
                        }
                        return const SizedBox.shrink();
                      },
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
                clipData: const FlClipData.all(),
                lineBarsData: [
                  LineChartBarData(
                    spots: netinPoints.map((p) => p.spot).toList(),
                    isCurved: true,
                    curveSmoothness: 0.3,
                    color: colors.success,
                    barWidth: 2,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          colors.success.withValues(alpha: 0.15),
                          colors.success.withValues(alpha: 0.0),
                        ],
                      ),
                    ),
                  ),
                  if (netoutPoints.length >= 2)
                    LineChartBarData(
                      spots: netoutPoints.map((p) => p.spot).toList(),
                      isCurved: true,
                      curveSmoothness: 0.3,
                      color: colors.info,
                      barWidth: 2,
                      dotData: const FlDotData(show: false),
                      belowBarData: BarAreaData(
                        show: true,
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            colors.info.withValues(alpha: 0.12),
                            colors.info.withValues(alpha: 0.0),
                          ],
                        ),
                      ),
                    ),
                ],
                minY: 0,
                maxY: chartMax,
                minX: netinPoints.first.x,
                maxX: netinPoints.last.x,
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Legend
          Row(children: [
            _LegendDot(color: colors.success, label: 'Gelen'),
            const SizedBox(width: 16),
            _LegendDot(color: colors.info, label: 'Giden'),
          ]),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Stat chip (Min/Ort/Maks) — Min/Maks nötr, sadece Ort metriğin kendi
// renginde kalır (Ortalama = o grafiğin "başlık" değeri; Min/Maks sadece
// tanımlayıcı istatistik, bir uyarı/başarı durumu değil).
// ─────────────────────────────────────────────

class _StatChip extends StatelessWidget {
  final String label, value;
  final Color color;
  final AppThemeData colors;
  final bool muted;

  const _StatChip({
    required this.label,
    required this.value,
    required this.color,
    required this.colors,
    this.muted = false,
  });

  @override
  Widget build(BuildContext context) {
    final displayColor = muted ? colors.textSecondary : color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: displayColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.xs),
        border: Border.all(color: displayColor.withValues(alpha: 0.2)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(label,
            style: TextStyle(
                color: colors.textMuted,
                fontSize: 10,
                fontWeight: FontWeight.w500)),
        const SizedBox(width: 5),
        Text(value,
            style: TextStyle(
                color: displayColor, fontSize: 11, fontWeight: FontWeight.bold)),
      ]),
    );
  }
}

// ─────────────────────────────────────────────
// Legend dot
// ─────────────────────────────────────────────

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 5),
      Text(label, style: TextStyle(color: colors.textSecondary, fontSize: 11)),
    ]);
  }
}

// ─────────────────────────────────────────────
// Section Card
// ─────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  final AppThemeData colors;
  final String title;
  final IconData icon;
  final List<Widget> children;

  const _SectionCard({
    required this.colors,
    required this.title,
    required this.icon,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: colors.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(children: [
              Icon(icon, color: colors.textMuted, size: 15),
              const SizedBox(width: 7),
              SectionLabel(title),
            ]),
          ),
          Divider(height: 1, thickness: 1, indent: 16, endIndent: 16, color: colors.hairline),
          ...children.asMap().entries.map((e) => Column(children: [
                e.value,
                if (e.key < children.length - 1)
                  Divider(
                      height: 1,
                      thickness: 0.5,
                      indent: 16,
                      endIndent: 16,
                      color: colors.hairline),
              ])),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Info Row
// ─────────────────────────────────────────────

class _InfoRow extends StatelessWidget {
  final AppThemeData colors;
  final String label, value;
  final Color? valueColor;

  const _InfoRow({
    required this.colors,
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      child: Row(children: [
        Text(label,
            style: TextStyle(color: colors.textSecondary, fontSize: 13)),
        const Spacer(),
        Text(value,
            style: TextStyle(
                color: valueColor ?? colors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w500)),
      ]),
    );
  }
}

// ─────────────────────────────────────────────
// Action Button
// ─────────────────────────────────────────────

/// Dolgun renkli buton yerine tonal/outline: renk sadece metin+ikonda ve
/// hafif bir zemin/kenarlıkta anlam taşır — "Durdur"/"Sil" gibi yıkıcı
/// aksiyonlar bile büyük kırmızı bir buton olarak bağırmıyor.
class _ActionButton extends StatelessWidget {
  final AppThemeData colors;
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionButton({
    required this.colors,
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 16, color: color),
      label: Text(label,
          style:
              TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w600)),
      style: OutlinedButton.styleFrom(
        backgroundColor: color.withValues(alpha: 0.08),
        side: BorderSide(color: color.withValues(alpha: 0.4)),
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
      ),
    );
  }
}
