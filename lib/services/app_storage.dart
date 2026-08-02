import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

abstract class AppStorage {
  Future<Map<String, Object?>?> read();

  Future<void> write(Map<String, Object?> data);
}

class SharedPreferencesAppStorage implements AppStorage {
  static const _storageKey = 'tomatolog_data_v1';

  @override
  Future<Map<String, Object?>?> read() async {
    final preferences = await SharedPreferences.getInstance();
    final value = preferences.getString(_storageKey);
    if (value == null) return null;
    try {
      final decoded = jsonDecode(value);
      if (decoded is! Map) return null;
      return decoded.cast<String, Object?>();
    } on FormatException {
      return null;
    }
  }

  @override
  Future<void> write(Map<String, Object?> data) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_storageKey, jsonEncode(data));
  }
}

class MemoryAppStorage implements AppStorage {
  Map<String, Object?>? value;

  @override
  Future<Map<String, Object?>?> read() async => value;

  @override
  Future<void> write(Map<String, Object?> data) async {
    value = data;
  }
}
