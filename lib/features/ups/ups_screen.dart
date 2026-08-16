import 'package:flutter/material.dart';
import '../../core/utils/app_transitions.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../../core/services/connectivity_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/design_widgets.dart';
import '../../core/utils/connection_target.dart';
import '../../core/widgets/connection_issue_view.dart';
import 'nut_provider.dart';
import 'nut_service.dart';

class UpsScreen extends StatefulWidget {
  const UpsScreen({super.key});

  @override
  State<UpsScreen> createState() => _UpsScreenState();
}

class _UpsScreenState extends State<UpsScreen> {
  @override
  void initState() {
    super.initState();
    final provider = context.read<NutProvider>();
    Future.microtask(() => provider.init());
  }

  void _showAddServerSheet(BuildContext context) {
    appShowModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _AddServerSheet(
        onSave: (server) => context.read<NutProvider>().addServer(server),
      ),
    );
  }

  /// "Kimlik bilgisi gerekli" kartına dokununca — mevcut sunucuyu (yapı
  /// bilgisi dolu, kimlik bilgisi boş) düzenleme sheet'i olarak açar.
  void _showEditServerSheet(
      BuildContext context, int index, NutServer server) {
    appShowModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _AddServerSheet(
        existing: server,
        onSave: (updated) =>
            context.read<NutProvider>().updateServer(index, updated),
      ),
    );
  }

  void _confirmRemove(BuildContext context, NutProvider provider, int index) {
    appShowDialog(
      context: context,
      builder: (ctx) {
        final dColors = ctx.appColors;
        return AlertDialog(
          backgroundColor: dColors.surface1,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.md)),
          title: Text('Sunucuyu Kaldır',
              style: TextStyle(color: dColors.textPrimary)),
          content: Text(
            '${provider.servers[index].name} kaldırılacak.',
            style: TextStyle(color: dColors.textSecondary, fontSize: 13),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child:
                  Text('İptal', style: TextStyle(color: dColors.textSecondary)),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                provider.removeServer(index);
              },
              child: Text('Kaldır',
                  style: TextStyle(
                      color: dColors.error, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<NutProvider>();

    if (provider.servers.isEmpty) {
      return _SetupScreen(onAddServer: () => _showAddServerSheet(context));
    }

    final colors = context.appColors;
    final hasInternet = context.watch<ConnectivityProvider>().hasInternet;

    return RefreshIndicator(
      onRefresh: () => provider.refresh(),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
        children: [
          Row(
            children: [
              Text(
                'UPS Monitör',
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => _showAddServerSheet(context),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: colors.primary,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: const Icon(Icons.add, color: Colors.white, size: 20),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...provider.servers.asMap().entries.map((entry) {
            final i = entry.key;
            final server = entry.value;
            final connected = provider.serverConnected[server.name] ?? false;

            Widget? connectionBanner;
            if (server.needsCredentials) {
              // Yapı bilgisiyle (cloud) geldi ama kullanıcı adı/şifre bu
              // cihazda hiç girilmemiş — hiç sorgu atılmadı, "erişilemiyor"
              // mesajından kasıtlı olarak ayrı (bkz. credential_sync.dart).
              connectionBanner = InkWell(
                onTap: () => _showEditServerSheet(context, i, server),
                borderRadius: BorderRadius.circular(AppRadius.md),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: colors.surface2,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    border: Border.all(color: colors.hairline),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.key_off_rounded,
                          color: colors.textMuted, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Kimlik bilgisi gerekli',
                                style: TextStyle(
                                    color: colors.warning,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600)),
                            const SizedBox(height: 2),
                            Text(
                                'Bu sunucu başka bir cihazda eklendi — kullanıcı adı/şifre girmek için dokunun',
                                style: TextStyle(
                                    color: colors.textMuted, fontSize: 11)),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right,
                          color: colors.textMuted, size: 16),
                    ],
                  ),
                ),
              );
            } else if (!connected) {
              final kind = !hasInternet
                  ? ConnectionIssueKind.noInternet
                  : switch (classifyHost(server.host)) {
                      ConnectionTarget.privateNetwork =>
                        ConnectionIssueKind.privateNetwork,
                      ConnectionTarget.tailscale =>
                        ConnectionIssueKind.tailscale,
                      ConnectionTarget.external => ConnectionIssueKind.generic,
                    };
              final (title, message) =
                  connectionIssueCopy(kind, 'UPS', server.host);
              final isGeneric = kind == ConnectionIssueKind.generic;
              final issueColor = isGeneric ? colors.error : colors.textSecondary;

              connectionBanner = Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isGeneric ? colors.errorMuted : colors.surface2,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(
                    color: isGeneric
                        ? colors.error.withValues(alpha: 0.2)
                        : colors.hairline,
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      isGeneric ? Icons.error_outline : Icons.lan_outlined,
                      color: isGeneric ? colors.error : colors.textMuted,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: TextStyle(
                                color: issueColor,
                                fontSize: 12,
                                fontWeight: FontWeight.w600),
                          ),
                          if (message.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              message,
                              style: TextStyle(
                                  color: colors.textMuted, fontSize: 11),
                            ),
                          ],
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: () => provider.refresh(),
                      child: Text(
                        'Tekrar Dene',
                        style: TextStyle(color: issueColor, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              );
            }

            return Column(
              key: ValueKey(server.name),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    StatusIndicator(
                      color: server.needsCredentials
                          ? colors.warning
                          : connected
                              ? colors.success
                              : colors.error,
                      label: server.name,
                      style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${server.host}:${server.port}',
                      style: TextStyle(color: colors.textMuted, fontSize: 11),
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: () => _confirmRemove(context, provider, i),
                      child: Icon(Icons.delete_outline,
                          color: colors.textMuted, size: 16),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                // Kimlik bilgisi eksikken hiç sorgu atılmadığından, burada
                // sonsuza dek dönecek bir yükleniyor kartı göstermek yerine
                // UPS listesi tamamen atlanır (bkz. aşağıdaki connectionBanner).
                if (!server.needsCredentials)
                  ...server.upsNames.map((upsName) {
                  final key = '${server.name}/$upsName';
                  final data = provider.upsDataMap[key];

                  if (data == null) {
                    if (!connected) return const SizedBox.shrink();
                    return Container(
                      key: ValueKey(key),
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: colors.surface1,
                        borderRadius: BorderRadius.circular(AppRadius.md),
                      ),
                      child: const Center(child: CircularProgressIndicator()),
                    );
                  }

                  return GestureDetector(
                    key: ValueKey(key),
                    onTap: () => Navigator.push(
                      context,
                      AppTransitions.slideFade(_UpsDetailScreen(data: data)),
                    ),
                    child: _UpsCard(data: data, isStale: !connected)
                        .animate()
                        .fadeIn(duration: AppMotion.slow, curve: AppMotion.curve)
                        .slideY(
                            begin: 0.05,
                            end: 0,
                            duration: AppMotion.slow,
                            curve: AppMotion.curve),
                  );
                }),
                if (connectionBanner != null) connectionBanner,
                const SizedBox(height: 8),
              ],
            );
          }),
        ],
      ),
    );
  }
}

