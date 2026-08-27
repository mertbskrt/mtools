import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../../core/utils/app_transitions.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dartssh2/dartssh2.dart';
import '../../core/theme/app_theme.dart';
import '../../core/services/cloud_sync_service.dart';
import '../../core/services/widget_service.dart';
import '../../core/utils/credential_sync.dart';
import '../proxmox/proxmox_provider.dart';

// ─────────────────────────────────────────────
// Model
// ─────────────────────────────────────────────

class WolTarget {
  String name;
  String mac;
  String relayNode;
  String broadcastIp;
  String method; // 'udp' | 'ssh' | 'both'
  String? description;

  WolTarget({
    required this.name,
    required this.mac,
    required this.relayNode,
    this.broadcastIp = '255.255.255.255',
    this.method = 'both',
    this.description,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'mac': mac,
        'relayNode': relayNode,
        'broadcastIp': broadcastIp,
        'method': method,
        'description': description,
      };

  factory WolTarget.fromJson(Map<String, dynamic> j) => WolTarget(
        name: j['name'] ?? '',
        mac: j['mac'] ?? '',
        relayNode: j['relayNode'] ?? '',
        broadcastIp: j['broadcastIp'] ?? '255.255.255.255',
        method: j['method'] ?? 'both',
        description: j['description'],
      );
}

// ─────────────────────────────────────────────
// Ana Ekran
// ─────────────────────────────────────────────

class WolScreen extends StatefulWidget {
  const WolScreen({super.key});

  @override
  State<WolScreen> createState() => _WolScreenState();
}

class _WolScreenState extends State<WolScreen> {
  List<WolTarget> _targets = [];
  StreamSubscription<User?>? _authSub;

  @override
  void initState() {
    super.initState();
    _load();
    // Bu ekran HomeScreen'in sekme önbelleğinde bir kez oluşturulup canlı
    // tutuluyor — kullanıcı uygulama açıkken Ayarlar'dan Google ile giriş/
    // çıkış yaparsa initState tekrar çalışmaz. Hesap değiştiğinde listeyi
    // yeniden yüklemek için oturum durumunu ayrıca dinliyoruz.
    _authSub = FirebaseAuth.instance.authStateChanges().listen((_) => _load());
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();

    // Önce cloud'dan dene, yoksa local'e bak
    String? raw = await CloudSyncService().getSetting('wol_devices');
    raw ??= prefs.getString('wol_devices');

    if (raw != null) {
      final List list = jsonDecode(raw);
      final parsed = list
          .map((e) => WolTarget.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      if (mounted) {
        setState(() => _targets = parsed);
      }
      // WOL widget'ının cihaz listesini beslemesi için — ekran kapalıyken
      // (mounted false) de widget'ın en son bilinen listeyle senkron
      // kalması gerekiyor, bu yüzden mounted kontrolünün dışında.
      await WidgetService.updateWol(parsed.map((t) => t.toJson()).toList());
    }
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(_targets.map((t) => t.toJson()).toList());
    await prefs.setString('wol_devices', encoded);
    await CloudSyncService().saveSetting('wol_devices', encoded);
    await WidgetService.updateWol(_targets.map((t) => t.toJson()).toList());
  }

  Future<List<String>> _loadTerminalServerNames() async {
    final prefs = await SharedPreferences.getInstance();
    final cloudRaw = await CloudSyncService().getSetting('ssh_servers');
    final localRaw = prefs.getString('ssh_servers');
    if (cloudRaw == null && localRaw == null) return [];
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
      credentialFields: ['password'],
    );
    return merged
        .where((m) => (m['needsCredentials'] as bool? ?? false) == false)
        .map((m) => m['name'] as String? ?? '')
        .where((name) => name.isNotEmpty)
        .toList();
  }

  Future<void> _showAddDialog({WolTarget? target, int? index}) async {
    final provider = context.read<ProxmoxProvider>();
    final nodes = provider.nodes.map((n) => n['node'] as String).toList();
    final terminalServers = await _loadTerminalServerNames();
    if (!mounted) return;

    appShowModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _WolTargetSheet(
        existing: target,
        nodes: nodes,
        terminalServers: terminalServers,
        onSave: (t) async {
          setState(() {
            if (index != null) {
              _targets[index] = t;
            } else {
              _targets.add(t);
            }
          });
          await _save();
        },
      ),
    );
  }

