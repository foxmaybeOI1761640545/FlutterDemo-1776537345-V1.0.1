import "dart:convert";

import "package:shared_preferences/shared_preferences.dart";

import "models.dart";

class LocalStorageService {
  static const String _settingsKey = "pulsebeat.settings.v1";
  static const String _presetsKey = "pulsebeat.presets.v1";

  Future<StoredAppState> load() async {
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    AppSettings settings = AppSettings.defaults();
    List<MetronomePreset> presets = <MetronomePreset>[];

    final String? settingsRaw = preferences.getString(_settingsKey);
    if (settingsRaw != null && settingsRaw.isNotEmpty) {
      try {
        final Map<String, dynamic> json =
            jsonDecode(settingsRaw) as Map<String, dynamic>;
        settings = AppSettings.fromJson(json);
      } on Object {
        settings = AppSettings.defaults();
      }
    }

    final String? presetsRaw = preferences.getString(_presetsKey);
    if (presetsRaw != null && presetsRaw.isNotEmpty) {
      try {
        final List<dynamic> json = jsonDecode(presetsRaw) as List<dynamic>;
        presets = json
            .map(
              (dynamic item) => MetronomePreset.fromJson(
                (item as Map<String, dynamic>?) ?? <String, dynamic>{},
              ),
            )
            .toList();
      } on Object {
        presets = <MetronomePreset>[];
      }
    }

    presets.sort(
      (MetronomePreset a, MetronomePreset b) =>
          b.lastUsedAtEpochMs.compareTo(a.lastUsedAtEpochMs),
    );

    return StoredAppState(settings: settings, presets: presets);
  }

  Future<void> saveSettings(AppSettings settings) async {
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    await preferences.setString(_settingsKey, jsonEncode(settings.toJson()));
  }

  Future<void> savePresets(List<MetronomePreset> presets) async {
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    final List<MetronomePreset> trimmed = presets.take(kMaxPresetCount).toList();
    await preferences.setString(
      _presetsKey,
      jsonEncode(trimmed.map((MetronomePreset e) => e.toJson()).toList()),
    );
  }

  Future<void> clearAll() async {
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    await preferences.remove(_settingsKey);
    await preferences.remove(_presetsKey);
  }
}
