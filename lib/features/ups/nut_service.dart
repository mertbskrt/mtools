import 'dart:async';
import 'dart:convert';
import 'dart:io';

class NutService {
  String _host = '';
  int _port = 3493;
  String _username = '';
  String _password = '';
  bool _configured = false;
  void configure({
    required String host,
    int port = 3493,
    String username = '',
    String password = '',
  }) {
    _host = host;
    _port = port;
    _username = username;
    _password = password;
    _configured = true;
  }

  bool get isConfigured => _configured;
  String get host => _host;
  int get port => _port;

  // Tek bir NUT oturumu aç, komutları gönder, kapat
  Future<List<String>> _sendCommand(String command) async {
    Socket? socket;
    try {
      // Domain kullanılıyorsa (IP değilse) 443 üzerinden bağlan
      socket = await Socket.connect(
        _host,
        _port,
        timeout: const Duration(seconds: 8),
      );

      final lines = <String>[];
      var buffer = '';
      final completer = Completer<List<String>>();

      // LIST komutları END LIST ile, GET komutu ERR veya VAR ile biter
      bool isDone(String line) {
        if (line.startsWith('ERR ')) return true;
        if (command.startsWith('LIST')) return line.startsWith('END LIST');
        if (command.startsWith('GET')) {
          return line.startsWith('VAR ') || line.startsWith('ERR ');
        }
        return line.startsWith('OK') || line.startsWith('ERR');
      }

      socket.listen(
        (data) {
          buffer += utf8.decode(data, allowMalformed: true);
          final parts = buffer.split('\n');

          for (int i = 0; i < parts.length - 1; i++) {
            final line = parts[i].trim();
            if (line.isEmpty) continue;
            // Auth OK'larını filtrele — asıl veriyle karışmasın
            if (line == 'OK') continue;
            lines.add(line);
            if (!completer.isCompleted && isDone(line)) {
              completer.complete(List.unmodifiable(lines));
            }
          }

          buffer = parts.last;
        },
        onError: (e) {
          if (!completer.isCompleted) completer.completeError(e);
        },
        onDone: () {
          if (!completer.isCompleted) {
            completer.complete(List.unmodifiable(lines));
          }
        },
      );

      // Auth — komuttan önce gönder, cevabını beklemeden devam et
      if (_username.isNotEmpty) {
        socket.write('USERNAME $_username\n');
        socket.write('PASSWORD $_password\n');
      }

      socket.write('$command\n');

      return await completer.future.timeout(
        const Duration(seconds: 8),
        onTimeout: () => List.unmodifiable(lines),
      );
    } finally {
      socket?.destroy();
    }
  }

  // UPS listesini al
  Future<List<String>> listUps() async {
    final lines = await _sendCommand('LIST UPS');
    final upsList = <String>[];
    for (final line in lines) {
      if (line.startsWith('UPS ')) {
        final parts = line.split(' ');
        if (parts.length >= 2) upsList.add(parts[1]);
      }
    }
    return upsList;
  }

  // Tek UPS'in tüm değişkenlerini al
  Future<Map<String, String>> getUpsVars(String upsName) async {
    final lines = await _sendCommand('LIST VAR $upsName');
    final vars = <String, String>{};
    for (final line in lines) {
      if (line.startsWith('VAR $upsName ')) {
        final rest = line.substring('VAR $upsName '.length);
        final idx = rest.indexOf(' ');
        if (idx != -1) {
          final key = rest.substring(0, idx);
          var value = rest.substring(idx + 1).trim();
          if (value.startsWith('"') &&
              value.endsWith('"') &&
              value.length >= 2) {
            value = value.substring(1, value.length - 1);
          }
          vars[key] = value;
        }
      }
    }
    return vars;
  }

  // Tek bir değişken al
  Future<String> getVar(String upsName, String varName) async {
    final lines = await _sendCommand('GET VAR $upsName $varName');
    for (final line in lines) {
      if (line.startsWith('VAR $upsName $varName ')) {
        var value = line.substring('VAR $upsName $varName '.length).trim();
        if (value.startsWith('"') && value.endsWith('"') && value.length >= 2) {
          value = value.substring(1, value.length - 1);
        }
        return value;
      }
    }
    return '';
  }

  // Bağlantı testi — LIST UPS ile gerçek bir NUT komutu dene
  Future<bool> testConnection() async {
    try {
      await listUps();
      return true;
    } catch (_) {
      return false;
    }
  }
}

// ── UPS veri modeli ───────────────────────────────────────────────────────

