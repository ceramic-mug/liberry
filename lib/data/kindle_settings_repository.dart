import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'reader_settings_repository.dart';

class KindleDevice {
  final String id;
  final String name;
  final String email;

  KindleDevice({required this.id, required this.name, required this.email});

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'email': email};

  factory KindleDevice.fromJson(Map<String, dynamic> json) {
    return KindleDevice(
      id: json['id'] as String,
      name: json['name'] as String,
      email: json['email'] as String,
    );
  }
}

class KindleSettingsRepository {
  final SharedPreferences _prefs;

  KindleSettingsRepository(this._prefs);

  static const _keyKindleEmail = 'kindle_email_address'; // Legacy key
  static const _keyKindleDevices = 'kindle_devices_list'; // New key

  List<KindleDevice> getDevices() {
    // 1. Check for legacy single email
    final legacyEmail = _prefs.getString(_keyKindleEmail);
    if (legacyEmail != null && legacyEmail.isNotEmpty) {
      // Migrate to new list format
      final newDevice = KindleDevice(
        id: const Uuid().v4(),
        name: 'Default Kindle',
        email: legacyEmail,
      );

      // Save to new list
      saveDevices([newDevice]);

      // Remote legacy key
      _prefs.remove(_keyKindleEmail);

      return [newDevice];
    }

    // 2. Return list from JSON
    final jsonList = _prefs.getStringList(_keyKindleDevices);
    if (jsonList == null) return [];

    return jsonList
        .map((jsonStr) => KindleDevice.fromJson(jsonDecode(jsonStr)))
        .toList();
  }

  Future<void> saveDevices(List<KindleDevice> devices) async {
    final jsonList = devices
        .map((device) => jsonEncode(device.toJson()))
        .toList();
    await _prefs.setStringList(_keyKindleDevices, jsonList);
  }

  Future<void> addDevice(String name, String email) async {
    final devices = getDevices();
    devices.add(KindleDevice(id: const Uuid().v4(), name: name, email: email));
    await saveDevices(devices);
  }

  Future<void> removeDevice(String id) async {
    final devices = getDevices();
    devices.removeWhere((d) => d.id == id);
    await saveDevices(devices);
  }

  // Helper to update a device (for full CRUD if needed later)
  Future<void> updateDevice(KindleDevice updatedDevice) async {
    final devices = getDevices();
    final index = devices.indexWhere((d) => d.id == updatedDevice.id);
    if (index != -1) {
      devices[index] = updatedDevice;
      await saveDevices(devices);
    }
  }
}

final kindleSettingsRepositoryProvider = Provider<KindleSettingsRepository>((
  ref,
) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return KindleSettingsRepository(prefs);
});
