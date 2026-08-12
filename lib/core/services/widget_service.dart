import 'dart:convert';
import 'package:home_widget/home_widget.dart';
import '../../features/proxmox/proxmox_provider.dart';
import '../../features/adguard/adguard_provider.dart';
import '../../features/ups/nut_provider.dart';
import '../../features/ups/nut_service.dart' show UpsStatus;

/// Android ana ekran widget'larını (App Widget) besler.
///
/// Widget'ların kendisi native Android tarafında (Kotlin + RemoteViews)
/// çiziliyor — Flutter tarafı sadece HomeWidgetPreferences'a bir veri
/// anlık görüntüsü yazıp native tarafın yeniden çizmesini tetikliyor.
/// Uygulama açıkken provider'lar yenilendiğinde VE arka plan servisi
/// periyodik kontrolü çalıştığında çağrılır — widget'lar için ayrı bir
/// zamanlayıcı eklenmedi, mevcut yenileme döngülerine (30sn) binildi.
class WidgetService {
  static const _proxmoxWidget = 'ProxmoxWidgetProvider';
  static const _adguardWidget = 'AdGuardWidgetProvider';
  static const _upsWidget = 'UpsWidgetProvider';
  static const _wolWidget = 'WolWidgetProvider';

  static Future<void> updateProxmox(ProxmoxProvider provider) async {
    try {
      final nodes = <Map<String, dynamic>>[];
      for (final node in provider.nodes) {
        final name = node['node'] as String? ?? '';
        if (name.isEmpty) continue;
        final status = provider.nodeStatuses[name] ?? {};
        final cpu = ((status['cpu'] ?? 0) as num) * 100;
        final memTotal = (status['memory']?['total'] ?? 1) as int;
        final memUsed = (status['memory']?['used'] ?? 0) as int;
        final mem = memTotal > 0 ? memUsed / memTotal * 100 : 0.0;
        final diskTotal = (status['rootfs']?['total'] ?? 1) as int;
        final diskUsed = (status['rootfs']?['used'] ?? 0) as int;
        final disk = diskTotal > 0 ? diskUsed / diskTotal * 100 : 0.0;
        final uptime = (status['uptime'] ?? 0) as int;
        final temp = provider.nodeTemps[name];
        nodes.add({
          'name': name,
          'online': node['status'] == 'online',
          'cpu': cpu.round(),
          'mem': mem.round(),
          'disk': disk.round(),
          'uptime': uptime,
          if (temp != null) 'temp': temp,
        });
      }
      // configured, "hiç sunucu eklenmedi" ile "sunucu ekli ama şu an
      // erişilemiyor" durumlarını widget'ın ayırt edebilmesi için — bkz.
      // ProxmoxWidgetProvider.kt'nin 3-durumlu boş mesajı (AdGuard'la aynı
      // desen).
      final data = {
        'configured': provider.isConfigured,
        'nodes': nodes,
      };
      await HomeWidget.saveWidgetData('proxmox_nodes_json', jsonEncode(data));
      await HomeWidget.saveWidgetData(
          'proxmox_updated_at', DateTime.now().millisecondsSinceEpoch);
      await HomeWidget.updateWidget(
        androidName: _proxmoxWidget,
        qualifiedAndroidName: 'com.example.mtools_v2.$_proxmoxWidget',
      );
    } catch (_) {
      // Widget güncellemesi ek/opsiyonel bir özellik — başarısız olması
      // uygulamanın ana akışını (veri çekme/bildirim) etkilemesin.
    }
  }