// ── UPS Kartı ─────────────────────────────────────────────────────────────

/// UPS durumuna karşılık gelen renk. `_UpsCard` ve `_UpsDetailScreen` aynı
/// eşlemeyi kullanır — tek yerden yönetilmezse ikisi zamanla birbirinden
/// sapabilir (nitekim detay ekranındaki "Durum" alanı daha önce bu eşlemeyi
/// kullanmak yerine rengi sabit `success` olarak hardcode etmişti).
Color upsStatusColor(AppThemeData colors, UpsStatus status) {
  switch (status) {
    case UpsStatus.online:
      return colors.success;
    case UpsStatus.onBattery:
      return colors.warning;
    case UpsStatus.lowBattery:
      return colors.error;
    case UpsStatus.charging:
      return colors.info;
    default:
      return colors.textMuted;
  }
}

Color upsChargeColor(AppThemeData colors, double charge) {
  if (charge >= 80) return colors.success;
  if (charge >= 40) return colors.warning;
  return colors.error;
}

class _UpsCard extends StatelessWidget {
  final UpsData data;
  final bool isStale;

  const _UpsCard({required this.data, this.isStale = false});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final statusColor = upsStatusColor(colors, data.parsedStatus);
    final chargeColor = upsChargeColor(colors, data.batteryCharge);