  void _deleteTarget(int i) {
    final colors = context.appColors;
    appShowDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.surface1,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md)),
        title: Text('Cihazı Sil', style: TextStyle(color: colors.textPrimary)),
        content: Text('${_targets[i].name} silinecek.',
            style: TextStyle(color: colors.textSecondary, fontSize: 13)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('İptal', style: TextStyle(color: colors.textSecondary)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              setState(() => _targets.removeAt(i));
              await _save();
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
      backgroundColor: colors.surface0,
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: colors.surface2,
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                          ),
                          child: Icon(Icons.power_settings_new,
                              color: colors.primary, size: 22),
                        ),
                        const SizedBox(width: 14),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Wake on LAN',
                                style: TextStyle(
                                    color: colors.textPrimary,
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold)),
                            Text('${_targets.length} cihaz kayıtlı',
                                style: TextStyle(
                                    color: colors.textMuted, fontSize: 12)),
                          ],
                        ),
                        const Spacer(),
                        GestureDetector(
                          onTap: () => _showAddDialog(),
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: colors.primary,
                              borderRadius: BorderRadius.circular(AppRadius.sm),
                            ),
                            child: const Icon(Icons.add,
                                color: Colors.white, size: 20),
                          ),
                        ),
                      ],
                    ).animate().fadeIn(
                        duration: AppMotion.slow, curve: AppMotion.curve),
                    const SizedBox(height: 20),
                    if (_targets.isEmpty)
                      const _HowItWorksCard().animate().fadeIn(
                          delay: 200.ms,
                          duration: AppMotion.base,
                          curve: AppMotion.curve),
                  ],
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            sliver: _targets.isEmpty
                ? SliverToBoxAdapter(
                    child: _EmptyState(onAdd: _showAddDialog).animate().fadeIn(
                        delay: 300.ms,
                        duration: AppMotion.base,
                        curve: AppMotion.curve),
                  )
                : SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, i) => _WolCard(
                        key: ValueKey(_targets[i].mac),
                        target: _targets[i],
                        onEdit: () =>
                            _showAddDialog(target: _targets[i], index: i),
                        onDelete: () => _deleteTarget(i),
                      )
                          .animate()
                          .fadeIn(
                              delay: (i * 80).ms,
                              duration: AppMotion.base,
                              curve: AppMotion.curve)
                          .slideX(
                              begin: 0.08,
                              end: 0,
                              duration: AppMotion.base,
                              curve: AppMotion.curve),
                      childCount: _targets.length,
                    ),
                  ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 80)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// WOL Kart Widget'ı
// ─────────────────────────────────────────────