  static Future<void> updateAdGuard(AdGuardProvider provider) async {
    try {
      final total = (provider.stats['num_dns_queries'] ?? 0) as num;
      final blocked = (provider.stats['num_blocked_filtering'] ?? 0) as num;
      final pct = total > 0 ? (blocked / total * 100) : 0.0;
      final avgMs = ((provider.stats['avg_processing_time'] ?? 0.0) as num) * 1000;
      final topClientsRaw = (provider.stats['top_clients'] as List?) ?? [];
      final clients = topClientsRaw.length;
      final topClientNames = topClientsRaw
          .take(3)
          .map((e) => (e as Map).keys.first as String)
          .toList();
      final safeBrowsing = (provider.stats['num_replaced_safebrowsing'] ?? 0) as num;
      final parental = (provider.stats['num_replaced_parental'] ?? 0) as num;
      final data = {
        'configured': provider.isConfigured,
        'connected': provider.isConnected,
        'protected': provider.status['protection_enabled'] ?? true,
        'total': total.round(),
        'blockedPct': pct.round(),
        'avgMs': avgMs.round(),
        'clients': clients,
        'topClients': topClientNames,
        'securityBlocked': (safeBrowsing + parental).round(),
      };
      await HomeWidget.saveWidgetData('adguard_stats_json', jsonEncode(data));
      await HomeWidget.saveWidgetData(
          'adguard_updated_at', DateTime.now().millisecondsSinceEpoch);
      await HomeWidget.updateWidget(
        androidName: _adguardWidget,
        qualifiedAndroidName: 'com.example.mtools_v2.$_adguardWidget',
      );
    } catch (_) {
      // Bilinçli sessiz: ana ekran widget'ı güncellenemese bile uygulama
      // içi deneyimi etkilemez, sadece OS ana ekranındaki widget bayat kalır.
    }
  }

  static Future<void> updateUps(NutProvider provider) async {
    try {
      final units = provider.upsDataMap.entries.map((entry) {
        // Anahtar '${server.name}/$upsName' — hangi sunucuya ait olduğunu
        // çıkarıp serverConnected ile eşleştiriyoruz, böylece bağlantısı
        // kopan bir sunucunun son bilinen verisi widget'ta "bayat" olarak
        // işaretlenir (bkz. UpsWidgetProvider.kt'nin reachable alanı).
        final serverName = entry.key.split('/').first;
        final data = entry.value;
        return {
          'name': data.name,
          'reachable': provider.serverConnected[serverName] ?? true,
          'charge': data.batteryCharge.round(),
          'onBattery': data.parsedStatus == UpsStatus.onBattery,
          'runtimeLabel': data.runtimeLabel,
          'load': data.load.round(),
          'temperature': data.temperature.round(),
          'voltage': data.batteryVoltage,
          'statusLabel': data.statusLabel,
        };
      }).toList();
      final data = {
        'configured': provider.servers.isNotEmpty,
        'units': units,
      };
      await HomeWidget.saveWidgetData('ups_units_json', jsonEncode(data));
      await HomeWidget.saveWidgetData(
          'ups_updated_at', DateTime.now().millisecondsSinceEpoch);
      await HomeWidget.updateWidget(
        androidName: _upsWidget,
        qualifiedAndroidName: 'com.example.mtools_v2.$_upsWidget',
      );
    } catch (_) {
      // Bilinçli sessiz: ana ekran widget'ı güncellenemese bile uygulama
      // içi deneyimi etkilemez, sadece OS ana ekranındaki widget bayat kalır.
    }
  }

  /// [devices], WolTarget.toJson() çıktılarının listesi — WidgetService
  /// bilinçli olarak wol_screen.dart'taki WolTarget tipine bağımlı değil,
  /// diğer update* metotlarıyla aynı seviyede kalması için düz Map alıyor.
  static Future<void> updateWol(List<Map<String, dynamic>> devices) async {
    try {
      await HomeWidget.saveWidgetData('wol_devices_json', jsonEncode(devices));
      await HomeWidget.saveWidgetData(
          'wol_devices_updated_at', DateTime.now().millisecondsSinceEpoch);
      await HomeWidget.updateWidget(
        androidName: _wolWidget,
        qualifiedAndroidName: 'com.example.mtools_v2.$_wolWidget',
      );
    } catch (_) {
      // Bilinçli sessiz: ana ekran widget'ı güncellenemese bile uygulama
      // içi deneyimi etkilemez, sadece OS ana ekranındaki widget bayat kalır.
    }
  }
}
