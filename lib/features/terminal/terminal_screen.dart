import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../../core/utils/app_transitions.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:xterm/xterm.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/design_widgets.dart';
import '../proxmox/proxmox_provider.dart';
import '../../core/services/cloud_sync_service.dart';
import '../../core/utils/credential_sync.dart';
import '../notifications/background_service.dart' show kNotificationAccent, hhmm;

class SshServer {
  String name;
  String host;
  int port;
  String username;
  String password;
  String? description;

  SshServer({
    required this.name,
    required this.host,
    this.port = 22,
    required this.username,
    required this.password,
    this.description,
    this.needsCredentials = false,
  });

  /// Bu sunucu cloud'dan geldiğinde, başka bir cihazda şifre girilmiş ama
  /// bu cihazda henüz yoksa true olur (bkz. credential_sync.dart). Boş
  /// şifre her zaman "eksik" demek değildir — bilinçli boş bırakılmışsa
  /// bu false kalır. Cloud'a hiç yazılmaz, sadece bu oturumda UI için.
  bool needsCredentials;

  Map<String, dynamic> toJson() => {
        'name': name,
        'host': host,
        'port': port,
        'username': username,
        'password': password,
        'description': description,
      };

  factory SshServer.fromJson(Map<String, dynamic> j) => SshServer(
        name: j['name'] ?? '',
        host: j['host'] ?? '',
        port: j['port'] ?? 22,
        username: j['username'] ?? 'root',
        password: j['password'] ?? '',
        description: j['description'],
      );
}

/// Termius'taki "snippets" özelliğinden esinlenildi — tek dokunuşla
/// çalıştırılabilen, sık kullanılan komutlar. Sunucular gibi cloud+local
/// olarak saklanır.
class TerminalSnippet {
  String label;
  String command;

  TerminalSnippet({required this.label, required this.command});

  Map<String, dynamic> toJson() => {'label': label, 'command': command};

  factory TerminalSnippet.fromJson(Map<String, dynamic> j) => TerminalSnippet(
        label: j['label'] ?? '',
        command: j['command'] ?? '',
      );

  static List<TerminalSnippet> defaults() => [
        TerminalSnippet(label: 'Disk Kullanımı', command: 'df -h'),
        TerminalSnippet(label: 'Bellek Kullanımı', command: 'free -h'),
        TerminalSnippet(label: 'Süreçler', command: 'top -bn1 | head -20'),
        TerminalSnippet(label: 'Docker Konteynerleri', command: 'docker ps'),
        TerminalSnippet(label: 'Sistem Günlüğü', command: 'journalctl -xe -n 50'),
      ];
}

class TerminalScreen extends StatefulWidget {
  const TerminalScreen({super.key});