    // Opaklık sadece bayat SAYISAL veriye (üst kısım) uygulanıyor — kenarlık
    // ve alttaki "Son güncelleme" göstergesi tam opaklıkta kalıyor, aksi
    // halde uyarı sinyalinin kendisi de soluklaşıp fark edilmez oluyordu.
    final staleContent = Column(
      children: [
        Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: colors.surface2,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Icon(Icons.electrical_services,
                      color: statusColor, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        data.model,
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        data.manufacturer,
                        style: TextStyle(color: colors.textMuted, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                StatusIndicator(
                  color: statusColor,
                  label: data.statusLabel,
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              children: [
                Row(
                  children: [
                    Icon(Icons.battery_charging_full,
                        color: chargeColor, size: 16),
                    const SizedBox(width: 6),
                    Text(
                      'Batarya',
                      style:
                          TextStyle(color: colors.textSecondary, fontSize: 12),
                    ),
                    const Spacer(),
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: data.batteryCharge),
                      duration: AppMotion.slow,
                      curve: AppMotion.curve,
                      builder: (_, val, __) => Text(
                        '${val.toStringAsFixed(0)}%',
                        style: TextStyle(
                          color: chargeColor,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    if (data.runtimeRemaining > 0) ...[
                      const SizedBox(width: 8),
                      Text(
                        '· ${data.runtimeLabel}',
                        style: TextStyle(color: colors.textMuted, fontSize: 11),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 6),
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: data.batteryCharge / 100),
                  duration: AppMotion.slow,
                  curve: AppMotion.curve,
                  builder: (_, val, __) => ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.xs),
                    child: LinearProgressIndicator(
                      value: val.clamp(0.0, 1.0),
                      backgroundColor: colors.surface2,
                      valueColor: AlwaysStoppedAnimation<Color>(chargeColor),
                      minHeight: 8,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Container(
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: colors.hairline)),
            ),
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _MetricTile(
                        icon: Icons.input,
                        label: 'Giriş V',
                        value: '${data.inputVoltage.toStringAsFixed(0)}V',
                        color: colors.textSecondary,
                      ),
                    ),
                    Expanded(
                      child: _MetricTile(
                        icon: Icons.output,
                        label: 'Çıkış V',
                        value: '${data.outputVoltage.toStringAsFixed(0)}V',
                        color: colors.textSecondary,
                      ),
                    ),
                    Expanded(
                      child: _MetricTile(
                        icon: Icons.speed,
                        label: 'Yük',
                        value: '${data.load.toStringAsFixed(0)}%',
                        color: colors.thresholdColor(data.load),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _MetricTile(
                        icon: Icons.thermostat,
                        label: 'Sıcaklık',
                        value: '${data.temperature.toStringAsFixed(1)}°C',
                        color: data.temperature > 40
                            ? colors.error
                            : colors.success,
                      ),
                    ),
                    Expanded(
                      child: _MetricTile(
                        icon: Icons.electric_bolt,
                        label: 'Batarya V',
                        value: '${data.batteryVoltage.toStringAsFixed(1)}V',
                        color: colors.textSecondary,
                      ),
                    ),
                    Expanded(
                      child: _MetricTile(
                        icon: Icons.waves,
                        label: 'Frekans',
                        value: '${data.inputFrequency.toStringAsFixed(1)}Hz',
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      );

    final footer = Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: colors.hairline)),
        borderRadius:
            const BorderRadius.vertical(bottom: Radius.circular(AppRadius.md)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Text(
            'Firmware: ${data.firmware}',
            style: TextStyle(color: colors.textMuted, fontSize: 10),
          ),
          const SizedBox(width: 12),
          Text(
            'Driver: ${data.driverName}',
            style: TextStyle(color: colors.textMuted, fontSize: 10),
          ),
          const Spacer(),
          if (isStale) ...[
            Icon(Icons.warning_amber_rounded, size: 12, color: colors.warning),
            const SizedBox(width: 4),
          ],
          Text(
            '${isStale ? 'Son güncelleme: ' : ''}'
            '${data.updatedAt.hour.toString().padLeft(2, '0')}:'
            '${data.updatedAt.minute.toString().padLeft(2, '0')}',
            style: TextStyle(
                color: isStale ? colors.warning : colors.textMuted,
                fontSize: 10,
                fontWeight: isStale ? FontWeight.w600 : FontWeight.normal),
          ),
        ],
      ),
    );

    final card = Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: isStale ? colors.warning : colors.hairline),
      ),
      child: Column(
        children: [
          isStale ? Opacity(opacity: 0.6, child: staleContent) : staleContent,
          footer,
        ],
      ),
    );

    return card;
  }
}

// ── Metrik Tile ───────────────────────────────────────────────────────────

class _MetricTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _MetricTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Column(
      children: [
        Icon(icon, color: color, size: 16),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
              color: color, fontSize: 13, fontWeight: FontWeight.bold),
        ),
        Text(
          label,
          style: TextStyle(color: colors.textMuted, fontSize: 10),
        ),
      ],
    );
  }
}

// ── Setup Ekranı ──────────────────────────────────────────────────────────

class _SetupScreen extends StatelessWidget {
  final VoidCallback onAddServer;

  const _SetupScreen({required this.onAddServer});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: colors.primary.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.electrical_services,
                  color: colors.primary, size: 48),
            ),
            const SizedBox(height: 20),
            Text(
              'UPS Monitör',
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'NUT (Network UPS Tools) sunucunuzu ekleyerek\nUPS\'inizi anlık izleyebilirsiniz.',
              textAlign: TextAlign.center,
              style:
                  TextStyle(color: colors.textMuted, fontSize: 13, height: 1.6),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: colors.surface2,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: colors.hairline),
              ),
              child: Text(
                'NUT varsayılan port: 3493\n'
                'Proxmox üzerinde NUT kuruluysa\n'
                'Proxmox IP adresinizi girebilirsiniz.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: colors.textSecondary,
                  fontSize: 12,
                  height: 1.5,
                ),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: onAddServer,
                icon: const Icon(Icons.add, color: Colors.white, size: 18),
                label: const Text(
                  'NUT Sunucusu Ekle',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: colors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.sm)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Sunucu Ekleme Sheet ───────────────────────────────────────────────────

class _AddServerSheet extends StatefulWidget {
  final Function(NutServer) onSave;
  final NutServer? existing;

  const _AddServerSheet({required this.onSave, this.existing});

  @override
  State<_AddServerSheet> createState() => _AddServerSheetState();
}

