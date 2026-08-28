import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:home_widget/home_widget.dart';
import '../../core/constants/app_constants.dart';
import 'proxmox_service.dart';
import '../notifications/notification_provider.dart';
import 'dart:async';
import 'dart:convert';
import '../dashboard/error_log_service.dart';
import '../ups/nut_provider.dart';
import '../../core/services/cloud_sync_service.dart';
import '../../core/services/widget_service.dart';
import '../../core/services/node_sensor_service.dart';
import '../../core/utils/credential_sync.dart';
import '../../core/utils/deliberate_off_store.dart';

/// Bu turda erişilemeyen, kayıtlı bir Proxmox sunucusu — ister daha önce en
/// az bir node'u bilinsin ister ilk bağlantısından beri hiç başarılı olmasın.
class UnreachableProxmoxServer {
  final String name;
  final String host;
  UnreachableProxmoxServer({required this.name, required this.host});
}

class ProxmoxProvider extends ChangeNotifier {
  final List<ProxmoxService> _services = [];
  final Map<String, ProxmoxService> _nodeServiceMap = {};

  List<dynamic> nodes = [];
  List<String> _nodeOrder = [];
  Map<String, Map<String, dynamic>> nodeStatuses = {};
  Map<String, int?> nodeTemps = {};
  String? _cachedServersRaw;
  Map<String, List<dynamic>> nodeDisks = {};
  Map<String, List<dynamic>> nodeStorages = {};
  Map<String, List<dynamic>> nodeLXCs = {};
  Map<String, List<dynamic>> nodeVMs = {};
  Map<String, List<dynamic>> nodeNetworks = {};
  Map<String, List<dynamic>> nodeRRDData = {};
  Map<String, Map<String, dynamic>> nodeDiskSmarts = {};
  Map<String, Map<String, dynamic>> containerConfigs = {};
  Map<String, List<dynamic>> nodeNetstat = {};

  bool isLoading = false;
  String? error;
  bool isInitialLoad = true;
  bool isReady = false;

  /// En az bir Proxmox sunucusu kaydedilmiş mi — `nodes.isNotEmpty`'den
  /// bilinçli olarak farklı: sunucu tanımlı ama şu an tamamen erişilemez
  /// olduğunda `nodes` boş kalabilir, bu widget'ın "hiç sunucu eklenmedi"
  /// ile "sunucu ekli ama erişilemiyor" durumlarını ayırt edebilmesi için
  /// gerekiyor (bkz. WidgetService.updateProxmox).
  bool get isConfigured => _services.isNotEmpty;

  // NotificationProvider sadece UI'da history göstermek için tutuluyor
  // Bildirim üretimi artık background_service.dart'ta
  NotificationProvider? notificationProvider;
  NutProvider? nutProvider;

  bool _refreshing = false;
  Timer? _periodicTimer;
  int _consecutiveFailCount = 0;

  // ── Retry state ───────────────────────────────────────────────────────────
  int _retryCount = 0;
  Timer? _retryTimer;
  bool isOffline = false;
  String? retryStatus;

  DateTime? lastSuccessAt;

  Map<String, DeliberateOffEntry> _deliberateOffNodes = {};
  Map<String, DeliberateOffEntry> _deliberateOffContainers = {};

  bool isDeliberateOff(String node) =>
      isDeliberateOffActive(_deliberateOffNodes[node]);
  DateTime? deliberateOffAt(String node) => _deliberateOffNodes[node]?.at;

  // ── "Yanlış ağdasın" ayrımı için son başarısız host ────────────────────────
  // Bağlantı hatasının internet'in yokluğundan mı yoksa hedef adresin türünden
  // mi (iç ağ/Tailscale/dış) kaynaklandığını ayırt edebilmek için hangi
  // sunucunun en son hata verdiği tutulur — yeni bir bağlantı-izleme sistemi
  // değil, sadece son hatanın kaynağı.
  String? lastFailedHost;

  /// Bu turda hata veren, önceden en az bir node'u bilinen node adları —
  /// sunucu/node listeden düşmüyor, sadece "erişilemiyor" olarak işaretleniyor.
  /// nodeStatuses/nodeDisks/... bu adlar için kasıtlı olarak BOŞ bırakılıyor,
  /// eski veri taze gibi gösterilmesin diye.
  Set<String> unreachableNodeNames = {};

  /// Bu turda hata veren TÜM kayıtlı sunucular (node geçmişi olsun olmasın).
  List<UnreachableProxmoxServer> unreachableServers = [];

  /// Cloud'dan yapı bilgisiyle (host/port) gelmiş ama token'ı bu cihazda
  /// hiç girilmemiş sunucular — bunlara hiç sorgu atılmaz (bkz.
  /// credential_sync.dart). "Erişilemiyor"dan ayrı: bağlantı hiç denenmedi.
  List<UnreachableProxmoxServer> credentialMissingServers = [];

  /// [name]'e sahip node'un bağlı olduğu servisin ham host'u — "erişilemiyor"
  /// kartında classifyHost() ile açıklama üretmek için.
  String? hostForNode(String name) => _nodeServiceMap[name]?.rawHost;

  static const List<int> _retryIntervals = [5, 15, 30, 60, 300];

  // ── Operasyon durumu ──────────────────────────────────────────────────────
  bool isOperationInProgress = false;
  String operationMessage = '';
  String operationSubMessage = '';
  double operationProgress = 0.0;
  bool operationSuccess = false;
  bool operationIsError = false;

  void _setOperation({
    required bool inProgress,
    String message = '',
    String subMessage = '',
    double progress = 0.0,
    bool success = false,
    bool isError = false,
  }) {
    isOperationInProgress = inProgress;
    operationMessage = message;
    operationSubMessage = subMessage;
    operationProgress = progress;
    operationSuccess = success;
    operationIsError = isError;
    notifyListeners();
  }

  /// Bir işlem (start/stop/reboot/delete...) başarısız olduğunda çağrılır.
  /// Önceden hata durumunda overlay sessizce kapanıyordu; artık kullanıcıya
  /// kısa süreliğine hatayı gösterip öyle kapanıyor.
  Future<void> _setOperationFailed(Object error) async {
    final detail =
        error is ProxmoxApiException ? error.message : error.toString();
    _setOperation(
      inProgress: true,
      message: 'İşlem Başarısız',
      subMessage: detail.length > 160 ? '${detail.substring(0, 160)}…' : detail,
      progress: 1.0,
      isError: true,
    );
    await Future.delayed(const Duration(milliseconds: 2600));
  }