class UpsData {
  final String name;
  final Map<String, String> vars;
  final DateTime updatedAt;

  UpsData({
    required this.name,
    required this.vars,
    required this.updatedAt,
  });

  double get batteryCharge =>
      double.tryParse(vars['battery.charge'] ?? '0') ?? 0;
  double get batteryVoltage =>
      double.tryParse(vars['battery.voltage'] ?? '0') ?? 0;
  double get inputVoltage => double.tryParse(vars['input.voltage'] ?? '0') ?? 0;
  double get outputVoltage =>
      double.tryParse(vars['output.voltage'] ?? '0') ?? 0;
  double get inputFrequency =>
      double.tryParse(vars['input.frequency'] ?? '0') ?? 0;
  double get load => double.tryParse(vars['ups.load'] ?? '0') ?? 0;
  double get temperature =>
      double.tryParse(vars['ups.temperature'] ?? '0') ?? 0;
  int get runtimeRemaining => int.tryParse(vars['battery.runtime'] ?? '0') ?? 0;

  String get status => vars['ups.status'] ?? 'UNKNOWN';
  String get model => vars['ups.model'] ?? vars['device.model'] ?? '-';
  String get manufacturer => vars['ups.mfr'] ?? vars['device.mfr'] ?? '-';
  String get firmware => vars['ups.firmware'] ?? '-';
  String get type => vars['ups.type'] ?? '-';
  String get driverName => vars['driver.name'] ?? '-';

  UpsStatus get parsedStatus {
    final s = status.toUpperCase();
    if (s.contains('LB')) return UpsStatus.lowBattery;
    if (s.contains('OB')) return UpsStatus.onBattery;
    if (s.contains('CHRG')) return UpsStatus.charging;
    if (s.contains('DISCHRG')) return UpsStatus.discharging;
    if (s.contains('BYPASS')) return UpsStatus.bypass;
    if (s.contains('OFF')) return UpsStatus.offline;
    if (s.contains('OL')) return UpsStatus.online;
    return UpsStatus.unknown;
  }

  String get statusLabel {
    switch (parsedStatus) {
      case UpsStatus.online:
        return 'Çevrimiçi';
      case UpsStatus.onBattery:
        return 'Batarya ile Çalışıyor';
      case UpsStatus.lowBattery:
        return 'Düşük Batarya';
      case UpsStatus.charging:
        return 'Şarj Oluyor';
      case UpsStatus.discharging:
        return 'Deşarj Oluyor';
      case UpsStatus.bypass:
        return 'Bypass Modu';
      case UpsStatus.offline:
        return 'Çevrimdışı';
      case UpsStatus.unknown:
        return 'Bilinmiyor';
    }
  }

  String get runtimeLabel {
    if (runtimeRemaining <= 0) return '-';
    final m = runtimeRemaining ~/ 60;
    final s = runtimeRemaining % 60;
    if (m >= 60) return '${m ~/ 60}s ${m % 60}dk';
    return '${m}dk ${s}sn';
  }
}

enum UpsStatus {
  online,
  onBattery,
  lowBattery,
  charging,
  discharging,
  bypass,
  offline,
  unknown,
}

// ── NUT Sunucu modeli ─────────────────────────────────────────────────────

class NutServer {
  final String name;
  final String host;
  final int port;
  final String username;
  final String password;
  final List<String> upsNames;

  /// Cloud'dan geldiğinde, kimlik bilgisi başka bir cihazda girilmiş ama bu
  /// cihazda henüz yoksa true olur (bkz. credential_sync.dart). Boş kimlik
  /// bilgisi her zaman "eksik" demek değildir — anonim NUT sunucuları için
  /// bilinçli olarak boş bırakılmışsa bu false kalır ve sorgu normal atılır.
  final bool needsCredentials;

  const NutServer({
    required this.name,
    required this.host,
    this.port = 3493,
    this.username = '',
    this.password = '',
    this.upsNames = const [],
    this.needsCredentials = false,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'host': host,
        'port': port,
        'username': username,
        'password': password,
        'upsNames': upsNames,
      };

  factory NutServer.fromJson(Map<String, dynamic> json) => NutServer(
        name: json['name'] as String,
        host: json['host'] as String,
        port: json['port'] as int? ?? 3493,
        username: json['username'] as String? ?? '',
        password: json['password'] as String? ?? '',
        upsNames:
            (json['upsNames'] as List?)?.map((e) => e as String).toList() ?? [],
        needsCredentials: json['needsCredentials'] as bool? ?? false,
      );
}