class _AddServerSheetState extends State<_AddServerSheet> {
  late final _nameCtrl =
      TextEditingController(text: widget.existing?.name ?? '');
  late final _hostCtrl =
      TextEditingController(text: widget.existing?.host ?? '');
  late final _portCtrl = TextEditingController(
      text: (widget.existing?.port ?? 3493).toString());
  // Kullanıcı adı/şifre bilinçli olarak prefill edilmiyor — kimlik bilgisi
  // eksik senaryosunda zaten boş, kullanıcı burada girer.
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  late final _upsNameCtrl = TextEditingController(
      text: widget.existing?.upsNames.join(', ') ?? '');
  bool _testing = false;
  bool? _testResult;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _hostCtrl.dispose();
    _portCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    _upsNameCtrl.dispose();
    super.dispose();
  }

  Future<void> _test() async {
    setState(() {
      _testing = true;
      _testResult = null;
    });
    final server = NutServer(
      name: _nameCtrl.text.trim().isEmpty ? 'test' : _nameCtrl.text.trim(),
      host: _hostCtrl.text.trim(),
      port: int.tryParse(_portCtrl.text.trim()) ?? 3493,
      username: _userCtrl.text.trim(),
      password: _passCtrl.text.trim(),
    );
    final result = await context.read<NutProvider>().testConnection(server);
    if (!mounted) return;
    setState(() {
      _testing = false;
      _testResult = result;
    });
  }

  void _save() {
    final colors = context.appColors;
    if (_nameCtrl.text.trim().isEmpty || _hostCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Lütfen zorunlu alanları doldurun'),
          backgroundColor: colors.error,
        ),
      );
      return;
    }

    final upsNames = _upsNameCtrl.text.trim().isNotEmpty
        ? _upsNameCtrl.text.trim().split(',').map((e) => e.trim()).toList()
        : <String>[];

    widget.onSave(NutServer(
      name: _nameCtrl.text.trim(),
      host: _hostCtrl.text.trim(),
      port: int.tryParse(_portCtrl.text.trim()) ?? 3493,
      username: _userCtrl.text.trim(),
      password: _passCtrl.text.trim(),
      upsNames: upsNames,
    ));
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(AppRadius.md)),
      ),
      padding: EdgeInsets.fromLTRB(
        24,
        16,
        24,
        MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
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
            const SizedBox(height: 20),
            Text(
              'NUT Sunucusu Ekle',
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'UPS adını boş bırakırsanız otomatik algılanır',
              style: TextStyle(color: colors.textMuted, fontSize: 11),
            ),
            const SizedBox(height: 20),
            _field(
              context,
              'Sunucu Adı *',
              _nameCtrl,
              'Örn: Homelab UPS',
              icon: Icons.label_outline,
            ),
            _field(
              context,
              'Host / IP *',
              _hostCtrl,
              '192.168.1.x veya hostname',
              icon: Icons.dns_outlined,
            ),
            _field(
              context,
              'Port',
              _portCtrl,
              '3493',
              icon: Icons.electrical_services_outlined,
              keyboard: TextInputType.number,
            ),
            _field(
              context,
              'Kullanıcı Adı',
              _userCtrl,
              'Opsiyonel',
              icon: Icons.person_outline,
            ),
            _field(
              context,
              'Şifre',
              _passCtrl,
              'Opsiyonel',
              icon: Icons.lock_outline,
              obscure: true,
            ),
            _field(
              context,
              'UPS Adı',
              _upsNameCtrl,
              'powerful (boş = otomatik)',
              icon: Icons.electrical_services,
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _testing ? null : _test,
                icon: _testing
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        _testResult == null
                            ? Icons.wifi_find
                            : _testResult!
                                ? Icons.check_circle
                                : Icons.error_outline,
                        size: 16,
                        color: _testResult == null
                            ? colors.primary
                            : _testResult!
                                ? colors.success
                                : colors.error,
                      ),
                label: Text(
                  _testResult == null
                      ? 'Bağlantıyı Test Et'
                      : _testResult!
                          ? 'Bağlantı Başarılı'
                          : 'Bağlantı Başarısız',
                  style: TextStyle(
                    color: _testResult == null
                        ? colors.primary
                        : _testResult!
                            ? colors.success
                            : colors.error,
                    fontSize: 13,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(
                    color: _testResult == null
                        ? colors.primary.withValues(alpha: 0.4)
                        : _testResult!
                            ? colors.success.withValues(alpha: 0.4)
                            : colors.error.withValues(alpha: 0.4),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.sm)),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: colors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.sm)),
                ),
                child: const Text(
                  'Kaydet',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(
    BuildContext context,
    String label,
    TextEditingController ctrl,
    String hint, {
    IconData? icon,
    bool obscure = false,
    TextInputType keyboard = TextInputType.text,
  }) {
    final colors = context.appColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: ctrl,
        obscureText: obscure,
        keyboardType: keyboard,
        style: TextStyle(color: colors.textPrimary, fontSize: 14),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          prefixIcon: icon != null
              ? Icon(icon, color: colors.textMuted, size: 18)
              : null,
          labelStyle: TextStyle(color: colors.textSecondary, fontSize: 13),
          hintStyle: TextStyle(color: colors.textMuted, fontSize: 13),
          filled: true,
          fillColor: colors.surface2,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            borderSide: BorderSide(color: colors.primary, width: 1.5),
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
      ),
    );
  }
}

// ── UPS Detay Ekranı ──────────────────────────────────────────────────────

class _UpsDetailScreen extends StatelessWidget {
  final UpsData data;

  const _UpsDetailScreen({required this.data});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    final groups = <String, Map<String, String>>{
      'Batarya': {},
      'Giriş': {},
      'Çıkış': {},
      'UPS': {},
      'Sürücü': {},
      'Cihaz': {},
      'Diğer': {},
    };

