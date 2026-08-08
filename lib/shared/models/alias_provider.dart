import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'disk_alias.dart';

class AliasProvider extends ChangeNotifier {
  Map<String, DiskAlias> _aliases = {};

  Map<String, DiskAlias> get aliases => _aliases;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('disk_aliases') ?? '{}';
    final map = jsonDecode(raw) as Map<String, dynamic>;
    _aliases = map.map((k, v) => MapEntry(k, DiskAlias.fromJson(v)));
    notifyListeners();
  }

  Future<void> setAlias(String devpath, String alias) async {
    _aliases[devpath] =
        DiskAlias(devpath: devpath, alias: alias, icon: 'storage');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        'disk_aliases',
        jsonEncode(
          _aliases.map((k, v) => MapEntry(k, v.toJson())),
        ));
    notifyListeners();
  }

  String getAlias(String devpath) => _aliases[devpath]?.alias ?? '';

  /// Çıkış yapıldığında çağrılır — bellek içi veriyi sıfırlar.
  void reset() {
    _aliases = {};
    notifyListeners();
  }
}