  void reset() {
    _periodicTimer?.cancel();
    _retryTimer?.cancel();
    _services.clear();
    _nodeServiceMap.clear();
    nodes = [];
    nodeStatuses.clear();
    nodeDisks.clear();
    nodeStorages.clear();
    nodeLXCs.clear();
    nodeVMs.clear();
    nodeNetworks.clear();
    nodeRRDData.clear();
    nodeDiskSmarts.clear();
    nodeNetstat.clear();
    isLoading = false;
    isInitialLoad = true;
    isReady = false;
    isOffline = false;
    error = null;
    retryStatus = null;
    _retryCount = 0;
    _consecutiveFailCount = 0;
    notifyListeners();
  }

  // ── Init ──────────────────────────────────────────────────────────────────

  Future<void> init() async {
    _periodicTimer?.cancel();
    _retryTimer?.cancel();
    isReady = false;
    isInitialLoad = true;
    isLoading = false;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    _deliberateOffNodes = decodeDeliberateOffMap(prefs.getString('deliberate_off_nodes'));
    _deliberateOffContainers = decodeDeliberateOffMap(prefs.getString('deliberate_off_containers'));
    _services.clear();
    _nodeServiceMap.clear();
    credentialMissingServers = [];
    nodes = [];
    nodeStatuses.clear();
    nodeDisks.clear();
    nodeStorages.clear();
    nodeLXCs.clear();
    nodeVMs.clear();
    nodeNetworks.clear();
    nodeRRDData.clear();
    nodeDiskSmarts.clear();
    notifyListeners();

    final cloudService = CloudSyncService();

    // Cloud (yapı, kimlik bilgisiz) ve local (tam) ayrı okunup birleştirilir
    // — bkz. credential_sync.dart. Cloud her zaman önceliklendirilip local'in
    // üzerine yazılırsa, token gibi hassas alanlar cloud'dan çıkarıldığında
    // bu cihazdaki tokenlar da silinmiş olurdu.
    final cloudRaw = await cloudService.getProxmoxServers();
    final localRaw = prefs.getString('proxmox_servers');
    String? serversRaw;
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
      serversRaw = jsonEncode(merged);

      // Cloud'da hiç kayıt yoksa, local yapıyı SANİTİZE EDİLMİŞ olarak
      // cloud'a bas (self-heal) — token asla cloud'a yazılmaz.
      if (cloudRaw == null && localList.isNotEmpty) {
        final sanitized = localList
            .map((e) => stripCredentialFields(e, ['tokenId', 'tokenSecret']))
            .toList();
        await cloudService.saveProxmoxServers(jsonEncode(sanitized));
      }
    }

    // Background service için SharedPreferences'a yaz (tam veri — arka plan
    // servisi gerçek sunuculara bağlanabilmeli).
    // NOT: Flutter SharedPreferences otomatik 'flutter.' prefix ekler
    // bu yüzden 'proxmox_servers' key'i diskte 'flutter.proxmox_servers' olur
    if (serversRaw != null) {
      await prefs.setString('proxmox_servers', serversRaw);
      // shared_preferences, arka plan servisinin AYRI FlutterEngine'i ile ana
      // uygulama arasında güvenilmez kaldı (aynı process olmasına rağmen
      // yazılan veri diğer taraftan hep boş görünüyordu) — bu yüzden arka
      // plan servisinin okuduğu kopya artık home_widget'ın kendi depolama
      // mekanizması üzerinden yazılıyor; o, tüm oturum boyunca güvenilir
      // çalıştığı kanıtlanmış tek kanal.
      await HomeWidget.saveWidgetData('bg_proxmox_servers', serversRaw);
    }
    // refresh() döngüsünde tekrar tekrar yazılabilmesi için saklanıyor —
    // init() sırasında bu yazma bir sebeple (ör. cloud'un henüz hazır
    // olmaması) başarısız olursa, arka plan servisi kalıcı olarak boş
    // sunucu listesi görmeye devam etmesin diye kendi kendini onarıyor.
    _cachedServersRaw = serversRaw;

    if (serversRaw != null) {
      final List list = jsonDecode(serversRaw);
      if (list.isEmpty) {
        isReady = true;
        notifyListeners();
        return;
      }
      for (final server in list) {
        final host = server['address'] ?? '';
        final port = (server['port'] ?? '8006').toString();
        final tokenId = server['tokenId'] ?? '';
        final tokenSecret = server['tokenSecret'] ?? '';
        final name = server['name'] ?? '';
        if (host.isEmpty) continue;
        if (tokenId.isEmpty || tokenSecret.isEmpty) {
          // Proxmox API her zaman bir token gerektirir — "bilinçli boş"
          // ihtimali yok, bu her zaman kimlik bilgisi eksik demektir.
          // Hiç sorgu atılmaz.
          credentialMissingServers
              .add(UnreachableProxmoxServer(name: name, host: host));
          continue;
        }
        final service = ProxmoxService();
        service.configure(host, port, tokenId, tokenSecret, name: name);
        _services.add(service);
      }
    } else {
      final host = prefs.getString(AppConstants.keyProxmoxHost) ?? '';
      final port = prefs.getString(AppConstants.keyProxmoxPort) ?? '8006';
      final tokenId = prefs.getString(AppConstants.keyProxmoxTokenId) ?? '';
      final tokenSecret =
          prefs.getString(AppConstants.keyProxmoxTokenSecret) ?? '';
      if (host.isEmpty || tokenId.isEmpty) {
        isReady = true;
        notifyListeners();
        return;
      }
      final service = ProxmoxService();
      service.configure(host, port, tokenId, tokenSecret);
      _services.add(service);
    }

    if (_services.isEmpty) {
      // refresh() _services boşken hiç notifyListeners() çağırmadan erken
      // döner — sadece kimlik bilgisi eksik sunucular varsa (hepsi
      // credentialMissingServers'a düştüyse) UI burada haber almalı.
      isReady = true;
      notifyListeners();
      return;
    }

    String? orderRaw = await cloudService.getNodeOrder();
    orderRaw ??= prefs.getString('node_order');
    if (orderRaw != null) {
      _nodeOrder = List<String>.from(jsonDecode(orderRaw));
    }

    await refresh();

    await prefs.setBool('app_active', true);