class _WolCard extends StatefulWidget {
  final WolTarget target;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _WolCard({
    super.key,
    required this.target,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  State<_WolCard> createState() => _WolCardState();
}

class _WolCardState extends State<_WolCard> with SingleTickerProviderStateMixin {
  bool _sending = false;
  bool? _sent; // null=idle, true=başarılı, false=hata
  String _statusMsg = '';
  late AnimationController _rippleCtrl;

  @override
  void initState() {
    super.initState();
    _rippleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
  }

  @override
  void dispose() {
    _rippleCtrl.dispose();
    super.dispose();
  }

  // ── Magic Packet gönderici (UDP) ──────────────────────────────────────────

  Future<void> _sendUdpMagicPacket(String mac, String broadcastIp) async {
    if (kIsWeb) {
      throw Exception(
          'UDP bu platformda (web) desteklenmiyor. SSH yöntemini kullanın.');
    }

    final cleanMac = mac.replaceAll(RegExp(r'[:\-]'), '');
    if (cleanMac.length != 12) throw Exception('Geçersiz MAC adresi: $mac');

    final macBytes = List.generate(
      6,
      (i) => int.parse(cleanMac.substring(i * 2, i * 2 + 2), radix: 16),
    );

    final packet = Uint8List(102);
    for (int i = 0; i < 6; i++) {
      packet[i] = 0xFF;
    }
    for (int i = 0; i < 16; i++) {
      for (int j = 0; j < 6; j++) {
        packet[6 + i * 6 + j] = macBytes[j];
      }
    }

    final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    socket.broadcastEnabled = true;
    socket.send(packet, InternetAddress(broadcastIp), 9);
    await Future.delayed(const Duration(milliseconds: 150));
    socket.close();
  }

  // ── SSH üzerinden etherwake / wakeonlan / python ───────────────────────────

  Future<void> _sendViaSsh(String nodeName, String mac) async {
    final prefs = await SharedPreferences.getInstance();

    // Local ÖNCELİKLİ: cloud'daki 'ssh_servers' artık şifre içermiyor (bkz.
    // credential_sync.dart) — cloud'u önce okumak SSH relay'i hep boş
    // şifreyle deneyip "SSH şifresi boş" hatasıyla başarısız kılardı.
    String? serversRaw = prefs.getString('ssh_servers');
    serversRaw ??= await CloudSyncService().getSetting('ssh_servers');

    String nodeIp = '';
    String sshUser = 'root';
    String sshPass = '';
    int sshPort = 22;

    if (serversRaw != null) {
      final List list = jsonDecode(serversRaw);
      final servers = list.map((e) => Map<String, dynamic>.from(e)).toList();

      Map<String, dynamic>? match;
      for (final s in servers) {
        if ((s['name'] as String? ?? '') == nodeName) {
          match = s;
          break;
        }
      }

      if (match != null) {
        nodeIp = match['host'] as String? ?? '';
        sshUser = match['username'] as String? ?? 'root';
        sshPass = match['password'] as String? ?? '';
        sshPort = (match['port'] as int?) ?? 22;
      }
    }

    if (nodeIp.isEmpty) {
      throw Exception(
          "'$nodeName' adlı SSH sunucusu bulunamadı. Cihazı düzenleyip relay'i tekrar seçin.");
    }
    if (sshPass.isEmpty) {
      throw Exception(
          'SSH şifresi boş. Terminal ekranından sunucuyu düzenleyin.');
    }

    final socket = await SSHSocket.connect(nodeIp, sshPort).timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw Exception(
            'SSH bağlantısı zaman aşımına uğradı ($nodeIp:$sshPort)'));

    final client = SSHClient(
      socket,
      username: sshUser,
      onPasswordRequest: () => sshPass,
    );

    await client.authenticated.timeout(const Duration(seconds: 10),
        onTimeout: () => throw Exception('SSH kimlik doğrulama zaman aşımı'));

    final macColon = mac
        .toUpperCase()
        .replaceAll('-', ':')
        .replaceAll(RegExp(r'[^0-9A-F]'), '');
    final macFormatted =
        List.generate(6, (i) => macColon.substring(i * 2, i * 2 + 2)).join(':');
    final macNoColon = macFormatted.replaceAll(':', '');

    final cmd = [
      'if command -v etherwake > /dev/null 2>&1; then',
      '  etherwake -b $macFormatted',
      'elif command -v wakeonlan > /dev/null 2>&1; then',
      '  wakeonlan $macFormatted',
      'else',
      '  python3 - <<\'PYEOF\'',
      'import socket',
      'mac = bytes.fromhex("$macNoColon")',
      'packet = b"\\xff" * 6 + mac * 16',
      's = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)',
      's.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)',
      's.sendto(packet, ("255.255.255.255", 9))',
      's.close()',
      'PYEOF',
      'fi',
    ].join('\n');

    await client.run(cmd).timeout(
          const Duration(seconds: 15),
          onTimeout: () => throw Exception('SSH komutu zaman aşımı'),
        );

    client.close();
    socket.destroy();
  }

  // ── Ana gönderim mantığı ──────────────────────────────────────────────────

  Future<void> _wake() async {
    final provider = context.read<ProxmoxProvider>();

    setState(() {
      _sending = true;
      _sent = null;
      _statusMsg = 'Paket gönderiliyor...';
    });
    _rippleCtrl.repeat();

    bool success = false;
    final errors = <String>[];
    final method = widget.target.method;

    if (method == 'udp' || method == 'both') {
      try {
        await _sendUdpMagicPacket(widget.target.mac, widget.target.broadcastIp);
        success = true;
        // UDP'nin doğası gereği teslimat/başarı onayı alınamaz (fire-and-
        // forget) — SSH/API yollarının aksine bu sadece PAKETİN bu cihazdan
        // çıktığını doğrular, hedefin gerçekten uyandığını değil.
        _statusMsg = 'Paket gönderildi — cihazın uyanması birkaç saniye sürebilir';
      } catch (e) {
        errors.add('UDP: ${e.toString().split('\n').first}');
      }
    }

    final relayNode = widget.target.relayNode;

    if (!success && (method == 'ssh' || method == 'both')) {
      if (relayNode.isNotEmpty) {
        try {
          await _sendViaSsh(relayNode, widget.target.mac);
          success = true;
          _statusMsg = 'SSH relay ile gönderildi ($relayNode) ✓';
        } catch (e) {
          errors.add('SSH: ${e.toString().split('\n').first}');
        }
      } else {
        errors.add('SSH: Relay sunucu seçilmemiş — cihazı düzenleyin');
      }
    }

    if (!success && (method == 'ssh' || method == 'both')) {
      final availableNodes =
          provider.nodes.map((n) => n['node'] as String).toList();
      if (availableNodes.contains(relayNode)) {
        try {
          await provider.sendWakeOnLan(relayNode, widget.target.mac);
          success = true;
          _statusMsg = 'Proxmox API ile gönderildi ✓';
        } catch (e) {
          errors.add('API: ${e.toString().split('\n').first}');
        }
      }
    }

    if (!mounted) return;
    _rippleCtrl.stop();
    _rippleCtrl.reset();

    setState(() {
      _sending = false;
      _sent = success;
      if (!success) {
        _statusMsg = errors.join('\n');
      }
    });

    await Future.delayed(const Duration(seconds: 4));
    if (mounted) {
      setState(() {
        _sent = null;
        _statusMsg = '';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    final statusColor = _sending
        ? colors.warning
        : _sent == true
            ? colors.success
            : _sent == false
                ? colors.error
                : colors.primary;

    final methodLabel = widget.target.method == 'udp'
        ? 'UDP'
        : widget.target.method == 'ssh'
            ? 'SSH'
            : 'UDP + SSH';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: colors.hairline),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            GestureDetector(
              onTap: _sending ? null : _wake,
              child: AnimatedBuilder(
                animation: _rippleCtrl,
                builder: (_, child) => Stack(
                  alignment: Alignment.center,
                  children: [
                    if (_sending)
                      Opacity(
                        opacity: (1 - _rippleCtrl.value).clamp(0.0, 1.0) * 0.3,
                        child: Container(
                          width: 52 + _rippleCtrl.value * 24,
                          height: 52 + _rippleCtrl.value * 24,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: colors.warning, width: 1),
                          ),
                        ),
                      ),
                    child!,
                  ],
                ),
                child: AnimatedContainer(
                  duration: AppMotion.base,
                  curve: AppMotion.curve,
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: statusColor.withValues(alpha: 0.15),
                    border: Border.all(
                        color: statusColor.withValues(alpha: 0.4), width: 2),
                    boxShadow: _sent == true
                        ? [
                            BoxShadow(
                              color: colors.success.withValues(alpha: 0.3),
                              blurRadius: 16,
                            )
                          ]
                        : null,
                  ),
                  child: _sending
                      ? SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: statusColor),
                        )
                      : Icon(
                          _sent == true
                              ? Icons.check_rounded
                              : _sent == false
                                  ? Icons.close_rounded
                                  : Icons.power_settings_new,
                          color: statusColor,
                          size: 24,
                        ),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.target.name,
                      style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Icon(Icons.memory, color: colors.textMuted, size: 12),
                      const SizedBox(width: 4),
                      Text(widget.target.mac,
                          style: TextStyle(
                              color: colors.textMuted,
                              fontSize: 11,
                              fontFamily: 'monospace')),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: colors.surface2,
                          borderRadius: BorderRadius.circular(AppRadius.xs),
                        ),
                        child: Text(methodLabel,
                            style: TextStyle(
                                color: colors.textSecondary,
                                fontSize: 9,
                                fontWeight: FontWeight.bold)),
                      ),
                      if (widget.target.method != 'udp' &&
                          widget.target.relayNode.isNotEmpty)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.dns_outlined,
                                color: colors.textMuted, size: 12),
                            const SizedBox(width: 3),
                            Text('Relay: ${widget.target.relayNode}',
                                style: TextStyle(
                                    color: colors.textMuted, fontSize: 10)),
                          ],
                        ),
                      if (widget.target.method != 'ssh' &&
                          widget.target.broadcastIp.isNotEmpty)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.wifi_tethering,
                                color: colors.textMuted, size: 12),
                            const SizedBox(width: 3),
                            Text(widget.target.broadcastIp,
                                style: TextStyle(
                                    color: colors.textMuted, fontSize: 10)),
                          ],
                        ),
                    ],
                  ),
                  if (_statusMsg.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: (_sent == true
                                ? colors.success
                                : _sent == false
                                    ? colors.error
                                    : colors.warning)
                            .withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(AppRadius.xs),
                      ),
                      child: Text(
                        _statusMsg,
                        style: TextStyle(
                            color: _sent == true
                                ? colors.success
                                : _sent == false
                                    ? colors.error
                                    : colors.warning,
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                            height: 1.4),
                      ),
                    ),
                  ],
                  if (widget.target.description != null &&
                      widget.target.description!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(widget.target.description!,
                        style: TextStyle(
                            color: colors.textSecondary, fontSize: 11)),
                  ],
                ],
              ),
            ),
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert, color: colors.textMuted, size: 20),
              color: colors.surface1,
              onSelected: (v) {
                if (v == 'edit') widget.onEdit();
                if (v == 'delete') widget.onDelete();
                if (v == 'copy') {
                  Clipboard.setData(ClipboardData(text: widget.target.mac));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content: const Text('MAC adresi kopyalandı'),
                        backgroundColor: colors.success),
                  );
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'copy',
                  child: Row(children: [
                    Icon(Icons.copy, color: colors.textSecondary, size: 16),
                    const SizedBox(width: 8),
                    Text('MAC Kopyala',
                        style: TextStyle(color: colors.textPrimary)),
                  ]),
                ),
                PopupMenuItem(
                  value: 'edit',
                  child: Row(children: [
                    Icon(Icons.edit_outlined,
                        color: colors.textSecondary, size: 16),
                    const SizedBox(width: 8),
                    Text('Düzenle',
                        style: TextStyle(color: colors.textPrimary)),
                  ]),
                ),
                PopupMenuItem(
                  value: 'delete',
                  child: Row(children: [
                    Icon(Icons.delete_outline, color: colors.error, size: 16),
                    const SizedBox(width: 8),
                    Text('Sil', style: TextStyle(color: colors.textPrimary)),
                  ]),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Cihaz Ekle / Düzenle Bottom Sheet
// ─────────────────────────────────────────────

class _WolTargetSheet extends StatefulWidget {
  final WolTarget? existing;
  final List<String> nodes;
  final List<String> terminalServers;
  final Function(WolTarget) onSave;

  const _WolTargetSheet({
    this.existing,
    required this.nodes,
    this.terminalServers = const [],
    required this.onSave,
  });

  @override
  State<_WolTargetSheet> createState() => _WolTargetSheetState();
}

class _WolTargetSheetState extends State<_WolTargetSheet> {
  late TextEditingController _nameCtrl;
  late TextEditingController _macCtrl;
  late TextEditingController _broadcastCtrl;
  late TextEditingController _descCtrl;
  String? _selectedNode;
  String _method = 'both';

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _nameCtrl = TextEditingController(text: e?.name ?? '');
    _macCtrl = TextEditingController(text: e?.mac ?? '');
    _broadcastCtrl =
        TextEditingController(text: e?.broadcastIp ?? '255.255.255.255');
    _descCtrl = TextEditingController(text: e?.description ?? '');
    _method = e?.method ?? 'both';

    if (e?.relayNode.isNotEmpty == true) {
      // Kaydı KORU — liste henüz yüklenmemiş, sunucu yeniden adlandırılmış/
      // silinmiş ya da (senkronize kimlik bilgisi eksikliğinden) bu cihazda
      // henüz seçilebilir olmasa bile burada sessizce BAŞKA bir sunucuya
      // değiştirmiyoruz. Aksi halde kullanıcı sadece cihaz adını düzenleyip
      // Kaydet'e bassa bile relay, farkında olmadan _allRelays.first'e
      // değişmiş olurdu — build() bu durumu _staleRelay ile ayrıca
      // kullanıcıya gösterip listede tekrar seçilebilir hale getiriyor.
      _selectedNode = e!.relayNode;
    } else if (_allRelays.isNotEmpty) {
      _selectedNode = _allRelays.first;
    }
  }

  List<String> get _allRelays => [...widget.nodes, ...widget.terminalServers];

  /// Kayıtlı relay artık mevcut Proxmox node / Terminal SSH sunucu
  /// listesinde yoksa (yeniden adlandırıldı/silindi/henüz yüklenmedi) bu,
  /// o değeri taşır — build() bunu ayrı, uyarılı bir seçenek olarak
  /// gösterir ki kullanıcı ya bilinçli olarak değiştirsin ya da olduğu
  /// gibi korunsun.
  String? get _staleRelay =>
      _selectedNode != null && !_allRelays.contains(_selectedNode)
          ? _selectedNode
          : null;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _macCtrl.dispose();
    _broadcastCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  bool _validMAC(String mac) =>
      RegExp(r'^([0-9A-Fa-f]{2}[:\-]){5}([0-9A-Fa-f]{2})$').hasMatch(mac);

  void _save() {
    final colors = context.appColors;
    final name = _nameCtrl.text.trim();
    final mac = _macCtrl.text.trim();

    if (name.isEmpty || mac.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('Lütfen zorunlu alanları doldurun'),
          backgroundColor: colors.error));
      return;
    }
    if (!_validMAC(mac)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text(
              'Geçerli bir MAC adresi girin\nÖrn: AA:BB:CC:DD:EE:FF'),
          backgroundColor: colors.error));
      return;
    }
    if ((_method == 'ssh' || _method == 'both') && _selectedNode == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('SSH yöntemi için bir relay sunucu seçin'),
          backgroundColor: colors.error));
      return;
    }

    widget.onSave(WolTarget(
      name: name,
      mac: mac.toUpperCase(),
      relayNode: _selectedNode ?? '',
      broadcastIp: _broadcastCtrl.text.trim().isEmpty
          ? '255.255.255.255'
          : _broadcastCtrl.text.trim(),
      method: _method,
      description: _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
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
          24, 16, 24, MediaQuery.of(context).viewInsets.bottom + 24),
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
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 20),
            Text(widget.existing == null ? 'Cihaz Ekle' : 'Cihazı Düzenle',
                style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('WOL ile uyandırılacak cihaz bilgilerini girin',
                style: TextStyle(color: colors.textMuted, fontSize: 12)),
            const SizedBox(height: 20),
            _buildField(context,
                label: 'Cihaz Adı *',
                ctrl: _nameCtrl,
                hint: 'Örn: Gaming PC, NAS',
                icon: Icons.computer_outlined),
            _buildField(context,
                label: 'MAC Adresi *',
                ctrl: _macCtrl,
                hint: 'AA:BB:CC:DD:EE:FF',
                icon: Icons.memory,
                caps: true),
            _infoBox(context,
                color: colors.textSecondary,
                icon: Icons.info_outline,
                text:
                    'Windows: ipconfig /all → Physical Address\nLinux/Mac: ip link show  |  arp -a'),
            Text('Gönderim Yöntemi',
                style: TextStyle(color: colors.textSecondary, fontSize: 13)),
            const SizedBox(height: 8),
            Row(
              children: [
                _MethodChip(
                    'UDP', 'udp', _method, (v) => setState(() => _method = v)),
                const SizedBox(width: 8),
                _MethodChip(
                    'SSH', 'ssh', _method, (v) => setState(() => _method = v)),
                const SizedBox(width: 8),
                _MethodChip('Her İkisi', 'both', _method,
                    (v) => setState(() => _method = v)),
              ],
            ),
            const SizedBox(height: 12),
            if (_method == 'udp' || _method == 'both') ...[
              _buildField(context,
                  label: 'Broadcast IP',
                  ctrl: _broadcastCtrl,
                  hint: '192.168.1.255',
                  icon: Icons.wifi_tethering),
              _infoBox(context,
                  color: colors.warning,
                  icon: Icons.warning_amber_outlined,
                  text:
                      'UDP yöntemi yalnızca aynı ağdayken (cihaz ile hedef aynı yerel ağda) çalışır.\nDış ağdan erişim için SSH yöntemini kullanın.'),
            ],
            if (_method == 'ssh' || _method == 'both') ...[
              Text('Relay Sunucu (SSH)',
                  style: TextStyle(color: colors.textSecondary, fontSize: 13)),
              const SizedBox(height: 8),
              if (_staleRelay != null) _staleRelayOption(context, _staleRelay!),
              if (widget.nodes.isEmpty && widget.terminalServers.isEmpty)
                if (_staleRelay == null)
                  _infoBox(context,
                      color: colors.error,
                      icon: Icons.warning_outlined,
                      text:
                          'Ne Proxmox sunucusu ne de Terminal SSH sunucusu bulundu. Lütfen önce birini ekleyin.')
                else
                  const SizedBox.shrink()
              else ...[
                if (widget.nodes.isNotEmpty) ...[
                  _relaySectionLabel(context, 'Proxmox Node\'ları'),
                  ...widget.nodes.map((node) => _relayOption(context, node,
                      icon: Icons.dns_outlined)),
                ],
                if (widget.terminalServers.isNotEmpty) ...[
                  _relaySectionLabel(context, 'Terminal SSH Sunucuları'),
                  ...widget.terminalServers.map((name) => _relayOption(
                      context, name,
                      icon: Icons.terminal)),
                ],
              ],
              const SizedBox(height: 4),
            ],
            _buildField(context,
                label: 'Açıklama',
                ctrl: _descCtrl,
                hint: 'Opsiyonel not',
                icon: Icons.notes),
            const SizedBox(height: 20),
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
                child: const Text('Kaydet',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _relaySectionLabel(BuildContext context, String text) {
    final colors = context.appColors;
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 6),
      child: Text(text,
          style: TextStyle(
              color: colors.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w600)),
    );
  }

  /// Şu an düzenlenen cihazın kayıtlı relay'i mevcut node/sunucu
  /// listesinde bulunmuyor (yeniden adlandırıldı, silindi ya da bu
  /// cihazda kimlik bilgisi henüz senkron değil). Kaydı sessizce
  /// kaybetmemek için ayrı, uyarılı bir seçenek olarak gösteriyoruz —
  /// kullanıcı dokunmazsa olduğu gibi korunur.
  Widget _staleRelayOption(BuildContext context, String name) {
    final colors = context.appColors;
    return Container(
      key: ValueKey('stale-$name'),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: colors.warning.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: colors.warning.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(Icons.radio_button_checked, color: colors.warning, size: 18),
          const SizedBox(width: 10),
          Icon(Icons.warning_amber_rounded, color: colors.warning, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: TextStyle(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.w600,
                        fontSize: 13)),
                Text('Kayıtlı ama şu an listede yok — dokunmazsanız korunur',
                    style: TextStyle(color: colors.textMuted, fontSize: 10)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _relayOption(BuildContext context, String name,
      {required IconData icon}) {
    final colors = context.appColors;
    final selected = _selectedNode == name;
    return GestureDetector(
      key: ValueKey(name),
      onTap: () => setState(() => _selectedNode = name),
      child: AnimatedContainer(
        duration: AppMotion.fast,
        curve: AppMotion.curve,
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? colors.primary.withValues(alpha: 0.12)
              : colors.surface2,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
            color: selected
                ? colors.primary.withValues(alpha: 0.4)
                : colors.hairline,
          ),
        ),
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              color: selected ? colors.primary : colors.textMuted,
              size: 18,
            ),
            const SizedBox(width: 10),
            Icon(icon, color: colors.textMuted, size: 16),
            const SizedBox(width: 8),
            Text(name,
                style: TextStyle(
                    color:
                        selected ? colors.textPrimary : colors.textSecondary,
                    fontWeight:
                        selected ? FontWeight.w600 : FontWeight.normal)),
          ],
        ),
      ),
    );
  }

  Widget _buildField(
    BuildContext context, {
    required String label,
    required TextEditingController ctrl,
    required String hint,
    IconData? icon,
    bool caps = false,
  }) {
    final colors = context.appColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: ctrl,
        textCapitalization:
            caps ? TextCapitalization.characters : TextCapitalization.none,
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
              borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              borderSide: BorderSide(color: colors.primary, width: 1.5)),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
      ),
    );
  }

  Widget _infoBox(
    BuildContext context, {
    required Color color,
    required IconData icon,
    required String text,
  }) {
    final colors = context.appColors;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: TextStyle(
                    color: colors.textSecondary, fontSize: 11, height: 1.6)),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Küçük Yardımcı Widget'lar
