import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import 'proxmox_provider.dart';
import 'proxmox_form_widgets.dart';
import '../dashboard/error_log_service.dart';

class CreateContainerScreen extends StatefulWidget {
  const CreateContainerScreen({super.key});

  @override
  State<CreateContainerScreen> createState() => _CreateContainerScreenState();
}

class _CreateContainerScreenState extends State<CreateContainerScreen> {
  final _formKey = GlobalKey<FormState>();
  final _hostnameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _idCtrl = TextEditingController();
  final _memCtrl = TextEditingController(text: '512');
  final _swapCtrl = TextEditingController(text: '512');
  final _diskCtrl = TextEditingController(text: '8');
  final _cpuCtrl = TextEditingController(text: '1');
  final _ipCtrl = TextEditingController();
  final _gwCtrl = TextEditingController();

  String? _selectedNode;
  String? _selectedTemplate;
  String? _selectedStorage;
  String _networkType = 'dhcp';
  bool _isLoading = false;
  bool _onBoot = true;
  bool _unprivileged = true;

  List<dynamic> _templates = [];
  List<dynamic> _storages = [];

  @override
  void initState() {
    super.initState();
    Future.microtask(_loadData);
  }

  @override
  void dispose() {
    _hostnameCtrl.dispose();
    _passwordCtrl.dispose();
    _idCtrl.dispose();
    _memCtrl.dispose();
    _swapCtrl.dispose();
    _diskCtrl.dispose();
    _cpuCtrl.dispose();
    _ipCtrl.dispose();
    _gwCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final provider = context.read<ProxmoxProvider>();
    if (provider.nodes.isEmpty) return;
    setState(() => _selectedNode = provider.nodes.first['node']);
    await _loadNodeData(_selectedNode!);
  }

  Future<void> _loadNodeData(String node) async {
    final provider = context.read<ProxmoxProvider>();
    setState(() {
      _storages = (provider.nodeStorages[node] ?? [])
          .where((s) => s['active'] == 1)
          .toList();
      if (_storages.isNotEmpty) _selectedStorage = _storages.first['storage'];
      _templates = [];
      _selectedTemplate = null;
    });
    try {
      final templates = await provider.getTemplateList(node);
      if (!mounted) return;
      setState(() {
        _templates = templates;
        if (_templates.isNotEmpty) {
          _selectedTemplate = _templates.first['volid'];
        }
      });
    } catch (e) {
      debugPrint('Template yüklenemedi: $e');
      await ErrorLogService().load();
      await ErrorLogService().log(
        type: ErrorLogType.unknown,
        message: 'Konteyner şablonları alınamadı',
        detail: e.toString(),
      );
    }
  }