    for (final entry in data.vars.entries) {
      final key = entry.key;
      if (key.startsWith('battery.')) {
        groups['Batarya']![key] = entry.value;
      } else if (key.startsWith('input.')) {
        groups['Giriş']![key] = entry.value;
      } else if (key.startsWith('output.')) {
        groups['Çıkış']![key] = entry.value;
      } else if (key.startsWith('ups.')) {
        groups['UPS']![key] = entry.value;
      } else if (key.startsWith('driver.')) {
        groups['Sürücü']![key] = entry.value;
      } else if (key.startsWith('device.')) {
        groups['Cihaz']![key] = entry.value;
      } else {
        groups['Diğer']![key] = entry.value;
      }
    }

    return Scaffold(
      backgroundColor: colors.surface0,
      appBar: AppBar(
        backgroundColor: colors.surface1,
        elevation: 0,
        title: Text(
          data.model,
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios, color: colors.textPrimary, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, color: colors.hairline),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Özet kart
          Container(
            padding: const EdgeInsets.all(16),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: colors.surface1,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _DetailSummaryTile(
                    label: 'Durum',
                    value: data.statusLabel,
                    color: upsStatusColor(colors, data.parsedStatus),
                  ),
                ),
                Expanded(
                  child: _DetailSummaryTile(
                    label: 'Batarya',
                    value: '${data.batteryCharge.toStringAsFixed(0)}%',
                    color: upsChargeColor(colors, data.batteryCharge),
                  ),
                ),
                Expanded(
                  child: _DetailSummaryTile(
                    label: 'Yük',
                    value: '${data.load.toStringAsFixed(0)}%',
                    color: colors.thresholdColor(data.load),
                  ),
                ),
                Expanded(
                  child: _DetailSummaryTile(
                    label: 'Süre',
                    value: data.runtimeLabel,
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          // Gruplar
          ...groups.entries
              .where((e) => e.value.isNotEmpty)
              .map((group) => _DetailGroup(
                    key: ValueKey(group.key),
                    title: group.key,
                    vars: group.value,
                    colors: colors,
                  )),
        ],
      ),
    );
  }
}

class _DetailSummaryTile extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _DetailSummaryTile({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(color: colors.textMuted, fontSize: 10),
        ),
      ],
    );
  }
}

class _DetailGroup extends StatelessWidget {
  final String title;
  final Map<String, String> vars;
  final AppThemeData colors;

