import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mtools/features/dashboard/error_log_service.dart';
import 'package:mtools/features/proxmox/proxmox_provider.dart';
import 'package:mtools/features/proxmox/proxmox_service.dart';

/// Ağa hiç çıkmayan sahte servis — [failing] içindeki uç noktalar hata
/// fırlatır, diğerleri sabit veri döner.
class _FakeProxmoxService extends ProxmoxService {
  final Set<String> failing;
  _FakeProxmoxService(this.failing) {
    configure('192.0.2.10', '8006', 'root@pam!MToolsV2', 'secret');
  }

  Future<T> _answer<T>(String endpoint, T value) async {
    if (failing.contains(endpoint)) {
      throw Exception('HTTP 403 ($endpoint)');
    }
    return value;
  }

  @override
  Future<List<dynamic>> getNodes() async => [
        {'node': 'pve', 'status': 'online'},
      ];
  @override
  Future<Map<String, dynamic>> getNodeStatus(String node) =>
      _answer('status', <String, dynamic>{
        'cpu': 0.25,
        'memory': {'total': 1000, 'used': 500},
      });
  @override
  Future<List<dynamic>> getNodeDisks(String node) => _answer('disks', [
        {'devpath': '/dev/sda', 'health': 'PASSED'},
      ]);
  @override
  Future<List<dynamic>> getNodeStorage(String node) =>
      _answer('storage', [
        {'storage': 'local', 'active': 1, 'used': 1, 'total': 2},
      ]);
  @override
  Future<List<dynamic>> getLXCs(String node) => _answer('lxc', [
        {'vmid': 101, 'name': 'ct1', 'status': 'running'},
      ]);
  @override
  Future<List<dynamic>> getVMs(String node) => _answer('qemu', [
        {'vmid': 201, 'name': 'vm1', 'status': 'stopped'},
      ]);
  @override
  Future<List<dynamic>> getNodeNetwork(String node) =>
      _answer('network', [
        {'iface': 'vmbr0', 'type': 'bridge', 'address': '192.0.2.10'},
      ]);
  @override
  Future<List<dynamic>> getNodeRRDData(String node) =>
      _answer('rrddata', <dynamic>[]);
  @override
  Future<List<dynamic>> getNetstat(String node) => _answer('netstat', [
        {'vmid': '101', 'dev': 'veth101i0', 'in': '1', 'out': '2'},
      ]);
  @override
  Future<Map<String, dynamic>> getDiskSmart(String node, String disk) =>
      _answer('smart', <String, dynamic>{'type': 'text', 'text': ''});
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final id = composeNodeId('192.0.2.10', 'pve');

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    // home_widget platform kanalı testte yok — sessizce başarılı say.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('home_widget'), (_) async => true);
  });

  Future<ProxmoxProvider> refreshWith(Set<String> failing) async {
    final provider = ProxmoxProvider()
      ..debugAddService(_FakeProxmoxService(failing));
    await provider.refresh();
    return provider;
  }

  test('disks uç noktası hata verince status, CT ve VM verisi kaybolmaz',
      () async {
    final p = await refreshWith({'disks'});

    expect(p.nodeStatuses[id]?['cpu'], 0.25);
    expect(p.nodeLXCs[id], hasLength(1));
    expect(p.nodeVMs[id], hasLength(1));
    expect(p.nodeStorages[id], hasLength(1));
    expect(p.nodeNetworks[id], hasLength(1));
    expect(p.nodeDisks[id], isEmpty);
    expect(p.nodeFetchFailures[id], {'disks'});
  });

  test('hata veren uç nokta günlüğe node ve uç nokta adıyla yazılır',
      () async {
    await refreshWith({'disks', 'qemu'});

    final messages = ErrorLogService().logs.map((e) => e.message).toList();
    expect(messages, contains('Node verisi alınamadı: pve / disks'));
    expect(messages, contains('Node verisi alınamadı: pve / qemu'));
  });

  test('netstat periyodik yenilemede de çekilir', () async {
    final p = await refreshWith({});

    expect(p.nodeNetstat[id], hasLength(1));
    expect(p.nodeFetchFailures[id], isEmpty);
  });
}
