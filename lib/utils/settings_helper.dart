import 'package:shared_preferences/shared_preferences.dart';

class SettingsHelper {
  static SharedPreferences? _prefs;

  static Future<void> initialize() async {
    _prefs = await SharedPreferences.getInstance();
  }

  static Future<bool> getBool(String key, {required bool defaultValue}) async {
    return _prefs?.getBool(key) ?? defaultValue;
  }

  static Future<String> getString(String key, {required String defaultValue}) async {
    return _prefs?.getString(key) ?? defaultValue;
  }

  static Future<void> setValue(String key, dynamic value) async {
    if (value is bool) {
      await _prefs?.setBool(key, value);
    } else if (value is String) {
      await _prefs?.setString(key, value);
    }
  }
}
