import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ErrorLogType { connection, node, refresh, operation, anomaly, performance, unknown }

class ErrorLogEntry {
  final String id;
  final DateTime time;
  final ErrorLogType type;
  final String message;
  final String? detail;

  ErrorLogEntry({
    required this.id,
    required this.time,
    required this.type,
    required this.message,
    this.detail,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'time': time.toIso8601String(),
        'type': type.name,
        'message': message,
        'detail': detail,
      };

  factory ErrorLogEntry.fromJson(Map<String, dynamic> j) => ErrorLogEntry(
        id: j['id'] ?? '',
        time: DateTime.tryParse(j['time'] ?? '') ?? DateTime.now(),
        type: ErrorLogType.values.firstWhere(
          (e) => e.name == j['type'],
          orElse: () => ErrorLogType.unknown,
        ),
        message: j['message'] ?? '',
        detail: j['detail'],
      );

  // Tema'dan bağımsız sabit renkler — hata türleri evrensel renk kodlaması kullanır
  Color get color {
    switch (type) {
      case ErrorLogType.connection:   return Colors.redAccent;
      case ErrorLogType.node:         return Colors.orangeAccent;
      case ErrorLogType.refresh:      return Colors.amber;
      case ErrorLogType.operation:    return Colors.blueAccent;
      case ErrorLogType.anomaly:      return Colors.deepOrangeAccent;
      case ErrorLogType.performance:  return Colors.purpleAccent;
      case ErrorLogType.unknown:      return Colors.grey;
    }
  }

  String get typeLabel {
    switch (type) {
      case ErrorLogType.connection:
        return 'Bağlantı';
      case ErrorLogType.node:
        return 'Node';
      case ErrorLogType.refresh:
        return 'Yenileme';
      case ErrorLogType.operation:
        return 'İşlem';
      case ErrorLogType.anomaly:
        return 'Anomali';
      case ErrorLogType.performance:
        return 'Performans';
      case ErrorLogType.unknown:
        return 'Bilinmiyor';
    }
  }

  IconData get icon {
    switch (type) {
      case ErrorLogType.connection:
        return Icons.wifi_off_rounded;
      case ErrorLogType.node:
        return Icons.dns_rounded;
      case ErrorLogType.refresh:
        return Icons.refresh_rounded;
      case ErrorLogType.operation:
        return Icons.settings_rounded;
      case ErrorLogType.anomaly:
        return Icons.warning_amber_rounded;
      case ErrorLogType.performance:
        return Icons.speed_rounded;
      case ErrorLogType.unknown:
        return Icons.error_outline_rounded;
    }
  }
}

class ErrorLogService {
  static const _key = 'app_error_logs';
  static const _maxLogs = 200;

  static final ErrorLogService _instance = ErrorLogService._();
  factory ErrorLogService() => _instance;
  ErrorLogService._();

  final List<ErrorLogEntry> _logs = [];
  List<ErrorLogEntry> get logs => List.unmodifiable(_logs);

  Future<void> load() async {
    final prefs = await _p;
    final raw = prefs.getString(_key);
    if (raw == null) return;
    try {
      final list = jsonDecode(raw) as List;
      _logs.clear();
      _logs.addAll(list.map((e) => ErrorLogEntry.fromJson(e)));
    } catch (_) {
      // Bilinçli sessiz: bu, hata-günlüğü servisinin KENDİ verisini yükleme
      // hatası — burayı yine ErrorLogService'e loglamak dairesel olur.
    }
  }

  Future<void> log({
    required ErrorLogType type,
    required String message,
    String? detail,
  }) async {
    final now = DateTime.now(); // tek seferinde al
    final entry = ErrorLogEntry(
      id: now.microsecondsSinceEpoch.toString(),
      time: now,
      type: type,
      message: message,
      detail: detail,
    );
    _logs.insert(0, entry);
    if (_logs.length > _maxLogs) _logs.removeLast();
    await _save();
  }

  Future<void> clear() async {
    _logs.clear();
    await _save();
  }

  SharedPreferences? _prefs;
  Future<SharedPreferences> get _p async =>
      _prefs ??= await SharedPreferences.getInstance();

  Future<void> _save() async {
    final prefs = await _p;
    await prefs.setString(
        _key, jsonEncode(_logs.map((e) => e.toJson()).toList()));
  }
}