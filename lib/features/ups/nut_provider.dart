import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:home_widget/home_widget.dart';
import 'nut_service.dart';
import '../../core/services/cloud_sync_service.dart';
import '../../core/services/widget_service.dart';
import '../../core/utils/credential_sync.dart';

// NutServer modeli nut_service.dart içinde tanımlı — burada tekrar tanımlanmıyor.

class NutProvider extends ChangeNotifier {
  // Her sunucu için ayrı service instance — config değişince yeniden oluşturulur
  final Map<String, NutService> _services = {};
  Timer? _timer;

  List<NutServer> servers = [];
  Map<String, UpsData> upsDataMap = {};
  Map<String, bool> serverConnected = {};
  Map<String, String> serverErrors = {}; // her sunucunun hatası ayrı tutulur
  bool isLoading = false;

  Future<void> init() async {
    await _loadServers();
    if (servers.isNotEmpty) {
      await refresh();
      _startTimer();
    }
  }

  String? _cachedServersRaw;

  Future<void> _loadServers() async {
    final prefs = await SharedPreferences.getInstance();
    final cloudRaw = await CloudSyncService().getSetting('nut_servers');
    final localRaw = prefs.getString('nut_servers');
    if (cloudRaw != null || (localRaw != null && localRaw.isNotEmpty)) {
      try {
        final cloudList = cloudRaw == null
            ? <Map<String, dynamic>>[]
            : (jsonDecode(cloudRaw) as List)
                .map((e) => Map<String, dynamic>.from(e))
                .toList();
        final localList = (localRaw == null || localRaw.isEmpty)
            ? <Map<String, dynamic>>[]
            : (jsonDecode(localRaw) as List)
                .map((e) => Map<String, dynamic>.from(e))
                .toList();
        final merged = mergeCloudStructureWithLocalCredentials(
          cloudList: cloudList,
          localList: localList,
          credentialFields: ['username', 'password'],
        );
        servers =
            merged.map((e) => NutServer.fromJson(e)).toList();
        final mergedRaw = jsonEncode(merged);
        // Arka plan servisi (ve widget'lar) yalnızca LOCAL SharedPreferences
        // okuyor — veri cloud'dan geldiyse bile burada yerel önbelleğe
        // yazılmazsa arka planda sunucu listesi kalıcı olarak boş görünür.
        _cachedServersRaw = mergedRaw;
        await prefs.setString('nut_servers', mergedRaw);
        // shared_preferences, arka plan servisinin ayrı FlutterEngine'i ile
        // güvenilmez kaldı (bkz. ProxmoxProvider'daki not) — home_widget'ın
        // depolama mekanizması üzerinden de yazılıyor.
        await HomeWidget.saveWidgetData('bg_nut_servers', mergedRaw);

        // Cloud'da hiç kayıt yoksa, local yapıyı sanitize edip cloud'a bas.
        if (cloudRaw == null && localList.isNotEmpty) {
          final sanitized = localList
              .map((e) => stripCredentialFields(e, ['username', 'password']))
              .toList();
          await CloudSyncService()
              .saveSetting('nut_servers', jsonEncode(sanitized));
        }
      } catch (_) {
        servers = [];
      }
    }
    notifyListeners();
  }

  Future<void> _saveServers() async {
    final prefs = await SharedPreferences.getInstance();
    final serversJson = jsonEncode(servers.map((s) => s.toJson()).toList());
    await prefs.setString('nut_servers', serversJson);
    // Kullanıcı adı/şifre cloud'a hiç yazılmaz — bkz. credential_sync.dart.
    final sanitizedJson = jsonEncode(servers
        .map((s) => stripCredentialFields(s.toJson(), ['username', 'password']))
        .toList());
    await CloudSyncService().saveSetting('nut_servers', sanitizedJson);
  }

  // Service'i her zaman güncel config ile döndür
  NutService _serviceFor(NutServer server) {
    final existing = _services[server.name];
    if (existing != null &&
        existing.host == server.host &&
        existing.port == server.port) {
      return existing;
    }
    final s = NutService();
    s.configure(
      host: server.host,
      port: server.port,
      username: server.username,
      password: server.password,
    );
    _services[server.name] = s;
    return s;
  }

  Future<void> addServer(NutServer server) async {
    servers.add(server);
    await _saveServers();
    // isLoading guard'ı bypass etmeden doğrudan refresh et
    await _refreshServer(server);
    _startTimer();
    notifyListeners();
  }

  Future<void> updateServer(int index, NutServer server) async {
    servers[index] = server;
    _services.remove(server.name);
    await _saveServers();
    await _refreshServer(server);
    notifyListeners();
  }

  Future<void> removeServer(int index) async {
    final server = servers[index];
    servers.removeAt(index);
    _services.remove(server.name);
    upsDataMap.removeWhere((k, _) => k.startsWith('${server.name}/'));
    serverConnected.remove(server.name);
    serverErrors.remove(server.name);
    await _saveServers();
    notifyListeners();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => refresh());
  }

  Future<void> refresh() async {
    if (isLoading) return;
    isLoading = true;
    notifyListeners();

    // Kendi kendini onaran yazma — bkz. _loadServers()'daki not.
    if (_cachedServersRaw != null) {
      HomeWidget.saveWidgetData('bg_nut_servers', _cachedServersRaw!);
    }

    for (final server in List.of(servers)) {
      // Kimlik bilgisi başka bir cihazda girilmiş, bu cihazda henüz yoksa
      // hiç sorgu atılmaz (bkz. credential_sync.dart).
      if (server.needsCredentials) continue;
      await _refreshServer(server);
    }

    isLoading = false;
    notifyListeners();
    WidgetService.updateUps(this);
  }

  Future<void> _refreshServer(NutServer server) async {
    final service = _serviceFor(server);

    try {
      // UPS adları bilinmiyorsa otomatik keşfet
      if (server.upsNames.isEmpty) {
        final discovered = await service.listUps();
        // Sunucu nesnesini mutate etmek yerine listeyi güncelle ve kaydet
        servers = servers.map((s) {
          if (s.name == server.name) {
            return NutServer(
              name: s.name,
              host: s.host,
              port: s.port,
              username: s.username,
              password: s.password,
              upsNames: discovered,
            );
          }
          return s;
        }).toList();
        await _saveServers();
        // Güncel server referansını al
        final updated = servers.firstWhere((s) => s.name == server.name);
        await _fetchUpsData(service, updated);
      } else {
        await _fetchUpsData(service, server);
      }

      serverConnected[server.name] = true;
      serverErrors.remove(server.name);
    } catch (e) {
      serverConnected[server.name] = false;
      serverErrors[server.name] = e.toString();
    }

    notifyListeners();
  }

  Future<void> _fetchUpsData(NutService service, NutServer server) async {
    for (final upsName in server.upsNames) {
      final vars = await service.getUpsVars(upsName);
      if (vars.isNotEmpty) {
        upsDataMap['${server.name}/$upsName'] = UpsData(
          name: upsName,
          vars: vars,
          updatedAt: DateTime.now(),
        );
      }
    }
  }

  Future<bool> testConnection(NutServer server) async {
    final service = NutService();
    service.configure(
      host: server.host,
      port: server.port,
      username: server.username,
      password: server.password,
    );
    return service.testConnection();
  }

void reset() {
    _timer?.cancel();
    servers = [];
    upsDataMap = {};
    serverConnected = {};
    serverErrors = {};
    isLoading = false;
    _services.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
