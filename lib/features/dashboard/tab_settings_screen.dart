import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/models/tab_config.dart';
import 'package:provider/provider.dart';

class TabSettingsScreen extends StatefulWidget {
  const TabSettingsScreen({super.key});

  @override
  State<TabSettingsScreen> createState() => _TabSettingsScreenState();
}

class _TabSettingsScreenState extends State<TabSettingsScreen> {
  List<TabItem> _tabs = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final tabs = context.read<TabConfigProvider>().allTabs;
    setState(() => _tabs = List.from(tabs));
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Scaffold(
      backgroundColor: colors.surface0,
      appBar: AppBar(
        title: const Text('Sekme Yönetimi'),
        actions: [
          TextButton(
            onPressed: () async {
              // ✅ DÜZELTME: mutation yerine copyWith ile yeni liste üret
              final updated = _tabs
                  .asMap()
                  .entries
                  .map((e) => e.value.copyWith(order: e.key))
                  .toList();
              await context.read<TabConfigProvider>().saveTabs(updated);
              if (context.mounted) Navigator.pop(context);
            },
            child: Text(
              'Kaydet',
              style: TextStyle(
                color: colors.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colors.surface2,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: colors.hairline),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: colors.textMuted, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Sistem ve Ayarlar sekmeleri kaldırılamaz. '
                      'Sıralamak için basılı tutup sürükleyin.',
                      style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: ReorderableListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _tabs.length,
              onReorder: (oldIndex, newIndex) {
                setState(() {
                  if (newIndex > oldIndex) newIndex--;
                  final item = _tabs.removeAt(oldIndex);
                  _tabs.insert(newIndex, item);
                  // ✅ DÜZELTME: order setter yerine copyWith
                  for (int i = 0; i < _tabs.length; i++) {
                    _tabs[i] = _tabs[i].copyWith(order: i);
                  }
                });
              },
              itemBuilder: (context, i) {
                final tab = _tabs[i];
                final isLocked = tab.id == 'sistem' || tab.id == 'ayarlar';

                return Container(
                  key: ValueKey(tab.id),
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: colors.surface1,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    border: Border.all(color: colors.hairline),
                  ),
                  child: ListTile(
                    leading: Icon(
                      _getIcon(tab.id),
                      color: tab.visible ? colors.primary : colors.textMuted,
                    ),
                    title: Text(
                      tab.label,
                      style: TextStyle(
                        color:
                            tab.visible ? colors.textPrimary : colors.textMuted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: isLocked
                        ? Text(
                            'Zorunlu sekme',
                            style: TextStyle(
                              color: colors.textMuted,
                              fontSize: 11,
                            ),
                          )
                        : null,
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Switch(
                          value: tab.visible,
                          activeThumbColor: colors.primary,
                          onChanged: isLocked
                              ? null
                              : (v) {
                                  // ✅ DÜZELTME: tab.visible = v yerine copyWith
                                  setState(() {
                                    _tabs[i] = _tabs[i].copyWith(visible: v);
                                  });
                                },
                        ),
                        const SizedBox(width: 4),
                        Icon(Icons.drag_handle, color: colors.textMuted),
                      ],
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

  IconData _getIcon(String id) {
    switch (id) {
      case 'sistem':
        return Icons.dashboard_rounded;
      case 'proxmox':
        return Icons.storage_rounded;
      case 'adguard':
        return Icons.shield_rounded;
      case 'ups':
        return Icons.battery_charging_full_rounded;
      case 'terminal':
        return Icons.terminal_rounded;
      case 'wol':
        return Icons.power_settings_new_rounded;
      case 'ayarlar':
        return Icons.settings_rounded;
      default:
        return Icons.widgets;
    }
  }
}
