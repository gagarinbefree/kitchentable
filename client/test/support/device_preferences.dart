import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DevicePreferences extends Fake implements SharedPreferencesAsync {
  final values = <String, String>{};

  @override
  Future<Map<String, Object?>> getAll({Set<String>? allowList}) async =>
      Map.of(values);

  @override
  Future<void> setString(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> remove(String key) async {
    values.remove(key);
  }
}
