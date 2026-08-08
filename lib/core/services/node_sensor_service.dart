import 'dart:convert';
import 'package:dartssh2/dartssh2.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'cloud_sync_service.dart';

/// Proxmox node'larının donanım sıcaklığını (CPU/paket) `sensors` (lm-sensors)
/// komutunu SSH ile çalıştırarak okur. Proxmox API'sinin kendisi bu veriyi
/// vermediği için, Terminal özelliğinde zaten kayıtlı olan SSH sunucularıyla
/// (host/isim eşleşmesi) eşleştirilip aynı kimlik bilgileri kullanılır —
/// ayrı bir kimlik bilgisi girişi istenmez.
///
/// SSH bağlantısı ucuz bir işlem olmadığı için sonuçlar node başına
/// [_ttl] süresince önbelleklenir; her yenileme döngüsünde (30sn) yeniden
/// bağlanılmaz.
class NodeSensorService {
  static final Map<String, _CachedTemp> _cache = {};
  static const _ttl = Duration(minutes: 3);

  static Future<int?> getTemperature(String nodeName) async {
    final cached = _cache[nodeName];
    if (cached != null && DateTime.now().difference(cached.at) < _ttl) {
      return cached.value;
    }

    try {
      final server = await _findServer(nodeName);
      if (server == null) return null;

      final socket = await SSHSocket.connect(server.host, server.port)
          .timeout(const Duration(seconds: 8));
      final client = SSHClient(
        socket,
        username: server.username,
        onPasswordRequest: () => server.password,
      );
      await client.authenticated.timeout(const Duration(seconds: 8));
      final output = await client.run('sensors').timeout(const Duration(seconds: 8));
      client.close();

      final temp = _parseTemperature(utf8.decode(output, allowMalformed: true));
      _cache[nodeName] = _CachedTemp(temp, DateTime.now());
      return temp;
    } catch (_) {
      _cache[nodeName] = _CachedTemp(null, DateTime.now());
      return null;
    }
  }

  static Future<_SshServerInfo?> _findServer(String nodeName) async {
    final prefs = await SharedPreferences.getInstance();
    // Local ÖNCELİKLİ: cloud'daki 'ssh_servers' artık şifre içermiyor (bkz.
    // credential_sync.dart) — cloud'u önce okumak SSH bağlantısını hep
    // boş şifreyle denetip başarısız kılardı.
    String? raw = prefs.getString('ssh_servers');
    raw ??= await CloudSyncService().getSetting('ssh_servers');
    if (raw == null) return null;

    try {
      final List list = jsonDecode(raw);
      for (final item in list) {
        final host = (item['host'] as String? ?? '').toLowerCase();
        final name = (item['name'] as String? ?? '').toLowerCase();
        final needle = nodeName.toLowerCase();
        if (host == needle || name == needle || host.startsWith('$needle.')) {
          return _SshServerInfo(
            host: item['host'] ?? '',
            port: item['port'] ?? 22,
            username: item['username'] ?? 'root',
            password: item['password'] ?? '',
          );
        }
      }
    } catch (_) {
      // Bilinçli sessiz: sıcaklık, opsiyonel bir zenginleştirme — eşleşen
      // SSH sunucusu bulunamazsa/parse hatası olursa sadece o node için
      // sıcaklık gösterilmez, başka bir etkisi yok.
    }
    return null;
  }

  /// lm-sensors çıktısında "Package id 0: +45.0°C", "Tctl: +50.0°C" veya
  /// "Core 0: +42.0°C" gibi satırlar aranır; en yüksek değer CPU sıcaklığı
  /// olarak kabul edilir (birden fazla çekirdek/paket varsa en sıcağı).
  static int? _parseTemperature(String output) {
    final regex = RegExp(r'\+([\d.]+)°?C');
    double? maxTemp;
    for (final match in regex.allMatches(output)) {
      final value = double.tryParse(match.group(1) ?? '');
      if (value != null && (maxTemp == null || value > maxTemp)) {
        maxTemp = value;
      }
    }
    return maxTemp?.round();
  }
}

class _CachedTemp {
  final int? value;
  final DateTime at;
  _CachedTemp(this.value, this.at);
}

class _SshServerInfo {
  final String host;
  final int port;
  final String username;
  final String password;
  _SshServerInfo({
    required this.host,
    required this.port,
    required this.username,
    required this.password,
  });
}
