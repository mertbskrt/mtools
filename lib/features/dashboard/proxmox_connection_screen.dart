import 'dart:convert';
import 'package:flutter/material.dart';
import '../../core/utils/app_transitions.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/theme/app_theme.dart';
import '../proxmox/proxmox_provider.dart';
import '../proxmox/proxmox_service.dart';
import '../../core/services/cloud_sync_service.dart';
import '../../core/utils/credential_sync.dart';

class ProxmoxServer {
  String name;
  String address;
  String port;
  String tokenId;
  String tokenSecret;

  /// Cloud'dan geldiğinde, token başka bir cihazda girilmiş ama bu cihazda
  /// henüz yoksa true olur (bkz. credential_sync.dart). Cloud'a hiç
  /// yazılmaz, sadece bu oturumda UI için.
  bool needsCredentials;

  ProxmoxServer({
    required this.name,
    required this.address,
    this.port = '8006',
    required this.tokenId,
    required this.tokenSecret,
    this.needsCredentials = false,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'address': address,
        'port': port,
        'tokenId': tokenId,
        'tokenSecret': tokenSecret,
      };

  factory ProxmoxServer.fromJson(Map<String, dynamic> json) => ProxmoxServer(
        name: json['name'] ?? '',
        address: json['address'] ?? '',
        port: json['port'] ?? '8006',
        tokenId: json['tokenId'] ?? '',
        tokenSecret: json['tokenSecret'] ?? '',
      );
}

class ProxmoxConnectionScreen extends StatefulWidget {
  /// Set edilirse, sunucu listesi yüklendikten sonra bu isimdeki sunucunun
  /// düzenleme sheet'i otomatik açılır — "kimlik bilgisi gerekli" kartından
  /// tek dokunuşla düzenlemeye geçmek için (bkz. system_screen.dart).
  final String? openEditForServerName;

  const ProxmoxConnectionScreen({super.key, this.openEditForServerName});

