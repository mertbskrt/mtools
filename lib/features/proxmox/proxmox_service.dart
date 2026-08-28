import 'package:dio/dio.dart';
import 'dart:io';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';

/// Proxmox API isteği 2xx dışında bir durum kodu döndürdüğünde fırlatılır.
/// `validateStatus: (s) => true` sayesinde Dio hiçbir zaman kendiliğinden
/// hata fırlatmadığı için (ör. 403 yetki reddi de "başarılı" sanılıyordu),
/// yazma işlemlerinden sonra bu kontrol elle yapılır.
class ProxmoxApiException implements Exception {
  final String message;
  final int? statusCode;
  ProxmoxApiException(this.message, {this.statusCode});
  @override
  String toString() => message;
}

class ProxmoxCommandUncertainException implements Exception {
  final String message;
  final bool likelyDelivered;
  ProxmoxCommandUncertainException(this.message,
      {required this.likelyDelivered});
  @override
  String toString() => message;
}

class ProxmoxService {
  late Dio _dio;
  String _host = '';
  String _rawHost = '';
  String _tokenId = '';
  String _tokenSecret = '';
  String _name = '';

  /// Şema/port eklenmemiş ham host — bağlantı hatası sınıflandırması
  /// (bkz. connection_target.dart) için kullanılır.
  String get rawHost => _rawHost;

  /// Kayıtlı sunucu listesindeki kullanıcı-tanımlı isim (boş olabilir —
  /// örn. eski tekli-sunucu ayarları yolunda hiç kayıtlı isim yok).
  String get name => _name;

  void configure(
      String host, dynamic port, String tokenId, String tokenSecret,
      {String name = ''}) {
    final resolvedPort =
        (port == null || port.toString().isEmpty) ? '8006' : port.toString();
    _rawHost = host;
    _host = 'https://$host:$resolvedPort';
    _tokenId = tokenId;
    _tokenSecret = tokenSecret;
    _name = name;
    _dio = Dio(BaseOptions(
      baseUrl: '$_host/api2/json',
      headers: {'Authorization': 'PVEAPIToken=$_tokenId=$_tokenSecret'},
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
      validateStatus: (s) => true,
    ))
      ..interceptors.add(InterceptorsWrapper(
        onError: (e, h) => h.next(e),
      ));

    (_dio.httpClientAdapter as IOHttpClientAdapter).createHttpClient = () {
      final client = HttpClient();
      client.badCertificateCallback = (cert, host, port) => true;
      return client;
    };
  }

  /// Yazma isteklerinden (start/stop/reboot/create/delete...) sonra çağrılır.
  /// 2xx dışında bir kod dönerse ProxmoxApiException fırlatır — Proxmox
  /// genelde {"errors": {...}} veya {"message": "..."} ile hatayı açıklar.
  void _ensureSuccess(Response res) {
    final code = res.statusCode ?? 0;
    if (code >= 200 && code < 300) return;

    String detail = 'Proxmox sunucusu $code döndürdü';
    final data = res.data;
    if (data is Map) {
      final errors = data['errors'];
      final msg = data['message'];
      if (errors is Map && errors.isNotEmpty) {
        detail = errors.values.join(', ');
      } else if (errors != null) {
        detail = errors.toString();
      } else if (msg != null) {
        detail = msg.toString();
      }
    }

    if (code == 401 || code == 403) {
      throw ProxmoxApiException(
        'Yetki reddedildi — API token bu işlem için izinli değil ($detail)',
        statusCode: code,
      );
    }
    throw ProxmoxApiException(detail, statusCode: code);
  }

  Future<List<dynamic>> getContainerRRD(String node, int vmid,
      {bool isLxc = true}) async {
    final type = isLxc ? 'lxc' : 'qemu';
    final res = await _dio
        .get('/nodes/$node/$type/$vmid/rrddata?timeframe=hour&cf=AVERAGE');
    if (res.statusCode != 200) return [];
    final data = res.data['data'];
    if (data == null || data is! List) return [];
    return data;
  }

  Future<List<dynamic>> getNodes() async {
    final res = await _dio.get('/nodes');
    return res.data['data'] ?? [];
  }

  Future<Map<String, dynamic>> getNodeStatus(String node) async {
    final res = await _dio.get('/nodes/$node/status');
    return res.data['data'] ?? {};
  }

  Future<Map<String, dynamic>> getNodeRRD(String node) async {
    final res = await _dio.get('/nodes/$node/rrddata?timeframe=hour');
    return res.data['data'] ?? {};
  }

  Future<List<dynamic>> getNodeDisks(String node) async {
    final res = await _dio.get('/nodes/$node/disks/list');
    return res.data['data'] ?? [];
  }

  Future<List<dynamic>> getNodeStorage(String node) async {
    final res = await _dio.get('/nodes/$node/storage');
    return res.data['data'] ?? [];
  }

  Future<List<dynamic>> getVMs(String node) async {
    final res = await _dio.get('/nodes/$node/qemu');
    return res.data['data'] ?? [];
  }

  Future<List<dynamic>> getLXCs(String node) async {
    final res = await _dio.get('/nodes/$node/lxc');
    return res.data['data'] ?? [];
  }