// ─────────────────────────────────────────────

class _MethodChip extends StatelessWidget {
  final String label;
  final String value;
  final String selected;
  final Function(String) onTap;

  const _MethodChip(this.label, this.value, this.selected, this.onTap);

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final isSelected = value == selected;
    return GestureDetector(
      onTap: () => onTap(value),
      child: AnimatedContainer(
        duration: AppMotion.fast,
        curve: AppMotion.curve,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? colors.primary.withValues(alpha: 0.15)
              : colors.surface2,
          borderRadius: BorderRadius.circular(AppRadius.xs),
          border: Border.all(
            color: isSelected
                ? colors.primary.withValues(alpha: 0.5)
                : colors.hairline,
          ),
        ),
        child: Text(label,
            style: TextStyle(
                color: isSelected ? colors.primary : colors.textMuted,
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal)),
      ),
    );
  }
}

class _HowItWorksCard extends StatelessWidget {
  const _HowItWorksCard();

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
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
              Icon(Icons.info_outline, color: colors.textMuted, size: 16),
              const SizedBox(width: 8),
              Text('Nasıl çalışır?',
                  style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 12),
          const _WorkStep(
              icon: Icons.wifi_tethering,
              text: 'UDP: Aynı ağdayken direkt magic packet gönderir'),
          const _WorkStep(
              icon: Icons.terminal,
              text:
                  'SSH: Proxmox node veya Terminal SSH sunucusu üzerinden etherwake çalıştırır (her platform)'),
          const _WorkStep(
              icon: Icons.repeat,
              text:
                  '"Her İkisi": Önce UDP, başarısız olursa SSH, son çare Proxmox API'),
        ],
      ),
    );
  }
}

class _WorkStep extends StatelessWidget {
  final IconData icon;
  final String text;

  const _WorkStep({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
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
            child: Text(text,
                style: TextStyle(
                    color: colors.textSecondary, fontSize: 12, height: 1.4)),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;

  const _EmptyState({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: colors.surface2,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.power_settings_new,
                color: colors.textSecondary, size: 32),
          ),
          const SizedBox(height: 16),
          Text('Cihaz bulunamadı',
              style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(
            'Uyandırmak istediğin cihazları ekle.\nUDP (masaüstü/iç ağ) veya SSH (her platform/dış ağ) ile çalışır.',
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
              label: const Text('İlk Cihazı Ekle',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold)),
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
    );
  }
}
