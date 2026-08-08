import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import 'proxmox_provider.dart';
import 'proxmox_form_widgets.dart';
import '../dashboard/error_log_service.dart';

class CreateVMScreen extends StatefulWidget {
  const CreateVMScreen({super.key});

  @override
  State<CreateVMScreen> createState() => _CreateVMScreenState();
}

class _CreateVMScreenState extends State<CreateVMScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _idCtrl = TextEditingController();
  final _memCtrl = TextEditingController(text: '2048');
  final _coresCtrl = TextEditingController(text: '2');
  final _diskCtrl = TextEditingController(text: '32');

  String? _selectedNode;
  String? _selectedStorage;
  String? _selectedISO;
  String _osType = 'l26';
  bool _isLoading = false;
  List<dynamic> _storages = [];
  List<dynamic> _isos = [];

  final _osTypes = const [
    {'value': 'l26', 'label': 'Linux', 'icon': Icons.terminal},
    {'value': 'win11', 'label': 'Windows 11', 'icon': Icons.window},
    {'value': 'win10', 'label': 'Windows 10', 'icon': Icons.window},
    {'value': 'other', 'label': 'Diğer', 'icon': Icons.devices_other},
  ];

  @override
  void initState() {
    super.initState();
    Future.microtask(_loadData);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _idCtrl.dispose();
    _memCtrl.dispose();
    _coresCtrl.dispose();
    _diskCtrl.dispose();
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
    });
    try {
      final isos = await provider.getISOList(node);
      if (!mounted) return;
      setState(() {
        _isos = isos;
        if (_isos.isNotEmpty) _selectedISO = _isos.first['volid'];
      });
    } catch (e) {
      debugPrint('ISO yüklenemedi: $e');
      await ErrorLogService().load();
      await ErrorLogService().log(
        type: ErrorLogType.unknown,
        message: 'ISO listesi alınamadı',
        detail: e.toString(),
      );
    }
  }

  Future<void> _create() async {
    final colors = context.appColors;
    if (!_formKey.currentState!.validate()) return;
    if (_selectedNode == null) return;

    setState(() => _isLoading = true);
    try {
      final provider = context.read<ProxmoxProvider>();
      await provider.createVM(
        node: _selectedNode!,
        vmid: int.parse(_idCtrl.text),
        name: _nameCtrl.text,
        memory: int.parse(_memCtrl.text),
        cores: int.parse(_coresCtrl.text),
        disk: int.parse(_diskCtrl.text),
        storage: _selectedStorage ?? 'local',
        iso: _selectedISO ?? '',
        osType: _osType,
      );
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('Sanal makine oluşturuluyor...'),
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
        title: Text('Yeni Sanal Makine',
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
            ProxmoxFormSectionHeader(
                colors: colors,
                title: 'Genel Bilgiler',
                icon: Icons.info_outline),
            Row(children: [
              Expanded(
                flex: 2,
                child: ProxmoxFormField(
                    colors: colors,
                    label: 'VM Adı',
                    ctrl: _nameCtrl,
                    hint: 'my-vm',
                    icon: Icons.label_outline),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ProxmoxFormField(
                    colors: colors,
                    label: 'VM ID',
                    ctrl: _idCtrl,
                    hint: '100',
                    icon: Icons.tag,
                    type: TextInputType.number),
              ),
            ]),
            const SizedBox(height: 20),
            ProxmoxFormSectionHeader(
                colors: colors,
                title: 'İşletim Sistemi',
                icon: Icons.computer_outlined),
            _OsTypeSelector(
              colors: colors,
              osTypes: _osTypes,
              selected: _osType,
              onSelect: (v) => setState(() => _osType = v),
            ),
            const SizedBox(height: 12),
            if (_isos.isNotEmpty)
              ProxmoxDropdownField(
                colors: colors,
                label: 'ISO Görüntüsü',
                icon: Icons.album_outlined,
                value: _selectedISO,
                items: _isos.map((iso) {
                  final volid = iso['volid'] as String;
                  return DropdownMenuItem<String>(
                    value: volid,
                    child: Text(volid.split('/').last,
                        overflow: TextOverflow.ellipsis),
                  );
                }).toList(),
                onChanged: (v) => setState(() => _selectedISO = v),
              )
            else
              ProxmoxInfoBox(
                colors: colors,
                icon: Icons.warning_amber_outlined,
                color: colors.warning,
                text: 'ISO bulunamadı. Önce Proxmox\'a bir ISO yükleyin.',
              ),
            const SizedBox(height: 20),
            ProxmoxFormSectionHeader(
                colors: colors,
                title: 'Kaynaklar',
                icon: Icons.memory_outlined),
            Row(children: [
              Expanded(
                child: ProxmoxFormField(
                    colors: colors,
                    label: 'CPU Çekirdek',
                    ctrl: _coresCtrl,
                    hint: '2',
                    icon: Icons.memory,
                    type: TextInputType.number),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ProxmoxFormField(
                    colors: colors,
                    label: 'RAM (MB)',
                    ctrl: _memCtrl,
                    hint: '2048',
                    icon: Icons.developer_board,
                    type: TextInputType.number),
              ),
            ]),
            ProxmoxFormField(
                colors: colors,
                label: 'Disk (GB)',
                ctrl: _diskCtrl,
                hint: '32',
                icon: Icons.storage,
                type: TextInputType.number),
            const SizedBox(height: 20),
            ProxmoxFormSectionHeader(
                colors: colors,
                title: 'Depolama',
                icon: Icons.storage_outlined),
            if (_storages.isNotEmpty)
              ProxmoxDropdownField(
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
            else
              ProxmoxInfoBox(
                colors: colors,
                icon: Icons.warning_amber_outlined,
                color: colors.warning,
                text: 'Aktif storage bulunamadı.',
              ),
            const SizedBox(height: 32),
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
                    : const Text('Sanal Makine Oluştur',
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

class _OsTypeSelector extends StatelessWidget {
  final AppThemeData colors;
  final List<Map<String, dynamic>> osTypes;
  final String selected;
  final Function(String) onSelect;

  const _OsTypeSelector({
    required this.colors,
    required this.osTypes,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: osTypes.map((os) {
        final value = os['value'] as String;
        final label = os['label'] as String;
        final icon = os['icon'] as IconData;
        final isSelected = selected == value;
        return GestureDetector(
          onTap: () => onSelect(value),
          child: AnimatedContainer(
            duration: AppMotion.fast,
            curve: AppMotion.curve,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: isSelected
                  ? colors.primary.withValues(alpha: 0.12)
                  : colors.bgCard,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(
                color: isSelected
                    ? colors.primary.withValues(alpha: 0.5)
                    : Colors.white.withValues(alpha: 0.06),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon,
                    color: isSelected ? colors.primary : colors.textMuted,
                    size: 15),
                const SizedBox(width: 6),
                Text(label,
                    style: TextStyle(
                        color:
                            isSelected ? colors.primary : colors.textSecondary,
                        fontSize: 12,
                        fontWeight:
                            isSelected ? FontWeight.w600 : FontWeight.normal)),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}