  @override
  State<ProxmoxConnectionScreen> createState() =>
      _ProxmoxConnectionScreenState();
}

class _ProxmoxConnectionScreenState extends State<ProxmoxConnectionScreen>
    with TickerProviderStateMixin {
  List<ProxmoxServer> _servers = [];
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 6000), // 2s → 6s, daha az CPU
    )..repeat(reverse: true);
    _init();
  }

  Future<void> _init() async {
    await _load();
    final targetName = widget.openEditForServerName;
    if (targetName == null || !mounted) return;
    final idx = _servers.indexWhere((s) => s.name == targetName);
    if (idx != -1) _openWizard(server: _servers[idx], index: idx);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final prefs = await _p;
    final cloudRaw = await CloudSyncService().getProxmoxServers();
    final localRaw = prefs.getString('proxmox_servers');
    if (cloudRaw != null || localRaw != null) {
      final cloudList = cloudRaw == null
          ? <Map<String, dynamic>>[]
          : (jsonDecode(cloudRaw) as List)
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
      final localList = localRaw == null
          ? <Map<String, dynamic>>[]
          : (jsonDecode(localRaw) as List)
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
      final merged = mergeCloudStructureWithLocalCredentials(
        cloudList: cloudList,
        localList: localList,
        credentialFields: ['tokenId', 'tokenSecret'],
      );
      if (!mounted) return;
      setState(() => _servers = merged.map((m) {
            final s = ProxmoxServer.fromJson(m);
            s.needsCredentials = m['needsCredentials'] as bool? ?? false;
            return s;
          }).toList());
    } else {
      final host = prefs.getString('proxmox_host') ?? '';
      final port = prefs.getString('proxmox_port') ?? '8006';
      final tokenId = prefs.getString('proxmox_token_id') ?? '';
      final tokenSecret = prefs.getString('proxmox_token_secret') ?? '';
      if (host.isNotEmpty) {
        _servers = [
          ProxmoxServer(
              name: 'Proxmox',
              address: host,
              port: port,
              tokenId: tokenId,
              tokenSecret: tokenSecret)
        ];
        await _save();
      }
    }
  }

  SharedPreferences? _prefs;
  Future<SharedPreferences> get _p async =>
      _prefs ??= await SharedPreferences.getInstance();

  Future<void> _save() async {
    final serversJson = jsonEncode(_servers.map((s) => s.toJson()).toList());
    // token cloud'a hiç yazılmaz — bkz. credential_sync.dart.
    final sanitizedJson = jsonEncode(_servers
        .map((s) => stripCredentialFields(s.toJson(), ['tokenId', 'tokenSecret']))
        .toList());
    final prefs = await _p;
    final writes = <Future>[
      prefs.setString('proxmox_servers', serversJson),
      CloudSyncService().saveProxmoxServers(sanitizedJson),
    ];
    // Legacy single-server keys — ilk sunucu varsa güncelle
    if (_servers.isNotEmpty) {
      final first = _servers.first;
      writes.addAll([
        prefs.setString('proxmox_host', first.address),
        prefs.setString('proxmox_port', first.port),
        prefs.setString('proxmox_token_id', first.tokenId),
        prefs.setString('proxmox_token_secret', first.tokenSecret),
      ]);
    }
    await Future.wait(writes);
  }

  void _openWizard({ProxmoxServer? server, int? index}) {
    appShowModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _ServerWizard(
        existing: server,
        onSave: (s) async {
          setState(() {
            if (index != null) {
              _servers[index] = s;
            } else {
              _servers.add(s);
            }
          });
          await _save();
          if (mounted) context.read<ProxmoxProvider>().init();
        },
      ),
    );
  }

  void _deleteServer(int i) {
    final colors = context.appColors;
    appShowDialog(
      context: context,
      builder: (dctx) => AlertDialog(
        backgroundColor: colors.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title:
            Text('Sunucuyu Sil', style: TextStyle(color: colors.textPrimary)),
        content: Text('${_servers[i].name} silinecek. Emin misiniz?',
            style: TextStyle(color: colors.textSecondary, fontSize: 13)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dctx),
            child: Text('İptal', style: TextStyle(color: colors.textSecondary)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(dctx);
              setState(() => _servers.removeAt(i));
              await _save();
              if (mounted) context.read<ProxmoxProvider>().init();
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

    return Scaffold(
      backgroundColor: colors.bgDark,
      body: CustomScrollView(
        slivers: [
          // ── Header ──
          SliverToBoxAdapter(
            child: Stack(
              children: [
                // Arka plan dekorasyon
                Positioned(
                  top: -40,
                  right: -40,
                  child: AnimatedBuilder(
                    animation: _pulseController,
                    builder: (_, __) => Container(
                      width: 200 + _pulseController.value * 20,
                      height: 200 + _pulseController.value * 20,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            colors.primary.withValues(alpha: 0.08),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Geri butonu
                        GestureDetector(
                          onTap: () => Navigator.pop(context),
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: colors.bgCard,
                              borderRadius: BorderRadius.circular(AppRadius.md),
                              border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.06)),
                            ),
                            child: Icon(Icons.arrow_back_ios_new,
                                color: colors.textSecondary, size: 16),
                          ),
                        ),
                        const SizedBox(height: 24),

                        // Başlık
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [colors.primary, colors.info],
                                ),
                                borderRadius: BorderRadius.circular(14),
                                boxShadow: [
                                  BoxShadow(
                                    color: colors.primary.withValues(alpha: 0.3),
                                    blurRadius: 16,
                                    spreadRadius: 1,
                                  ),
                                ],
                              ),
                              child: const Icon(Icons.dns_rounded,
                                  color: Colors.white, size: 24),
                            ),
                            const SizedBox(width: 14),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Proxmox Sunucuları',
                                    style: TextStyle(
                                        color: colors.textPrimary,
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold)),
                                Text('${_servers.length} sunucu kayıtlı',
                                    style: TextStyle(
                                        color: colors.textMuted, fontSize: 12)),
                              ],
                            ),
                          ],
                        ).animate().fadeIn(duration: 400.ms),

                        const SizedBox(height: 24),

                        // ── Bilgi kartları ──
                        if (_servers.isEmpty) ...[
                          _InfoSection().animate().fadeIn(delay: 200.ms),
                          const SizedBox(height: 20),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Sunucu listesi ──
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, i) {
                  final s = _servers[i];
                  return _ServerCard(
                    server: s,
                    index: i,
                    onEdit: () => _openWizard(server: s, index: i),
                    onDelete: () => _deleteServer(i),
                  )
                      .animate()
                      .fadeIn(delay: (i * 80).ms)
                      .slideX(begin: 0.1, end: 0);
                },
                childCount: _servers.length,
              ),
            ),
          ),

          // ── Boş durum ──
          if (_servers.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: _EmptyState(onAdd: _openWizard)
                    .animate()
                    .fadeIn(delay: 400.ms),
              ),
            ),

          // ── Ekle butonu (sunucu varken) ──
          if (_servers.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                child: OutlinedButton.icon(
                  onPressed: _openWizard,
                  icon: Icon(Icons.add, color: colors.primary),
                  label: Text('Yeni Sunucu Ekle',
                      style: TextStyle(color: colors.primary)),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: colors.primary.withValues(alpha: 0.4)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
            ),

          const SliverToBoxAdapter(child: SizedBox(height: 40)),
        ],
      ),
    );
  }
}