  @override
  State<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends State<TerminalScreen> {
  List<SshServer> _servers = [];
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
    final cloudRaw = await CloudSyncService().getSetting('ssh_servers');
    final localRaw = prefs.getString('ssh_servers');
    final List<SshServer> servers = [];
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
        credentialFields: ['password'],
      );
      servers.addAll(merged.map((m) {
        final s = SshServer.fromJson(m);
        s.needsCredentials = m['needsCredentials'] as bool? ?? false;
        return s;
      }));
    }
    if (!mounted) return;
    setState(() => _servers = servers);
    _syncProxmoxNodes();
  }

  void _syncProxmoxNodes() {
    final provider = context.read<ProxmoxProvider>();
    for (final node in provider.nodes) {
      final name = node['node'] as String;
      if (_servers.any((s) => s.name == 'Proxmox: $name')) continue;
      final networks = provider.nodeNetworks[name] ?? [];
      String ip = '';
      for (final net in networks) {
        if (net['address'] != null) {
          ip = net['address'];
          break;
        }
      }
      if (ip.isEmpty) continue;
    }
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(_servers.map((s) => s.toJson()).toList());
    await prefs.setString('ssh_servers', encoded);
    // Şifre cloud'a hiç yazılmaz — bkz. credential_sync.dart.
    final sanitized = jsonEncode(_servers
        .map((s) => stripCredentialFields(s.toJson(), ['password']))
        .toList());
    await CloudSyncService().saveSetting('ssh_servers', sanitized);
    if (_servers.isNotEmpty) {
      await prefs.setString('proxmox_ssh_user', _servers.first.username);
      await prefs.setString('proxmox_ssh_pass', _servers.first.password);
      await prefs.setInt('proxmox_ssh_port', _servers.first.port);
    }
  }

  void _showAddDialog({SshServer? server, int? index}) {
    appShowModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _SshServerSheet(
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
        },
      ),
    );
  }

  void _deleteServer(int i) {
    final colors = context.appColors;
    appShowDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.surface1,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md)),
        title:
            Text('Sunucuyu Sil', style: TextStyle(color: colors.textPrimary)),
        content: Text('${_servers[i].name} silinecek.',
            style: TextStyle(color: colors.textSecondary, fontSize: 13)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('İptal', style: TextStyle(color: colors.textSecondary)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              setState(() => _servers.removeAt(i));
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

  void _openTerminal(SshServer server) {
    Navigator.push(
      context,
      AppTransitions.slideFade(_TerminalView(server: server)),
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
                          child:
                              Icon(Icons.terminal, color: colors.primary, size: 22),
                        ),
                        const SizedBox(width: 14),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Terminal',
                                style: TextStyle(
                                    color: colors.textPrimary,
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold)),
                            Text('${_servers.length} sunucu kayıtlı',
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
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: colors.surface2,
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        border: Border.all(color: colors.hairline),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.link, color: colors.textMuted, size: 16),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Wake on LAN SSH relay bu ekrandaki sunucu bilgilerini kullanır.\nBuraya eklediğin sunucular WOL\'da da kullanılabilir.',
                              style: TextStyle(
                                  color: colors.textSecondary,
                                  fontSize: 11,
                                  height: 1.5),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          ),
          if (_servers.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: _EmptyState(onAdd: _showAddDialog),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 80),
              sliver: SliverList.separated(
                itemCount: _servers.length,
                separatorBuilder: (_, __) =>
                    Divider(height: 1, color: colors.hairline),
                itemBuilder: (context, i) => _ServerCard(
                  key: ValueKey(_servers[i].name),
                  server: _servers[i],
                  onTap: _servers[i].needsCredentials
                      ? () => _showAddDialog(server: _servers[i], index: i)
                      : () => _openTerminal(_servers[i]),
                  onEdit: () => _showAddDialog(server: _servers[i], index: i),
                  onDelete: () => _deleteServer(i),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ServerCard extends StatelessWidget {
  final SshServer server;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ServerCard({
    super.key,
    required this.server,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  void _showActions(BuildContext context, AppThemeData colors) {
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
            ListTile(
              leading: Icon(Icons.edit_outlined, color: colors.textSecondary),
              title:
                  Text('Düzenle', style: TextStyle(color: colors.textPrimary)),
              onTap: () {
                Navigator.pop(ctx);
                onEdit();
              },
            ),
            ListTile(
              leading: Icon(Icons.delete_outline, color: colors.error),
              title: Text('Sil', style: TextStyle(color: colors.textPrimary)),
              onTap: () {
                Navigator.pop(ctx);
                onDelete();
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

    return InkWell(
      onTap: onTap,
      onLongPress: () => _showActions(context, colors),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Icon(Icons.terminal, color: colors.textSecondary, size: 16),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(server.name,
                      style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(
                    '${server.username}@${server.host}:${server.port}',
                    style: TextStyle(
                        color: colors.textMuted,
                        fontSize: 11,
                        fontFamily: 'monospace'),
                  ),
                  if (server.description != null &&
                      server.description!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(server.description!,
                        style: TextStyle(
                            color: colors.textSecondary, fontSize: 11)),
                  ],
                  if (server.needsCredentials) ...[
                    const SizedBox(height: 4),
                    StatusIndicator(
                      color: colors.warning,
                      label: 'Kimlik bilgisi gerekli',
                      style: colors.meta,
                    ),
                  ],
                ],
              ),
            ),
            Icon(
                server.needsCredentials
                    ? Icons.key_off_rounded
                    : Icons.chevron_right,
                color: colors.textMuted,
                size: 18),
          ],
        ),
      ),
    );
  }
}

class _TerminalView extends StatefulWidget {
  final SshServer server;
  const _TerminalView({required this.server});

  @override
  State<_TerminalView> createState() => _TerminalViewState();
}

class _TerminalViewState extends State<_TerminalView> {
  final _terminal = Terminal();
  final _terminalController = TerminalController();
  final _plugin = FlutterLocalNotificationsPlugin();
  SSHClient? _client;
  SSHSession? _session;
  bool _connected = false;
  bool _connecting = true;
  String _error = '';
  List<TerminalSnippet> _snippets = [];

  @override
  void initState() {
    super.initState();
    _initNotifications();
    _connect();
    _loadSnippets();
  }

  Future<void> _initNotifications() async {
    const android = AndroidInitializationSettings('@drawable/ic_notification');
    await _plugin.initialize(const InitializationSettings(android: android));
  }

  // ── Metin seçimi / pano ───────────────────────────────────────────────────

  Future<void> _copySelection() async {
    final selection = _terminalController.selection;
    if (selection == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Önce kopyalamak istediğin metni basılı tutup sürükleyerek seç'),
        backgroundColor: Color(0xFF2D2D2D),
      ));
      return;
    }
    final text = _terminal.buffer.getText(selection);
    await Clipboard.setData(ClipboardData(text: text));
    _terminalController.clearSelection();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Kopyalandı'),
      backgroundColor: Colors.green,
      duration: Duration(seconds: 1),
    ));
  }

  void _selectAll() {
    _terminalController.setSelection(
      _terminal.buffer.createAnchor(
        0,
        _terminal.buffer.height - _terminal.viewHeight,
      ),
      _terminal.buffer.createAnchor(
        _terminal.viewWidth,
        _terminal.buffer.height - 1,
      ),
      mode: SelectionMode.line,
    );
  }

  Future<void> _pasteClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text != null && text.isNotEmpty) {
      _terminal.paste(text);
    }
  }

  // ── Komut kısayolları (Termius "snippets"inden esinlenildi) ───────────────

  Future<void> _loadSnippets() async {
    final prefs = await SharedPreferences.getInstance();
    String? raw = await CloudSyncService().getSetting('terminal_snippets');
    raw ??= prefs.getString('terminal_snippets');
    if (raw == null) {
      if (mounted) setState(() => _snippets = TerminalSnippet.defaults());
      return;
    }
    try {
      final List list = jsonDecode(raw);
      final loaded = list
          .map((e) => TerminalSnippet.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      if (mounted) setState(() => _snippets = loaded);
    } catch (_) {
      if (mounted) setState(() => _snippets = TerminalSnippet.defaults());
    }
  }

  Future<void> _saveSnippets() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(_snippets.map((s) => s.toJson()).toList());
    await prefs.setString('terminal_snippets', encoded);
    await CloudSyncService().saveSetting('terminal_snippets', encoded);
  }

  void _runSnippet(String command) {
    _session?.stdin.add(utf8.encode('$command\n'));
  }

  void _showSnippetsSheet() {
    appShowModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _SnippetsSheet(
        snippets: _snippets,
        onRun: (command) {
          Navigator.pop(ctx);
          _runSnippet(command);
        },
        onChanged: (updated) {
          setState(() => _snippets = updated);
          _saveSnippets();
        },
      ),
    );
  }

  Future<void> _notify(String title, String body) async {
    const details = AndroidNotificationDetails(
      'mtools_terminal',
      'Terminal Bildirimleri',
      channelDescription: 'SSH terminal bağlantı durumu',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      icon: '@drawable/ic_notification',
      color: kNotificationAccent,
    );
    await _plugin.show(
        99, title, body, const NotificationDetails(android: details));
  }

  Future<void> _connect() async {
    setState(() {
      _connecting = true;
      _error = '';
    });
    try {
      final socket =
          await SSHSocket.connect(widget.server.host, widget.server.port);
      _client = SSHClient(socket,
          username: widget.server.username,
          onPasswordRequest: () => widget.server.password,
          // dartssh2 zaten varsayılan 10 sn'lik bir keepalive gönderiyor,
          // ama bunu burada açıkça belirtmek hem niyeti koda yazıyor hem de
          // kütüphanenin gelecekteki varsayılanından bağımsız kılıyor —
          // sessiz ağ kaybında bağlantının canlı görünmeye devam etmesi
          // süresini kısaltmaya yardımcı olur.
          keepAliveInterval: const Duration(seconds: 15));
      await _client!.authenticated;
      _session = await _client!.shell(
        pty: const SSHPtyConfig(width: 80, height: 24),
      );
      if (!mounted) return;
      setState(() {
        _connected = true;
        _connecting = false;
      });
      await _notify('Terminal Bağlandı',
          '${widget.server.name} · ${widget.server.host} · ${hhmm(DateTime.now())}');
      _terminal.onOutput = (data) {
        _session!.stdin.add(utf8.encode(data));
      };
      _session!.stdout.listen((data) {
        _terminal.write(utf8.decode(data, allowMalformed: true));
      });
      _session!.stderr.listen((data) {
        _terminal.write(utf8.decode(data, allowMalformed: true));
      });
      _session!.done.then((_) async {
        if (mounted) {
          setState(() {
            _connected = false;
            _error = 'Oturum sonlandı';
          });
        }
        await _notify('Terminal Bağlantısı Kesildi',
            '${widget.server.name} · Oturum sonlandı · ${hhmm(DateTime.now())}');
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _connecting = false;
          _connected = false;
          _error = e.toString();
        });
      }
      await _notify('Bağlantı Hatası',
          '${widget.server.name} · ${e.toString().split('\n').first} · ${hhmm(DateTime.now())}');
    }
  }

  @override
  void dispose() {
    _terminalController.dispose();
    _session?.close();
    _client?.close();
    super.dispose();
  }

  Widget _key(String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFF2D2D2D),
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        ),
        child: Text(label,
            style: const TextStyle(
                color: Colors.white70,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                fontFamily: 'monospace')),
      ),
    );
  }

  // İkonlu eylem düğmeleri (Kopyala/Yapıştır/Tümü Seç/Kısayollar) — ham
  // kontrol tuşlarından (Ctrl+C vb.) görsel olarak ayırt edilsin diye ayrı
  // bir stil kullanılıyor.
  Widget _actionKey(IconData icon, String label, VoidCallback onTap,
      {bool active = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: active
              ? Colors.greenAccent.withValues(alpha: 0.15)
              : const Color(0xFF2D2D2D),
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(
            color: active
                ? Colors.greenAccent.withValues(alpha: 0.4)
                : Colors.white.withValues(alpha: 0.1),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 13, color: active ? Colors.greenAccent : Colors.white70),
            const SizedBox(width: 5),
            Text(label,
                style: TextStyle(
                    color: active ? Colors.greenAccent : Colors.white70,
                    fontSize: 11,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A1A),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new,
              color: Colors.white70, size: 16),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.server.name,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600)),
            Text(
              '${widget.server.username}@${widget.server.host}',
              style: const TextStyle(
                  color: Colors.white54, fontSize: 11, fontFamily: 'monospace'),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Center(
              child: StatusIndicator(
                // 3 gerçek durum var (bağlanıyor/bağlı/kesildi) ama önceden
                // sadece 2 renk vardı — "bağlanıyor" görsel olarak "kesildi"
                // ile aynı (kırmızı) görünüyordu. Amber üçüncü durumu ayırt eder.
                color: _connecting
                    ? Colors.amber
                    : _connected
                        ? Colors.green
                        : Colors.red,
                label: _connecting
                    ? 'Bağlanıyor...'
                    : _connected
                        ? 'Bağlı'
                        : 'Bağlantı Kesildi',
                style: TextStyle(
                  color: _connecting
                      ? Colors.amber
                      : _connected
                          ? Colors.green
                          : Colors.red,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          if (_connected)
            IconButton(
              icon: const Icon(Icons.power_settings_new,
                  color: Colors.red, size: 18),
              onPressed: () {
                appShowDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    backgroundColor: const Color(0xFF1A1A1A),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.md)),
                    title: const Text('Oturumu Sonlandır',
                        style: TextStyle(color: Colors.white)),
                    content: const Text('SSH bağlantısı kapatılacak.',
                        style: TextStyle(color: Colors.white54)),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('İptal',
                            style: TextStyle(color: Colors.white54)),
                      ),
                      TextButton(
                        onPressed: () {
                          Navigator.pop(ctx);
                          _session?.close();
                          _client?.close();
                          Navigator.pop(context);
                        },
                        child: const Text('Sonlandır',
                            style: TextStyle(
                                color: Colors.red,
                                fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                );
              },
            ),
          if (!_connected && !_connecting)
            IconButton(
              icon: const Icon(Icons.refresh, color: Colors.white70, size: 18),
              onPressed: _connect,
            ),
        ],
      ),
      body: _connecting
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(color: Colors.green),
                  const SizedBox(height: 16),
                  Text(
                    'Bağlanılıyor...\n${widget.server.host}:${widget.server.port}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white54, fontSize: 13),
                  ),
                ],
              ),
            )
          : !_connected
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline,
                          color: Colors.red, size: 48),
                      const SizedBox(height: 16),
                      const Text('Bağlantı Başarısız',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: Text(_error,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                color: Colors.white54, fontSize: 12)),
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        onPressed: _connect,
                        icon: const Icon(Icons.refresh, size: 16),
                        label: const Text('Tekrar Dene'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: colors.primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(AppRadius.sm)),
                        ),
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    Container(
                      height: 44,
                      color: const Color(0xFF1A1A1A),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 6),
                        child: Row(
                          children: [
                            // Sadece bu düğme seçim durumuna göre yeniden
                            // çiziliyor — önceden tüm ekranı (AppBar,
                            // xterm görünümü dahil) her seçim hareketinde
                            // setState ile yeniden kuran bir dinleyici vardı,
                            // bu da seçim sırasında gözle görülür takılmaya
                            // yol açıyordu.
                            ListenableBuilder(
                              listenable: _terminalController,
                              builder: (context, _) => _actionKey(
                                Icons.content_copy_rounded,
                                'Kopyala',
                                _copySelection,
                                active: _terminalController.selection != null,
                              ),
                            ),
                            _actionKey(Icons.select_all_rounded, 'Tümü',
                                _selectAll),
                            _actionKey(Icons.content_paste_rounded, 'Yapıştır',
                                _pasteClipboard),
                            _actionKey(Icons.bolt_rounded, 'Kısayollar',
                                _showSnippetsSheet),
                            Container(
                              height: 22,
                              width: 1,
                              margin: const EdgeInsets.symmetric(
                                  horizontal: 4, vertical: 4),
                              color: Colors.white.withValues(alpha: 0.12),
                            ),
                            _key(
                                'Ctrl+C',
                                () => _session?.stdin
                                    .add(Uint8List.fromList([3]))),
                            _key(
                                'Ctrl+D',
                                () => _session?.stdin
                                    .add(Uint8List.fromList([4]))),
                            _key(
                                'Ctrl+Z',
                                () => _session?.stdin
                                    .add(Uint8List.fromList([26]))),
                            _key(
                                'Ctrl+L',
                                () => _session?.stdin
                                    .add(Uint8List.fromList([12]))),
                            _key(
                                'Tab',
                                () => _session?.stdin
                                    .add(Uint8List.fromList([9]))),
                            _key(
                                'Esc',
                                () => _session?.stdin
                                    .add(Uint8List.fromList([27]))),
                            _key(
                                '↑',
                                () => _session?.stdin
                                    .add(Uint8List.fromList([27, 91, 65]))),
                            _key(
                                '↓',
                                () => _session?.stdin
                                    .add(Uint8List.fromList([27, 91, 66]))),
                            _key(
                                '←',
                                () => _session?.stdin
                                    .add(Uint8List.fromList([27, 91, 68]))),
                            _key(
                                '→',
                                () => _session?.stdin
                                    .add(Uint8List.fromList([27, 91, 67]))),
                            _key(
                                '|',
                                () => _session?.stdin
                                    .add(Uint8List.fromList('|'.codeUnits))),
                            _key(
                                '~',
                                () => _session?.stdin
                                    .add(Uint8List.fromList('~'.codeUnits))),
                            _key(
                                '/',
                                () => _session?.stdin
                                    .add(Uint8List.fromList('/'.codeUnits))),
                          ],
                        ),
                      ),
                    ),
                    Expanded(
                      child: TerminalView(
                        _terminal,
                        controller: _terminalController,
                        theme: const TerminalTheme(
                          cursor: Color(0xFF00FF00),
                          selection: Color(0xFF44475A),
                          foreground: Color(0xFFF8F8F2),
                          background: Color(0xFF0D0D0D),
                          black: Color(0xFF000000),
                          white: Color(0xFFBFBFBF),
                          red: Color(0xFFFF5555),
                          green: Color(0xFF50FA7B),
                          yellow: Color(0xFFF1FA8C),
                          blue: Color(0xFFBD93F9),
                          magenta: Color(0xFFFF79C6),
                          cyan: Color(0xFF8BE9FD),
                          brightBlack: Color(0xFF4D4D4D),
                          brightRed: Color(0xFFFF6E6E),
                          brightGreen: Color(0xFF69FF94),
                          brightYellow: Color(0xFFFFFFA5),
                          brightBlue: Color(0xFFD6ACFF),
                          brightMagenta: Color(0xFFFF92DF),
                          brightCyan: Color(0xFFA4FFFF),
                          brightWhite: Color(0xFFFFFFFF),
                          searchHitBackground: Color(0xFFFFB86C),
                          searchHitBackgroundCurrent: Color(0xFFFF5555),
                          searchHitForeground: Color(0xFF282A36),
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
}

class _SshServerSheet extends StatefulWidget {
  final SshServer? existing;
  final Function(SshServer) onSave;
  const _SshServerSheet({this.existing, required this.onSave});

  @override
  State<_SshServerSheet> createState() => _SshServerSheetState();
}

class _SshServerSheetState extends State<_SshServerSheet> {
  late TextEditingController _nameCtrl;
  late TextEditingController _hostCtrl;
  late TextEditingController _portCtrl;
  late TextEditingController _userCtrl;
  late TextEditingController _passCtrl;
  late TextEditingController _descCtrl;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _nameCtrl = TextEditingController(text: e?.name ?? '');
    _hostCtrl = TextEditingController(text: e?.host ?? '');
    _portCtrl = TextEditingController(text: '${e?.port ?? 22}');
    _userCtrl = TextEditingController(text: e?.username ?? 'root');
    _passCtrl = TextEditingController(text: e?.password ?? '');
    _descCtrl = TextEditingController(text: e?.description ?? '');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _hostCtrl.dispose();
    _portCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  void _save() {
    final colors = context.appColors;
    if (_nameCtrl.text.trim().isEmpty ||
        _hostCtrl.text.trim().isEmpty ||
        _userCtrl.text.trim().isEmpty ||
        _passCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: const Text('Lütfen zorunlu alanları doldurun'),
            backgroundColor: colors.error),
      );
      return;
    }
    widget.onSave(SshServer(
      name: _nameCtrl.text.trim(),
      host: _hostCtrl.text.trim(),
      port: int.tryParse(_portCtrl.text.trim()) ?? 22,
      username: _userCtrl.text.trim(),
      password: _passCtrl.text.trim(),
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
                        borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 20),
            Text(
              widget.existing == null
                  ? 'SSH Sunucusu Ekle'
                  : 'Sunucuyu Düzenle',
              style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              'Bu bilgiler Terminal ve Wake on LAN SSH relay için kullanılır',
              style: TextStyle(color: colors.textMuted, fontSize: 11),
            ),
            const SizedBox(height: 20),
            _field(context, 'Sunucu Adı *', _nameCtrl, 'Örn: Proxmox Ana',
                icon: Icons.label_outline),
            _field(
                context, 'Host / IP *', _hostCtrl, '192.168.1.10 veya hostname',
                icon: Icons.dns_outlined),
            _field(context, 'Port', _portCtrl, '22',
                icon: Icons.electrical_services_outlined,
                keyboard: TextInputType.number),
            _field(context, 'Kullanıcı Adı *', _userCtrl, 'root',
                icon: Icons.person_outline),
            _field(context, 'Şifre *', _passCtrl, '••••••••',
                icon: Icons.lock_outline, obscure: true),
            _field(context, 'Açıklama', _descCtrl, 'Opsiyonel not',
                icon: Icons.notes),
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colors.surface2,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: colors.hairline),
              ),
              child: Row(
                children: [
                  Icon(Icons.power_settings_new,
                      color: colors.textMuted, size: 14),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Wake on LAN SSH relay özelliği bu sunucu bilgilerini kullanır.\nProxmox node\'larının SSH bilgilerini buraya ekleyin.',
                      style: TextStyle(
                          color: colors.textSecondary,
                          fontSize: 11,
                          height: 1.5),
                    ),
                  ),
                ],
              ),
            ),
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

  Widget _field(BuildContext context, String label, TextEditingController ctrl,
      String hint,
      {IconData? icon,
      bool obscure = false,
      TextInputType keyboard = TextInputType.text}) {
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
}