    _periodicTimer?.cancel();
    _periodicTimer =
        Timer.periodic(const Duration(seconds: 30), (_) => refresh());
  }

  // ── Retry mekanizması ─────────────────────────────────────────────────────

  void _onRefreshFailed() {
    if (_services.isEmpty) return;
    isOffline = true;
    ErrorLogService().log(
      type: ErrorLogType.connection,
      message: 'Sunucuya bağlanılamadı',
      detail: error,
    );
    _retryTimer?.cancel();
    if (_retryCount >= _retryIntervals.length) {
      retryStatus = 'Bağlantı kurulamadı. Manuel yenile.';
      notifyListeners();
      return;
    }
    final seconds = _retryIntervals[_retryCount];
    _retryCount++;
    retryStatus =
        '$seconds saniye içinde tekrar deneniyor... ($_retryCount/${_retryIntervals.length})';
    notifyListeners();
    _retryTimer = Timer(Duration(seconds: seconds), () async {
      retryStatus = 'Yeniden bağlanılıyor...';
      notifyListeners();
      await refresh();
    });
  }

  void _onRefreshSuccess() {
    lastSuccessAt = DateTime.now();
    if (isOffline) {
      isOffline = false;
      _retryCount = 0;
      _retryTimer?.cancel();
      retryStatus = null;
      lastFailedHost = null;
    }
  }

  Future<void> _persistDeliberateOffMaps() async {
    final prefs = await SharedPreferences.getInstance();
    final nEncoded = encodeDeliberateOffMap(_deliberateOffNodes);
    final cEncoded = encodeDeliberateOffMap(_deliberateOffContainers);
    await prefs.setString('deliberate_off_nodes', nEncoded);
    await prefs.setString('deliberate_off_containers', cEncoded);
    await HomeWidget.saveWidgetData('bg_deliberate_off_nodes', nEncoded);
    await HomeWidget.saveWidgetData('bg_deliberate_off_containers', cEncoded);
  }

  /// Node kapatma/yeniden başlatma komutu (kesin ya da muhtemel olarak)
  /// teslim edildiğinde çağrılır. Shutdown durumunda, node üzerinde o an
  /// çalışan tüm CT/VM'ler de işaretlenir — Proxmox'un pve-guests servisi
  /// node kapanınca bunları kendi (MTools token'ı taşımayan) task'larıyla
  /// ayrı ayrı durdurur; background_service.dart bu kaydı kullanarak o
  /// kaskad bildirimlerini bastırır.
  Future<void> _markDeliberateOff(String node, {required String action}) async {
    _deliberateOffNodes[node] = DeliberateOffEntry(action, DateTime.now());
    if (action == 'shutdown') {
      for (final c in [...?nodeLXCs[node], ...?nodeVMs[node]]) {
        if (c['status'] != 'running') continue;
        final vmid = c['vmid'];
        if (vmid == null) continue;
        _deliberateOffContainers['$node::$vmid'] =
            DeliberateOffEntry('shutdown', DateTime.now());
      }
    }
    await _persistDeliberateOffMaps();
  }

  Future<void> _markContainerDeliberateOff(String node, int vmid) async {
    _deliberateOffContainers['$node::$vmid'] =
        DeliberateOffEntry('shutdown', DateTime.now());
    await _persistDeliberateOffMaps();
  }

  /// Sadece bu turda TAZE olarak `online` raporlanan node'lar için bilinçli-
  /// kapatma kaydı temizlenir. `nodes` listesindeki birleştirilmiş (bu turda
  /// hata veren servisler için eski kaydı geri ekleyen, bkz. refresh())
  /// veri kullanılmaz — aksi halde hâlâ gerçekten erişilemeyen bir node'un
  /// kaydı yanlışlıkla temizlenip alarmlar kesinti ortasında susturulabilir.
  Future<void> _clearDeliberateOffForOnlineNodes(
      Map<String, String?> freshNodeStatus) async {
    final online = freshNodeStatus.entries
        .where((e) => e.value == 'online')
        .map((e) => e.key)
        .toSet();
    final removed = online
        .where((n) => _deliberateOffNodes.remove(n) != null)
        .toSet();
    if (removed.isEmpty) return;
    _deliberateOffContainers
        .removeWhere((k, _) => removed.any((n) => k.startsWith('$n::')));
    await _persistDeliberateOffMaps();
  }

  Future<void> manualRefresh() async {
    _retryTimer?.cancel();
    _retryCount = 0;
    retryStatus = null;
    isOffline = false;
    isLoading = true;
    notifyListeners();
    await refresh();
  }

  // ── Refresh ───────────────────────────────────────────────────────────────

  Future<void> refresh() async {
    if (_services.isEmpty) return;
    if (_refreshing) return;
    _refreshing = true;
    final refreshStart = DateTime.now();

    // Kendi kendini onaran yazma — bkz. init()'teki not.
    if (_cachedServersRaw != null) {
      HomeWidget.saveWidgetData('bg_proxmox_servers', _cachedServersRaw!);
    }

    if (isInitialLoad) {
      isLoading = true;
      notifyListeners();
    }
    error = null;

    try {
      final newNodes = <dynamic>[];
      final newStatuses = <String, Map<String, dynamic>>{};
      final newDisks = <String, List<dynamic>>{};
      final newStorages = <String, List<dynamic>>{};
      final newLXCs = <String, List<dynamic>>{};
      final newVMs = <String, List<dynamic>>{};
      final newNetworks = <String, List<dynamic>>{};
      final newRRDData = <String, List<dynamic>>{};
      final newNetstat = <String, List<dynamic>>{};
      final newDiskSmarts = <String, Map<String, dynamic>>{};
      final failedThisCycle = <ProxmoxService>{};
      final freshNodeStatus = <String, String?>{};

      for (final service in _services) {
        List<dynamic> serviceNodes;
        try {
          serviceNodes = await service.getNodes();
        } catch (e) {
          debugPrint('getNodes hatası: $e');
          lastFailedHost = service.rawHost;
          failedThisCycle.add(service);
          ErrorLogService().log(
            type: ErrorLogType.node,
            message: 'Node listesi alınamadı',
            detail: e.toString(),
          );
          continue;
        }
        newNodes.addAll(serviceNodes);

        for (final node in serviceNodes) {
          final name = node['node'] as String;
          _nodeServiceMap[name] = service;
          freshNodeStatus[name] = node['status'] as String?;
        }

        // Node'lar birbirinden bağımsız olduğu için paralel sorgulanır.
        // Sıralı (sequential) sorgu, çok node'lu kurulumlarda yenileme
        // süresini node sayısıyla orantılı şekilde uzatıyordu.
        await Future.wait(serviceNodes.map((node) async {
          final name = node['node'] as String;

          try {
            final results = await Future.wait([
              service.getNodeStatus(name),
              service.getNodeDisks(name),
              service.getNodeStorage(name),
              service.getLXCs(name),
              service.getVMs(name),
              service.getNodeNetwork(name),
              service.getNodeRRDData(name),
            ]);

            newStatuses[name] = results[0] as Map<String, dynamic>;
            newDisks[name] = results[1] as List<dynamic>;
            newStorages[name] = results[2] as List<dynamic>;
            newLXCs[name] = results[3] as List<dynamic>;
            newVMs[name] = results[4] as List<dynamic>;
            newNetworks[name] = results[5] as List<dynamic>;
            newRRDData[name] = results[6] as List<dynamic>;
          } catch (e) {
            debugPrint('Node sorgu hatası ($name): $e');
            ErrorLogService().log(
              type: ErrorLogType.refresh,
              message: 'Node verisi alınamadı: $name',
              detail: e.toString(),
            );
            newStatuses[name] = nodeStatuses[name] ?? {};
            newDisks[name] = nodeDisks[name] ?? [];
            newStorages[name] = nodeStorages[name] ?? [];
            newLXCs[name] = nodeLXCs[name] ?? [];
            newVMs[name] = nodeVMs[name] ?? [];
            newNetworks[name] = nodeNetworks[name] ?? [];
            newRRDData[name] = nodeRRDData[name] ?? [];
          }

          final rrd = newRRDData[name] ?? [];
          if (rrd.isNotEmpty) {
            final last = rrd.last as Map<String, dynamic>;
            newStatuses[name]?['netin'] = last['netin'];
            newStatuses[name]?['netout'] = last['netout'];
            newStatuses[name]?['iowait'] = last['iowait'];
          }

          final disks = newDisks[name] ?? [];
          if (disks.isNotEmpty) {
            final smartFutures = disks
                .map((disk) => disk['devpath'] as String? ?? '')
                .where((devpath) => devpath.isNotEmpty)
                .map((devpath) async {
              try {
                final smartData = await service.getDiskSmart(name, devpath);
                smartData['temperature'] = _parseDiskTemp(smartData) ?? 0;
                return MapEntry(devpath, smartData);
              } catch (e) {
                // Bilinçli sessiz: tek bir diskin SMART verisi alınamaması
                // tüm yenilemeyi etkilemez — sadece o disk için sıcaklık/
                // sağlık verisi eksik kalır.
                debugPrint('SMART sorgu hatası ($devpath): $e');
                return null;
              }
            }).toList();

            final smartResults = await Future.wait(smartFutures);
            for (final entry in smartResults) {
              if (entry != null) {
                newDiskSmarts[entry.key] = entry.value;
              }
            }
          }
        }));
      }

      // Kısmi/tam hata: bu turda hata veren servislere ait, ÖNCEDEN bilinen
      // node'lar listeden düşmesin diye eski kimlikleri geri ekleniyor —
      // ama nodeStatuses/nodeDisks/... için hiçbir şey yazılmıyor (yukarıda
      // zaten hiç dokunulmadı), böylece UI eski veriyi taze gibi gösteremez.
      final newUnreachableNodeNames = <String>{};
      if (failedThisCycle.isNotEmpty) {
        final knownNodeNames = <String>{...nodes.map((n) => n['node'] as String)}
            .where((name) => !newNodes.any((n) => n['node'] == name));
        for (final name in knownNodeNames) {
          final owner = _nodeServiceMap[name];
          if (owner != null && failedThisCycle.contains(owner)) {
            final oldNode = nodes.firstWhere((n) => n['node'] == name);
            newNodes.add(oldNode);
            newUnreachableNodeNames.add(name);
          }
        }
      }
      unreachableNodeNames = newUnreachableNodeNames;
      unreachableServers = failedThisCycle
          .map((s) => UnreachableProxmoxServer(name: s.name, host: s.rawHost))
          .toList();

      await _clearDeliberateOffForOnlineNodes(freshNodeStatus);
      // Kendi kendini onaran yazma — bkz. _cachedServersRaw yorumundaki not.
      if (_deliberateOffNodes.isNotEmpty || _deliberateOffContainers.isNotEmpty) {
        HomeWidget.saveWidgetData(
            'bg_deliberate_off_nodes', encodeDeliberateOffMap(_deliberateOffNodes));
        HomeWidget.saveWidgetData('bg_deliberate_off_containers',
            encodeDeliberateOffMap(_deliberateOffContainers));
      }

      if (_nodeOrder.isNotEmpty) {
        newNodes.sort((a, b) {
          final ai = _nodeOrder.indexOf(a['node'] as String);
          final bi = _nodeOrder.indexOf(b['node'] as String);
          if (ai == -1 && bi == -1) return 0;
          if (ai == -1) return 1;
          if (bi == -1) return -1;
          return ai.compareTo(bi);
        });
      }

      if (newNodes.isNotEmpty) {
        nodes = newNodes;
        nodeStatuses = newStatuses;
        nodeDisks = newDisks;
        nodeStorages = newStorages;
        nodeLXCs = newLXCs;
        nodeVMs = newVMs;
        nodeNetworks = newNetworks;
        nodeRRDData = newRRDData;
        nodeDiskSmarts = newDiskSmarts;
        nodeNetstat = newNetstat;
      }

      _consecutiveFailCount = 0;

      final elapsed = DateTime.now().difference(refreshStart).inSeconds;
      if (elapsed > 10) {
        ErrorLogService().log(
          type: ErrorLogType.performance,
          message: 'Yavaş refresh: ${elapsed}sn sürdü',
          detail: 'Normal süre 3-5sn olmalı.',
        );
      }

      for (final name in newStatuses.keys) {
        final status = newStatuses[name]!;
        final cpu = ((status['cpu'] ?? 0) * 100).toDouble();
        if (cpu > 90) {
          ErrorLogService().log(
            type: ErrorLogType.anomaly,
            message: 'Yüksek CPU: $name → %${cpu.toStringAsFixed(0)}',
          );
        }
        final disks = newDisks[name] ?? [];
        for (final disk in disks) {
          final devpath = disk['devpath'] ?? '';
          final smart = newDiskSmarts[devpath] ?? {};
          final temp = smart['temperature'];
          if (temp != null && temp > 50) {
            ErrorLogService().log(
              type: ErrorLogType.anomaly,
              message:
                  'Yüksek disk sıcaklığı: $name → $devpath → $temp°C',
            );
          }
          final health = disk['health'] ?? '';
          if (health == 'FAILED') {
            ErrorLogService().log(
              type: ErrorLogType.anomaly,
              message: 'Disk sağlık sorunu: $name → $devpath → FAILED',
            );
          }
        }
      }

      // isOffline/ConnectionIssueView eskiden hiç tetiklenmiyordu — tek tek
      // servis hataları döngü İÇİNDE yakalanıp `continue` ediliyordu, dıştaki
      // catch'e hiç ulaşmıyordu. Artık "kayıtlı TÜM servisler bu turda hata
      // verdi mi" doğrudan kontrol ediliyor.
      final allServicesFailed =
          _services.isNotEmpty && failedThisCycle.length == _services.length;
      if (allServicesFailed) {
        error = 'Tüm Proxmox sunucularına erişilemedi';
        _onRefreshFailed();
      } else {
        _onRefreshSuccess();
      }

      // UI'daki bildirim geçmişini background service'in yazdığı veriden güncelle
      await notificationProvider?.reloadHistory();
    } catch (e) {
      error = e.toString();
      debugPrint('Refresh genel hata: $e');
      _consecutiveFailCount++;
      if (_consecutiveFailCount >= 3) {
        ErrorLogService().log(
          type: ErrorLogType.connection,
          message: 'Ardışık $_consecutiveFailCount refresh başarısız',
          detail: e.toString(),
        );
      }
      _onRefreshFailed();
    }

    isReady = true;
    isLoading = false;
    isInitialLoad = false;
    _refreshing = false;
    notifyListeners();
    WidgetService.updateProxmox(this);
    _fetchNodeTemperatures();
  }

  /// SSH üzerinden `sensors` çalıştırmak yavaş olabileceği için ana refresh
  /// döngüsünü bloklamadan, arka planda (fire-and-forget) yapılır — sonuç
  /// geldiğinde widget'lar ayrıca güncellenir.
  void _fetchNodeTemperatures() {
    for (final node in nodes) {
      final name = node['node'] as String? ?? '';
      if (name.isEmpty || node['status'] != 'online') continue;
      NodeSensorService.getTemperature(name).then((temp) {
        if (temp != null && nodeTemps[name] != temp) {
          nodeTemps[name] = temp;
          WidgetService.updateProxmox(this);
        }
      });
    }
  }

  // ── Silent refresh helpers ────────────────────────────────────────────────

  Future<Map<String, dynamic>?> _fetchAllData() async {
    if (_services.isEmpty) return null;

    final newNodes = <dynamic>[];
    final newStatuses = <String, Map<String, dynamic>>{};
    final newDisks = <String, List<dynamic>>{};
    final newStorages = <String, List<dynamic>>{};
    final newLXCs = <String, List<dynamic>>{};
    final newVMs = <String, List<dynamic>>{};
    final newNetworks = <String, List<dynamic>>{};
    final newRRDData = <String, List<dynamic>>{};
    final newDiskSmarts = <String, Map<String, dynamic>>{};
    final newNetstat = <String, List<dynamic>>{};

    for (final service in _services) {
      List<dynamic> serviceNodes;
      try {
        serviceNodes = await service.getNodes();
      } catch (e) {
        // Bilinçli sessiz: bu "sessiz yenileme" yardımcısı (bkz. bölüm
        // başlığı) sadece CT/VM işlemi sonrası durum kontrolü için — aynı
        // servisin asıl periyodik refresh() döngüsü zaten bağlantı
        // hatalarını ErrorLogService'e düşürüyor, burada tekrar loglamak
        // gürültü olur.
        debugPrint('getNodes hatası: $e');
        continue;
      }
      newNodes.addAll(serviceNodes);

      await Future.wait(serviceNodes.map((node) async {
        final name = node['node'] as String;
        try {
          final results = await Future.wait([
            service.getNodeStatus(name),
            service.getNodeDisks(name),
            service.getNodeStorage(name),
            service.getLXCs(name),
            service.getVMs(name),
            service.getNodeNetwork(name),
            service.getNodeRRDData(name),
            service.getNetstat(name),
          ]);
          newStatuses[name] = results[0] as Map<String, dynamic>;
          newDisks[name] = results[1] as List<dynamic>;
          newStorages[name] = results[2] as List<dynamic>;
          newLXCs[name] = results[3] as List<dynamic>;
          newVMs[name] = results[4] as List<dynamic>;
          newNetworks[name] = results[5] as List<dynamic>;
          newRRDData[name] = results[6] as List<dynamic>;
          newNetstat[name] = results[7] as List<dynamic>;

          final rrd = newRRDData[name] ?? [];
          if (rrd.isNotEmpty) {
            final last = rrd.last as Map<String, dynamic>;
            newStatuses[name]?['netin'] = last['netin'];
            newStatuses[name]?['netout'] = last['netout'];
            newStatuses[name]?['iowait'] = last['iowait'];
          }
        } catch (e) {
          // Bilinçli sessiz: bkz. yukarıdaki getNodes() catch'i — "sessiz
          // yenileme" yardımcısı, asıl loglama periyodik refresh()'te.
          debugPrint('Node sorgu hatası ($name): $e');
          newStatuses[name] = nodeStatuses[name] ?? {};
          newDisks[name] = nodeDisks[name] ?? [];
          newStorages[name] = nodeStorages[name] ?? [];
          newLXCs[name] = nodeLXCs[name] ?? [];
          newVMs[name] = nodeVMs[name] ?? [];
          newNetworks[name] = nodeNetworks[name] ?? [];
          newRRDData[name] = nodeRRDData[name] ?? [];
        }
      }));
    }

    if (newNodes.isEmpty) return null;

    return {
      'nodes': newNodes,
      'nodeStatuses': newStatuses,
      'nodeDisks': newDisks,
      'nodeStorages': newStorages,
      'nodeLXCs': newLXCs,
      'nodeVMs': newVMs,
      'nodeNetworks': newNetworks,
      'nodeRRDData': newRRDData,
      'nodeDiskSmarts': newDiskSmarts,
      'nodeNetstat': newNetstat,
    };
  }

  void _applyFreshData(Map<String, dynamic> data) {
    final newNodes = data['nodes'] as List<dynamic>;

    if (_nodeOrder.isNotEmpty) {
      newNodes.sort((a, b) {
        final ai = _nodeOrder.indexOf(a['node'] as String);
        final bi = _nodeOrder.indexOf(b['node'] as String);
        if (ai == -1 && bi == -1) return 0;
        if (ai == -1) return 1;
        if (bi == -1) return -1;
        return ai.compareTo(bi);
      });
    }

    nodes = newNodes;
    nodeStatuses = data['nodeStatuses'] as Map<String, Map<String, dynamic>>;
    nodeDisks = data['nodeDisks'] as Map<String, List<dynamic>>;
    nodeStorages = data['nodeStorages'] as Map<String, List<dynamic>>;
    nodeLXCs = data['nodeLXCs'] as Map<String, List<dynamic>>;
    nodeVMs = data['nodeVMs'] as Map<String, List<dynamic>>;
    nodeNetworks = data['nodeNetworks'] as Map<String, List<dynamic>>;
    nodeRRDData = data['nodeRRDData'] as Map<String, List<dynamic>>;
    nodeNetstat = data['nodeNetstat'] as Map<String, List<dynamic>>? ?? {};
    nodeDiskSmarts =
        data['nodeDiskSmarts'] as Map<String, Map<String, dynamic>>;

    _onRefreshSuccess();
    notifyListeners();
  }

  /// Hedef duruma ulaşıldığını DOĞRULARSA `true`, `maxAttempts` sonunda hâlâ
  /// doğrulanamadıysa (zaman aşımı) `false` döner — çağıran bu ayrımı honest
  /// bir "Tamamlandı!" / "Komut Gönderildi ama teyit edilemedi" mesajına
  /// çevirmeli. Önceden bu fonksiyon zaman aşımında da sessizce dönüyordu ve
  /// çağıranlar hep "Tamamlandı!" gösteriyordu — rebootNode/shutdownNode'un
  /// zaten kullandığı dürüst-belirsizlik prensibiyle tutarsızdı.
  Future<bool> _silentRefreshUntil({
    required String node,
    required int vmid,
    required String targetStatus,
    required bool isLxc,
  }) async {
    const maxAttempts = 20;
    const pollInterval = Duration(seconds: 3);

    for (int attempt = 0; attempt < maxAttempts; attempt++) {
      await Future.delayed(pollInterval);

      final progress = 0.3 + (attempt / maxAttempts) * 0.6;
      _setOperation(
        inProgress: true,
        message: operationMessage,
        subMessage: attempt == 0
            ? 'Komut gönderildi, bekleniyor...'
            : 'Durum kontrol ediliyor... (${attempt + 1}/$maxAttempts)',
        progress: progress.clamp(0.0, 0.9),
      );

      try {
        final freshData = await _fetchAllData();
        if (freshData == null) continue;

        final lxcList = freshData['nodeLXCs']?[node] as List? ?? [];
        final vmList = freshData['nodeVMs']?[node] as List? ?? [];
        final list = isLxc ? lxcList : vmList;

        final target = list.firstWhere(
          (item) => item['vmid'] == vmid,
          orElse: () => null,
        );

        final currentStatus = target?['status'] as String? ?? '';
        if (currentStatus == targetStatus) {
          _applyFreshData(freshData);
          return true;
        }
      } catch (e) {
        // Bilinçli sessiz: tek bir poll denemesinin başarısız olması normal
        // (geçici ağ gecikmesi) — döngü tekrar dener, nihai zaman aşımı
        // aşağıda zaten loglanıyor.
        debugPrint('Poll hatası (attempt $attempt): $e');
      }
    }

    ErrorLogService().log(
      type: ErrorLogType.operation,
      message: 'CT/VM işlemi zaman aşımına uğradı',
      detail: 'vmid: $vmid, node: $node, hedef: $targetStatus',
    );

    try {
      final freshData = await _fetchAllData();
      if (freshData != null) _applyFreshData(freshData);
    } catch (_) {
      // Bilinçli sessiz: zaman aşımı zaten yukarıda ErrorLogService'e
      // düştü — bu, vazgeçmeden önceki son iyi-niyet yenilemesi, o da
      // başarısız olursa raporlanacak yeni bir bilgi yok.
    }
    return false;
  }

  // ── Container / VM işlemleri ──────────────────────────────────────────────

  Future<void> startContainer(String node, int vmid,
      {bool isLxc = true}) async {
    _setOperation(
      inProgress: true,
      message:
          isLxc ? 'Konteyner Başlatılıyor' : 'Sanal Makine Başlatılıyor',
      subMessage: 'Komut gönderiliyor...',
      progress: 0.15,
    );
    try {
      await _serviceFor(node).startVM(node, vmid, isLxc: isLxc);
      _setOperation(
        inProgress: true,
        message:
            isLxc ? 'Konteyner Başlatılıyor' : 'Sanal Makine Başlatılıyor',
        subMessage: 'Başlatma komutu gönderildi...',
        progress: 0.3,
      );
      final confirmed = await _silentRefreshUntil(
          node: node, vmid: vmid, targetStatus: 'running', isLxc: isLxc);
      _setOperation(
        inProgress: true,
        message: confirmed ? 'Tamamlandı!' : 'Komut Gönderildi',
        subMessage: confirmed
            ? (isLxc ? 'Konteyner çalışıyor.' : 'Sanal makine çalışıyor.')
            : (isLxc
                ? 'Başlatma komutu gönderildi ama durum doğrulanamadı — konteyner birkaç dakika içinde çalışır duruma gelmiş olabilir.'
                : 'Başlatma komutu gönderildi ama durum doğrulanamadı — sanal makine birkaç dakika içinde çalışır duruma gelmiş olabilir.'),
        progress: 1.0,
        success: true,
      );
      await Future.delayed(Duration(milliseconds: confirmed ? 1200 : 1800));
    } catch (e) {
      // Bilinçli sessiz: hata zaten _setOperationFailed ile kullanıcıya
      // OperationOverlay üzerinde gösteriliyor — burada tekrar loglamak gürültü olur.
      debugPrint('startContainer hatası: $e');
      await _setOperationFailed(e);
    } finally {
      _setOperation(inProgress: false);
    }
  }

  Future<void> stopContainer(String node, int vmid,
      {bool isLxc = true}) async {
    _setOperation(
      inProgress: true,
      message:
          isLxc ? 'Konteyner Durduruluyor' : 'Sanal Makine Durduruluyor',
      subMessage: 'Komut gönderiliyor...',
      progress: 0.15,
    );
    try {
      await _serviceFor(node).stopVM(node, vmid, isLxc: isLxc);
      await _markContainerDeliberateOff(node, vmid);
      _setOperation(
        inProgress: true,
        message:
            isLxc ? 'Konteyner Durduruluyor' : 'Sanal Makine Durduruluyor',
        subMessage: 'Durdurma komutu gönderildi...',
        progress: 0.3,
      );
      final confirmed = await _silentRefreshUntil(
          node: node, vmid: vmid, targetStatus: 'stopped', isLxc: isLxc);
      _setOperation(
        inProgress: true,
        message: confirmed ? 'Tamamlandı!' : 'Komut Gönderildi',
        subMessage: confirmed
            ? (isLxc ? 'Konteyner durduruldu.' : 'Sanal makine durduruldu.')
            : (isLxc
                ? 'Durdurma komutu gönderildi ama durum doğrulanamadı — konteyner birkaç dakika içinde durmuş olabilir.'
                : 'Durdurma komutu gönderildi ama durum doğrulanamadı — sanal makine birkaç dakika içinde durmuş olabilir.'),
        progress: 1.0,
        success: true,
      );
      await Future.delayed(Duration(milliseconds: confirmed ? 1200 : 1800));
    } catch (e) {
      // Bilinçli sessiz: hata zaten _setOperationFailed ile kullanıcıya
      // OperationOverlay üzerinde gösteriliyor — burada tekrar loglamak gürültü olur.
      debugPrint('stopContainer hatası: $e');
      await _setOperationFailed(e);
    } finally {
      _setOperation(inProgress: false);
    }
  }

  Future<void> rebootContainer(String node, int vmid,
      {bool isLxc = true}) async {
    _setOperation(
      inProgress: true,
      message: isLxc
          ? 'Konteyner Yeniden Başlatılıyor'
          : 'Sanal Makine Yeniden Başlatılıyor',
      subMessage: 'Komut gönderiliyor...',
      progress: 0.15,
    );
    try {
      await _serviceFor(node).rebootVM(node, vmid, isLxc: isLxc);
      _setOperation(
        inProgress: true,
        message: isLxc
            ? 'Konteyner Yeniden Başlatılıyor'
            : 'Sanal Makine Yeniden Başlatılıyor',
        subMessage: 'Yeniden başlatma komutu gönderildi...',
        progress: 0.3,
      );
      final stoppedConfirmed = await _silentRefreshUntil(
          node: node, vmid: vmid, targetStatus: 'stopped', isLxc: isLxc);
      final runningConfirmed = await _silentRefreshUntil(
          node: node, vmid: vmid, targetStatus: 'running', isLxc: isLxc);
      final confirmed = stoppedConfirmed && runningConfirmed;
      _setOperation(
        inProgress: true,
        message: confirmed ? 'Tamamlandı!' : 'Komut Gönderildi',
        subMessage: confirmed
            ? (isLxc
                ? 'Konteyner yeniden başlatıldı.'
                : 'Sanal makine yeniden başlatıldı.')
            : (isLxc
                ? 'Yeniden başlatma komutu gönderildi ama durum doğrulanamadı — konteyner birkaç dakika içinde çalışır duruma gelmiş olabilir.'
                : 'Yeniden başlatma komutu gönderildi ama durum doğrulanamadı — sanal makine birkaç dakika içinde çalışır duruma gelmiş olabilir.'),
        progress: 1.0,
        success: true,
      );
      await Future.delayed(Duration(milliseconds: confirmed ? 1200 : 1800));
    } catch (e) {
      // Bilinçli sessiz: hata zaten _setOperationFailed ile kullanıcıya
      // OperationOverlay üzerinde gösteriliyor — burada tekrar loglamak gürültü olur.
      debugPrint('rebootContainer hatası: $e');
      await _setOperationFailed(e);
    } finally {
      _setOperation(inProgress: false);
    }
  }

  Future<void> rebootNode(String node) async {
    _setOperation(
      inProgress: true,
      message: 'Makine Yeniden Başlatılıyor',
      subMessage: '$node yeniden başlatma komutu gönderildi...',
      progress: 0.5,
    );
    try {
      await _serviceFor(node).rebootNode(node);
      await _markDeliberateOff(node, action: 'reboot');
      _setOperation(
        inProgress: true,
        message: 'Tamamlandı!',
        subMessage: '$node yeniden başlatılıyor.',
        progress: 1.0,
        success: true,
      );
      await Future.delayed(const Duration(milliseconds: 1200));
    } catch (e) {
      debugPrint('rebootNode hatası: $e');
      ErrorLogService().log(
        type: ErrorLogType.operation,
        message: 'Node yeniden başlatma başarısız: $node',
        detail: e.toString(),
      );
      if (e is ProxmoxCommandUncertainException && e.likelyDelivered) {
        await _markDeliberateOff(node, action: 'reboot');
        _setOperation(
          inProgress: true,
          message: 'Komut Gönderildi',
          subMessage:
              '$node için yeniden başlatma komutu iletildi ama yanıt alınamadı — makine yeniden başlıyor olabilir.',
          progress: 1.0,
          success: true,
        );
        await Future.delayed(const Duration(milliseconds: 1800));
      } else {
        await _setOperationFailed(e);
      }
    } finally {
      _setOperation(inProgress: false);
    }
  }

  Future<void> shutdownNode(String node) async {
    _setOperation(
      inProgress: true,
      message: 'Makine Kapatılıyor',
      subMessage: '$node kapatma komutu gönderildi...',
      progress: 0.5,
    );
    try {
      await _serviceFor(node).shutdownNode(node);
      await _markDeliberateOff(node, action: 'shutdown');
      _setOperation(
        inProgress: true,
        message: 'Tamamlandı!',
        subMessage: '$node kapatılıyor.',
        progress: 1.0,
        success: true,
      );
      await Future.delayed(const Duration(milliseconds: 1200));
    } catch (e) {
      debugPrint('shutdownNode hatası: $e');
      ErrorLogService().log(
        type: ErrorLogType.operation,
        message: 'Node kapatma başarısız: $node',
        detail: e.toString(),
      );
      if (e is ProxmoxCommandUncertainException && e.likelyDelivered) {
        // Proxmox'un shutdown API'si fire-and-forget'tir — komut muhtemelen
        // ulaştı, yanıt geri dönerken bağlantı koptu. "Başarısız" değil,
        // nötr bir "gönderildi ama teyit edilemedi" mesajı gösterilir.
        await _markDeliberateOff(node, action: 'shutdown');
        _setOperation(
          inProgress: true,
          message: 'Komut Gönderildi',
          subMessage:
              '$node için kapatma komutu iletildi ama yanıt alınamadı — makine kapanıyor olabilir. Birkaç dakika sonra durumu kontrol edin.',
          progress: 1.0,
          success: true,
        );
        await Future.delayed(const Duration(milliseconds: 1800));
      } else {
        await _setOperationFailed(e);
      }
    } finally {
      _setOperation(inProgress: false);
    }
  }

  Future<Map<String, dynamic>> getContainerConfig(String node, int vmid,
      {bool isLxc = true}) async {
    final config =
        await _serviceFor(node).getVMConfig(node, vmid, isLxc: isLxc);
    containerConfigs['$node-$vmid'] = config;
    notifyListeners();
    return config;
  }

  Future<List<dynamic>> getContainerRRD(String node, int vmid,
      {bool isLxc = true}) async {
    if (_services.isEmpty) return [];
    return await _serviceFor(node).getContainerRRD(node, vmid, isLxc: isLxc);
  }

  Future<void> deleteContainer(String node, int vmid,
      {bool isLxc = true}) async {
    _setOperation(
      inProgress: true,
      message: isLxc ? 'Konteyner Siliniyor' : 'Sanal Makine Siliniyor',
      subMessage: 'Silme komutu gönderiliyor...',
      progress: 0.2,
    );
    try {
      if (isLxc) {
        await _serviceFor(node).deleteLXC(node, vmid);
      } else {
        await _serviceFor(node).deleteVM(node, vmid);
      }
      _setOperation(
        inProgress: true,
        message: isLxc ? 'Konteyner Siliniyor' : 'Sanal Makine Siliniyor',
        subMessage: 'Silme işlemi devam ediyor...',
        progress: 0.5,
      );
      final confirmed =
          await _waitUntilGone(node: node, vmid: vmid, isLxc: isLxc);
      _setOperation(
        inProgress: true,
        message: confirmed ? 'Tamamlandı!' : 'Komut Gönderildi',
        subMessage: confirmed
            ? (isLxc ? 'Konteyner silindi.' : 'Sanal makine silindi.')
            : (isLxc
                ? 'Silme komutu gönderildi ama tamamlandığı doğrulanamadı — birkaç dakika sonra tekrar kontrol edin.'
                : 'Silme komutu gönderildi ama tamamlandığı doğrulanamadı — birkaç dakika sonra tekrar kontrol edin.'),
        progress: 1.0,
        success: true,
      );
      await Future.delayed(Duration(milliseconds: confirmed ? 1200 : 1800));
    } catch (e) {
      // Bilinçli sessiz: hata zaten _setOperationFailed ile kullanıcıya
      // OperationOverlay üzerinde gösteriliyor — burada tekrar loglamak gürültü olur.
      debugPrint('deleteContainer hatası: $e');
      await _setOperationFailed(e);
    } finally {
      _setOperation(inProgress: false);
    }
  }

  /// Konteyner/VM'in listeden gerçekten kaybolduğunu DOĞRULARSA `true`,
  /// zaman aşımında `false` — bkz. `_silentRefreshUntil` üzerindeki not,
  /// aynı dürüst-belirsizlik gerekçesi silme için de geçerli.
  Future<bool> _waitUntilGone({
    required String node,
    required int vmid,
    required bool isLxc,
  }) async {
    const maxAttempts = 20;
    const pollInterval = Duration(seconds: 3);

    for (int attempt = 0; attempt < maxAttempts; attempt++) {
      await Future.delayed(pollInterval);
      final progress = 0.5 + (attempt / maxAttempts) * 0.4;
      _setOperation(
        inProgress: true,
        message:
            isLxc ? 'Konteyner Siliniyor' : 'Sanal Makine Siliniyor',
        subMessage:
            'Silme işlemi devam ediyor... (${attempt + 1}/$maxAttempts)',
        progress: progress.clamp(0.0, 0.9),
      );
      try {
        final freshData = await _fetchAllData();
        if (freshData == null) continue;
        final lxcList = freshData['nodeLXCs']?[node] as List? ?? [];
        final vmList = freshData['nodeVMs']?[node] as List? ?? [];
        final list = isLxc ? lxcList : vmList;
        if (!list.any((item) => item['vmid'] == vmid)) {
          _applyFreshData(freshData);
          return true;
        }
      } catch (e) {
        // Bilinçli sessiz: tek bir poll denemesinin başarısız olması normal
        // (geçici ağ gecikmesi) — döngü tekrar dener.
        debugPrint('Silme poll hatası (attempt $attempt): $e');
      }
    }
    try {
      final freshData = await _fetchAllData();
      if (freshData != null) _applyFreshData(freshData);
    } catch (_) {
      // Bilinçli sessiz: silme işleminin son iyi-niyet yenilemesi — vazgeçmeden
      // önce son bir kez taze veri denenir, o da başarısız olursa raporlanacak
      // yeni bir bilgi yok.
    }
    return false;
  }

  Future<void> reorderNodes(int oldIndex, int newIndex) async {
    if (newIndex > oldIndex) newIndex--;
    final node = nodes.removeAt(oldIndex);
    nodes.insert(newIndex, node);
    _nodeOrder = nodes.map((n) => n['node'] as String).toList();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('node_order', jsonEncode(_nodeOrder));
    await CloudSyncService().saveNodeOrder(jsonEncode(_nodeOrder));
    notifyListeners();
  }

  Future<List<dynamic>> getISOList(String node) async {
    return await _serviceFor(node).getISOList(node);
  }

  Future<void> createVM({
    required String node,
    required int vmid,
    required String name,
    required int memory,
    required int cores,
    required int disk,
    required String storage,
    required String iso,
    required String osType,
  }) async {
    await _serviceFor(node).createQemuVM(
      node: node,
      vmid: vmid,
      name: name,
      memory: memory,
      cores: cores,
      disk: disk,
      storage: storage,
      iso: iso,
      osType: osType,
    );
    final freshData = await _fetchAllData();
    if (freshData != null) _applyFreshData(freshData);
  }

  Future<List<dynamic>> getTemplateList(String node) async {
    return await _serviceFor(node).getTemplates(node);
  }

  Future<void> createContainer({
    required String node,
    required int vmid,
    required String hostname,
    required String password,
    required String template,
    required String storage,
    required int memory,
    required int swap,
    required int disk,
    required int cores,
    required String ip,
    required String gw,
    required bool onBoot,
    required bool unprivileged,
  }) async {
    await _serviceFor(node).createLXC(
      node: node,
      vmid: vmid,
      hostname: hostname,
      password: password,
      template: template,
      storage: storage,
      memory: memory,
      swap: swap,
      disk: disk,
      cores: cores,
      ip: ip,
      gw: gw,
      onBoot: onBoot,
      unprivileged: unprivileged,
    );
    final freshData = await _fetchAllData();
    if (freshData != null) _applyFreshData(freshData);
  }

  Future<List<dynamic>> getStorageContent(String node, String storage) async {
    if (_services.isEmpty) return [];
    return await _serviceFor(node).getStorageContent(node, storage);
  }

  Future<void> deleteStorageContent(
      String node, String storage, String volume) async {
    await _serviceFor(node).deleteStorageContent(node, storage, volume);
  }

  Future<void> restoreBackup({
    required String node,
    required String storage,
    required String volume,
    required int vmid,
    required bool isLxc,
  }) async {
    await _serviceFor(node).restoreBackup(
      node: node,
      storage: storage,
      volume: volume,
      vmid: vmid,
      isLxc: isLxc,
    );
  }

  Future<void> sendWakeOnLan(String node, String mac) async {
    if (_services.isEmpty) return;
    await _serviceFor(node).sendWakeOnLan(node, mac);
  }

  // ── Yardımcılar ───────────────────────────────────────────────────────────

  ProxmoxService _serviceFor(String node) {
    return _nodeServiceMap[node] ?? _services.first;
  }

  int? _parseDiskTemp(Map<String, dynamic> smartData) {
    final type = smartData['type'] ?? '';
    if (type == 'text') {
      final text = smartData['text'] as String? ?? '';
      final m = RegExp(r'Temperature:\s+(\d+)').firstMatch(text);
      if (m != null) return int.tryParse(m.group(1)!);
    } else {
      final attrs = smartData['attributes'] as List? ?? [];
      final tempAttr = attrs.firstWhere(
        (a) =>
            ['190', '194'].contains(a['id']?.toString().trim()) ||
            a['name'] == 'Temperature_Celsius' ||
            a['name'] == 'Airflow_Temperature_Cel',
        orElse: () => null,
      );
      if (tempAttr != null) {
        return int.tryParse(tempAttr['raw'].toString().split(' ').first);
      }
    }
    return null;
  }

  @override
  void dispose() {
    _periodicTimer?.cancel();
    _retryTimer?.cancel();
    super.dispose();
  }
}