// ── Bilgi Bölümü ──────────────────────────────────────────────────────────

class _InfoSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Column(
      children: [
        _InfoCard(
          icon: Icons.lan_outlined,
          color: colors.info,
          title: 'API Token ile Güvenli Bağlantı',
          body:
              'MTools, Proxmox VE API token sistemi ile bağlanır. Kullanıcı adı/şifre saklanmaz.',
        ),
        const SizedBox(height: 10),
        _InfoCard(
          icon: Icons.vpn_key_outlined,
          color: colors.warning,
          title: 'Token nasıl oluşturulur?',
          body:
              'Proxmox arayüzünde:\nDatacenter → Permissions → API Tokens → Add\nToken ID: root@pam!mtools',
        ),
        const SizedBox(height: 10),
        _InfoCard(
          icon: Icons.router_outlined,
          color: colors.success,
          title: 'Bağlantı türleri',
          body:
              '• İç ağ (LAN): IP:8006\n• Cloudflare Tunnel: domain:443\n• Tailscale: 100.x.x.x:8006',
        ),
      ],
    );
  }
}

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String body;

  const _InfoCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(body,
                    style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: 12,
                        height: 1.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Sunucu Kartı ─────────────────────────────────────────────────────────

class _ServerCard extends StatefulWidget {
  final ProxmoxServer server;
  final int index;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ServerCard({
    required this.server,
    required this.index,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  State<_ServerCard> createState() => _ServerCardState();
}

class _ServerCardState extends State<_ServerCard> {
  bool _testing = false;
  bool? _online;

  @override
  void initState() {
    super.initState();
    // Kimlik bilgisi eksikse hiç sorgu atılmaz (bkz. credential_sync.dart).
    if (!widget.server.needsCredentials) {
      _testConnection();
    }
  }

  Future<void> _testConnection() async {
    if (!mounted) return;
    setState(() {
      _testing = true;
      _online = null;
    });
    bool? result;
    try {
      final service = ProxmoxService();
      service.configure(widget.server.address, widget.server.port,
          widget.server.tokenId, widget.server.tokenSecret);
      await service.getNodes().timeout(const Duration(seconds: 5));
      result = true;
    } catch (_) {
      result = false;
    }
    if (mounted) {
      setState(() {
        _testing = false;
        _online = result;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    final needsCredentials = widget.server.needsCredentials;
    final statusColor = needsCredentials
        ? colors.warning
        : _testing
            ? colors.warning
            : _online == true
                ? colors.success
                : colors.error;
    final statusText = needsCredentials
        ? 'Kimlik bilgisi gerekli'
        : _testing
            ? 'Test ediliyor...'
            : _online == true
                ? 'Çevrimiçi'
                : 'Erişilemiyor';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: colors.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: statusColor.withValues(alpha: 0.25)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // İkon
                AnimatedContainer(
                  duration: AppMotion.slow,
                  curve: AppMotion.curve,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: _testing
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: statusColor,
                          ),
                        )
                      : Icon(
                          needsCredentials
                              ? Icons.key_off_rounded
                              : _online == true
                                  ? Icons.dns_rounded
                                  : Icons.dns_outlined,
                          color: statusColor,
                          size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.server.name,
                          style: TextStyle(
                              color: colors.textPrimary,
                              fontSize: 15,
                              fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text('${widget.server.address}:${widget.server.port}',
                          style:
                              TextStyle(color: colors.textMuted, fontSize: 12)),
                    ],
                  ),
                ),
                // Durum badge
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: statusColor,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(statusText,
                          style: TextStyle(
                              color: statusColor,
                              fontSize: 11,
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Alt butonlar
          Container(
            decoration: BoxDecoration(
              border: Border(
                  top: BorderSide(color: Colors.white.withValues(alpha: 0.05))),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextButton.icon(
                    onPressed: needsCredentials ? null : _testConnection,
                    icon:
                        Icon(Icons.refresh, size: 14, color: colors.textMuted),
                    label: Text('Yenile',
                        style:
                            TextStyle(color: colors.textMuted, fontSize: 12)),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
                Container(
                    width: 1,
                    height: 20,
                    color: Colors.white.withValues(alpha: 0.05)),
                Expanded(
                  child: TextButton.icon(
                    onPressed: widget.onEdit,
                    icon: Icon(Icons.edit_outlined,
                        size: 14, color: colors.primary),
                    label: Text('Düzenle',
                        style: TextStyle(color: colors.primary, fontSize: 12)),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
                Container(
                    width: 1,
                    height: 20,
                    color: Colors.white.withValues(alpha: 0.05)),
                Expanded(
                  child: TextButton.icon(
                    onPressed: widget.onDelete,
                    icon: Icon(Icons.delete_outline,
                        size: 14, color: colors.error),
                    label: Text('Sil',
                        style: TextStyle(color: colors.error, fontSize: 12)),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
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

// ── Boş Durum ────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyState({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: colors.bgCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: colors.primary.withValues(alpha: 0.15), style: BorderStyle.solid),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: colors.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.add_link, color: colors.primary, size: 36),
          ),
          const SizedBox(height: 16),
          Text('Sunucu bağlantısı yok',
              style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(
            'Proxmox sunucunuzu ekleyerek\nsunucu yönetimine başlayın.',
            textAlign: TextAlign.center,
            style:
                TextStyle(color: colors.textMuted, fontSize: 13, height: 1.6),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add, color: Colors.white, size: 18),
              label: const Text('İlk Sunucuyu Ekle',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.primary,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Wizard ───────────────────────────────────────────────────────────────

class _ServerWizard extends StatefulWidget {
  final ProxmoxServer? existing;
  final Function(ProxmoxServer) onSave;

  const _ServerWizard({this.existing, required this.onSave});

  @override
  State<_ServerWizard> createState() => _ServerWizardState();
}

class _ServerWizardState extends State<_ServerWizard>
    with TickerProviderStateMixin {
  int _step = 0; // 0: adres, 1: token, 2: bağlanıyor
  bool _testing = false;
  bool? _success;
  String _errorMsg = '';

  late TextEditingController _nameCtrl;
  late TextEditingController _addressCtrl;
  late TextEditingController _portCtrl;
  late TextEditingController _tokenIdCtrl;
  late TextEditingController _tokenSecretCtrl;

  late AnimationController _connectAnim;

  @override
  void initState() {
    super.initState();
    final s = widget.existing;
    _nameCtrl = TextEditingController(text: s?.name ?? '');
    _addressCtrl = TextEditingController(text: s?.address ?? '');
    _portCtrl = TextEditingController(text: s?.port ?? '8006');
    _tokenIdCtrl = TextEditingController(text: s?.tokenId ?? '');
    _tokenSecretCtrl = TextEditingController(text: s?.tokenSecret ?? '');

    _connectAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _addressCtrl.dispose();
    _portCtrl.dispose();
    _tokenIdCtrl.dispose();
    _tokenSecretCtrl.dispose();
    _connectAnim.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    setState(() {
      _step = 2;
      _testing = true;
      _success = null;
      _errorMsg = '';
    });
    _connectAnim.repeat();

    try {
      final service = ProxmoxService();
      service.configure(
        _addressCtrl.text.trim(),
        _portCtrl.text.trim(),
        _tokenIdCtrl.text.trim(),
        _tokenSecretCtrl.text.trim(),
      );
      await service.getNodes().timeout(const Duration(seconds: 5));
      if (!mounted) return;
      _connectAnim.stop();
      setState(() {
        _testing = false;
        _success = true;
      });

      // 1.5 sn bekle sonra kaydet
      await Future.delayed(const Duration(milliseconds: 1500));
      if (mounted) {
        widget.onSave(ProxmoxServer(
          name: _nameCtrl.text.trim().isEmpty
              ? _addressCtrl.text.trim()
              : _nameCtrl.text.trim(),
          address: _addressCtrl.text.trim(),
          port: _portCtrl.text.trim(),
          tokenId: _tokenIdCtrl.text.trim(),
          tokenSecret: _tokenSecretCtrl.text.trim(),
        ));
        Navigator.pop(context);
      }
    } catch (e) {
      if (!mounted) return;
      _connectAnim.stop();
      setState(() {
        _testing = false;
        _success = false;
        _errorMsg = e.toString().contains('timeout')
            ? 'Sunucuya ulaşılamadı (5 saniye zaman aşımı)'
            : e.toString().contains('401') || e.toString().contains('403')
                ? 'Token geçersiz veya yetkisiz erişim'
                : e.toString().contains('SocketException')
                    ? 'Ağ bağlantısı yok veya adres hatalı'
                    : 'Bağlantı hatası: ${e.toString().split('\n').first}';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Container(
      decoration: BoxDecoration(
        color: colors.bgCard,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
            24, 16, 24, MediaQuery.of(context).viewInsets.bottom + 24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle
              Center(
                  child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                          color: colors.textMuted,
                          borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 20),

              // Step indicator
              _StepIndicator(currentStep: _step),
              const SizedBox(height: 24),

              // İçerik
              AnimatedSwitcher(
                duration: AppMotion.base,
                switchInCurve: AppMotion.curve,
                switchOutCurve: AppMotion.curve,
                transitionBuilder: (child, anim) => FadeTransition(
                  opacity: anim,
                  child: SlideTransition(
                    position: Tween<Offset>(
                            begin: const Offset(0.05, 0), end: Offset.zero)
                        .animate(anim),
                    child: child,
                  ),
                ),
                child: _step == 0
                    ? _Step1(
                        key: const ValueKey(0),
                        nameCtrl: _nameCtrl,
                        addressCtrl: _addressCtrl,
                        portCtrl: _portCtrl,
                        onNext: () {
                          if (_addressCtrl.text.trim().isEmpty) return;
                          setState(() => _step = 1);
                        },
                      )
                    : _step == 1
                        ? _Step2(
                            key: const ValueKey(1),
                            tokenIdCtrl: _tokenIdCtrl,
                            tokenSecretCtrl: _tokenSecretCtrl,
                            onBack: () => setState(() => _step = 0),
                            onConnect: _connect,
                          )
                        : _Step3(
                            key: const ValueKey(2),
                            testing: _testing,
                            success: _success,
                            errorMsg: _errorMsg,
                            connectAnim: _connectAnim,
                            onRetry: () => setState(() => _step = 1),
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Step Indicator ────────────────────────────────────────────────────────

class _StepIndicator extends StatelessWidget {
  final int currentStep;
  const _StepIndicator({required this.currentStep});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    final labels = ['Sunucu Adresi', 'Token Bilgisi', 'Bağlantı'];
    return Row(
      children: List.generate(3, (i) {
        final active = i == currentStep;
        final done = i < currentStep;
        final color = done || active ? colors.primary : colors.textMuted;
        return Expanded(
          child: Row(
            children: [
              Column(
                children: [
                  AnimatedContainer(
                    duration: AppMotion.base,
                    curve: AppMotion.curve,
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: done || active
                          ? colors.primary.withValues(alpha: 0.2)
                          : colors.bgCardLight,
                      border: Border.all(color: color, width: active ? 2 : 1),
                    ),
                    child: Center(
                      child: done
                          ? Icon(Icons.check, color: colors.primary, size: 14)
                          : Text('${i + 1}',
                              style: TextStyle(
                                  color: color,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(labels[i],
                      style: TextStyle(
                          color: color,
                          fontSize: 9,
                          fontWeight:
                              active ? FontWeight.w600 : FontWeight.normal)),
                ],
              ),
              if (i < 2)
                Expanded(
                  child: Container(
                    height: 1,
                    margin: const EdgeInsets.only(bottom: 18),
                    color: i < currentStep
                        ? colors.primary.withValues(alpha: 0.4)
                        : Colors.white.withValues(alpha: 0.06),
                  ),
                ),
            ],
          ),
        );
      }),
    );
  }
}

// ── Step 1: Adres ─────────────────────────────────────────────────────────

class _Step1 extends StatelessWidget {
  final TextEditingController nameCtrl;
  final TextEditingController addressCtrl;
  final TextEditingController portCtrl;
  final VoidCallback onNext;

  const _Step1({
    super.key,
    required this.nameCtrl,
    required this.addressCtrl,
    required this.portCtrl,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Sunucu Adresi',
            style: TextStyle(
                color: colors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text('Proxmox sunucunuzun ağ bilgilerini girin',
            style: TextStyle(color: colors.textMuted, fontSize: 12)),
        const SizedBox(height: 20),
        _WizardField(
          label: 'Sunucu Adı',
          controller: nameCtrl,
          hint: 'Örn: Ana Proxmox',
          icon: Icons.label_outline,
        ),
        _WizardField(
          label: 'IP / Domain',
          controller: addressCtrl,
          hint: '192.168.1.10 veya proxmox.domain.com',
          icon: Icons.router_outlined,
          keyboard: TextInputType.url,
        ),
        _WizardField(
          label: 'Port',
          controller: portCtrl,
          hint: '8006',
          icon: Icons.electrical_services_outlined,
          keyboard: TextInputType.number,
        ),
        const SizedBox(height: 8),
        // Port bilgi kartı
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colors.info.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colors.info.withValues(alpha: 0.2)),
          ),
          child: Row(
            children: [
              Icon(Icons.info_outline, color: colors.info, size: 16),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'LAN bağlantısı → 8006\nCloudflare / Reverse proxy → 443',
                  style: TextStyle(
                      color: colors.textSecondary, fontSize: 11, height: 1.6),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: onNext,
            style: ElevatedButton.styleFrom(
              backgroundColor: colors.primary,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('Devam Et',
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold)),
                SizedBox(width: 6),
                Icon(Icons.arrow_forward, color: Colors.white, size: 16),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ── Step 2: Token ─────────────────────────────────────────────────────────

class _Step2 extends StatelessWidget {
  final TextEditingController tokenIdCtrl;
  final TextEditingController tokenSecretCtrl;
  final VoidCallback onBack;
  final VoidCallback onConnect;

  const _Step2({
    super.key,
    required this.tokenIdCtrl,
    required this.tokenSecretCtrl,
    required this.onBack,
    required this.onConnect,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('API Token',
            style: TextStyle(
                color: colors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text('Proxmox API token bilgilerinizi girin',
            style: TextStyle(color: colors.textMuted, fontSize: 12)),
        const SizedBox(height: 16),
        // Token oluşturma yol haritası
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: colors.warning.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colors.warning.withValues(alpha: 0.2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.route_outlined, color: colors.warning, size: 14),
                  const SizedBox(width: 6),
                  Text('Token oluşturma yolu',
                      style: TextStyle(
                          color: colors.warning,
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                ],
              ),
              const SizedBox(height: 8),
              _stepText(context, '1', 'Proxmox arayüzünü açın'),
              _stepText(context, '2', 'Datacenter → Permissions → API Tokens'),
              _stepText(context, '3', 'Add → Token ID: mtools'),
              _stepText(context, '4',
                  'Privilege Separation: kapalı (tam yetki için)'),
              _stepText(context, '5', 'Token Secret\'i kopyalayın'),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _WizardField(
          label: 'Token ID',
          controller: tokenIdCtrl,
          hint: 'root@pam!mtools',
          icon: Icons.badge_outlined,
        ),
        _WizardField(
          label: 'Token Secret',
          controller: tokenSecretCtrl,
          hint: 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx',
          icon: Icons.key_outlined,
          obscure: true,
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            OutlinedButton(
              onPressed: onBack,
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
                padding:
                    const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              child: Icon(Icons.arrow_back, color: colors.textMuted, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: onConnect,
                icon: const Icon(Icons.link, color: Colors.white, size: 16),
                label: const Text('Bağlan',
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: colors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _stepText(BuildContext context, String num, String text) {
    final colors = context.appColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              color: colors.warning.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(num,
                  style: TextStyle(
                      color: colors.warning,
                      fontSize: 10,
                      fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: TextStyle(
                    color: colors.textSecondary, fontSize: 11, height: 1.5)),
          ),
        ],
      ),
    );
  }
}

// ── Step 3: Bağlantı Durumu ───────────────────────────────────────────────

class _Step3 extends StatelessWidget {
  final bool testing;
  final bool? success;
  final String errorMsg;
  final AnimationController connectAnim;
  final VoidCallback onRetry;

  const _Step3({
    super.key,
    required this.testing,
    required this.success,
    required this.errorMsg,
    required this.connectAnim,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Column(
      children: [
        const SizedBox(height: 20),
        // Ana animasyon alanı
        SizedBox(
          height: 140,
          child: Center(
            child: AnimatedSwitcher(
              duration: AppMotion.slow,
              switchInCurve: AppMotion.curve,
              switchOutCurve: AppMotion.curve,
              child: testing
                  ? _ConnectingWidget(anim: connectAnim)
                  : success == true
                      ? const _SuccessWidget()
                      : const _FailWidget(),
            ),
          ),
        ),
        const SizedBox(height: 20),
        // Durum metni
        AnimatedSwitcher(
          duration: AppMotion.base,
          switchInCurve: AppMotion.curve,
          switchOutCurve: AppMotion.curve,
          child: testing
              ? Column(
                  key: const ValueKey('testing'),
                  children: [
                    Text('Sunucuya bağlanılıyor...',
                        style: TextStyle(
                            color: colors.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text('En fazla 5 saniye sürebilir',
                        style:
                            TextStyle(color: colors.textMuted, fontSize: 12)),
                  ],
                )
              : success == true
                  ? Column(
                      key: const ValueKey('success'),
                      children: [
                        Text('Bağlantı Başarılı!',
                            style: TextStyle(
                                color: colors.success,
                                fontSize: 16,
                                fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        Text('Sunucu eklendi, yönlendiriliyorsunuz...',
                            style: TextStyle(
                                color: colors.textMuted, fontSize: 12)),
                      ],
                    )
                  : Column(
                      key: const ValueKey('fail'),
                      children: [
                        Text('Bağlantı Başarısız',
                            style: TextStyle(
                                color: colors.error,
                                fontSize: 16,
                                fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        Text(errorMsg,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: colors.textSecondary,
                                fontSize: 12,
                                height: 1.5)),
                        const SizedBox(height: 20),
                        OutlinedButton.icon(
                          onPressed: onRetry,
                          icon: Icon(Icons.arrow_back,
                              size: 14, color: colors.primary),
                          label: Text('Geri Dön',
                              style: TextStyle(
                                  color: colors.primary, fontSize: 13)),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(
                                color: colors.primary.withValues(alpha: 0.4)),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ],
                    ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }
}

class _ConnectingWidget extends StatelessWidget {
  final AnimationController anim;

  const _ConnectingWidget({
    required this.anim,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: anim,
        builder: (_, __) {
          return Stack(
            alignment: Alignment.center,
            children: [
              // Dış ring
              Opacity(
                opacity: (1 - anim.value).clamp(0.0, 1.0) * 0.3,
                child: Container(
                  width: 80 + anim.value * 60,
                  height: 80 + anim.value * 60,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: colors.primary,
                      width: 1,
                    ),
                  ),
                ),
              ),

              Container(
                width: 70,
                height: 70,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colors.primary.withValues(alpha: 0.12),
                  border: Border.all(
                    color: colors.primary.withValues(alpha: 0.4),
                    width: 2,
                  ),
                ),
                child: Center(
                  child: SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: colors.primary,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SuccessWidget extends StatelessWidget {
  const _SuccessWidget();

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Container(
      width: 80,
      height: 80,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: colors.success.withValues(alpha: 0.12),
        border: Border.all(color: colors.success.withValues(alpha: 0.4), width: 2),
      ),
      child: Icon(Icons.check_rounded, color: colors.success, size: 36),
    )
        .animate()
        .scale(begin: const Offset(0.5, 0.5), curve: Curves.easeOutBack)
        .fadeIn();
  }
}

class _FailWidget extends StatelessWidget {
  const _FailWidget();

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Container(
      width: 80,
      height: 80,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: colors.error.withValues(alpha: 0.12),
        border: Border.all(color: colors.error.withValues(alpha: 0.4), width: 2),
      ),
      child: Icon(Icons.close_rounded, color: colors.error, size: 36),
    )
        .animate()
        .scale(begin: const Offset(0.5, 0.5), curve: Curves.easeOutBack)
        .fadeIn();
  }
}

// ── Wizard Field ─────────────────────────────────────────────────────────

class _WizardField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final bool obscure;
  final TextInputType keyboard;

  const _WizardField({
    required this.label,
    required this.controller,
    required this.hint,
    required this.icon,
    this.obscure = false,
    this.keyboard = TextInputType.text,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        obscureText: obscure,
        keyboardType: keyboard,
        style: TextStyle(color: colors.textPrimary, fontSize: 14),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          prefixIcon: Icon(icon, color: colors.textMuted, size: 18),
          labelStyle: TextStyle(color: colors.textSecondary, fontSize: 13),
          hintStyle: TextStyle(color: colors.textMuted, fontSize: 13),
          filled: true,
          fillColor: colors.bgDark,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: colors.primary, width: 1.5)),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
      ),
    );
  }
}