  /// Bu üçü ve deleteLXC/deleteVM, Proxmox'ta arka planda bir GÖREV (task)
  /// olarak yürütülür — API isteğinin 2xx dönmesi sadece görevin
  /// KUYRUĞA ALINDIĞINI gösterir, gerçekten başarılı olup olmadığını
  /// göstermez. Proxmox bu görevi bir UPID (benzersiz görev kimliği) ile
  /// döndürür; bunu döndürüyoruz ki çağıran taraf getTaskStatus() ile
  /// görevin GERÇEK sonucunu (exitstatus) otoriter şekilde sorgulayabilsin
  /// — CT/VM'in durum alanını dolaylı yoklamak yerine.
  Future<String> startVM(String node, int vmid, {bool isLxc = false}) async {
    final type = isLxc ? 'lxc' : 'qemu';
    final res = await _dio.post('/nodes/$node/$type/$vmid/status/start');
    _ensureSuccess(res);
    return (res.data['data'] as String?) ?? '';
  }

  Future<String> stopVM(String node, int vmid, {bool isLxc = false}) async {
    final type = isLxc ? 'lxc' : 'qemu';
    final res = await _dio.post('/nodes/$node/$type/$vmid/status/stop');
    _ensureSuccess(res);
    return (res.data['data'] as String?) ?? '';
  }

  Future<String> rebootVM(String node, int vmid, {bool isLxc = false}) async {
    final type = isLxc ? 'lxc' : 'qemu';
    final res = await _dio.post('/nodes/$node/$type/$vmid/status/reboot');
    _ensureSuccess(res);
    return (res.data['data'] as String?) ?? '';
  }

  /// Bir Proxmox görevinin (UPID) şu anki durumunu sorgular. `status` alanı
  /// görev bitince "stopped" olur; o noktada `exitstatus` "OK" ise gerçek
  /// başarı, değilse Proxmox'un kendi hata metnidir — bu, bir işlemin
  /// gerçekten başarılı olup olmadığını öğrenmenin TEK otoriter yolu.
  Future<Map<String, dynamic>> getTaskStatus(String node, String upid) async {
    final res = await _dio.get('/nodes/$node/tasks/$upid/status');
    _ensureSuccess(res);
    return res.data['data'] ?? {};
  }

  Future<Map<String, dynamic>> getClusterStatus() async {
    final res = await _dio.get('/cluster/status');
    return res.data['data'] ?? {};
  }

  Future<void> rebootNode(String node) async {
    try {
      final res = await _dio
          .post('/nodes/$node/status', data: {'command': 'reboot'});
      _ensureSuccess(res);
    } on DioException catch (e) {
      throw ProxmoxCommandUncertainException(
        e.message ?? 'Bağlantı hatası',
        likelyDelivered: _likelyDelivered(e),
      );
    }
  }

  Future<void> shutdownNode(String node) async {
    try {
      final res = await _dio
          .post('/nodes/$node/status', data: {'command': 'shutdown'});
      _ensureSuccess(res);
    } on DioException catch (e) {
      throw ProxmoxCommandUncertainException(
        e.message ?? 'Bağlantı hatası',
        likelyDelivered: _likelyDelivered(e),
      );
    }
  }

  bool _likelyDelivered(DioException e) => ![
        DioExceptionType.connectionTimeout,
        DioExceptionType.badCertificate,
        DioExceptionType.cancel,
      ].contains(e.type);

  Future<void> mountDisk(String node, String disk) async {
    final res = await _dio.post('/nodes/$node/disks/directory',
        data: {'disk': disk, 'name': disk.split('/').last});
    _ensureSuccess(res);
  }

  Future<Map<String, dynamic>> getNodeHardware(String node) async {
    final res = await _dio.get('/nodes/$node/hardware/pci');
    return res.data['data'] ?? {};
  }

  Future<Map<String, dynamic>> getDiskSmart(String node, String disk) async {
    final res = await _dio.get('/nodes/$node/disks/smart?disk=$disk');
    return res.data['data'] ?? {};
  }

  Future<List<dynamic>> getNodeNetwork(String node) async {
    final res = await _dio.get('/nodes/$node/network');
    return res.data['data'] ?? [];
  }

  Future<List<dynamic>> getNodeRRDData(String node) async {
    final res =
        await _dio.get('/nodes/$node/rrddata?timeframe=hour&cf=AVERAGE');
    return res.data['data'] ?? [];
  }

  Future<Map<String, dynamic>> getNodeCpuThermal(String node) async {
    final res = await _dio.get('/nodes/$node/status');
    return res.data['data'] ?? {};
  }

  Future<List<dynamic>> getNodeSensors(String node) async {
    final res = await _dio.get('/nodes/$node/hardware/pci');
    return res.data['data'] ?? [];
  }

  Future<Map<String, dynamic>> getLXCConfig(String node, int vmid) async {
    final res = await _dio.get('/nodes/$node/lxc/$vmid/config');
    return res.data['data'] ?? {};
  }

