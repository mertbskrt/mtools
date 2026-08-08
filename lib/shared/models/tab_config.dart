import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import '../../core/services/cloud_sync_service.dart';
import '../../features/dashboard/error_log_service.dart';

// ---------------------------------------------------------------------------
// Model – tamamen immutable, copyWith ile güncelleme
// ---------------------------------------------------------------------------
@immutable
class TabItem {
  const TabItem({
    required this.id,
    required this.label,
    required this.visible,
    required this.order,
  });

  final String id;
  final String label;
  final bool visible;
  final int order;

  TabItem copyWith({bool? visible, int? order}) => TabItem(
        id: id,
        label: label,
        visible: visible ?? this.visible,
        order: order ?? this.order,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'visible': visible,
        'order': order,
      };

  factory TabItem.fromJson(Map<String, dynamic> json) {
    return TabItem(
      id: json['id'] as String? ?? '',
      label: json['label'] as String? ?? '',
      visible: json['visible'] as bool? ?? true,
      order: json['order'] as int? ?? 0,
    );
  }

  static List<TabItem> defaults() => const [
        TabItem(id: 'sistem', label: 'Sistem', visible: true, order: 0),
        TabItem(id: 'proxmox', label: 'Proxmox', visible: true, order: 1),
        TabItem(id: 'adguard', label: 'AdGuard', visible: false, order: 2),
        TabItem(id: 'ups', label: 'UPS', visible: false, order: 3),
        TabItem(id: 'terminal', label: 'Terminal', visible: false, order: 4),
        TabItem(id: 'wol', label: 'WOL', visible: false, order: 5),
        TabItem(id: 'ayarlar', label: 'Ayarlar', visible: true, order: 6),
      ];
}

// ---------------------------------------------------------------------------
// Kalıcı depolama katmanı – SharedPreferences tekil instance
// ---------------------------------------------------------------------------
class _TabStorage {
  _TabStorage._();
  static final _TabStorage instance = _TabStorage._();

  static const _key = 'tab_config';
  SharedPreferences? _prefs;

  Future<SharedPreferences> get _p async =>
      _prefs ??= await SharedPreferences.getInstance();

  Future<List<TabItem>> load() async {
    try {
      final prefs = await _p;
      final raw = prefs.getString(_key);
      if (raw == null) return TabItem.defaults();

      final list = jsonDecode(raw) as List<dynamic>;
      final items = list
          .whereType<Map>()
          .map((e) => TabItem.fromJson(Map<String, dynamic>.from(e)))
          .toList()
        ..sort((a, b) => a.order.compareTo(b.order));
      return items;
    } catch (_) {
      return TabItem.defaults();
    }
  }

  Future<void> save(List<TabItem> items) async {
    final prefs = await _p;
    await prefs.setString(
      _key,
      jsonEncode(items.map((e) => e.toJson()).toList()),
    );
  }
}

// ---------------------------------------------------------------------------
// Provider – önbellekli getter'lar, minimize notifyListeners
// ---------------------------------------------------------------------------
class TabConfigProvider extends ChangeNotifier {
  List<TabItem> _tabs = const [];

  List<TabItem>? _visibleCache;
  List<TabItem> get visibleTabs =>
      _visibleCache ??= List.unmodifiable(_tabs.where((t) => t.visible));

  List<TabItem> get allTabs => _tabs;

  bool _loaded = false;
  bool get isLoaded => _loaded;

  Future<void> load() async {
    final tabs = await _TabStorage.instance.load();
    _tabs = List.unmodifiable(tabs);
    _visibleCache = null;
    _loaded = true;
    notifyListeners();

    final cloudJson = await CloudSyncService().getTabConfig();
    if (cloudJson != null) {
      try {
        final list = jsonDecode(cloudJson) as List<dynamic>;
        final cloudTabs = list
            .whereType<Map>()
            .map((e) => TabItem.fromJson(Map<String, dynamic>.from(e)))
            .toList()
          ..sort((a, b) => a.order.compareTo(b.order));
        _tabs = List.unmodifiable(cloudTabs);
        _visibleCache = null;
        await _TabStorage.instance.save(cloudTabs);
        notifyListeners();
      } catch (e) {
        // Bozuk/parse edilemeyen cloud verisi: yerel sekme durumu (yukarıda
        // zaten yüklendi) korunur, sadece cloud senkronu bu turda atlanır —
        // ama kullanıcıyı ilgilendirebilir (sekmeler cihazlar arası
        // senkronlanmıyor), bu yüzden günlüğe düşüyor.
        await ErrorLogService().load();
        await ErrorLogService().log(
          type: ErrorLogType.unknown,
          message: 'Sekme ayarları cloud senkronu başarısız',
          detail: e.toString(),
        );
      }
    }
  }

  Future<void> saveTabs(List<TabItem> tabs) async {
    _tabs = List.unmodifiable(tabs);
    _visibleCache = null;
    await _TabStorage.instance.save(tabs);
    final json = jsonEncode(tabs.map((e) => e.toJson()).toList());
    await CloudSyncService().saveTabConfig(json);
    notifyListeners();
  }

  Future<void> toggleVisibility(String id) async {
    final updated = _tabs.map((t) {
      return t.id == id ? t.copyWith(visible: !t.visible) : t;
    }).toList();
    await saveTabs(updated);
  }

  /// Çıkış yapıldığında çağrılır — tab listesini varsayılana döndürür.
  void reset() {
    _tabs = List.unmodifiable(TabItem.defaults());
    _visibleCache = null;
    _loaded = false;
    notifyListeners();
  }
}