  Future<void> _create() async {
    final colors = context.appColors;
    if (!_formKey.currentState!.validate()) return;
    if (_selectedNode == null || _selectedTemplate == null) return;

    setState(() => _isLoading = true);
    try {
      final provider = context.read<ProxmoxProvider>();
      await provider.createContainer(
        node: _selectedNode!,
        vmid: int.parse(_idCtrl.text),
        hostname: _hostnameCtrl.text,
        password: _passwordCtrl.text,
        template: _selectedTemplate!,
        storage: _selectedStorage ?? 'local',
        memory: int.parse(_memCtrl.text),
        swap: int.parse(_swapCtrl.text),
        disk: int.parse(_diskCtrl.text),
        cores: int.parse(_cpuCtrl.text),
        ip: _networkType == 'static' ? '${_ipCtrl.text}/24' : 'dhcp',
        gw: _networkType == 'static' ? _gwCtrl.text : '',
        onBoot: _onBoot,
        unprivileged: _unprivileged,
      );
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('Konteyner oluşturuluyor...'),
          backgroundColor: colors.success,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Hata: $e'),
          backgroundColor: colors.error,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
        ));
      }
    }
    if (mounted) setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final provider = context.watch<ProxmoxProvider>();

    return Scaffold(
      backgroundColor: colors.bgDark,
      appBar: AppBar(
        backgroundColor: colors.bgDark,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new,
              color: colors.textPrimary, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Yeni Konteyner',
            style: TextStyle(
                color: colors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.bold)),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
          children: [
            // ── Node ────────────────────────────────────────────────────────
            ProxmoxFormSectionHeader(
                colors: colors, title: 'Node', icon: Icons.dns_outlined),
            ProxmoxNodeSelector(
              colors: colors,
              nodes: provider.nodes,
              selected: _selectedNode,
              onSelect: (v) {
                setState(() => _selectedNode = v);
                if (v != null) _loadNodeData(v);
              },
            ),
            const SizedBox(height: 20),

            // ── Genel ────────────────────────────────────────────────────────
            ProxmoxFormSectionHeader(
                colors: colors,
                title: 'Genel Bilgiler',
                icon: Icons.info_outline),
            Row(children: [
              Expanded(
                flex: 2,
                child: ProxmoxFormField(
                    colors: colors,
                    label: 'Hostname',
                    ctrl: _hostnameCtrl,
                    hint: 'my-container',
                    icon: Icons.computer_outlined),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ProxmoxFormField(
                    colors: colors,
                    label: 'CT ID',
                    ctrl: _idCtrl,
                    hint: '100',
                    icon: Icons.tag,
                    type: TextInputType.number),
              ),
            ]),
            ProxmoxFormField(
                colors: colors,
                label: 'Şifre',
                ctrl: _passwordCtrl,
                hint: '••••••••',
                icon: Icons.lock_outline,
                obscure: true),
            const SizedBox(height: 20),

            // ── Şablon ───────────────────────────────────────────────────────
            ProxmoxFormSectionHeader(
                colors: colors, title: 'Şablon', icon: Icons.archive_outlined),
            _templates.isEmpty
                ? ProxmoxInfoBox(
                    colors: colors,
                    icon: Icons.hourglass_empty,
                    color: colors.info,
                    text: 'Şablonlar yükleniyor...')
                : ProxmoxDropdownField(
                    colors: colors,
                    label: 'Konteyner Şablonu',
                    icon: Icons.archive_outlined,
                    value: _selectedTemplate,
                    items: _templates.map((t) {
                      final volid = t['volid'] as String;
                      return DropdownMenuItem<String>(
                        value: volid,
                        child: Text(volid.split('/').last,
                            overflow: TextOverflow.ellipsis),
                      );
                    }).toList(),
                    onChanged: (v) => setState(() => _selectedTemplate = v),
                  ),
            const SizedBox(height: 20),

            // ── Kaynaklar ────────────────────────────────────────────────────
            ProxmoxFormSectionHeader(
                colors: colors,
                title: 'Kaynaklar',
                icon: Icons.memory_outlined),
            Row(children: [
              Expanded(
                child: ProxmoxFormField(
                    colors: colors,
                    label: 'CPU Çekirdek',
                    ctrl: _cpuCtrl,
                    hint: '1',
                    icon: Icons.memory,
                    type: TextInputType.number),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ProxmoxFormField(
                    colors: colors,
                    label: 'RAM (MB)',
                    ctrl: _memCtrl,
                    hint: '512',
                    icon: Icons.developer_board,
                    type: TextInputType.number),
              ),
            ]),
            Row(children: [
              Expanded(
                child: ProxmoxFormField(
                    colors: colors,
                    label: 'Swap (MB)',
                    ctrl: _swapCtrl,
                    hint: '512',
                    icon: Icons.swap_horiz,
                    type: TextInputType.number),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ProxmoxFormField(
                    colors: colors,
                    label: 'Disk (GB)',
                    ctrl: _diskCtrl,
                    hint: '8',
                    icon: Icons.storage,
                    type: TextInputType.number),
              ),
            ]),
            const SizedBox(height: 20),

            // ── Depolama ─────────────────────────────────────────────────────
            ProxmoxFormSectionHeader(
                colors: colors,
                title: 'Depolama',
                icon: Icons.storage_outlined),
            _storages.isNotEmpty
                ? ProxmoxDropdownField(
                    colors: colors,
                    label: 'Storage',
                    icon: Icons.storage,
                    value: _selectedStorage,
                    items: _storages
                        .map((s) => DropdownMenuItem<String>(
                              value: s['storage'] as String,
                              child: Text(s['storage'] as String),
                            ))
                        .toList(),
                    onChanged: (v) => setState(() => _selectedStorage = v),
                  )
                : ProxmoxInfoBox(
                    colors: colors,
                    icon: Icons.warning_amber_outlined,
                    color: colors.warning,
                    text: 'Aktif storage bulunamadı.'),
            const SizedBox(height: 20),

            // ── Ağ ───────────────────────────────────────────────────────────
            ProxmoxFormSectionHeader(
                colors: colors, title: 'Ağ', icon: Icons.wifi_outlined),
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: colors.bgCard,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
              ),
              child: Row(
                children: [
                  _NetTypeBtn(
                      colors: colors,
                      label: 'DHCP',
                      icon: Icons.autorenew,
                      selected: _networkType == 'dhcp',
                      onTap: () => setState(() => _networkType = 'dhcp')),
                  _NetTypeBtn(
                      colors: colors,
                      label: 'Statik IP',
                      icon: Icons.pin_outlined,
                      selected: _networkType == 'static',
                      onTap: () => setState(() => _networkType = 'static')),
                ],
              ),
            ),
            if (_networkType == 'static') ...[
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: ProxmoxFormField(
                      colors: colors,
                      label: 'IP Adresi',
                      ctrl: _ipCtrl,
                      hint: '192.168.1.100',
                      icon: Icons.lan_outlined,
                      type: TextInputType.number),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ProxmoxFormField(
                      colors: colors,
                      label: 'Gateway',
                      ctrl: _gwCtrl,
                      hint: '192.168.1.1',
                      icon: Icons.router_outlined,
                      type: TextInputType.number),
                ),
              ]),
            ],
            const SizedBox(height: 20),

            // ── Seçenekler ───────────────────────────────────────────────────
            ProxmoxFormSectionHeader(
                colors: colors, title: 'Seçenekler', icon: Icons.tune_outlined),
            ProxmoxSwitchTile(
              colors: colors,
              title: 'Başlangıçta Başlat',
              subtitle: 'Node yeniden başladığında otomatik başlat',
              value: _onBoot,
              onChanged: (v) => setState(() => _onBoot = v),
            ),
            ProxmoxSwitchTile(
              colors: colors,
              title: 'Ayrıcalıksız Konteyner',
              subtitle: 'Güvenlik için önerilir',
              value: _unprivileged,
              onChanged: (v) => setState(() => _unprivileged = v),
            ),
            const SizedBox(height: 32),

            // ── Oluştur ──────────────────────────────────────────────────────
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _create,
                style: ElevatedButton.styleFrom(
                  backgroundColor: colors.primary,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : const Text('Konteyner Oluştur',
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
}

class _NetTypeBtn extends StatelessWidget {
  final AppThemeData colors;
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _NetTypeBtn({
    required this.colors,
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: AppMotion.fast,
          curve: AppMotion.curve,
          margin: const EdgeInsets.all(4),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected
                ? colors.primary.withValues(alpha: 0.12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected
                  ? colors.primary.withValues(alpha: 0.4)
                  : Colors.transparent,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  color: selected ? colors.primary : colors.textMuted,
                  size: 15),
              const SizedBox(width: 6),
              Text(label,
                  style: TextStyle(
                      color: selected ? colors.primary : colors.textMuted,
                      fontSize: 13,
                      fontWeight:
                          selected ? FontWeight.w600 : FontWeight.normal)),
            ],
          ),
        ),
      ),
    );
  }
}