  Future<Map<String, dynamic>> getVMConfig(String node, int vmid,
      {bool isLxc = true}) async {
    final type = isLxc ? 'lxc' : 'qemu';
    final res = await _dio.get('/nodes/$node/$type/$vmid/config');
    return res.data['data'] ?? {};
  }

  Future<String> deleteLXC(String node, int vmid) async {
    final res = await _dio.delete('/nodes/$node/lxc/$vmid');
    _ensureSuccess(res);
    return (res.data['data'] as String?) ?? '';
  }

  Future<String> deleteVM(String node, int vmid) async {
    final res = await _dio.delete('/nodes/$node/qemu/$vmid');
    _ensureSuccess(res);
    return (res.data['data'] as String?) ?? '';
  }

  Future<List<dynamic>> getTemplates(String node) async {
    final res = await _dio.get('/nodes/$node/storage');
    final storages = res.data['data'] as List? ?? [];
    final List<dynamic> templates = [];
    for (final storage in storages) {
      if (storage['active'] == 1) {
        final storageName = storage['storage'];
        final contentRes = await _dio
            .get('/nodes/$node/storage/$storageName/content?content=vztmpl');
        final items = contentRes.data['data'] as List? ?? [];
        templates.addAll(items);
      }
    }
    return templates;
  }

  Future<void> createLXC({
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
    final netConfig = ip == 'dhcp'
        ? 'name=eth0,bridge=vmbr0,ip=dhcp'
        : 'name=eth0,bridge=vmbr0,ip=$ip,gw=$gw';
    final res = await _dio.post('/nodes/$node/lxc', data: {
      'vmid': vmid,
      'hostname': hostname,
      'ostemplate': template,
      'storage': storage,
      'memory': memory,
      'swap': swap,
      'rootfs': '$storage:$disk',
      'cores': cores,
      'net0': netConfig,
      'onboot': onBoot ? 1 : 0,
      'unprivileged': unprivileged ? 1 : 0,
      'password': password,
    });
    _ensureSuccess(res);
  }

  Future<List<dynamic>> getISOList(String node) async {
    final List<dynamic> isos = [];
    final storages = await getNodeStorage(node);
    for (final storage in storages) {
      if (storage['active'] == 1) {
        final name = storage['storage'];
        final res =
            await _dio.get('/nodes/$node/storage/$name/content?content=iso');
        final items = res.data['data'] as List? ?? [];
        isos.addAll(items);
      }
    }
    return isos;
  }

  Future<void> createQemuVM({
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
    final res = await _dio.post('/nodes/$node/qemu', data: {
      'vmid': vmid,
      'name': name,
      'memory': memory,
      'cores': cores,
      'sockets': 1,
      'ostype': osType,
      'ide2': '$iso,media=cdrom',
      'scsi0': '$storage:$disk',
      'scsihw': 'virtio-scsi-pci',
      'boot': 'order=ide2;scsi0',
      'net0': 'virtio,bridge=vmbr0',
    });
    _ensureSuccess(res);
  }

  Future<List<dynamic>> getStorageContent(String node, String storage,
      {String contentType = 'backup'}) async {
    try {
      final res = await _dio
          .get('/nodes/$node/storage/$storage/content?content=$contentType');
      debugPrint(
          'STORAGE CONTENT [$storage]: status=${res.statusCode} data=${res.data}');
      if (res.statusCode != 200) return [];
      return res.data['data'] ?? [];
    } catch (e) {
      // Bilinçli sessiz: depolama içeriği görüntüleme salt-okunur, ikincil
      // bir ekran — hata durumunda çağıran taraf zaten boş listeyi "içerik
      // yok" olarak gösteriyor.
      debugPrint('STORAGE CONTENT ERROR [$storage]: $e');
      return [];
    }
  }

  Future<void> deleteStorageContent(
      String node, String storage, String volume) async {
    final res =
        await _dio.delete('/nodes/$node/storage/$storage/content/$volume');
    _ensureSuccess(res);
  }

  Future<String> restoreBackup({
    required String node,
    required String storage,
    required String volume,
    required int vmid,
    required bool isLxc,
  }) async {
    final type = isLxc ? 'lxc' : 'qemu';
    final res = await _dio.post('/nodes/$node/$type', data: {
      'vmid': vmid,
      'ostemplate': volume,
      'archive': volume,
      'storage': storage,
      'force': 1,
    });
    _ensureSuccess(res);
    return res.data['data'] ?? '';
  }

  Future<void> sendWakeOnLan(String node, String mac) async {
    final res = await _dio.post('/nodes/$node/wakeonlan', data: {'mac': mac});
    _ensureSuccess(res);
  }

  Future<List<dynamic>> getNodeTasks(String node, {int? since}) async {
    final params = <String, dynamic>{
      'limit': 200,
      'source': 'all',
    };
    if (since != null) {
      params['since'] = since;
    }
    final response = await _dio.get(
      '/nodes/$node/tasks',
      queryParameters: params,
    );
    final data = response.data['data'];
    if (data == null) return [];
    return data as List<dynamic>;
  }

  Future<List<dynamic>> getNetstat(String node) async {
    final res = await _dio.get('/nodes/$node/netstat');
    return res.data['data'] ?? [];
  }
}