  const _DetailGroup({
    super.key,
    required this.title,
    required this.vars,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: SectionLabel(title),
          ),
          Divider(height: 1, color: colors.hairline),
          ...vars.entries.map((e) => _DetailRow(
                key: ValueKey(e.key),
                varKey: e.key,
                value: e.value,
                colors: colors,
              )),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String varKey;
  final String value;
  final AppThemeData colors;

  const _DetailRow({
    super.key,
    required this.varKey,
    required this.value,
    required this.colors,
  });

  static final _translations = {
    // Batarya
    'battery.charge': 'Şarj Seviyesi',
    'battery.charge.low': 'Düşük Şarj Eşiği',
    'battery.charge.warning': 'Uyarı Şarj Eşiği',
    'battery.voltage': 'Batarya Voltajı',
    'battery.voltage.high': 'Yüksek Voltaj Eşiği',
    'battery.voltage.low': 'Düşük Voltaj Eşiği',
    'battery.voltage.nominal': 'Nominal Batarya Voltajı',
    'battery.current': 'Batarya Akımı',
    'battery.current.total': 'Toplam Batarya Akımı',
    'battery.runtime': 'Kalan Süre (sn)',
    'battery.runtime.low': 'Düşük Süre Eşiği (sn)',
    'battery.runtime.restart': 'Yeniden Başlatma İçin Gereken Süre (sn)',
    'battery.type': 'Batarya Tipi',
    'battery.date': 'Batarya Değişim Tarihi',
    'battery.mfr.date': 'Batarya Üretim Tarihi',
    'battery.temperature': 'Batarya Sıcaklığı',
    'battery.packs': 'Batarya Paketi Sayısı',
    'battery.packs.bad': 'Arızalı Paket Sayısı',
    'battery.protection': 'Batarya Koruma Durumu',
    'battery.energysave': 'Enerji Tasarrufu Modu',
    'battery.alarm.threshold': 'Alarm Eşiği',
    // Giriş
    'input.voltage': 'Giriş Voltajı',
    'input.voltage.nominal': 'Nominal Giriş Voltajı',
    'input.voltage.minimum': 'Minimum Giriş Voltajı',
    'input.voltage.maximum': 'Maksimum Giriş Voltajı',
    'input.voltage.extended': 'Genişletilmiş Giriş Voltajı',
    'input.voltage.fault': 'Arıza Anındaki Giriş Voltajı',
    'input.frequency': 'Giriş Frekansı',
    'input.frequency.nominal': 'Nominal Giriş Frekansı',
    'input.frequency.low': 'Minimum Giriş Frekansı',
    'input.frequency.high': 'Maksimum Giriş Frekansı',
    'input.frequency.extended': 'Genişletilmiş Frekans Aralığı',
    'input.transfer.low': 'Düşük Voltaj Transfer Eşiği',
    'input.transfer.high': 'Yüksek Voltaj Transfer Eşiği',
    'input.transfer.reason': 'Son Transfer Nedeni',
    'input.sensitivity': 'Giriş Hassasiyeti',
    'input.current': 'Giriş Akımı',
    'input.current.nominal': 'Nominal Giriş Akımı',
    'input.power': 'Giriş Gücü',
    'input.realpower': 'Gerçek Giriş Gücü',
    // Çıkış
    'output.voltage': 'Çıkış Voltajı',
    'output.voltage.nominal': 'Nominal Çıkış Voltajı',
    'output.frequency': 'Çıkış Frekansı',
    'output.frequency.nominal': 'Nominal Çıkış Frekansı',
    'output.current': 'Çıkış Akımı',
    'output.current.nominal': 'Nominal Çıkış Akımı',
    'output.power': 'Çıkış Gücü',
    'output.realpower': 'Gerçek Çıkış Gücü',
    // UPS
    'ups.status': 'UPS Durumu',
    'ups.load': 'Anlık Yük',
    'ups.load.high': 'Yüksek Yük Eşiği',
    'ups.model': 'Model',
    'ups.mfr': 'Üretici',
    'ups.mfr.date': 'Üretim Tarihi',
    'ups.serial': 'Seri Numarası',
    'ups.firmware': 'Donanım Yazılımı',
    'ups.firmware.aux': 'Yardımcı Donanım Yazılımı',
    'ups.type': 'UPS Tipi',
    'ups.temperature': 'UPS İç Sıcaklığı',
    'ups.beeper.status': 'Sesli Uyarı Durumu',
    'ups.delay.shutdown': 'Kapanma Gecikmesi (sn)',
    'ups.delay.start': 'Başlatma Gecikmesi (sn)',
    'ups.power': 'Anlık Güç (VA)',
    'ups.power.nominal': 'Nominal Güç (VA)',
    'ups.realpower': 'Gerçek Güç (W)',
    'ups.realpower.nominal': 'Nominal Gerçek Güç (W)',
    'ups.test.result': 'Son Test Sonucu',
    'ups.test.date': 'Son Test Tarihi',
    'ups.efficiency': 'Verimlilik',
    'ups.id': 'UPS Kimliği',
    'ups.displayname': 'Görünen Ad',
    'ups.vendorid': 'Üretici Kodu',
    'ups.productid': 'Ürün Kodu',
    'ups.watchdog.status': 'İzleme Durumu',
    'ups.start.auto': 'Otomatik Başlatma',
    'ups.start.battery': 'Batarya ile Başlatma',
    'ups.start.reboot': 'Yeniden Başlatma Modu',
    'ups.shutdown': 'Kapanma Durumu',
    // Sürücü
    'driver.name': 'Sürücü Adı',
    'driver.version': 'Sürücü Sürümü',
    'driver.version.data': 'Sürücü Veri Sürümü',
    'driver.version.internal': 'Sürücü İç Sürümü',
    'driver.version.usb': 'USB Sürücü Sürümü',
    'driver.flag.allow_killpower': 'Güç Kesme İzni',
    'driver.debug': 'Hata Ayıklama Seviyesi',
    'driver.state': 'Sürücü Durumu',
    'driver.parameter.port': 'Bağlantı Noktası',
    'driver.parameter.bus': 'USB Bus Numarası',
    'driver.parameter.device': 'USB Cihaz Numarası',
    'driver.parameter.vendorid': 'Üretici ID',
    'driver.parameter.productid': 'Ürün ID',
    'driver.parameter.serial': 'Seri Numarası',
    'driver.parameter.pollfreq': 'Periyodik Sorgulama Sıklığı',
    'driver.parameter.pollinterval': 'Sorgulama Aralığı (sn)',
    'driver.parameter.synchronous': 'Senkron Sürücü Modu',
    'driver.parameter.lowbatt': 'Düşük Batarya Eşiği',
    'driver.parameter.offdelay': 'Kapanma Gecikmesi',
    'driver.parameter.ondelay': 'Açılma Gecikmesi',
    'driver.parameter.override.battery.charge.low': 'Düşük Şarj Eşiği (Geçersiz Kılma)',
    'driver.parameter.override.ups.delay.shutdown': 'Kapanma Gecikmesi (Geçersiz Kılma)',
    'driver.parameter.override.ups.delay.start': 'Açılma Gecikmesi (Geçersiz Kılma)',
    // Cihaz
    'device.model': 'Cihaz Modeli',
    'device.mfr': 'Cihaz Üreticisi',
    'device.serial': 'Cihaz Seri Numarası',
    'device.type': 'Cihaz Tipi',
    'device.description': 'Cihaz Açıklaması',
    'device.contact': 'İletişim Bilgisi',
    'device.location': 'Cihaz Konumu',
    'device.part': 'Parça Numarası',
    'device.macaddr': 'MAC Adresi',
  };

  static const _descriptions = {
    // Batarya
    'battery.charge': 'Bataryanın anlık şarj yüzdesi.',
    'battery.charge.low': 'Bu seviyenin altında UPS kritik uyarı verir.',
    'battery.charge.warning': 'Bu seviyenin altında UPS uyarı vermeye başlar.',
    'battery.voltage': 'Bataryanın anlık voltaj değeri.',
    'battery.voltage.high': 'Batarya voltajının güvenli üst sınırı. Bu değerin üstü aşırı şarj riskine işaret eder.',
    'battery.voltage.low': 'Batarya voltajının güvenli alt sınırı. Bu değerin altı derin deşarj riskine işaret eder.',
    'battery.voltage.nominal': 'Bataryanın tasarım voltajı.',
    'battery.current': 'Bataryaya giren veya çıkan anlık akım.',
    'battery.current.total': 'Tüm batarya paketlerinin toplam akımı.',
    'battery.runtime': 'Mevcut yük ile tahmini çalışma süresi.',
    'battery.runtime.low': 'Bu sürenin altında UPS kritik uyarı verir.',
    'battery.runtime.restart': 'UPS yeniden başlatılabilmek için gereken minimum şarj süresi.',
    'battery.type': 'Kullanılan batarya teknolojisi (ör. PbAc = Kurşun-Asit).',
    'battery.date': 'Bataryanın en son değiştirildiği tarih.',
    'battery.mfr.date': 'Bataryanın fabrikadan çıkış tarihi.',
    'battery.temperature': 'Bataryanın anlık sıcaklığı.',
    'battery.packs': 'UPS içindeki batarya paketi sayısı.',
    'battery.packs.bad': 'Arızalı veya değiştirilmesi gereken paket sayısı.',
    'battery.protection': 'Aşırı deşarjdan koruma aktif mi?',
    'battery.energysave': 'Düşük yükte enerji tasarrufu modu etkin mi?',
    'battery.alarm.threshold': 'Alarm tetiklenecek şarj eşiği.',
    // Giriş
    'input.voltage': 'Şebeke hattından gelen anlık voltaj.',
    'input.voltage.nominal': 'UPS\'in tasarlandığı nominal şebeke voltajı.',
    'input.voltage.minimum': 'Son ölçüm dönemindeki minimum giriş voltajı.',
    'input.voltage.maximum': 'Son ölçüm dönemindeki maksimum giriş voltajı.',
    'input.voltage.extended': 'Genişletilmiş voltaj aralığı desteği.',
    'input.frequency': 'Şebekeden gelen anlık frekans (Hz).',
    'input.frequency.nominal': 'Beklenen nominal şebeke frekansı.',
    'input.frequency.low': 'Kabul edilen minimum frekans değeri.',
    'input.frequency.high': 'Kabul edilen maksimum frekans değeri.',
    'input.frequency.extended': 'Genişletilmiş frekans aralığı desteği.',
    'input.transfer.low': 'Şebeke voltajı bu değerin altına düşünce bataryaya geçilir.',
    'input.transfer.high': 'Şebeke voltajı bu değerin üstüne çıkınca bataryaya geçilir.',
    'input.transfer.reason': 'En son bataryaya geçiş nedeni.',
    'input.sensitivity': 'UPS\'in voltaj dalgalanmalarına tepki hassasiyeti.',
    'input.current': 'Şebekeden çekilen anlık akım.',
    'input.voltage.fault': 'Son arıza veya transfer anında ölçülen giriş voltajı.',
    'input.current.nominal': 'Nominal giriş akımı.',
    'input.power': 'Şebekeden alınan toplam güç (VA).',
    'input.realpower': 'Şebekeden alınan gerçek güç (W).',
    // Çıkış
    'output.voltage': 'UPS\'in cihazlara verdiği anlık voltaj.',
    'output.voltage.nominal': 'Beklenen nominal çıkış voltajı.',
    'output.frequency': 'UPS çıkışındaki anlık frekans.',
    'output.frequency.nominal': 'Beklenen nominal çıkış frekansı.',
    'output.current': 'Bağlı cihazlara verilen anlık akım.',
    'output.current.nominal': 'Nominal çıkış akımı.',
    'output.power': 'Bağlı cihazlara verilen toplam güç (VA).',
    'output.realpower': 'Bağlı cihazlara verilen gerçek güç (W).',
    // UPS
    'ups.status': 'UPS\'in anlık çalışma durumu. OL: Şebeke, OB: Batarya, LB: Düşük Batarya.',
    'ups.load': 'UPS\'in maksimum kapasitesine oranla anlık yük yüzdesi.',
    'ups.load.high': 'Bu yük yüzdesinin üstünde uyarı verilir.',
    'ups.model': 'UPS\'in model adı.',
    'ups.mfr': 'UPS üreticisinin adı.',
    'ups.mfr.date': 'UPS\'in üretim tarihi.',
    'ups.serial': 'UPS\'e ait benzersiz seri numarası.',
    'ups.firmware': 'UPS içindeki donanım yazılımının sürümü.',
    'ups.firmware.aux': 'Yardımcı donanım yazılımının sürümü.',
    'ups.type': 'UPS topolojisi (ör. offline, line-interactive, online).',
    'ups.temperature': 'UPS içindeki anlık sıcaklık.',
    'ups.beeper.status': 'Sesli uyarı buzzer\'ının durumu.',
    'ups.delay.shutdown': 'Kapanma komutu sonrası UPS\'in çıkışı kesmeden önceki bekleme süresi.',
    'ups.delay.start': 'Güç gelince UPS\'in çıkış vermeden önceki bekleme süresi.',
    'ups.power': 'UPS\'in anlık görünür gücü (Volt-Amper).',
    'ups.power.nominal': 'UPS\'in maksimum kapasitesi (Volt-Amper).',
    'ups.realpower': 'UPS\'in anlık gerçek gücü (Watt).',
    'ups.realpower.nominal': 'UPS\'in maksimum gerçek güç kapasitesi (Watt).',
    'ups.test.result': 'Son batarya testinin sonucu.',
    'ups.test.date': 'Son batarya testinin yapıldığı tarih.',
    'ups.efficiency': 'Giriş gücüne oranla çıkış gücü verimliliği.',
    'ups.start.auto': 'Güç kesilip gelince UPS otomatik başlasın mı?',
    'ups.start.battery': 'UPS batarya ile başlatılabilir mi?',
    'ups.start.reboot': 'UPS yeniden başlatma modunu destekliyor mu?',
    'ups.shutdown': 'UPS\'in anlık kapanma durumu.',
    // Sürücü
    'driver.name': 'NUT\'un bu UPS için kullandığı sürücünün adı.',
    'driver.version': 'NUT sürücüsünün sürüm numarası.',
    'driver.version.data': 'Sürücünün kullandığı veri dosyasının sürümü.',
    'driver.version.internal': 'Sürücünün iç yapı sürüm numarası.',
    'driver.version.usb': 'USB iletişim katmanının sürümü.',
    'driver.flag.allow_killpower': 'Sürücünün UPS gücünü tamamen kesme yetkisi.',
    'driver.parameter.port': 'UPS\'in bağlı olduğu port veya adres.',
    'driver.parameter.bus': 'UPS\'in bağlı olduğu USB bus numarası.',
    'driver.parameter.device': 'USB bus üzerindeki cihaz numarası.',
    'driver.parameter.vendorid': 'USB üretici kimlik kodu.',
    'driver.parameter.productid': 'USB ürün kimlik kodu.',
    'driver.parameter.serial': 'Bağlantı için kullanılan seri numarası.',
    'driver.parameter.pollfreq': 'Yavaş değişen verilerin kaç saniyede bir sorgulandığı.',
    'driver.parameter.pollinterval': 'UPS\'in kaç saniyede bir sorgulandığı.',
    'driver.parameter.synchronous': 'Sürücünün senkron modda çalışıp çalışmadığı.',
    'driver.debug': 'Sürücünün hata ayıklama çıktısı seviyesi. 0 = kapalı.',
    'driver.state': 'Sürücünün anlık çalışma durumu.',
    'driver.parameter.override.battery.charge.low': 'Yapılandırma dosyasında manuel olarak geçersiz kılınan düşük batarya şarj eşiği.',
    'driver.parameter.override.ups.delay.shutdown': 'Yapılandırma dosyasında manuel olarak geçersiz kılınan kapanma gecikmesi.',
    'driver.parameter.override.ups.delay.start': 'Yapılandırma dosyasında manuel olarak geçersiz kılınan açılma gecikmesi.',
    'driver.parameter.lowbatt': 'Sürücünün düşük batarya için kullandığı eşik değeri.',
    'driver.parameter.offdelay': 'Kapanma komutundan sonraki gecikme süresi.',
    'driver.parameter.ondelay': 'Açılma komutundan sonraki gecikme süresi.',
    // Cihaz
    'device.model': 'Cihazın tam model adı.',
    'device.mfr': 'Cihazı üreten firmanın adı.',
    'device.serial': 'Cihaza ait benzersiz seri numarası.',
    'device.type': 'Cihaz kategorisi (ör. ups, pdu, scd).',
    'device.description': 'Cihaz için tanımlanan açıklama metni.',
    'device.contact': 'Cihazdan sorumlu kişi veya birim.',
    'device.location': 'Cihazın fiziksel konumu.',
    'device.part': 'Cihazın parça veya katalog numarası.',
    'device.macaddr': 'Cihazın ağ arayüzüne ait MAC adresi.',
  };

  String _translate(String key) => _translations[key] ?? key;
  String? _describe(String key) => _descriptions[key];

  @override
  Widget build(BuildContext context) {
    final description = _describe(varKey);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.hairline)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    _translate(varKey),
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ),
                if (description != null) ...[
                  const SizedBox(width: 4),
                  GestureDetector(
                    onTap: () => appShowDialog(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        backgroundColor: colors.surface1,
                        shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(AppRadius.md)),
                        title: Text(
                          _translate(varKey),
                          style: TextStyle(
                            color: colors.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        content: Text(
                          description,
                          style: TextStyle(
                            color: colors.textSecondary,
                            fontSize: 13,
                            height: 1.5,
                          ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: Text(
                              'Tamam',
                              style: TextStyle(color: colors.primary),
                            ),
                          ),
                        ],
                      ),
                    ),
                    child: Icon(
                      Icons.help_outline,
                      size: 13,
                      color: colors.textMuted,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            flex: 1,
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}