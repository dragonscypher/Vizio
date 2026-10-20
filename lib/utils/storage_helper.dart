import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class StorageHelper {
  /// Save a critical alert to a local file.
  static Future<void> saveAlert(String alert) async {
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/alerts.txt');
    // Append the alert if it contains critical info.
    await file.writeAsString("$alert\n", mode: FileMode.append);
  }

  /// Returns true if saving alerts is enabled.
  static Future<bool> shouldSaveAlerts() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('saveAlerts') ?? false;
  }
}
