import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'models/drying_environment.dart';

abstract interface class EnvironmentStore {
  Future<DryingEnvironment?> load();
  Future<void> save(DryingEnvironment environment);
}

class PreferencesEnvironmentStore implements EnvironmentStore {
  PreferencesEnvironmentStore({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();
  final SharedPreferencesAsync _preferences;
  static const storageKey = 'drynow.environment.v1';

  @override
  Future<DryingEnvironment?> load() async {
    final raw = await _preferences.getString(storageKey);
    if (raw == null) return null;
    try {
      final environment = DryingEnvironment.fromJson(jsonDecode(raw));
      if (environment == null) throw const FormatException('環境設定が不正です。');
      return environment;
    } on FormatException {
      // 壊れた設定を既定値にせず、再設定を案内する。
      throw const FormatException('保存した環境設定を読み取れません。再設定してください。');
    }
  }

  @override
  Future<void> save(DryingEnvironment environment) =>
      _preferences.setString(storageKey, jsonEncode(environment.toJson()));
}