// ─────────────────────────────────────────────
// Komut Kısayolları Sheet (Termius "snippets"inden esinlenildi)
// ─────────────────────────────────────────────

class _SnippetsSheet extends StatefulWidget {
  final List<TerminalSnippet> snippets;
  final void Function(String command) onRun;
  final void Function(List<TerminalSnippet>) onChanged;

  const _SnippetsSheet({
    required this.snippets,
    required this.onRun,
    required this.onChanged,
  });

  @override
  State<_SnippetsSheet> createState() => _SnippetsSheetState();
}

class _SnippetsSheetState extends State<_SnippetsSheet> {
  late List<TerminalSnippet> _snippets;

  @override
  void initState() {
    super.initState();
    _snippets = List.of(widget.snippets);
  }

  void _addSnippet() {
    final labelCtrl = TextEditingController();
    final cmdCtrl = TextEditingController();
    appShowDialog<void>(
      context: context,
      builder: (dctx) {
        final colors = dctx.appColors;
        return AlertDialog(
          backgroundColor: colors.surface1,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.md)),
          title: Text('Kısayol Ekle',
              style: TextStyle(color: colors.textPrimary)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: labelCtrl,
                autofocus: true,
                style: TextStyle(color: colors.textPrimary),
                decoration: InputDecoration(
                  labelText: 'İsim',
                  hintText: 'Örn: Disk Kullanımı',
                  labelStyle: TextStyle(color: colors.textMuted),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: cmdCtrl,
                style: TextStyle(
                    color: colors.textPrimary, fontFamily: 'monospace'),
                decoration: InputDecoration(
                  labelText: 'Komut',
                  hintText: 'Örn: df -h',
                  labelStyle: TextStyle(color: colors.textMuted),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dctx),
              child:
                  Text('İptal', style: TextStyle(color: colors.textSecondary)),
            ),
            TextButton(
              onPressed: () {
                if (labelCtrl.text.trim().isEmpty ||
                    cmdCtrl.text.trim().isEmpty) {
                  return;
                }
                setState(() {
                  _snippets.add(TerminalSnippet(
                      label: labelCtrl.text.trim(),
                      command: cmdCtrl.text.trim()));
                });
                widget.onChanged(_snippets);
                Navigator.pop(dctx);
              },
              child: Text('Ekle',
                  style: TextStyle(
                      color: colors.primary, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    ).whenComplete(() {
      labelCtrl.dispose();
      cmdCtrl.dispose();
    });
  }

  void _deleteSnippet(int i) {
    setState(() => _snippets.removeAt(i));
    widget.onChanged(_snippets);
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
          20, 16, 20, MediaQuery.of(context).viewInsets.bottom + 24),
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
          const SizedBox(height: 16),
          Row(
            children: [
              Icon(Icons.bolt_rounded, color: colors.primary, size: 18),
              const SizedBox(width: 8),
              Text('Komut Kısayolları',
                  style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.bold)),
              const Spacer(),
              GestureDetector(
                onTap: _addSnippet,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                      color: colors.primary,
                      borderRadius: BorderRadius.circular(AppRadius.sm)),
                  child: const Icon(Icons.add, color: Colors.white, size: 18),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text('Sık kullandığın komutları kaydet, tek dokunuşla çalıştır.',
              style: TextStyle(color: colors.textMuted, fontSize: 11)),
          const SizedBox(height: 16),
          if (_snippets.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text('Henüz kısayol yok',
                  style: TextStyle(color: colors.textMuted, fontSize: 13),
                  textAlign: TextAlign.center),
            )
          else
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _snippets.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (ctx, i) {
                  final s = _snippets[i];
                  return Container(
                    key: ValueKey(s.label),
                    decoration: BoxDecoration(
                      color: colors.surface2,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      border: Border.all(color: colors.hairline),
                    ),
                    child: ListTile(
                      onTap: () => widget.onRun(s.command),
                      leading: Icon(Icons.chevron_right_rounded,
                          color: colors.textMuted),
                      title: Text(s.label,
                          style: TextStyle(
                              color: colors.textPrimary,
                              fontSize: 14,
                              fontWeight: FontWeight.w600)),
                      subtitle: Text(s.command,
                          style: TextStyle(
                              color: colors.textMuted,
                              fontSize: 11,
                              fontFamily: 'monospace')),
                      trailing: GestureDetector(
                        onTap: () => _deleteSnippet(i),
                        child: Icon(Icons.close_rounded,
                            color: colors.textMuted, size: 18),
                      ),
                    ),
                  );
                },
              ),
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
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: colors.surface2,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.terminal, color: colors.textSecondary, size: 32),
          ),
          const SizedBox(height: 16),
          Text('Sunucu bulunamadı',
              style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(
            'SSH sunucusu ekleyerek terminal bağlantısı kur.\nAynı bilgiler WOL SSH relay için de kullanılır.',
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
              label: const Text('Sunucu Ekle',
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
